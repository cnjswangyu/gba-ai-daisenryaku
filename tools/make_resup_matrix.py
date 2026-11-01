"""make_resup_matrix.py — 造一个「25 种建筑补给能力」矩阵实验存档。

原理：EWRAM 里的地形表可以直接离线改（文件偏移 = 0x21004 + (地址-0x02000000)）。
我们在地图角落伪造 25 格建筑（地形码 0x10..0x28，归属=1 我方）+ 5 格归属=2 的对照，
把 30 个我方单位分别放上去（hp=1 fuel=1 ammo=0），然后跑一个回合边界，
就能一次性问出「哪些建筑地形会在回合开始时补给」以及「归属是否必须是自己」。

产出：states/resup_matrix.State + logs/resup_matrix_map.txt（槽->地形 对照表）
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from state_edit import State, CTX  # noqa: E402

EW = 0x21004          # EWRAM 在 Core.bin 里的偏移
EWB = 0x02000000
SRC = "states/current_20261018_221519_t1.State"
OUT = "states/resup_matrix.State"


def main() -> None:
    st = State(SRC)
    raw = st.raw

    def er(a: int) -> int:
        return raw[EW + (a - EWB)]

    def ew(a: int, v: int) -> None:
        raw[EW + (a - EWB)] = v & 0xFF

    def r32(a: int) -> int:
        o = st.off(a)
        return raw[o] | (raw[o + 1] << 8) | (raw[o + 2] << 16) | (raw[o + 3] << 24)

    tb = r32(CTX + 0x18)
    print(f"地形表 = 0x{tb:08X}")

    plan: list[tuple[int, int, int, int]] = []   # (slot, x, y, terr)
    slot = 0
    # 25 种建筑，归属=1（我方）
    for i in range(25):
        x, y = 2 + i % 5, 2 + i // 5
        plan.append((slot, x, y, 0x10 + i))
        slot += 1
    # 5 格对照：归属=2（敌方）
    for i in range(5):
        plan.append((slot, 2 + i, 8, 0x10 + i))
        slot += 1
    # 1 格对照：我方野地（非建筑）
    plan.append((slot, 8, 8, 0x01))

    for s, x, y, terr in plan:
        b = CTX + 0x2760 + s * 0x18
        uid = st.r16(b)
        assert uid, f"槽 {s} 没有单位"
        ox, oy = st.r8(b + 2), st.r8(b + 3)
        # 清旧格表
        go = CTX + 0x3F60 + ox * 4 + oy * 0xC0
        if st.r8(go) == 1 and st.r8(go + 1) == s + 1:
            st.w8(go, 0)
            st.w8(go + 1, 0)
        # 写地形（EWRAM）+ 归属 + 城市 HP
        c = tb + x * 4 + y * 0xC0
        ew(c, terr)
        ew(c + 1, 0x96)
        ew(c + 2, 1 if terr != 0x01 or y != 8 else 1)
        ew(c + 3, 0)
        if y == 8 and terr != 0x01:
            ew(c + 2, 2)          # 敌方归属对照
        if terr == 0x01:
            ew(c + 2, 1)          # 野地对照（我方"归属"）
        # 写新格表 + 单位坐标 + 低血低油无弹
        st.w8(CTX + 0x3F60 + x * 4 + y * 0xC0, 1)
        st.w8(CTX + 0x3F60 + x * 4 + y * 0xC0 + 1, s + 1)
        st.w8(b + 2, x)
        st.w8(b + 3, y)
        st.w8(b + 6, 1)
        st.w8(b + 4, 1)
        for k in range(4):
            st.w8(b + 8 + k, 0)
        st.w8(b + 7, st.r8(b + 7) & 0xFE)

    st.save(OUT)
    lines = [f"{s}\t{x}\t{y}\t0x{terr:02X}\t{'我方' if (y != 8 or terr == 0x01) else '敌方'}"
             for s, x, y, terr in plan]
    (ROOT / "logs/resup_matrix_map.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"已写 {OUT}，{len(plan)} 个受测单位；对照表 logs/resup_matrix_map.txt")


if __name__ == "__main__":
    main()
