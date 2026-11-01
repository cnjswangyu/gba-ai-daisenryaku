"""check_keys.py — 核对 / 修复 BizHawk 里与 S 键相关的绑定

背景（为什么会有"S 键歧义"）：S 在两个表里含义不同
  AllTrollers           → GBA "Left": "S"   （S = 方向左，这是想要的唯一含义）
  AllTrollersAutoFire   → GBA "A": "S"      （S = A 连发 → 按住 S 会"左移 + 连打 A"）
  HotkeyBindings        → "Toggle Turbo Seek": "Shift+S"  （含 S 的组合键，易误触）

要点：BizHawk 只在启动时读 config.ini、退出时会回写。
      所以"先关掉所有实例 → 再改 → 再启动"，否则改动会被退出时的回写冲掉。

用法（项目根目录）：
    python tools/check_keys.py            # 只读核对
    python tools/check_keys.py --apply    # 修正为规范值（要求没有 EmuHawk 在跑）
"""
from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "tools" / "config.ini"

WANT_AUTOFIRE = {"B": "O", "A": "U"}   # 连发：O = B连发，U = A连发（避开 S / A）
WANT_TURBO = "Shift+T"                 # 原 Shift+S
WANT_LEFT = "S"                        # 主键位：S = GBA 方向左


def emu_running() -> list[str]:
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq EmuHawk.exe"],
                         capture_output=True, text=True, errors="replace").stdout
    return [l.strip() for l in out.splitlines() if "EmuHawk.exe" in l]


def block_start(lines: list[str], section: str) -> int:
    sec = next(i for i, l in enumerate(lines) if f'"{section}"' in l)
    return next(i for i in range(sec, len(lines)) if '"GBA Controller"' in lines[i])


def read_bind(lines: list[str], start: int, n: int = 14) -> dict[str, str]:
    """读取一个控制器块的 键=值；遇到下一个块（以 { 结尾的行）即停。"""
    out: dict[str, str] = {}
    for i in range(start + 1, min(start + 1 + n, len(lines))):
        line = lines[i]
        if line.rstrip().endswith("{"):        # 进入下一个块，停止
            break
        m = re.match(r'\s*"([^"]+)":\s*"([^"]*)",?\s*$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="修正为规范值")
    a = ap.parse_args()

    if not CFG.exists():
        print(f"找不到 {CFG}")
        return 2

    lines = CFG.read_text(encoding="utf-8").splitlines(keepends=True)
    main_start = block_start(lines, "AllTrollers")
    af_start = block_start(lines, "AllTrollersAutoFire")
    main_bind = read_bind(lines, main_start)
    af_bind = read_bind(lines, af_start)

    turbo_idx, turbo_val = None, None
    for i, l in enumerate(lines):
        if '"Toggle Turbo Seek"' in l:
            m = re.search(r'"([^"]*)"\s*,\s*$', l)
            turbo_idx, turbo_val = i, (m.group(1) if m else "?")

    print("== GBA 主键位 (AllTrollers) ==")
    print("   " + "  ".join(f"{k}={v or '—'}" for k, v in main_bind.items()))
    print("== GBA 连发键位 (AllTrollersAutoFire) ==")
    print("   " + "  ".join(f"{k}={v or '—'}" for k, v in af_bind.items()))
    print(f"== 热键 Toggle Turbo Seek = {turbo_val}")

    problems: list[str] = []
    if main_bind.get("Left") != WANT_LEFT:
        problems.append(f'主键位 Left 应为 {WANT_LEFT}，当前 {main_bind.get("Left")!r}')
    for btn, want in WANT_AUTOFIRE.items():
        cur = af_bind.get(btn)
        if cur != want:
            extra = "（与主键位 S 冲突：按住 S 会连打 A）" if cur == "S" else ""
            problems.append(f"连发键位 {btn} 应为 {want}，当前 {cur!r}{extra}")
    if turbo_val is not None and turbo_val != WANT_TURBO:
        problems.append(f"Toggle Turbo Seek 应为 {WANT_TURBO}，当前 {turbo_val!r}")

    if not problems:
        print("\n[OK] 键位规范：S 的唯一含义 = GBA 方向左（无连发/热键冲突）")
        print("     前提：当前模拟器是在本次修改之后启动的。")
        return 0

    print("\n[问题]")
    for p in problems:
        print("   - " + p)

    if not a.apply:
        print("\n（只读核对）加 --apply 修正；修正前请先关闭所有 EmuHawk 实例。")
        return 1

    running = emu_running()
    if running:
        print("\n[中止] 检测到 EmuHawk 仍在运行——它退出时会回写旧值，改了也会被冲掉：")
        for r in running:
            print("   " + r)
        print("   请先关闭它，再运行 --apply。")
        return 3

    for off in range(1, 15):
        ln = af_start + off
        m = re.match(r'(\s*"([^"]+)":\s*)"([^"]*)"(,?)(\s*)$', lines[ln])
        if m and m.group(2) in WANT_AUTOFIRE and m.group(3) != WANT_AUTOFIRE[m.group(2)]:
            lines[ln] = f'{m.group(1)}"{WANT_AUTOFIRE[m.group(2)]}"{m.group(4)}{m.group(5)}'
    if turbo_idx is not None and turbo_val != WANT_TURBO:
        lines[turbo_idx] = lines[turbo_idx].replace(f'"{turbo_val}"', f'"{WANT_TURBO}"')

    CFG.write_text("".join(lines), encoding="utf-8")
    print("\n[已修正] 连发 B=O / A=U，Toggle Turbo Seek=Shift+T")
    print("          现在可以启动模拟器（S = 方向左，唯一含义）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
