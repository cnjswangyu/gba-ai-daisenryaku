#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《大战略》USA 局 AI 闭环大脑（语义指令版）。

与 brain_file.py 的区别：
    - 读的是**游戏数据态**（双方单位/HP/燃料/地形），不是硬件态 GRID/OAM
    - 让模型输出**语义指令**（MOVE/ATTACK/ENDTURN），不是按键
      按键由 lua/usa_ai_state.lua 展开成确定性序列（模型数不准帧）
    - 每轮把上一轮的执行结果（shots/result.txt）回喂给模型，形成闭环反馈

协议：
    shots/state.txt   <- Lua 写：step=N / CURSOR / MY n / U<idx> ... / EN n / E<idx> ...
    shots/action.txt  <- 本脚本写：step=N / MOVE 3 24 26 / ENDTURN
    shots/result.txt  <- Lua 写：step=N / OK|FAIL MOVE ... / END

用法：
    C:\\ProgramData\\Anaconda3\\python.exe -u tools/ai_loop.py
    --vs 真实 JSON 模式  --max-units 20  只看最近 20 个单位
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import brain  # noqa: E402

STATE = os.path.join(ROOT, "shots", "state.txt")
ACTION = os.path.join(ROOT, "shots", "action.txt")
RESULT = os.path.join(ROOT, "shots", "result.txt")
SHOT = os.path.join(ROOT, "shots", "cur.png")
LOG = os.path.join(ROOT, "logs", "ai_loop.log")
UNITDB = os.path.join(ROOT, "lua", "unitdb.tsv")

# ---------------------------------------------------------------- 日志


def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


# ---------------------------------------------------------------- 单位库


class UnitDB:
    """lua/unitdb.tsv: id name class move sub speed dur atk(5) fuel price wtype"""

    def __init__(self, path: str) -> None:
        self.rows: dict[int, dict] = {}
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("#") or not line.strip():
                    continue
                c = line.rstrip("\n").split("\t")
                if len(c) < 11:
                    continue
                try:
                    uid = int(c[0])
                except ValueError:
                    continue
                atk = [int(x) for x in c[7].split(",") if x.strip().lstrip("-").isdigit()]
                self.rows[uid] = {
                    "name": c[1], "class": int(c[2]), "move": int(c[3]),
                    "speed": int(c[5]), "dur": int(c[6]),
                    "atk": atk, "fuel": int(c[8]), "price": int(c[9]),
                }

    def get(self, uid: int) -> dict:
        return self.rows.get(uid, {})

    def atk_vs(self, uid: int, target_class: int) -> int:
        """攻击力：atk[0]=对空 atk[1]=对装甲 atk[2]=对人员 atk[3]=对陆 atk[4]=对海"""
        atk = self.get(uid).get("atk") or []
        if not atk:
            return 0
        # class: 0=航空 1=车辆 2=步兵（unitdb 的 class 列）
        return atk[0] if target_class == 0 else (atk[1] if target_class == 1 else atk[2])


# ---------------------------------------------------------------- 状态解析


def parse_state(text: str) -> dict:
    st: dict = {"step": 0, "turn": 1, "money": 0, "cursor": None,
                "terrain": "", "def": 0, "weather": None, "my": [], "en": []}
    side = None
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        m = re.match(r"step=(\d+)\s+turn=(\d+)\s+money=(-?\d+)", line)
        if m:
            st["step"], st["turn"], st["money"] = int(m.group(1)), int(m.group(2)), int(m.group(3))
            continue
        m = re.match(r"WEATHER\s+(\d+)", line)
        if m:
            st["weather"] = int(m.group(1))
            continue
        m = re.match(r"CURSOR\s+(-?\d+),(-?\d+)\s+(\S+)\s+def\+(\d+)", line)
        if m:
            st["cursor"] = (int(m.group(1)), int(m.group(2)))
            st["terrain"], st["def"] = m.group(3), int(m.group(4))
            continue
        if line.startswith("MY "):
            side = "my"
            continue
        if line.startswith("EN "):
            side = "en"
            continue
        if line == "END":
            break
        m = re.match(
            r"([UE])(\d+)\s+id(\d+)\s+(.+?)\s+x(\d+)\s+y(\d+)\s+hp(\d+)/(\d+)\s+f(\d+)\s+st(\d+)(?:\s+act(\d))?(?:\s+ammo(\d+))?",
            line)
        if m and side:
            st[side].append({
                "idx": int(m.group(2)), "id": int(m.group(3)), "name": m.group(4).strip(),
                "x": int(m.group(5)), "y": int(m.group(6)),
                "hp": int(m.group(7)), "maxhp": int(m.group(8)),
                "fuel": int(m.group(9)), "st": int(m.group(10)),
                "acted": (m.group(11) == "1"),
                "ammo": int(m.group(12)) if m.group(12) is not None else None,
            })
    return st


def parse_result(text: str) -> list[str]:
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("step=") or line == "END":
            continue
        out.append(line)
    return out


def hexdist(a: tuple[int, int], b: tuple[int, int]) -> int:
    """游戏原生 FUN_08002E74 的 odd-r 六角距离。"""
    dq = (a[0] - a[1] // 2) - (b[0] - b[1] // 2)
    dr = a[1] - b[1]
    return max(abs(dq), abs(dr), abs(dq + dr))


# ---------------------------------------------------------------- 战场分析


def analyze(st: dict, db: UnitDB) -> dict:
    """给模型一份"已经算好"的态势，别让它自己数坐标"""
    my, en = st["my"], st["en"]
    info: dict = {"threats": [], "targets": [], "notes": []}

    # 每个我方单位：最近敌人距离 + 能不能打
    for u in my:
        if not en:
            continue
        nearest = min(en, key=lambda e: hexdist((u["x"], u["y"]), (e["x"], e["y"])))
        d = hexdist((u["x"], u["y"]), (nearest["x"], nearest["y"]))
        u["nearest_enemy"] = (nearest["idx"], d, nearest["name"])

    # 敌方威胁：按"最靠近我方"排序
    for e in sorted(en, key=lambda e: min(
            (hexdist((e["x"], e["y"]), (u["x"], u["y"])) for u in my), default=99))[:8]:
        dmin = min((hexdist((e["x"], e["y"]), (u["x"], u["y"])) for u in my), default=99)
        info["threats"].append({**e, "dmin": dmin})

    # 交战评估：对我方每个可打单位，找一个最优攻击目标
    for u in my:
        best = None
        if u.get("acted") or u.get("ammo") == 0:
            continue
        for e in en:
            d = hexdist((u["x"], u["y"]), (e["x"], e["y"]))
            if d > (db.get(u["id"]).get("speed", 6) + 1):
                continue
            e_class = db.get(e["id"]).get("class", 1)
            mine = db.atk_vs(u["id"], e_class)
            theirs = db.atk_vs(e["id"], db.get(u["id"]).get("class", 1))
            score = mine - theirs
            if best is None or score > best["score"]:
                best = {"e": e, "d": d, "mine": mine, "theirs": theirs, "score": score}
        if best:
            info["targets"].append({"u": u, **best})
    info["targets"].sort(key=lambda x: -x["score"])
    return info


# ---------------------------------------------------------------- prompt


RULES = """你在指挥《大战略》(GBA) 里的一支美军装甲部队，蓝方(BLUE)=我方，红方(RED)=敌方。
目标是消灭敌军 / 占领敌方首都。胜负按回合数结算，弹药和燃料有限。

【你只能下达语义指令，不要输出按键】系统会负责把指令翻译成具体按键。
每条指令一行，最多 3 条：

  MOVE <单位序号> <目标x> <目标y>    把该单位移动到地图格 (x,y)
  ATTACK <单位序号> <敌方序号>      自动移动到该敌人旁边并开火（会吃反击）
  ENDTURN                            结束我方回合，交给敌方行动
  WAIT                               什么都不做（观察一回合）

【地图与坐标】六角格，奇数行向右偏移。x/y 是格坐标。距离使用下方系统计算结果。
移动是"沿可达路径走"，红格=不可达。单位燃料(f)每移动消耗，燃料 0 就动不了。

【战术原则】
1. 先看清态势再动手：哪个敌人最弱(HP低)、哪个离你最近、谁在射程外。
2. 坦克(M1A2)是主力，别单独冲进敌群；自行炮(M-109A6)射程远但脆，留在后方。
3. 侦察车(M-3A2)视野好，放侧翼探路。补给车别上一线。
4. 有把握才打：我方攻击力 < 敌方反击力 时不要交换。优先用 ATTACK 打 HP 低的敌人。
5. 一个回合内能做的有限（每个单位一次行动），不要贪。
6. 若所有单位都动过了，就 ENDTURN。

【硬性纪律（违反会白白浪费回合）】
A. 标了 [已行动] 的单位本回合不能再下令，给它下指令会直接失败。
B. 上一轮标了 FAIL 的指令**绝对不要原样重下**。先看失败原因：
   "HP 仍 N" = 没打中或目标不在这条线上；"槽 N 为空" = 那个单位已经死了/不存在。
   局面变了就换目标、换单位。
C. ATTACK 会吃反击，我方 HP 低于 6 的单位不要主动攻击 HP 还很高的敌人。
D. 每次下令前先自问：这条指令上一轮是不是已经失败过？目标现在还活着吗？
E. 天气会影响攻击力（见下方天气说明），恶劣天气下更不要做亏本交换。

【输出格式】严格 JSON，不要 markdown：
{"plan":"一句话战术意图","orders":["ATTACK 0 4","MOVE 9 20 26","ENDTURN"]}
orders 里每条是上面四种指令之一。不确定就只输出 ["ENDTURN"]。"""


def build_prompt(st: dict, info: dict, db: UnitDB, history: list[str],
                 last_result: list[str], img_note: str = "",
                 moved: set | None = None, warn_repeat: bool = False) -> str:
    moved = moved or set()
    L = [RULES, ""]
    L.append(f"=== 当前态势：第 {st['turn']} 回合，资金 {st['money']} ===")
    w = st.get("weather")
    if w is not None:
        # 实测（FUN_08030644 地面部队分支）：1=100%，0/2=85%，3=70%
        # 修正倍率已经实测；具体天气名称尚未从图标确认。
        wn, wf = {1: ("天气码1", "100%"), 0: ("天气码0", "85%"),
                  2: ("天气码2", "85%"), 3: ("天气码3", "70%")}.get(w, (f"码{w}", "?%"))
        L.append(f"天气：{wn}（本回合攻击力 ×{wf}）")
    if st["cursor"]:
        L.append(f"光标在 {st['cursor']}（{st['terrain']}，防御+{st['def']}）")
    L.append("")

    L.append(f"--- 我方 {len(st['my'])} 个单位（序号=下指令时用的编号）---")
    L.append("序号 兵种                坐标    HP      燃料  距最近敌")
    for u in st["my"]:
        ne = u.get("nearest_enemy")
        ne_s = f"{ne[1]}格({ne[2]})" if ne else "-"
        # 真实"已行动"标志（内存 +7 bit0）；moved 只是本地记账，作兜底
        acted = u.get("acted") or (u["idx"] in moved)
        tag = " [已行动,本回合不能再动]" if acted else ""
        ammo = u.get("ammo")
        ammo_s = f" 弹药{ammo}" if ammo is not None else ""
        L.append(f"U{u['idx']:<3} {u['name'][:16]:<18} ({u['x']:>2},{u['y']:>2}) "
                 f"{u['hp']:>2}/{u['maxhp']:<2}  {u['fuel']:>3}   {ne_s}{ammo_s}{tag}")
    L.append("")

    L.append(f"--- 敌方 {len(st['en'])} 个单位 ---")
    L.append("序号 兵种                坐标    HP      燃料")
    for e in st["en"]:
        L.append(f"E{e['idx']:<3} {e['name'][:16]:<18} ({e['x']:>2},{e['y']:>2}) "
                 f"{e['hp']:>2}/{e['maxhp']:<2}  {e['fuel']:>3}")
    L.append("")

    if info["targets"]:
        L.append("--- 可交战机会（已按收益排序）---")
        for t in info["targets"][:6]:
            u, e = t["u"], t["e"]
            verdict = "占优" if t["score"] > 5 else ("均势" if t["score"] > -5 else "吃亏")
            L.append(f"U{u['idx']} 可打 E{e['idx']}（距离{t['d']}格）："
                     f"我攻击{t['mine']} / 它反击{t['theirs']} → {verdict}")
        L.append("")

    if info["threats"]:
        L.append("--- 最迫近的敌人 ---")
        for e in info["threats"][:5]:
            L.append(f"E{e['idx']} {e['name'][:14]} ({e['x']},{e['y']}) 距我最近 {e['dmin']} 格")
        L.append("")

    if last_result:
        fails = [r for r in last_result if r.startswith("FAIL") or r.startswith("ERR")]
        oks = [r for r in last_result if not (r.startswith("FAIL") or r.startswith("ERR"))]
        if fails:
            L.append("!!! 上一轮这些指令失败了 —— 本轮绝对不要原样重下 !!!")
            for r in fails[:6]:
                L.append("  ✗ " + r)
            L.append("")
        if oks:
            L.append("--- 上一轮成功的指令 ---")
            for r in oks[:6]:
                L.append("  ✓ " + r)
            L.append("")

    if warn_repeat:
        L.append("!! 警告：你这次的指令和上一次完全相同，但局面已经变了。")
        L.append("   标了 [本回合已动] 的单位不能再移动；请换其他单位，或者直接 ENDTURN。")
        L.append("")

    if history:
        L.append("--- 最近几轮 ---")
        for h in history[-6:]:
            L.append("  " + h)
        L.append("")

    if img_note:
        L.append(img_note)
    return "\n".join(L)


# ---------------------------------------------------------------- 指令解析


VALID = re.compile(r"^(MOVE\s+\d+\s+\d+\s+\d+|ENDTURN|WAIT|ATTACK\s+\d+\s+\d+)$")


def parse_orders(reply: str) -> tuple[str, list[str]]:
    obj = None
    try:
        obj = json.loads(reply)
    except Exception:
        m = re.search(r"\{.*\}", reply, re.S)
        if m:
            try:
                obj = json.loads(m.group(0))
            except Exception:
                obj = None
    plan, orders = "", []
    if isinstance(obj, dict):
        plan = str(obj.get("plan") or obj.get("thought") or "")[:200]
        raw = obj.get("orders") or obj.get("orders".upper()) or obj.get("actions") or []
        if isinstance(raw, str):
            raw = [raw]
        for o in raw:
            s = re.sub(r"\s+", " ", str(o).strip().upper())
            s = re.sub(r"^[\[\"']|[\]\"',]+$", "", s).strip()
            if VALID.match(s):
                orders.append(s)
            elif s in ("END_TURN", "END TURN", "PASS"):
                orders.append("ENDTURN")
            elif s in ("NOOP", "SKIP", "NONE"):
                orders.append("WAIT")
    if not orders:
        # 兜底：一行一条指令的自由文本
        for line in reply.splitlines():
            s = re.sub(r"\s+", " ", line.strip().upper())
            if VALID.match(s):
                orders.append(s)
    return plan, orders[:3]


# ---------------------------------------------------------------- 主循环


def read_text(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--model", default="local")
    ap.add_argument("--max-step", type=int, default=400)
    ap.add_argument("--vision", action="store_true", help="同时送截图（更慢但能读画面）")
    ap.add_argument("--from-step", type=int, default=0, help="从第几步开始接（Lua 重开时要对齐）")
    a = ap.parse_args()

    brain.ARGS = __import__("types").SimpleNamespace(
        url=a.url, model=a.model, profile="strategy", no_think=True, max_state_chars=20000)

    db = UnitDB(UNITDB)
    log(f"单位库 {len(db.rows)} 条 | state={STATE} | vision={a.vision}")

    last_step = a.from_step - 1
    history: list[str] = []
    last_result: list[str] = []
    last_orders: list[str] = []
    prev_repeat = False
    moved: set[int] = set()          # 本回合已经动过的单位序号（告诉模型别重复下令）

    while last_step < a.max_step:
        text = read_text(STATE)
        if not text:
            time.sleep(0.2)
            continue
        st = parse_state(text)
        if st["step"] == last_step:
            time.sleep(0.2)
            continue
        last_step = st["step"]

        # 上一轮执行结果
        rtext = read_text(RESULT)
        if re.search(rf"step={st['step'] - 1}\b", rtext):
            last_result = parse_result(rtext)

        info = analyze(st, db)
        img_note = ""
        img_b64 = None
        if a.vision:
            try:
                img_b64, _ = brain.encode_frame(SHOT)
                img_note = "--- 下面是当前画面截图（原始 240x160 放大）---\n以图为准，图上看不清的不要编。"
            except Exception as e:  # noqa: BLE001
                log(f"读图失败，退回纯文本: {e!r}")

        warn_repeat = prev_repeat
        prompt = build_prompt(st, info, db, history, last_result, img_note,
                              moved=moved, warn_repeat=warn_repeat)
        t0 = time.time()
        try:
            reply = brain.llm_chat(prompt, img_b64)
        except Exception as e:  # noqa: BLE001
            log(f"模型调用失败: {e!r}")
            time.sleep(2)
            continue
        plan, orders = parse_orders(reply)
        if not orders:
            orders = ["WAIT"]
            log("!! 模型没给出合法指令，退化为 WAIT；原始回复: " + reply[:200])

        log(f"step {st['step']}: T{st['turn']} {plan[:60]} | {orders} ({time.time() - t0:.1f}s)")

        # 记录哪些单位本回合已下令移动；ENDTURN 后清空
        for o in orders:
            if o.startswith("MOVE"):
                try:
                    moved.add(int(o.split()[1]))
                except (IndexError, ValueError):
                    pass
        if "ENDTURN" in orders:
            moved.clear()
        prev_repeat = bool(last_orders) and orders == last_orders
        last_orders = list(orders)

        out = [f"step={st['step']}", f"PLAN: {plan}"]
        out += orders
        out.append("END")
        tmp = ACTION + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
        os.replace(tmp, ACTION)

        history.append(f"T{st['turn']} {plan[:40]} -> {' / '.join(orders)}")
        del history[:-10]
        brain.log_jsonl({"t": time.strftime("%H:%M:%S"), "step": st["step"], "turn": st["turn"],
                         "plan": plan, "orders": orders, "raw": reply[:600]})


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("bye")
