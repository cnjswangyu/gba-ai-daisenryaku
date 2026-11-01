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
buckets = {}
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
    buckets.setdefault(kind, []).append((i, name, price))
names = {0:'步兵/APC',1:'工兵',2:'侦察/轻车',3:'坦克',4:'ATGM',5:'火炮',6:'防空',7:'补给',12:'飞机',13:'攻击机',19:'?',20:'舰船'}
for k in sorted(buckets):
    print(f'--- kind={k} ({names.get(k,"?")}) ---')
    seen = {}
    for i, n, p in buckets[k]:
        seen.setdefault(n, []).append(i)
    for n, ids in seen.items():
        print(f'  {n[:24]:26} ids={ids[:6]}')
