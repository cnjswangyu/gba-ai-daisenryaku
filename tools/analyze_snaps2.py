#!/usr/bin/env python3
"""放宽条件，列出 Combined WRAM 中变化最频繁的字，附界面边界对齐显示。
界面边界（来自 boot_trace.txt 的 95 条记录）已标注在序列下方。"""
import os, re

SNAP = r"D:\prog\gba-ai\logs\boot_snaps"
tags = sorted((f.split("_")[0] for f in os.listdir(SNAP) if f.endswith("_iwram.bin")),
              key=lambda t: int(t[1:]))
snaps = [(open(os.path.join(SNAP, t + "_ewram.bin"), "rb").read(),
          open(os.path.join(SNAP, t + "_iwram.bin"), "rb").read()) for t in tags]
N = len(tags)

# 界面名（人工标注，来自截图核对）
NAMES = {}
for i in range(N):
    n = i + 1
    if n <= 2: NAMES[n] = "开机图"
    elif n <= 6: NAMES[n] = "LOGO"
    elif n <= 14: NAMES[n] = "标题"
    elif n <= 16: NAMES[n] = "主菜单"
    elif n <= 18: NAMES[n] = "姓名提示"
    elif n <= 31: NAMES[n] = "假名键盘"
    elif n <= 34: NAMES[n] = "国家"
    elif n <= 37: NAMES[n] = "国歌"
    elif n <= 49: NAMES[n] = "确认/存档"
    elif n <= 59: NAMES[n] = "存档/情报"
    elif n <= 72: NAMES[n] = "剧本选择"
    elif n <= 90: NAMES[n] = "出击编成"
    else: NAMES[n] = "战场"

def words(buf, base):
    out = []
    for off in range(0, len(buf) - 3, 4):
        out.append((base + off, int.from_bytes(buf[off:off+4], "little")))
    return out

allw = {}
for e, i in snaps:
    for a, v in words(e, 0x02000000): allw.setdefault(a, []).append(v)
    for a, v in words(i, 0x03000000): allw.setdefault(a, []).append(v)

scored = []
for a, vals in allw.items():
    ch = sum(1 for k in range(1, N) if vals[k] != vals[k-1])
    if ch >= 15:
        scored.append((ch, a, vals))
scored.sort(key=lambda x: -x[0])
print(f"共 {len(scored)} 个字变化>=15次，前 30：\n")
for ch, a, vals in scored[:30]:
    seq = " ".join(f"{v:X}" for v in vals)
    print(f"0x{a:08X} ch={ch:2d} | {seq}")

# 打印界面名边界条
print("\n界面边界（每格一个界面）:")
print(" ".join(NAMES[i+1][:2] for i in range(N)))
