import struct

rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()

def txt(a):
    off = a - 0x08000000
    if not (0x08000000 <= a < 0x0D000000):
        return None
    end = rom.find(b'\x00', off)
    s = rom[off:end].decode('shift_jis', 'replace')
    return s if len(s) < 30 else s[:27] + '...'

base = 0x08798A98
STRIDE = 0x5C

# 先确认 ROM 大小
print(f'ROM size = {len(rom):08X} ({len(rom)} bytes)')

# dump 前 40 条的价格(+0x1A)和类别(+0x06)
print('=== 单位表前 40 条: ID / 名 / 类别 / 价格 ===')
rows = []
for i in range(1, 60):
    a = base + i * STRIDE
    off = a - 0x08000000
    if off + STRIDE > len(rom):
        break
    nameptr = struct.unpack_from('<I', rom, off)[0]
    name = txt(nameptr)
    kind = rom[off + 6]
    price = struct.unpack_from('<H', rom, off + 0x1A)[0]
    if name:
        rows.append((i, name, kind, price))

for i, name, kind, price in rows[:45]:
    print(f'  ID {i:3d} (0x{i:03X}): {name!r:24} kind={kind:3d} price={price}')
