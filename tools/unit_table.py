#!/usr/bin/env python3
"""解出单位主数据表：0x0879D2D4 附近区域。
每项推测: [名字指针 u32][若干属性]。前后扫，找表边界与规律。
"""
import struct

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()

def u32(a): return struct.unpack_from("<I", ROM, a - 0x08000000)[0]
def u16(a): return struct.unpack_from("<H", ROM, a - 0x08000000)[0]

def sjis_at(a, n=16):
    off = a - 0x08000000
    b = ROM[off:off+n]
    out = []
    i = 0
    while i < len(b):
        c = b[i]
        if c == 0: break
        if 0x81 <= c <= 0x9F or 0xE0 <= c <= 0xEF:
            if i + 1 < len(b):
                try: out.append(bytes([c, b[i+1]]).decode("shift_jis")); i += 2; continue
                except Exception: pass
        out.append(chr(c) if 32 <= c < 127 else ".")
        i += 1
    return "".join(out)

# 向前向后找"名字指针"模式：u32 值落在 0x08067000-0x08068000 (单位名文本区)
print("=== 单位名文本区 (0x08067400-0x08067A00) ===")
a = 0x08067400
while a < 0x08067A00:
    s = sjis_at(a, 12)
    if len(s) >= 2 and not all(ch == "." for ch in s):
        print(f"  0x{a:08X}: {s!r}")
    a += 1

print("\n=== 单位表候选区 0x0879D200-0x0879D400: 每16字节一行 ===")
for a in range(0x0879D200, 0x0879D400, 16):
    vals = [u32(a + i * 4) for i in range(4)]
    desc = []
    for v in vals:
        if 0x08067000 <= v < 0x08067C00:
            desc.append(f"\"{sjis_at(v, 10)}\"")
    print(f"  0x{a:08X}: " + " ".join(f"{v:08X}" for v in vals) + ("   " + " ".join(desc) if desc else ""))
