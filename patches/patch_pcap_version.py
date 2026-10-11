#!/usr/bin/env python3
"""
patch_pcap_version.py -- make eNSP's packet.dll users treat any capture
driver as WinPcap 4.x, so the Cloud device sees host adapters under Npcap.

Several eNSP modules compute the capture driver's "major version" as
PacketGetVersion()[0] - '0' and branch on it == 4 (the old WinPcap sample
code):
  - == 4  : adapter list is ANSI, NetType.LinkSpeed is a 64-bit field
  - else  : adapter list is UTF-16 (WinPcap 3.x on NT), LinkSpeed 32-bit
Npcap reports "1.89", so the major version becomes 1 and the modules parse
Npcap's ANSI list as UTF-16 and read LinkSpeed from padding: no adapter
survives and the Cloud dialog only offers UDP. See
docs/findings/cloud-npcap.md.

The patch replaces the single instruction pair that computes the major
version with "mov reg, 4" (eNSP_Firewall compares the character directly,
so its je becomes jmp). Every later branch in that module then takes the
WinPcap 4 path. Under WinPcap 4.x the value already is 4, so behaviour
there is unchanged.

Targets (paths relative to the eNSP install directory):
  default  : tools\\eNSP_Cloud_Plugin.dll, eNSP_Client.exe
  --devices: also the AR / S3700 / S5700 / USG5500 host-side device
             executables, which carry the same check (no visible symptom
             has been tied to them yet).

Every file must match its known factory SHA-256 (or the known patched one);
anything else is refused. Fully reversible (--restore).

Usage:
    python patch_pcap_version.py [eNSP dir]              # patch default set
    python patch_pcap_version.py --devices [eNSP dir]    # also device exes
    python patch_pcap_version.py --check   [eNSP dir]    # report, change nothing
    python patch_pcap_version.py --restore [eNSP dir]    # patched -> pristine
    python patch_pcap_version.py --no-backup ...         # skip the .bak copy
"""
import argparse
import hashlib
import os
import shutil
import sys

DEFAULT_ENSP = r"C:\Program Files\Huawei\eNSP"

# (relative path, size, sha256 pristine, sha256 patched,
#  file offset, pristine bytes, patched bytes, device-only?, what)
TARGETS = [
    ("tools\\eNSP_Cloud_Plugin.dll", 507904,
     "4a101d7fbf03927ff16cd7847aed34bf71c052ec18efd81245deb0346d9303a3",
     "5d4e89964b8b055c2fc8b5c557eceb54aab15608b10edd7818291c5e128ad3e2",
     0x1152B, "0FBE3083EE30", "BE0400000090", False,
     "1001152B movsx esi,[eax]; sub esi,'0'  ->  mov esi,4; nop"),
    ("eNSP_Client.exe", 3547136,
     "e2cdd4c77eaca23fbc84c9e466e6847988cc42a349df3ede0b65c1c1f8080b7e",
     "2079572fde3347d6267b8c54c3bf73f51a33602b493ba894aea5d11bd4a98443",
     0xD6225, "0FBE3083EE30", "BE0400000090", False,
     "004D6225 movsx esi,[eax]; sub esi,'0'  ->  mov esi,4; nop"),
    ("vboxserver\\devices\\AR\\AR\\eNSP_Router.exe", 157749248,
     "15666df1b06b95a1efc470cbd7b49ea6d9c4a54dd38d7760cbc87bf65d1713f4",
     "2f3810ec923d82e877202dc6170262a358df539895513589b22a485bb9ce3fc0",
     0x7665A3, "0FBE0283E830", "B80400000090", True,
     "00B665A3 movsx eax,[edx]; sub eax,'0'  ->  mov eax,4; nop"),
    ("vboxserver\\devices\\LSW\\s3700\\eNSP_Switch.exe", 139079680,
     "79d7052d39e2374745bfda9285296c8f44d9ebc34c7084623ba5ff4d85f9ce1d",
     "7b6b9064b07450d974871cb478bf820fcfc19b83505741f5b221bc8256d792a1",
     0x2D42BE3, "0FBE0283E830", "B80400000090", True,
     "03142BE3 movsx eax,[edx]; sub eax,'0'  ->  mov eax,4; nop"),
    ("vboxserver\\devices\\LSW\\s5700\\eNSP_Switch.exe", 140005376,
     "083c2a3a602ea7eaa345db009f9db11df142f58e6e5722a4172cc2604a2c6432",
     "e1e8193c221a0c80811df5a169b814bba63162ea2b4e0eefb73eef1887c57898",
     0x310D033, "0FBE0283E830", "B80400000090", True,
     "05E64033 movsx eax,[edx]; sub eax,'0'  ->  mov eax,4; nop"),
    ("vboxserver\\devices\\FW\\USG5500\\eNSP_Firewall.exe", 55635968,
     "d9912c875563591f34f41ccad0e2d6572d93dac663dfc9e7682f59010721c3ea",
     "9b98348733d3d9ed2bb9ede2bd0502ac0e433106ccac751fc259096bb00a7090",
     0x1B2DC7, "7402", "EB02", True,
     "005B2DC7 je (version[0]=='4')  ->  jmp"),
]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def classify(data: bytes, t) -> str:
    _, size, h_pris, h_pat = t[:4]
    if len(data) != size:
        return "unknown"
    h = sha256(data)
    if h == h_pris:
        return "pristine"
    if h == h_pat:
        return "patched"
    return "unknown"


def process(path: str, t, mode: str, backup: bool) -> int:
    rel, _, _, _, off, b_pris, b_pat, _, what = t
    b_pris, b_pat = bytes.fromhex(b_pris), bytes.fromhex(b_pat)
    if not os.path.isfile(path):
        print(f"[!] not found: {path}")
        return 2
    data = bytearray(open(path, "rb").read())
    state = classify(bytes(data), t)
    print(f"{rel}")
    print(f"    state : {state}")
    if mode == "check":
        if state == "unknown":
            here = bytes(data[off:off + len(b_pris)])
            print(f"    bytes : {here.hex().upper()} at 0x{off:X} "
                  f"(pristine {b_pris.hex().upper()}, patched {b_pat.hex().upper()})")
        return 0

    restore = mode == "restore"
    want_from, want_to = ("patched", "pristine") if restore else ("pristine", "patched")
    src, dst = (b_pat, b_pris) if restore else (b_pris, b_pat)
    if state == want_to:
        print(f"    [=] already {want_to}; nothing to do.")
        return 0
    if state != want_from:
        print(f"    [!] expected '{want_from}'; refusing to touch an unrecognized file.")
        return 2
    if bytes(data[off:off + len(src)]) != src:
        print(f"    [!] bytes at 0x{off:X} are not {src.hex().upper()}; aborting.")
        return 2

    if backup and not restore:
        bak = path + ".bak"
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
            print(f"    [+] backup -> {bak}")
        else:
            print(f"    [=] backup already exists -> {bak} (kept)")

    data[off:off + len(dst)] = dst
    out = bytes(data)
    if classify(out, t) != want_to:
        print(f"    [!] post-write hash is not the known {want_to} hash. NOT saving.")
        return 3
    try:
        with open(path, "r+b") as f:
            f.seek(off)
            f.write(dst)
    except PermissionError:
        print("    [!] cannot write (run as administrator, and close eNSP first).")
        return 4
    print(f"    [+] {'restored' if restore else 'patched'}: {what}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Make eNSP treat any packet.dll as WinPcap 4.x (Cloud + Npcap)")
    ap.add_argument("ensp", nargs="?", default=DEFAULT_ENSP,
                    help=f"eNSP install directory (default: {DEFAULT_ENSP})")
    ap.add_argument("--check", action="store_true", help="report state only, change nothing")
    ap.add_argument("--restore", action="store_true", help="revert patched -> pristine")
    ap.add_argument("--devices", action="store_true",
                    help="also the AR/S3700/S5700/USG5500 device executables")
    ap.add_argument("--no-backup", action="store_true", help="do not write a .bak copy")
    a = ap.parse_args()

    if not os.path.isdir(a.ensp):
        print(f"[!] not a directory: {a.ensp}")
        return 2
    mode = "check" if a.check else "restore" if a.restore else "patch"
    # --check and --restore look at every target so nothing is left behind.
    targets = [t for t in TARGETS if a.devices or mode != "patch" or not t[7]]
    rc = 0
    for t in targets:
        rc = max(rc, process(os.path.join(a.ensp, t[0]), t, mode, not a.no_backup))
    return rc


if __name__ == "__main__":
    sys.exit(main())
