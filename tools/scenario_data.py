#!/usr/bin/env python3
"""1. 找单位名文本在 ROM 的位置 (shift_jis)
2. 解出剧本数据区 0x08762B10 附近的结构
3. 找单位名指针数组（指向名字文本的 u32 指针表）
"""
import struct

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()

def find_text(s, enc="shift_jis"):
    b = s.encode(enc)
    hits = []
    off = 0
    while True:
        i = ROM.find(b, off)
        if i < 0: break
        hits.append(0x08000000 + i)
        off = i + 1
    return hits

for name in ["74式", "FH70", "軽歩兵", "戦車", "火炮", "軍事演習", "大戦略"]:
    hits = find_text(name)
    print(f"文本 {name!r}: {len(hits)} 处 -> {[hex(h) for h in hits[:12]]}")

# 剧本数据区 dump
def dump(a0, n):
    print(f"\n=== ROM 0x{a0:08X} 起 {n} 字节 ===")
    off = a0 - 0x08000000
    for i in range(0, n, 16):
        row = ROM[off+i:off+i+16]
        hexs = " ".join(f"{x:02X}" for x in row)
        asc = "".join(chr(x) if 32 <= x < 127 else "." for x in row)
        print(f"  0x{a0+i:08X}: {hexs}  {asc}")

dump(0x08762B00, 256)

# 找指向单位名的指针表：扫 0x08760000-0x08770000 里指向 "74式" 文本的 u32
t74 = find_text("74式")
print(f"\n=== 指向 74式文本({[hex(x) for x in t74]}) 的指针 ===")
if t74:
    target = t74[0]
    tb = struct.pack("<I", target)
    off = 0
    cnt = 0
    while cnt < 10:
        i = ROM.find(tb, off)
        if i < 0: break
        print(f"  0x{0x08000000+i:08X} (file 0x{i:06X})")
        off = i + 1
        cnt += 1
