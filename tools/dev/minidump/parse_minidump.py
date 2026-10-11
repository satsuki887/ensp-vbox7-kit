"""Minimal Windows kernel triage-minidump parser: bugcheck + faulting driver + drivers on stack."""
import struct, sys

def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]

def read_dump_string(b, off):
    if off <= 0 or off + 4 > len(b):
        return None
    n = u32(b, off)
    if n == 0 or n > 260 or off + 4 + n * 2 > len(b):
        return None
    try:
        s = b[off + 4: off + 4 + n * 2].decode('utf-16-le')
    except UnicodeDecodeError:
        return None
    return s if s.isprintable() else None

def parse(path):
    b = open(path, 'rb').read()
    print(f'===== {path}')
    if b[:8] != b'PAGEDU64':
        print('not a 64-bit kernel dump'); return
    code = u32(b, 0x38)
    params = [u64(b, 0x40 + i * 8) for i in range(4)]
    print(f'BugCheck 0x{code:X}  params: ' + ', '.join(f'0x{p:X}' for p in params))
    t = 0x2000
    drv_off, drv_cnt = u32(b, t + 0x30), u32(b, t + 0x34)
    pool_off = u32(b, t + 0x38)
    cs_off, cs_size = u32(b, t + 0x28), u32(b, t + 0x2c)
    # find stride of DUMP_DRIVER_ENTRY64 by validating name offsets
    drivers = None
    for stride in range(0x60, 0x200, 8):
        names = [read_dump_string(b, u32(b, drv_off + i * stride)) for i in range(min(drv_cnt, 5))]
        if all(names):
            drivers = []
            for i in range(drv_cnt):
                e = drv_off + i * stride
                name = read_dump_string(b, u32(b, e))
                base, size = u64(b, e + 8 + 0x30), u32(b, e + 8 + 0x40)
                drivers.append((name, base, size))
            break
    if not drivers:
        print('could not decode driver list'); return
    def lookup(addr):
        for n, base, size in drivers:
            if base <= addr < base + size:
                return f'{n}+0x{addr - base:X}'
        return None
    print(f'{len(drivers)} drivers loaded')
    print('Faulting IP (param4):', lookup(params[3]) or '?')
    if cs_off and cs_size:
        seen = []
        for o in range(cs_off, cs_off + cs_size - 7, 8):
            m = lookup(u64(b, o))
            if m:
                seen.append(m)
        print('Driver addresses found on stack (top first):')
        for m in seen[:40]:
            print('   ', m)
    third = [d for d in drivers if d[0] and d[0].lower().startswith(('vbox', 'npf', 'npcap', 'vm', 'usbpcap', 'hcmon', 'vsock'))]
    print('Third-party virt/capture drivers loaded:', ', '.join(d[0] for d in third))

for p in sys.argv[1:]:
    parse(p)
