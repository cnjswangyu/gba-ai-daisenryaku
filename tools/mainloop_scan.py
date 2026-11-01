#!/usr/bin/env python3
"""聚合 boot_trace.txt 全部 95 个界面的 PC 直方图：
找出在最多界面里出现的 PC —— 主循环/调度器的特征。
同时输出"只在少数界面出现"的 PC —— 各界面专属函数。
"""
import re, collections

txt = open(r"D:\prog\gba-ai\logs\boot_trace.txt", encoding="utf-8", errors="replace").read()

# 解析每个 SCREEN 的 PC 直方图
screens = {}   # tag -> Counter(pc)
cur = None
in_hist = False
for line in txt.splitlines():
    m = re.match(r"===== SCREEN (\d+)\s+tag=(\w+)", line)
    if m:
        cur = m.group(2)
        screens[cur] = collections.Counter()
        in_hist = False
        continue
    if cur and "PC 直方图" in line:
        in_hist = True
        continue
    if in_hist:
        m = re.match(r"\s+(0x[0-9A-Fa-f]+)\s+x(\d+)", line)
        if m:
            screens[cur][m.group(1)] += int(m.group(2))
        elif line.strip() and not line.startswith("    "):
            in_hist = False

N = len(screens)
print(f"共 {N} 个界面\n")

# 1) 每个 PC 出现在多少个界面里
pc_screens = collections.defaultdict(set)
for tag, c in screens.items():
    for pc in c:
        pc_screens[pc].add(tag)

# 主循环候选：出现在 >=90% 界面
print("=== 出现在 >=85% 界面的 PC（主循环/调度器候选）===")
for pc, tags in sorted(pc_screens.items(), key=lambda kv: -len(kv[1])):
    if len(tags) >= N * 0.85:
        tot = sum(c[pc] for c in screens.values())
        print(f"  {pc}  界面数 {len(tags):>3}/{N}  总采样 {tot}")

# 2) 每个界面的 top3 PC（看专属函数）
print("\n=== 各界面 top3 PC（专属于该界面的函数）===")
for tag in sorted(screens, key=lambda t: int(t[1:])):
    c = screens[tag]
    top = c.most_common(3)
    print(f"  {tag}: " + "  ".join(f"{pc}x{n}" for pc, n in top))
