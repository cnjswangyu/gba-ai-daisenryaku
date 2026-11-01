#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""直接操控《大战略》存档（不依赖模拟器 Lua、不依赖模型）。

原理：
    BizHawk 的 .State 是 zip，里面 Core.bin.zst 是 zstd 压缩的核心状态，
    解压后直接包含 IWRAM/EWRAM 快照。实测映射：
        文件偏移 = 0x19004 + (内存地址 - 0x03000000)      # IWRAM
    所以改存档字节 = 改游戏状态；重新打包后模拟器 load 即生效。

已知结构（逆向确认，HANDOFF §0.9.4b / §0.9.4e）：
    单位表  ctx+0x2760 + 阵营*0x600 + 槽*0x18     （ctx=0x03000480，阵营 0=蓝 1=红）
      记录（以 id 所在为起点）：+0 id(u16)  +2 x  +3 y  +4 燃料  +6 HP  +7 bit0=已行动  +8 类别码
    格表    ctx+0x3F60 + x*4 + y*0xC0
      +0 阵营(0空/1蓝/2红)  +1 槽号(1-based)
    掩码    ctx+0x0C5D + y*0x30 + x   （0xF1=不可走）

用法：
    python tools/state_edit.py dump   states/battle_usa_ready.State
    python tools/state_edit.py move   states/in.State 17 24 26 states/out.State
    python tools/state_edit.py hp     states/in.State 0 99     states/out.State
    python tools/state_edit.py money  states/in.State 999999   states/out.State
    python tools/state_edit.py enemyoff states/in.State 5      states/out.State
"""
from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path

import zstandard as zstd

ROOT = Path(__file__).resolve().parent.parent

IW_FILE_OFF = 0x19004       # IWRAM(0x03000000) 在 Core.bin 里的偏移
IW_BASE = 0x03000000
CTX = 0x03000480

UNIT_OFF = 0x2760           # ctx 偏移；我方
SIDE_STRIDE = 0x600
REC_STRIDE = 0x18
GRID_OFF = 0x3F60
GRID_W = 48
GRID_ROW = 0xC0             # y 行距（x 步长 4）


class State:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self.members: dict[str, bytes] = {}
        with zipfile.ZipFile(self.path) as z:
            self.order = z.namelist()
            for n in self.order:
                self.members[n] = z.read(n)
        blob = zstd.ZstdDecompressor().decompress(
            self.members["Core.bin.zst"], max_output_size=1 << 23)
        self.raw = bytearray(blob)
        self.base = self._find_iwram_base()

    # ---------------- 基础 ----------------
    def _find_iwram_base(self) -> int:
        """用单位表基址锚定 IWRAM 在文件中的起点"""
        # M1A2 id=187, 常见坐标 (21,30) —— 找不到就退回已知常量
        pat = bytes([0xBB, 0x00])
        for i in range(0, len(self.raw) - 32):
            if self.raw[i:i + 2] == pat:
                # 记录后 4 字节应是 x,y,fuel 的合理值
                x, y, f = self.raw[i + 2], self.raw[i + 3], self.raw[i + 4]
                if 0 < x < 64 and 0 < y < 64 and 0 < f <= 100:
                    return i - 0x2BE0
        return IW_FILE_OFF

    def off(self, addr: int) -> int:
        return self.base + (addr - IW_BASE)

    def r8(self, addr: int) -> int:
        return self.raw[self.off(addr)]

    def w8(self, addr: int, v: int) -> None:
        self.raw[self.off(addr)] = v & 0xFF

    def r16(self, addr: int) -> int:
        o = self.off(addr)
        return self.raw[o] | (self.raw[o + 1] << 8)

    # ---------------- 单位 ----------------
    def unit_addr(self, slot: int, side: int = 0) -> int:
        return CTX + UNIT_OFF + side * SIDE_STRIDE + slot * REC_STRIDE

    def units(self, side: int = 0, slots: int = 64) -> list[dict]:
        out = []
        for k in range(slots):
            a = self.unit_addr(k, side)
            uid = self.r16(a)
            if uid == 0:
                continue
            x, y = self.r8(a + 2), self.r8(a + 3)
            if not (0 < x < 64 and 0 < y < 64):
                continue
            out.append({"slot": k, "id": uid, "x": x, "y": y,
                        "fuel": self.r8(a + 4), "hp": self.r8(a + 6),
                        "cls": self.r8(a + 8), "st": self.r8(a + 7), "addr": a})
        return out

    def grid_addr(self, x: int, y: int) -> int:
        return CTX + GRID_OFF + x * 4 + y * GRID_ROW

    def grid(self, x: int, y: int) -> tuple[int, int]:
        a = self.grid_addr(x, y)
        return self.r8(a), self.r8(a + 1)

    # ---------------- 操作 ----------------
    def teleport(self, slot: int, tx: int, ty: int, side: int = 0) -> str:
        """移动单位：改单位表坐标 + 迁移格表（两处必须同时改）"""
        a = self.unit_addr(slot, side)
        if self.r16(a) == 0:
            return f"失败：槽 {slot} 无单位"
        ox, oy = self.r8(a + 2), self.r8(a + 3)
        camp = side + 1
        # 清旧格
        g = self.grid_addr(ox, oy)
        if self.grid(ox, oy) == (camp, slot + 1):
            self.w8(g, 0)
            self.w8(g + 1, 0)
        # 写新格
        n = self.grid_addr(tx, ty)
        if self.grid(tx, ty) != (0, 0):
            return f"失败：目标格 ({tx},{ty}) 已被占 {self.grid(tx, ty)}"
        self.w8(n, camp)
        self.w8(n + 1, slot + 1)
        # 改坐标
        self.w8(a + 2, tx)
        self.w8(a + 3, ty)
        return f"槽 {slot} (id{self.r16(a)}) ({ox},{oy}) -> ({tx},{ty})"

    def set_hp(self, slot: int, hp: int, side: int = 0) -> str:
        a = self.unit_addr(slot, side)
        old = self.r8(a + 6)
        self.w8(a + 6, hp)
        return f"槽 {slot} HP {old} -> {hp}"

    def set_money(self, v: int) -> str:
        # 势力表 ctx+0x24 + idx*0xC，+0 资金 u32
        a = CTX + 0x24
        old = struct.unpack_from("<I", self.raw, self.off(a))[0]
        struct.pack_into("<I", self.raw, self.off(a), v)
        return f"资金 {old} -> {v}"

    def set_acted(self, slot: int, acted: bool, side: int = 0) -> str:
        """设置/清除 +7 的 bit0（已行动标志）"""
        a = self.unit_addr(slot, side)
        v = self.r8(a + 7)
        nv = (v | 1) if acted else (v & 0xFE)
        self.w8(a + 7, nv)
        return f"槽 {slot} +7 {v:#04x} -> {nv:#04x} (acted={acted})"

    # ---------------- 存 ----------------
    def save(self, out: str | Path) -> None:
        comp = zstd.ZstdCompressor(level=9).compress(bytes(self.raw))
        self.members["Core.bin.zst"] = comp
        out = Path(out)
        out.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            for n in self.order:
                z.writestr(n, self.members[n])


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("dump", help="打印双方单位与格表")
    d.add_argument("state")

    m = sub.add_parser("move", help="移动单位（同步改格表）")
    m.add_argument("state")
    m.add_argument("slot", type=int)
    m.add_argument("x", type=int)
    m.add_argument("y", type=int)
    m.add_argument("out")
    m.add_argument("--side", type=int, default=0)

    h = sub.add_parser("hp")
    h.add_argument("state")
    h.add_argument("slot", type=int)
    h.add_argument("hp", type=int)
    h.add_argument("out")
    h.add_argument("--side", type=int, default=0)

    mo = sub.add_parser("money")
    mo.add_argument("state")
    mo.add_argument("value", type=int)
    mo.add_argument("out")

    a2 = sub.add_parser("acted")
    a2.add_argument("state")
    a2.add_argument("slot", type=int)
    a2.add_argument("value", type=int, choices=[0, 1])
    a2.add_argument("out")
    a2.add_argument("--side", type=int, default=0)

    a = ap.parse_args()
    st = State(a.state)

    if a.cmd == "dump":
        print(f"IWRAM 基址 = 0x{st.base:05X}")
        for side, nm in ((0, "蓝方"), (1, "红方")):
            us = st.units(side)
            print(f"\n== {nm} {len(us)} 个单位 ==")
            print("槽  id   坐标     HP  st 格表")
            for u in us:
                print(f"{u['slot']:2d} {u['id']:4d} ({u['x']:2d},{u['y']:2d}) "
                      f"{u['hp']:3d} {u['st']:2d} {st.grid(u['x'], u['y'])}")
        print(f"\n资金 = {struct.unpack_from('<I', st.raw, st.off(CTX + 0x24))[0]}")
    elif a.cmd == "move":
        print(st.teleport(a.slot, a.x, a.y, a.side))
        st.save(a.out)
        print("已写入", a.out)
    elif a.cmd == "hp":
        print(st.set_hp(a.slot, a.hp, a.side))
        st.save(a.out)
        print("已写入", a.out)
    elif a.cmd == "money":
        print(st.set_money(a.value))
        st.save(a.out)
        print("已写入", a.out)
    elif a.cmd == "acted":
        print(st.set_acted(a.slot, bool(a.value), a.side))
        st.save(a.out)
        print("已写入", a.out)


if __name__ == "__main__":
    sys.exit(main())
