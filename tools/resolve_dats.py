import struct, re
rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()
src = open('D:/prog/gba-ai/logs/main22.c', encoding='utf-8', errors='replace').read()
dats = sorted(set(re.findall(r'_DAT_([0-9a-fA-F]{8})', src)))
for d in dats:
    a = int(d, 16)
    off = a - 0x08000000
    if 0 <= off <= len(rom) - 4:
        v = struct.unpack_from('<I', rom, off)[0]
        print(f'_DAT_{d} -> 0x{v:08X}')
    else:
        print(f'_DAT_{d} -> (out of ROM)')
