#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""伤害收益评估器 —— 公式来自反编译 FUN_0802008c / FUN_08002a5c。

用法:
  python tools/damage_calc.py                      # 演示：几种典型对局
  python tools/damage_calc.py --list               # 列出兵种表
  python tools/damage_calc.py --atk 74式MBT --def M60A3 --terr 30

公式:
  atk  = rec[+0x14 + 目标类别]        # 目标类别 0=空 1=裝 2=人 3=陸 4=海
  terr = terrain_table[cell-0x10]     # 0/10/20/30（建物 200+ 是耐久，另算）
  r1   = atk * unit_attr // 2550
  rank = rec[+0xF]==1 ? rec[+0xE] : 1
  dmg  = min(999, rank * (atk + terr + r1))
"""
from __future__ import annotations

import argparse
import struct
from pathlib import Path

ROM = Path(__file__).resolve().parent.parent / "roms" / "0219 - Daisenryaku.gba"
BASE = 0x08000000
UNIT_TABLE = 0x08798A98
STRIDE = 0x5C
# 地形加成表（表B），按 cell-0x10 索引
TERR_TABLE = 0x080470C5
TERR_BASE_CELL = 0x10
CLASSES = ["空", "裝", "人", "陸", "海"]


def load_rom() -> bytes:
    return ROM.read_bytes()


def s_at(d: bytes, va: int, n: int = 24) -> str:
    o = va - BASE
    if not (0 <= o < len(d)):
        return ""
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


class Unit:
    def __init__(self, d: bytes, idx: int):
        o = UNIT_TABLE - BASE + idx * STRIDE
        self.idx = idx
        # 名字：通常是 +0x1C 或 +0x20 之类的指针；这里用扫描法找第一个合法字符串指针
        self.name = ""
        for off in (0x00, 0x1C, 0x20, 0x24, 0x18):
            p = struct.unpack_from("<I", d, o + off)[0]
            nm = s_at(d, p, 20)
            if nm and 1 <= len(nm) <= 16 and all(ord(c) > 31 for c in nm):
                self.name = nm
                break
        self.speed = d[o + 0x0D]
        self.durability = d[o + 0x0E]
        self.kind_flag = d[o + 0x0F]
        self.atk = list(d[o + 0x14:o + 0x19])
        self.fuel = d[o + 0x25]
        self.price = d[o + 0x26]
        self.class_id = d[o + 0x04]

    def __repr__(self) -> str:
        return (f"{self.name or '?':14s} idx={self.idx:<4d} spd={self.speed:<3d} "
                f"dur={self.durability:<3d} atk={self.atk} price={self.price}")


def load_units(d: bytes) -> list[Unit]:
    out = []
    for i in range(0, 400):
        o = UNIT_TABLE - BASE + i * STRIDE
        if o + STRIDE > len(d):
            break
        u = Unit(d, i)
        if not u.name:
            continue
        if not (1 <= u.speed <= 20 and 0 <= u.durability <= 20):
            continue
        if not (1 <= u.fuel <= 100):
            continue
        out.append(u)
    return out


def terr_bonus(d: bytes, cell_id: int) -> int:
    if cell_id < TERR_BASE_CELL:
        return 0
    o = TERR_TABLE - BASE + (cell_id - TERR_BASE_CELL)
    return d[o] if 0 <= o < len(d) else 0


def damage(d: bytes, atk: Unit, dfn: Unit, target_class: int,
           terr: int = 0, rank: int = 1, unit_attr: int = 0) -> int:
    a = atk.atk[target_class]
    if a == 0:
        return 0
    r1 = a * unit_attr // 2550
    return min(999, rank * (a + terr + r1))


def find(units: list[Unit], key: str) -> Unit | None:
    key = key.replace(" ", "").lower()
    for u in units:
        if key in u.name.replace(" ", "").lower():
            return u
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--atk")
    ap.add_argument("--def", dest="dfn")
    ap.add_argument("--terr", type=int, default=0, help="地形加成 0/10/20/30")
    ap.add_argument("--class", dest="tclass", type=int, default=1, help="0空 1裝 2人 3陸 4海")
    a = ap.parse_args()

    d = load_rom()
    units = load_units(d)
    print(f"兵种表 0x{UNIT_TABLE:08X} 解析到 {len(units)} 条")

    if a.list:
        for u in units[:60]:
            print("  ", u)
        return

    if a.atk and a.dfn:
        ua, ud = find(units, a.atk), find(units, a.dfn)
        if not ua or not ud:
            print("找不到兵种:", a.atk, a.dfn)
            return
        c = a.tclass
        my = damage(d, ua, ud, c, a.terr)
        back = damage(d, ud, ua, c, 0)   # 反击：对方站在自己格（默认无加成）
        print(f"\n{a.atk} → {a.dfn}  目标类别={CLASSES[c]} 地形+{a.terr}")
        print(f"  我方攻击值 {ua.atk[c]}（全列 {ua.atk}）")
        print(f"  我方伤害 ≈ {my}")
        print(f"  敌方反击 ≈ {back}（按同一类别粗算）")
        print(f"  敌 HP={ud.durability} → 需 {max(1, -(-ud.durability // max(1, my)))} 次击毁")
        print("  结论:", "占优，可打" if my > back else "亏，别打")
        return

    # 演示
    print("\n=== 演示：74式 MBT 打不同类型目标（无地形加成）===")
    t74 = find(units, "74式")
    for tn in ["軽歩兵", "M60A3", "FH70", "補給車"]:
        t = find(units, tn)
        if t74 and t:
            for c in (1, 2):
                my = damage(d, t74, t, c)
                back = damage(d, t, t74, c)
                print(f"  74式 vs {t.name:12s} 类别{CLASSES[c]}: 我 {my:3d} / 它 {back:3d}"
                      f"  {'✔可打' if my > back else '✘亏'}")
    print("\n=== 地形加成（cell-0x10）===")
    for cid in list(range(0x10, 0x18)) + list(range(0x22, 0x2A)):
        print(f"  cell 0x{cid:02X} → +{terr_bonus(d, cid)}")


if __name__ == "__main__":
    main()
