import struct

rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()

def txt(a):
    off = a - 0x08000000
    if not (0x08000000 <= a < 0x0A000000):
        return None
    end = rom.find(b'\x00', off)
    s = rom[off:end].decode('shift_jis', 'replace')
    return s if len(s) < 40 else s[:37] + '...'

# 6 个地图结构 @ 0x087A3F04, stride 8: {u8 w, u8 h, u16 pad, u32 data}
base = 0x087A3F04
print('=== 6 个网格结构 ===')
for i in range(6):
    a = base + i * 8
    w, h = rom[a - 0x08000000], rom[a - 0x08000000 + 1]
    ptr = struct.unpack_from('<I', rom, a - 0x08000000 + 4)[0]
    print(f'结构[{i}] @0x{a:08X}: w={w} h={h} data=0x{ptr:08X}')
    # dump 网格 (h 行 x w 列, u32)
    if 0x08000000 <= ptr < 0x0A000000:
        print(f'  网格内容 ({h}行 x {w}列):')
        for r in range(h):
            row = []
            for c in range(w):
                v = struct.unpack_from('<I', rom, ptr - 0x08000000 + (r * w + c) * 4)[0]
                row.append(f'{v:08X}')
            print(f'    row{r}: ' + ' '.join(row))
    # 结构后面可能跟名字指针: data 之后 h*w*4 字节
    if 0x08000000 <= ptr < 0x0A000000:
        after = ptr + w * h * 4
        print(f'  data 之后 0x{after:08X} 起的字: ' +
              ' '.join(f'{struct.unpack_from("<I", rom, after - 0x08000000 + k * 4)[0]:08X}' for k in range(6)))
        for k in range(6):
            p = struct.unpack_from('<I', rom, after - 0x08000000 + k * 4)[0]
            if 0x08000000 <= p < 0x0A000000:
                print(f'    [{k}] 0x{p:08X} -> {txt(p)!r}')
