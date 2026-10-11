#!/usr/bin/env python3
"""
patch_pcap_version.py -- let eNSP's Cloud device see host adapters under Npcap.

Two things in eNSP's old WinPcap sample code reject every Npcap adapter
(see docs/findings/cloud-npcap.md):

1. Version check. The major version is computed as PacketGetVersion()[0]-'0'
   and branched on == 4. Npcap reports "1.89", so the modules take the
   WinPcap 3.x paths (UTF-16 adapter list, 32-bit LinkSpeed). Patched by
   turning that instruction pair into "mov reg, 4" (eNSP_Firewall compares
   the character directly, so its je becomes jmp).

2. Link-speed filter. Adapters reporting LinkSpeed < 10 Mbps are dropped,
   and Npcap's PacketGetNetType reports 0 for every adapter. Patched to drop
   only 0 < LinkSpeed < 10 Mbps, i.e. an unknown (0) speed passes:
       nop x5; mov eax,[esp+X]; dec eax; cmp eax,98967Fh; jb <same target>
   in place of the original 17-byte compare-and-branch.

Under WinPcap 4.x the version already is 4 and speeds are never 0, so the
patched modules behave exactly as before.

Targets (paths relative to the eNSP install directory):
  default  : tools\\eNSP_Cloud_Plugin.dll (both fixes, 3 sites),
             eNSP_Client.exe (both fixes, 2 sites)
  --devices: also the AR / S3700 / S5700 / USG5500 host-side device
             executables (version fix only; no visible symptom tied to them)

A file is accepted only if, with every site put back to its factory bytes,
it hashes to the known factory SHA-256 -- so pristine, fully patched and
partially patched (e.g. an older version of this patcher) files are all
recognized, and anything else is refused. Fully reversible (--restore).

Usage:
    python patch_pcap_version.py [eNSP dir]              # patch default set
    python patch_pcap_version.py --devices [eNSP dir]    # also device exes
    python patch_pcap_version.py --check   [eNSP dir]    # report, change nothing
    python patch_pcap_version.py --restore [eNSP dir]    # back to factory
    python patch_pcap_version.py --no-backup ...         # skip the .bak copy
"""
import argparse
import hashlib
import os
import shutil
import sys

DEFAULT_ENSP = r"C:\Program Files\Huawei\eNSP"

_VER_ESI = ("0FBE3083EE30", "BE0400000090")   # movsx esi,[eax]; sub esi,'0' -> mov esi,4; nop
_VER_EAX = ("0FBE0283E830", "B80400000090")   # movsx eax,[edx]; sub eax,'0' -> mov eax,4; nop


def _speed(x: str, rel: str):
    # cmp [esp+X+4],0; ja pass; cmp [esp+X],989680h; jb drop
    #   -> nop x5; mov eax,[esp+X]; dec eax; cmp eax,98967Fh; jb drop
    return ("837C24" + "%02X" % (int(x, 16) + 4) + "00770A817C24" + x + "80969800" + "72" + rel,
            "9090909090" + "8B4424" + x + "48" + "3D7F969800" + "72" + rel)


# relative path -> (size, sha256 factory, sha256 fully patched, device-only?,
#                   [(file offset, (factory hex, patched hex), what), ...])
TARGETS = {
    "tools\\eNSP_Cloud_Plugin.dll": (
        507904,
        "4a101d7fbf03927ff16cd7847aed34bf71c052ec18efd81245deb0346d9303a3",
        "38ab157f0db72844cdc433d0b49be38d03fe4e9414aac8719afabf7766113afc",
        False, [
            (0x1152B, _VER_ESI, "1001152B version -> 4"),
            (0x1141E, _speed("10", "49"), "1001141E speed 0 passes (adapter list)"),
            (0x0DF3F, _speed("20", "25"), "1000DF3F speed 0 passes (adapter open)"),
        ]),
    "eNSP_Client.exe": (
        3547136,
        "e2cdd4c77eaca23fbc84c9e466e6847988cc42a349df3ede0b65c1c1f8080b7e",
        "172cdefbdc479b50174d14a5cff19046c4825c233cc742c53f79e6c23dd63b22",
        False, [
            (0xD6225, _VER_ESI, "004D6225 version -> 4"),
            (0xD611E, _speed("10", "49"), "004D611E speed 0 passes"),
        ]),
    "vboxserver\\devices\\AR\\AR\\eNSP_Router.exe": (
        157749248,
        "15666df1b06b95a1efc470cbd7b49ea6d9c4a54dd38d7760cbc87bf65d1713f4",
        "2f3810ec923d82e877202dc6170262a358df539895513589b22a485bb9ce3fc0",
        True, [(0x7665A3, _VER_EAX, "00B665A3 version -> 4")]),
    "vboxserver\\devices\\LSW\\s3700\\eNSP_Switch.exe": (
        139079680,
        "79d7052d39e2374745bfda9285296c8f44d9ebc34c7084623ba5ff4d85f9ce1d",
        "7b6b9064b07450d974871cb478bf820fcfc19b83505741f5b221bc8256d792a1",
        True, [(0x2D42BE3, _VER_EAX, "03142BE3 version -> 4")]),
    "vboxserver\\devices\\LSW\\s5700\\eNSP_Switch.exe": (
        140005376,
        "083c2a3a602ea7eaa345db009f9db11df142f58e6e5722a4172cc2604a2c6432",
        "e1e8193c221a0c80811df5a169b814bba63162ea2b4e0eefb73eef1887c57898",
        True, [(0x310D033, _VER_EAX, "05E64033 version -> 4")]),
    "vboxserver\\devices\\FW\\USG5500\\eNSP_Firewall.exe": (
        55635968,
        "d9912c875563591f34f41ccad0e2d6572d93dac663dfc9e7682f59010721c3ea",
        "9b98348733d3d9ed2bb9ede2bd0502ac0e433106ccac751fc259096bb00a7090",
        True, [(0x1B2DC7, ("7402", "EB02"), "005B2DC7 version check je -> jmp")]),
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def site_states(data: bytes, sites) -> list:
    """Per site: 'pristine', 'patched' or 'other'."""
    out = []
    for off, (a, b), _ in sites:
        cur = bytes(data[off:off + len(a) // 2])
        out.append("pristine" if cur == bytes.fromhex(a) else
                   "patched" if cur == bytes.fromhex(b) else "other")
    return out


def with_sites(data: bytes, sites, column: int) -> bytes:
    """Copy of data with every site set to column 0 (factory) or 1 (patched)."""
    d = bytearray(data)
    for off, pair, _ in sites:
        new = bytes.fromhex(pair[column])
        d[off:off + len(new)] = new
    return bytes(d)


def classify(data: bytes, t) -> str:
    size, h_pris, _, _, sites = t
    if len(data) != size:
        return "unknown (size)"
    states = site_states(data, sites)
    if "other" in states or sha256(with_sites(data, sites, 0)) != h_pris:
        return "unknown"
    if all(s == "pristine" for s in states):
        return "pristine"
    if all(s == "patched" for s in states):
        return "patched"
    return "partial (%d/%d sites)" % (states.count("patched"), len(states))


def process(path: str, rel: str, t, mode: str, backup: bool) -> int:
    _, h_pris, h_pat, _, sites = t
    if not os.path.isfile(path):
        print(f"[!] not found: {path}")
        return 2
    data = open(path, "rb").read()
    state = classify(data, t)
    print(f"{rel}")
    print(f"    state : {state}")
    if mode == "check":
        if state.startswith(("unknown", "partial")):
            for (off, _, what), s in zip(sites, site_states(data, sites)):
                print(f"            {s:8} 0x{off:X} {what}")
        return 0
    if state.startswith("unknown"):
        print("    [!] not a known build of this file; refusing to touch it.")
        return 2
    want = "pristine" if mode == "restore" else "patched"
    if state == want:
        print(f"    [=] already {want}; nothing to do.")
        return 0

    out = with_sites(data, sites, 0 if mode == "restore" else 1)
    if sha256(out) != (h_pris if mode == "restore" else h_pat):
        print(f"    [!] result would not hash to the known {want} SHA-256. NOT saving.")
        return 3
    if backup and mode == "patch":
        bak = path + ".bak"
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
            print(f"    [+] backup -> {bak}")
        else:
            print(f"    [=] backup already exists -> {bak} (kept)")
    try:
        with open(path, "r+b") as f:
            for off, pair, what in sites:
                new = bytes.fromhex(pair[0 if mode == "restore" else 1])
                if data[off:off + len(new)] != new:
                    f.seek(off)
                    f.write(new)
                    print(f"    [+] {'restored' if mode == 'restore' else 'patched'}: {what}")
    except PermissionError:
        print("    [!] cannot write (run as administrator, and close eNSP first).")
        return 4
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Let eNSP's Cloud device see host adapters under Npcap")
    ap.add_argument("ensp", nargs="?", default=DEFAULT_ENSP,
                    help=f"eNSP install directory (default: {DEFAULT_ENSP})")
    ap.add_argument("--check", action="store_true", help="report state only, change nothing")
    ap.add_argument("--restore", action="store_true", help="put every file back to factory")
    ap.add_argument("--devices", action="store_true",
                    help="also the AR/S3700/S5700/USG5500 device executables")
    ap.add_argument("--no-backup", action="store_true", help="do not write a .bak copy")
    a = ap.parse_args()

    if not os.path.isdir(a.ensp):
        print(f"[!] not a directory: {a.ensp}")
        return 2
    mode = "check" if a.check else "restore" if a.restore else "patch"
    rc = 0
    for rel, t in TARGETS.items():
        # --check and --restore look at every target so nothing is left behind.
        if t[3] and mode == "patch" and not a.devices:
            continue
        rc = max(rc, process(os.path.join(a.ensp, rel), rel, t, mode, not a.no_backup))
    return rc


if __name__ == "__main__":
    sys.exit(main())
