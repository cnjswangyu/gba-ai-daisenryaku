#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 ROM 兵种表导出 Lua 单位数据库 lua/unitdb.lua。

字段布局（已与战场记录实测对齐，见 tools/cmp_rom_battle.py）：
  +0x00 名指针(u32)  +0x04 大类(0空/1车/2步)  +0x05 移动种别(0飞/2装軌/4徒歩)
  +0x06 细分类(0步/2IFV/3坦克/4ATGM/5炮/7补给/13战斗机)
  +0x0D 速度(每回合可走格数)  +0x0E 耐久(HP)
  +0x14..18 攻击5列[空,裝甲,人員,陸,海]（99=不能攻击）
  +0x19 燃料  +0x1A 价格(u16)  +0x25 兵器种别(1普通/3间射/0后勤)
"""
from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = ROOT / "roms" / "0219 - Daisenryaku.gba"
OUT = ROOT / "lua" / "unitdb.lua"
BASE = 0x08000000
TBL = 0x08798A98
ST = 0x5C


def s_at(d: bytes, va: int, n: int = 24) -> str:
    o = va - BASE
    if not (BASE <= va < BASE + len(d)):
        return ""
    raw = d[o:o + n]
    e = raw.find(b"\x00")
    if e >= 0:
        raw = raw[:e]
    for enc in ("cp932", "shift_jis"):
        try:
            return raw.decode(enc, "replace").strip()
        except Exception:
            pass
    return ""


def clean(nm: str) -> str:
    """Lua 源码安全：只留 ASCII 可打印 + CJK/假名，其余（含 U+FFFD）换成 ?"""
    out = []
    for ch in nm:
        o = ord(ch)
        if 0x20 <= o <= 0x7E or 0x4E00 <= o <= 0x9FFF or 0x3040 <= o <= 0x30FF or 0xFF66 <= o <= 0xFF9D:
            out.append(ch)
        else:
            out.append("?")
    return "".join(out).strip() or "?"


def main() -> None:
    d = ROM.read_bytes()
    rows = []
    for i in range(512):
        o = TBL + i * ST - BASE
        if o + ST > len(d):
            break
        r = d[o:o + ST]
        nm = s_at(d, struct.unpack_from("<I", r, 0)[0])
        spd, dur = r[0x0D], r[0x0E]
        if not nm or not (1 <= spd <= 20) or not (1 <= dur <= 60):
            continue
        atk = list(r[0x14:0x19])
        if max(atk) > 99:
            continue
        rows.append((i, clean(nm), r[4], r[5], r[6], spd, dur, atk, r[0x19],
                     struct.unpack_from("<H", r, 0x1A)[0], r[0x25]))

    lines = [
        "-- 自动生成：ROM 兵种表（0x08798A98，步长 0x5C）→ Lua 表。勿手改。",
        "-- 重新生成：python tools/gen_unitdb.py",
        "-- 字段: [1]名 [2]大类(0空1车2步) [3]移动种别 [4]细分类 [5]速度 [6]耐久",
        "--       [7]攻击5列{空,裝甲,人員,陸,海} [8]燃料 [9]价格 [10]兵器(1普通/3间射/0后勤)",
        "UNITDB = {",
    ]
    for i, nm, c, mv, sub, spd, dur, atk, fuel, price, wt in rows:
        a = ",".join(str(v) for v in atk)
        lines.append(
            f'  [{i}] = {{"{nm}",{c},{mv},{sub},{spd},{dur},{{{a}}},{fuel},{price},{wt}}},'
        )
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    # 运行时用 TSV（BizHawk Lua 沙箱没有 loadfile/dofile，只能 io.open 逐行解析）
    tsv = ["# id\tname\tclass\tmove\tsub\tspeed\tdur\tatk(空,裝甲,人員,陸,海)\tfuel\tprice\twtype"]
    for i, nm, c, mv, sub, spd, dur, atk, fuel, price, wt in rows:
        tsv.append(f"{i}\t{nm}\t{c}\t{mv}\t{sub}\t{spd}\t{dur}\t"
                   + ",".join(str(v) for v in atk) + f"\t{fuel}\t{price}\t{wt}")
    (OUT.parent / "unitdb.tsv").write_text("\n".join(tsv) + "\n", encoding="utf-8")
    print(f"{len(rows)} units -> {OUT} (+ unitdb.tsv)")

    # 控制台抽样核对
    for i in (187, 241, 208, 339, 290, 200, 239, 305, 344):
        r = next((x for x in rows if x[0] == i), None)
        if r:
            print(f"  {i:3d} {r[1][:18]:20} 类{r[2]} 移{r[3]} 细{r[4]} 速{r[5]} 久{r[6]} "
                  f"攻{r[7]} 油{r[8]} 价{r[9]} 兵{r[10]}")


if __name__ == "__main__":
    main()
