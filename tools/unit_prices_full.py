import struct
rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()
def txt(a):
    off = a - 0x08000000
    if not (0x08000000 <= a < 0x0D000000):
        return None
    end = rom.find(b'\x00', off)
    s = rom[off:end].decode('shift_jis', 'replace')
    return s
base = 0x08798A98
STRIDE = 0x5C
print('ID    name                          kind price  (kind: 12/13=航空?)')
for i in range(1, 400):
    a = base + i * STRIDE
    off = a - 0x08000000
    if off + STRIDE > len(rom):
        break
    nameptr = struct.unpack_from('<I', rom, off)[0]
    name = txt(nameptr)
    if name is None:
        continue
    kind = rom[off + 6]
    price = struct.unpack_from('<H', rom, off + 0x1A)[0]
    if 200 <= i <= 360:
        print(f'{i:4d}  {name[:26]:28}  {kind:3d}  {price:5d}')
