#!/usr/bin/env python3
"""分析出击编成表界面：
1. s72 -> s73 (进入编成表) IWRAM/EWRAM 差异：界面初始化写了什么
2. 解出界面持有的 ROM 指针 0x08093500 数据
3. 编成表界面 RAM 里指向 0x03002BE2(我方单位表) 的引用
"""
import struct, os

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()
SNAP = r"D:\prog\gba-ai\logs\boot_snaps"

def load(tag, reg):
    return open(os.path.join(SNAP, f"{tag}_{reg}.bin"), "rb").read()

def diff_regions(a, b, base, minlen=4):
    """返回 [(addr, old, new)]"""
    out = []
    n = min(len(a), len(b))
    i = 0
    while i < n:
        if a[i] != b[i]:
            j = i
            while j < n and a[j] != b[j]: j += 1
            if j - i >= minlen:
                out.append((base + i, a[i:j], b[i:j]))
            i = j
        else:
            i += 1
    return out

print("=== s72 -> s73 进入出击编成表的 IWRAM 差异 ===")
a, b = load("s72", "iwram"), load("s73", "iwram")
for addr, old, new in diff_regions(a, b, 0x03000000):
    # 只打 u32 可读的
    print(f"  0x{addr:08X}: {old[:16].hex()} -> {new[:16].hex()}  ({len(new)}B)")

print("\n=== s73 EWRAM 差异 ===")
a, b = load("s72", "ewram"), load("s73", "ewram")
for addr, old, new in diff_regions(a, b, 0x02000000)[:40]:
    print(f"  0x{addr:08X}: {old[:16].hex()} -> {new[:16].hex()}  ({len(new)}B)")

# ROM 0x08093500 数据结构
off = 0x08093500 - 0x08000000
print(f"\n=== ROM 0x08093500 前 512 字节 ===")
d = ROM[off:off+512]
for i in range(0, 512, 16):
    row = d[i:i+16]
    hexs = " ".join(f"{x:02X}" for x in row)
    asc = "".join(chr(x) if 32 <= x < 127 else "." for x in row)
    print(f"  0x{0x08093500+i:08X}: {hexs}  {asc}")

# 该界面的单位表: 0x03002BE2 步长24
print("\n=== s73 我方单位表 0x03002BE2 前 12 个单位 (步长24) ===")
iw = load("s73", "iwram")
base = 0x03002BE2 - 0x03000000
for u in range(12):
    r = iw[base + u*24: base + u*24 + 24]
    if all(x == 0 for x in r): continue
    x, y, hp = r[0], r[1], r[2]
    kind = r[6]
    print(f"  单位{u}: x={x} y={y} hp={hp} 兵种={kind}  原始: {r.hex()}")
