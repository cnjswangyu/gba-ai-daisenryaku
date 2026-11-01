#!/usr/bin/env python3
"""在 95 个界面快照里搜索已知 ROM 数据块的副本。
ROM 数据块来源：
  - 兵种表记录（0x08798A98 + idx*0x5C，步长 92）
  - 地形名指针数组 0x08761664
  - ROM 头 0x08000000
若某块 ROM 数据出现在某界面的 RAM/VRAM 里，说明该界面把这份数据读进去了。
"""
import os, sys

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()
SNAP = r"D:\prog\gba-ai\logs\boot_snaps"
tags = sorted((f.split("_")[0] for f in os.listdir(SNAP) if f.endswith("_iwram.bin")),
              key=lambda t: int(t[1:]))

UNIT_BASE = 0x08798A98
def unit_off(idx): return UNIT_BASE - 0x08000000 + idx * 0x5C

# 关键 ROM 数据块：名字 + 取前 24 字节作签名
PROBES = {
    "74式MBT记录":   unit_off(200),
    "FH70记录":      0x0879DF68 - 0x08000000,
    "軽歩兵记录":    0x0879F668 - 0x08000000,
    "地形名指针数组": 0x08761664 - 0x08000000,
    "ROM头":         0x00000000,
    "表B地形防御":   0x080470C5 - 0x08000000,
}
SIGLEN = 24
for name, off in PROBES.items():
    sig = ROM[off:off + SIGLEN]
    if len(sig) < SIGLEN:
        print(f"{name}: ROM 偏移越界 {off:#x}"); continue
    hits = []
    for t in tags:
        for reg, base in (("ewram", 0x02000000), ("iwram", 0x03000000), ("vram", 0x06000000)):
            d = open(os.path.join(SNAP, f"{t}_{reg}.bin"), "rb").read()
            i = d.find(sig)
            while i != -1:
                hits.append((t, reg, base + i))
                i = d.find(sig, i + 1)
    if hits:
        print(f"\n### {name} (ROM {0x08000000+off:#x}) 出现在:")
        byscreen = {}
        for t, reg, a in hits: byscreen.setdefault(t, []).append(f"{reg}@0x{a:08X}")
        for t in sorted(byscreen, key=lambda x: int(x[1:])):
            print(f"   {t}: {' '.join(byscreen[t][:6])}")
    else:
        print(f"\n### {name} (ROM {0x08000000+off:#x}): 任何界面都未整块复制（按需字段读取）")
