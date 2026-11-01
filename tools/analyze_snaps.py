#!/usr/bin/env python3
"""分析 boot_snaps 快照，找"界面状态变量"候选。
对 Combined WRAM（EWRAM 256K + IWRAM 32K）每个 4 字节对齐的字，
提取它在 95 个界面快照上的取值序列，筛选：
  - 取值集合大小 >= 8（随界面反复变化）
  - 所有取值都 < 256（小整数，像状态号而不是坐标/指针）
  - 变化次数 >= 20（不是写一次就恒定）
"""
import glob, re, os, collections

SNAP = r"D:\prog\gba-ai\logs\boot_snaps"
tags = sorted({f.split("_")[0] for f in os.listdir(SNAP) if f.endswith("_iwram.bin")})
tags = [t for t in tags if re.fullmatch(r"s\d+", t)]
tags.sort(key=lambda t: int(t[1:]))
print(f"快照数: {len(tags)}")

# 内存布局：EWRAM 0x02000000 (256K) + IWRAM 0x03000000 (32K)
def load(tag):
    e = open(os.path.join(SNAP, tag + "_ewram.bin"), "rb").read()
    i = open(os.path.join(SNAP, tag + "_iwram.bin"), "rb").read()
    return e, i

snaps = [load(t) for t in tags]
EW_LEN = len(snaps[0][0])
IW_LEN = len(snaps[0][1])
print(f"EWRAM {EW_LEN:#x}  IWRAM {IW_LEN:#x}")

cands = []
# EWRAM 区
for base in range(0, EW_LEN - 3, 4):
    vals = []
    for e, i in snaps:
        vals.append(int.from_bytes(e[base:base+4], "little"))
    s = set(vals)
    if len(s) < 8: continue
    if max(s) > 255: continue
    changes = sum(1 for k in range(1, len(vals)) if vals[k] != vals[k-1])
    if changes < 20: continue
    cands.append((0x02000000 + base, vals, changes))
# IWRAM 区
for base in range(0, IW_LEN - 3, 4):
    vals = []
    for e, i in snaps:
        vals.append(int.from_bytes(i[base:base+4], "little"))
    s = set(vals)
    if len(s) < 8: continue
    if max(s) > 255: continue
    changes = sum(1 for k in range(1, len(vals)) if vals[k] != vals[k-1])
    if changes < 20: continue
    cands.append((0x03000000 + base, vals, changes))

cands.sort(key=lambda c: -c[2])
print(f"\n候选状态变量 {len(cands)} 个（按变化次数排序，前 25）:\n")
for addr, vals, ch in cands[:25]:
    seq = " ".join(f"{v:X}" for v in vals[:40])
    print(f"0x{addr:08X} 变化{ch:3d}次 取值{len(set(vals)):2d}种  序列: {seq}{' ...' if len(vals)>40 else ''}")

# 另外：单字节粒度也扫一遍（状态可能只占 1 字节）
print("\n=== 单字节粒度候选（IWRAM，小整数高频变化） ===")
bc = []
for base in range(0, IW_LEN):
    vals = [i[base] for e, i in snaps]
    s = set(vals)
    if len(s) < 10 or max(s) > 100: continue
    ch = sum(1 for k in range(1, len(vals)) if vals[k] != vals[k-1])
    if ch < 30: continue
    bc.append((0x03000000 + base, vals, ch))
bc.sort(key=lambda c: -c[2])
for addr, vals, ch in bc[:15]:
    seq = " ".join(f"{v:X}" for v in vals[:40])
    print(f"0x{addr:08X} 变化{ch:3d}次 取值{len(set(vals)):2d}种  序列: {seq}{' ...' if len(vals)>40 else ''}")
