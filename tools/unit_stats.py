import struct
rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()
def txt(a):
    off = a - 0x08000000
    if not (0x08000000 <= a < 0x0D000000):
        return None
    end = rom.find(b'\x00', off)
    return rom[off:end].decode('shift_jis', 'replace')
base = 0x08798A98
STRIDE = 0x5C
cands = [186, 187, 188, 189, 190, 191, 197, 199, 202, 205, 228, 208, 210, 216, 234, 241, 242, 250, 222, 339, 300, 290, 291, 293, 295, 298]
for i in cands:
    off = base + i * STRIDE - 0x08000000
    rec = rom[off:off+STRIDE]
    name = txt(struct.unpack_from('<I', rec, 0)[0])
    kind = rec[6]
    price = struct.unpack_from('<H', rec, 0x1A)[0]
    # 猜字段: 每 2 字节看成 u16
    vals = struct.unpack_from('<22H', rec, 0)
    print(f'ID {i:3d} {str(name)[:16]:18} kind={kind:2d} price={price:4d}')
    print('   u16[0..21]:', ' '.join(f'{v}' for v in vals))
