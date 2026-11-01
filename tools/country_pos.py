import struct

rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()

def txt(a):
    off = a - 0x08000000
    if not (0x08000000 <= a < 0x0A000000):
        return None
    end = rom.find(b'\x00', off)
    s = rom[off:end].decode('shift_jis', 'replace')
    return s if len(s) < 40 else s[:37] + '...'

# func_08005338 的字面量池 (函数尾 0x08005440-0x080054A0)
print('=== func_08005338 字面量池 ===')
for a in range(0x08005440, 0x080054A8, 4):
    v = struct.unpack_from('<I', rom, a - 0x08000000)[0]
    tag = ''
    if 0x02000000 <= v < 0x02040000:
        tag = ' [EWRAM]'
    elif 0x03000000 <= v < 0x03008000:
        tag = ' [IWRAM]'
    elif 0x08000000 <= v < 0x0A000000:
        tag = ' [ROM]'
    print(f'  0x{a:08X}: {v:08X}{tag}')

# _DAT_080053e4 和 _DAT_08005464: 光标位置表 (7 项 x 2 字节)
for lit in [0x080053E4, 0x08005464]:
    tbl = struct.unpack_from('<I', rom, lit - 0x08000000)[0]
    print(f'\n=== 位置表 _DAT_{lit:08X} -> 0x{tbl:08X} ===')
    if 0x08000000 <= tbl < 0x0A000000:
        for i in range(8):
            x, y = rom[tbl - 0x08000000 + i * 2], rom[tbl - 0x08000000 + i * 2 + 1]
            print(f'  国家[{i}]: 光标=({x}, {y}) -> 屏幕=({x - 8 if x >= 8 else x}, {y - 5 if y >= 5 else y})')
