import struct

rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()

def txt(a):
    off = a - 0x08000000
    if not (0x08000000 <= a < 0x0A000000):
        return None
    end = rom.find(b'\x00', off)
    s = rom[off:end].decode('shift_jis', 'replace')
    return s if len(s) < 40 else s[:37] + '...'

def dump(lo, hi, label=''):
    print(f'=== ROM 0x{lo:08X}-0x{hi:08X} {label} ===')
    for a in range(lo, hi, 4):
        v = struct.unpack_from('<I', rom, a - 0x08000000)[0]
        note = ''
        if 0x08000000 <= v < 0x0A000000:
            t = txt(v)
            if t and len(t) >= 1 and any(ord(c) > 0x80 for c in t[:2]):
                note = f' -> {t!r}'
        print(f'  0x{a:08X}: {v:08X}{note}')

# 剧本数据 0x08762B10 (軍事演習1)
dump(0x08762B10, 0x08762BC0, '剧本数据 軍事演習1')
