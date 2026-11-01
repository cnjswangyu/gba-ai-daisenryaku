#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""读 logs/state_dump.txt + ROM 兵种表，输出战场态势与交战建议。

用法: python tools/advise.py
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "roms" / "0219 - Daisenryaku.gba"
DUMP = ROOT / "logs" / "state_dump.txt"
BASE = 0x08000000
UNIT_TABLE = 0x08798A98
STRIDE = 0x5C

# 运行时 kind → 用于估算的 ROM 兵种（以我方实测 kind 为锚）
KIND_REP = {0x04: "軽歩兵", 0x05: "74式", 0x06: "FH70", 0x28: "補給車", 0x01: "軽歩兵"}
KIND_NAME = {0x04: "歩兵", 0x05: "坦克", 0x06: "自行炮", 0x28: "补给车", 0x01: "装甲/侦察"}


def s_at(d: bytes, va: int, n: int = 20) -> str:
    o = va - BASE
    raw = d[o:o + n]
    e = raw.find(b"\x00")
    if e >= 0:
        raw = raw[:e]
    for enc in ("cp932", "shift_jis"):
        try:
            return raw.decode(enc).strip()
        except Exception:
            pass
    return ""


def load_types() -> dict[str, list[int]]:
    d = ROM.read_bytes()
    out = {}
    for i in range(400):
        o = UNIT_TABLE - BASE + i * STRIDE
        if o + STRIDE > len(d):
            break
        p = struct.unpack_from("<I", d, o)[0]
        nm = s_at(d, p)
        if not nm or not (1 <= d[o + 0x0D] <= 20):
            continue
        out.setdefault(nm, list(d[o + 0x14:o + 0x19]))
    return out


def find_atk(types: dict[str, list[int]], key: str) -> list[int]:
    """名字模糊匹配（ROM 里是 '74式 MBT' 这种）"""
    key = key.replace(" ", "").lower()
    for nm, atk in types.items():
        if key in nm.replace(" ", "").lower():
            return atk
    return [0, 0, 0, 0, 0]


def hdist(a: tuple[int, int], b: tuple[int, int]) -> int:
    """六角格近似距离（坐标步长为 1，取 Chebyshev 近似）"""
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def main() -> None:
    types = load_types()
    factions, ours, enemies, cursor = {}, [], [], None
    for line in DUMP.read_text(encoding="utf-8").splitlines():
        f = line.split()
        if not f or f[0].startswith("#"):
            continue
        if f[0] == "FACTION":
            factions[int(f[1])] = dict(funds=int(f[2].split("=")[1]),
                                       cap=tuple(int(v) for v in f[3].split("=")[1].split(",")))
        elif f[0] == "CURSOR":
            cursor = (int(f[1]), int(f[2]))
        elif f[0] == "UNIT":
            rec = dict(side=f[1], idx=int(f[2]), pos=(int(f[3]), int(f[4])),
                       fuel=int(f[5]), attr=int(f[6]), acted=int(f[7]), kind=int(f[8]))
            (ours if f[1] == "US" else enemies).append(rec)

    print(f"势力: {factions}")
    print(f"我方 {len(ours)} 单位 / 敌方 {len(enemies)} 单位 / 光标 {cursor}")
    ecap = factions.get(1, {}).get("cap")
    print(f"敌方首都 {ecap}")

    # 每个我方单位到敌方首都的距离
    if ecap:
        print("\n=== 推进距离（到敌方首都）===")
        for u in sorted(ours, key=lambda r: hdist(r["pos"], ecap)):
            print(f"  {u['pos']} kind={KIND_NAME.get(u['kind'],'?'):6s} 燃料{u['fuel']:3d} "
                  f"距首都 {hdist(u['pos'], ecap):2d}")

    # 敌方威胁排序（离我最近的）
    print("\n=== 敌方最近单位 ===")
    for e in sorted(enemies, key=lambda r: min(hdist(r["pos"], u["pos"]) for u in ours))[:8]:
        dmin = min(hdist(e["pos"], u["pos"]) for u in ours)
        print(f"  {e['pos']} kind={KIND_NAME.get(e['kind'],'?'):6s} 距我最近 {dmin:2d} 格")

    # 交战评估：假设我方最强单位（kind 5 坦克）对被评估目标
    tank = next((u for u in ours if u["kind"] == 0x05), None)
    if tank:
        my_atk = find_atk(types, "74式")
        print("\n=== 交战评估（74式 视角，未计地形）===")
        for e in sorted(enemies, key=lambda r: hdist(r["pos"], tank["pos"]))[:6]:
            rep = KIND_REP.get(e["kind"], "軽歩兵")
            their = find_atk(types, rep)
            cls = 1 if e["kind"] in (0x05, 0x06, 0x01) else 2   # 装甲类 / 人员类
            mine = my_atk[cls]
            back = their[cls]
            verdict = "可打" if mine > back * 1.5 else ("勉强" if mine > back else "亏，别打")
            print(f"  对 {e['pos']} {KIND_NAME.get(e['kind'],'?'):6s} 类别{cls}: "
                  f"我 {mine:3d} / 它 {back:3d}   → {verdict}")

    print("\n建议:")
    print("  1) 敌主力在北侧(y14-25)，我方需先北上集结，别单兵突进")
    print("  2) 步兵(kind4)对空25、耐6，适合顶前排；坦克在后，自行炮隔格支援")
    print("  3) 打之前用 damage_calc.py 算双方伤害，我<它就不打")


if __name__ == "__main__":
    main()
