"""make_v2_battle_fixture.py — 造一个「小规模多阵营」战局，用来验证 v2 真的会打两个敌对阵营。

从 states/current_20261018_221519_ready.State（军事演习3：蓝=我方 / 红=阵营1 / 绿=阵营2）出发：
  * 只保留 2 个阵营 1 单位 + 2 个阵营 2 单位，其余敌方全部删除（id 清零 + 清格表），
    并把 4 个幸存者搬到离我方阵地 3~5 格处；
  * 我方 40 个单位保持原样（够快打完）。
产出：states/v2_fixture.State + logs/v2_fixture.txt（幸存敌人清单）
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from state_edit import State, CTX, SIDE_STRIDE, REC_STRIDE, GRID_OFF  # noqa: E402

SRC = "states/current_20261018_221519_ready.State"
OUT = "states/v2_fixture.State"
# 幸存敌人：(阵营, 原槽, 目标x, 目标y)
# 每个阵营保留：首都守军（留在首都，正常打法必须先打死它才能占首都）+ 2 个野战单位
KEEP = [(1, 0, 27, 14), (1, 1, 22, 28), (1, 2, 23, 29),
        (2, 25, 30, 34), (2, 18, 24, 30), (2, 22, 25, 31)]


def main() -> None:
    st = State(SRC)
    raw = st.raw
    EW = 0x21004
    EWB = 0x02000000

    def grid(x: int, y: int) -> tuple[int, int]:
        a = CTX + GRID_OFF + x * 4 + y * 0xC0
        return st.r8(a), st.r8(a + 1)

    kept = {}
    for side, slot, tx, ty in KEEP:
        b = CTX + 0x2760 + side * SIDE_STRIDE + slot * REC_STRIDE
        uid = st.r16(b)
        assert uid, f"side{side} slot{slot} 没有单位"
        ox, oy = st.r8(b + 2), st.r8(b + 3)
        # 清旧格
        g = CTX + GRID_OFF + ox * 4 + oy * 0xC0
        if st.r8(g) == side + 1 and st.r8(g + 1) == slot + 1:
            st.w8(g, 0); st.w8(g + 1, 0)
        # 写新格 + 坐标
        ng = CTX + GRID_OFF + tx * 4 + ty * 0xC0
        assert (st.r8(ng), st.r8(ng + 1)) == (0, 0), f"({tx},{ty}) 已被占"
        st.w8(ng, side + 1); st.w8(ng + 1, slot + 1)
        st.w8(b + 2, tx); st.w8(b + 3, ty)
        kept[(side, slot)] = (uid, tx, ty)
        print(f"保留 side{side} slot{slot} id{uid} -> ({tx},{ty})")

    removed = 0
    for side in (1, 2, 3):
        for slot in range(64):
            if (side, slot) in kept:
                continue
            b = CTX + 0x2760 + side * SIDE_STRIDE + slot * REC_STRIDE
            if st.r16(b) == 0:
                continue
            x, y = st.r8(b + 2), st.r8(b + 3)
            g = CTX + GRID_OFF + x * 4 + y * 0xC0
            if st.r8(g) == side + 1 and st.r8(g + 1) == slot + 1:
                st.w8(g, 0); st.w8(g + 1, 0)
            st.w8(b, 0); st.w8(b + 1, 0)
            removed += 1

    st.save(OUT)
    lines = [f"side{side} slot{slot} id{uid} ({x},{y})" for (side, slot), (uid, x, y) in kept.items()]
    (ROOT / "logs/v2_fixture.txt").write_text(
        f"删除 {removed} 个敌方单位\n" + "\n".join(lines) + "\n", encoding="utf-8")
    print(f"已写 {OUT}：删除 {removed} 个敌单位，保留 {len(kept)} 个（两个敌对阵营各 2）")


if __name__ == "__main__":
    main()
