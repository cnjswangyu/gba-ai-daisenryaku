#!/usr/bin/env python3
"""扫全部界面快照，找出 RAM 里指向 ROM 数据区的指针（u32，范围 0x08040000-0x087FFFFF）。
这就是"ROM 数据如何进入界面"的真实路径：界面结构体里存 ROM 数据指针，渲染时按指针取字段。
"""
import os, collections

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()
SNAP = r"D:\prog\gba-ai\logs\boot_snaps"
tags = sorted((f.split("_")[0] for f in os.listdir(SNAP) if f.endswith("_iwram.bin")),
              key=lambda t: int(t[1:]))
LO, HI = 0x08040000, 0x08800000

def sjis(b):
    out = []; i = 0
    while i < len(b):
        c = b[i]
        if c == 0: out.append(' '); i += 1; continue
        if 0x81 <= c <= 0x9F or 0xE0 <= c <= 0xEF:
            if i + 1 < len(b):
                try: out.append(bytes([c, b[i+1]]).decode('shift_jis')); i += 2; continue
                except Exception: pass
        out.append(chr(c) if 32 <= c < 127 else '.')
        i += 1
    return ''.join(out)

def rom_str(a, n=12):
    off = a - 0x08000000
    if 0 <= off < len(ROM) - n:
        s = sjis(ROM[off:off+n])
        s = s.replace('\x00', ' ').strip()
        if len(s) >= 2 and sum(1 for ch in s if ch != '.') >= 2: return s
    return ""

# 每个界面：ROM 指针按目标地址聚合
print(f"{'界面':>5} {'ROM指针命中':>8}  主要目标(计数)")
for t in tags:
    counters = collections.Counter()
    for reg, base in (("ewram", 0x02000000), ("iwram", 0x03000000)):
        d = open(os.path.join(SNAP, f"{t}_{reg}.bin"), "rb").read()
        for off in range(0, len(d) - 3, 4):
            v = int.from_bytes(d[off:off+4], "little")
            if LO <= v < HI:
                counters[v] += 1
    if not counters:
        print(f"{t:>5} {0:>8}")
        continue
    top = counters.most_common(6)
    desc = "  ".join(f"0x{a:08X}({rom_str(a) or '数据'})x{c}" for a, c in top)
    print(f"{t:>5} {sum(counters.values()):>8}  {desc}")

# 全周期汇总：哪些 ROM 区域被指针引用最多
allc = collections.Counter()
for t in tags:
    for reg, base in (("ewram", 0x02000000), ("iwram", 0x03000000)):
        d = open(os.path.join(SNAP, f"{t}_{reg}.bin"), "rb").read()
        for off in range(0, len(d) - 3, 4):
            v = int.from_bytes(d[off:off+4], "little")
            if LO <= v < HI: allc[v] += 1
print("\n=== 全周期被引用最多的 ROM 地址 top30 ===")
for a, c in allc.most_common(30):
    print(f"  0x{a:08X} x{c:<4} {rom_str(a) or ''}")
