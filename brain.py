#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GBA AI 大脑：BizHawk(Lua) <-> 本地 llama.cpp 视觉模型 的决策服务。

默认后端：http://127.0.0.1:8080 （llama-server，OpenAI 兼容 /v1/chat/completions）

协议（行文本，避免 Lua 侧依赖 JSON）：
  Lua  --POST-->  Python
      frame=1234
      shot=C:/path/a.png        # 当前帧
      prev=C:/path/b.png        # 上一帧（用于判断画面是否稳定）
      step=7
      last=RIGHT
  Python --response--> Lua
      THOUGHT: 光标在地图中央，等待指令
      STABLE: 1
      ACT: A
      WAIT: 30
      END

启动：
  python brain.py --url http://127.0.0.1:8080 --profile strategy
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import re
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from PIL import Image

KEYS = ("UP", "DOWN", "LEFT", "RIGHT", "A", "B", "L", "R", "START", "SELECT")
CN_KEYS = {
    "上": "UP", "下": "DOWN", "左": "LEFT", "右": "RIGHT",
    "确认": "A", "决定": "A", "取消": "B", "返回": "B",
}

# ---------------------------------------------------------------- 提示词

COMMON = """你在通过按键操作一台 Game Boy Advance，只能看到当前这一帧画面。
可用按键（每次一个）：UP DOWN LEFT RIGHT A B L R START SELECT
没有鼠标，移动光标/角色只能靠方向键；确认用 A，取消/返回用 B。
必须基于画面里真实可见的内容决策，不要凭想象。
只输出一个 JSON 对象，不要任何解释文字、不要 markdown 代码块。"""

PROFILES = {
    "strategy": """当前游戏：《大战略》类回合制战棋 / 城市建设（GBA）。
操作链路通常是：光标移动 -> A 选单位/建筑 -> 选目标 -> 确认。
先判断画面属于哪一类：
- "地图"：可见网格地形、单位或建筑，光标在闪烁
- "菜单"：出现选项列表（移动/攻击/建造/待机/取消…）
- "对话"：出现对话框和头像，需要按 A 推进
- "演出"：单位特写、伤害数字、镜头移动等动画
- "结算"：回合数、势力名、收支结算
- "标题"：Logo 或标题画面
决策原则：
- 标题：按 A 或 START 进入游戏
- 对话/结算：按 A 推进，wait 给 40 让文字跑完
- 菜单：用 UP/DOWN 选中目标项再 A 确认；看不清当前选中项时按 A
- 地图：用方向键把光标移向有价值的目标，一次只走 1-2 格
- 演出：不要按键，wait 给 60
输出 JSON：
{"screen":"地图/菜单/对话/演出/结算/标题/其他","thought":"一句话：看到什么、下一步为什么","actions":["RIGHT"],"wait":24}""",

    "generic": """先判断这是【等待输入】【动画/过场】还是【加载】。
- 动画/过场：actions 置空，wait 20-60
- 等待输入：给出 1-3 个动作
输出 JSON：
{"screen":"菜单/地图/对话/战斗/其他","thought":"一句话说明","actions":["A"],"wait":20}""",

    "rpg": """当前游戏：RPG/动作类。
- 对话框：按 A 推进
- 地图探索：沿可通行方向移动，遇阻换方向
- 菜单：方向键选择 + A 确认
输出 JSON：
{"screen":"...","thought":"...","actions":["A"],"wait":20}""",
}


def build_prompt(profile: str, step: int, last: str, history: list[str]) -> str:
    """把系统提示 + 当前步上下文拼成单条文本（配合图片一起送）"""
    body = PROFILES.get(profile, PROFILES["generic"])
    hist = "\n".join(history[-6:]) if history else "（无）"
    return (
        COMMON
        + "\n\n"
        + body
        + f"\n\n--- 当前状态 ---\n第 {step} 步，上一步动作：{last or '（无）'}\n"
        + f"最近几步：\n{hist}\n\n"
        + f"下面是当前 GBA 画面（原始 240x160，已最近邻放大 {SCALE}x 以便看清小字）："
    )


# ---------------------------------------------------------------- 图像

SCALE = 4


def encode_frame(path: str) -> tuple[str, str]:
    """读截图 -> 放大 -> base64。返回 (b64, md5)"""
    with open(path, "rb") as f:
        raw = f.read()
    h = hashlib.md5(raw).hexdigest()
    im = Image.open(io.BytesIO(raw)).convert("RGB")
    if SCALE != 1:
        im = im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode(), h


# ---------------------------------------------------------------- 模型调用

def llm_chat(prompt: str, image_b64: str | None = None, timeout: int = 300) -> str:
    """OpenAI 兼容接口。image_b64 为 None 时走纯文本（读内存状态模式）。"""
    content: list[dict] = [{"type": "text", "text": prompt}]
    if image_b64:
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{image_b64}"},
            }
        )
    payload = {
        "model": ARGS.model,
        "messages": [{"role": "user", "content": content}],
        "temperature": 0.2,
        "max_tokens": 400,
        "stream": False,
        "response_format": {"type": "json_object"},
    }
    if ARGS.no_think:
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    req = urllib.request.Request(
        f"{ARGS.url}/v1/chat/completions",
        json.dumps(payload).encode(),
        {"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.load(r)
    return d["choices"][0]["message"].get("content") or ""


def parse_decision(text: str) -> dict:
    obj = None
    try:
        obj = json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text, re.S)
        if m:
            try:
                obj = json.loads(m.group(0))
            except Exception:
                obj = None
    if not isinstance(obj, dict):
        return {"screen": "?", "thought": text.strip()[:200], "actions": [], "wait": 20}

    acts: list[str] = []
    raw = obj.get("actions")
    if raw is None:
        raw = obj.get("action") or []
    if isinstance(raw, str):
        raw = re.split(r"[,+>、\s]+", raw)
    for a in raw:
        s = str(a).strip()
        k = CN_KEYS.get(s, s.upper().replace(" ", ""))
        if k in KEYS and len(acts) < 4:
            acts.append(k)

    try:
        wait = max(0, min(240, int(obj.get("wait", 20))))
    except Exception:
        wait = 20
    return {
        "screen": str(obj.get("screen", "?"))[:40],
        "thought": str(obj.get("thought", ""))[:300],
        "actions": acts,
        "wait": wait,
    }


# ---------------------------------------------------------------- 状态

class State:
    def __init__(self) -> None:
        self.step = 0
        self.history: list[str] = []
        self.last_action = ""
        self.repeat = 0
        self.lock = threading.Lock()

    def anti_stall(self, acts: list[str]) -> list[str]:
        if not acts:
            return acts
        if acts[0] == self.last_action:
            self.repeat += 1
        else:
            self.repeat = 0
        if self.repeat >= 4:
            self.repeat = 0
            return ["B" if self.last_action == "A" else "A"]
        return acts


ST = State()
HERE = os.path.dirname(os.path.abspath(__file__))
LOG_DIR = os.path.join(HERE, "logs")


def log_jsonl(obj: dict) -> None:
    os.makedirs(LOG_DIR, exist_ok=True)
    with open(
        os.path.join(LOG_DIR, f"steps-{time.strftime('%Y%m%d')}.jsonl"),
        "a",
        encoding="utf-8",
    ) as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _send(self, text: str, code: int = 200) -> None:
        b = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        self._send("ok")

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode("utf-8", "replace")
        t0 = time.time()
        try:
            text = self.handle_payload(raw)
        except Exception as e:  # noqa: BLE001
            print(f"[brain] error: {e!r}", flush=True)
            text = f"THOUGHT: error {e}\nSTABLE: 1\nWAIT: 30\nEND\n"
        dt = time.time() - t0
        first = text.splitlines()[0] if text else ""
        print(f"[brain] {dt:5.2f}s  {first[:100]}", flush=True)
        self._send(text)

    def handle_payload(self, raw: str) -> str:
        kv: dict[str, str] = {}
        for line in raw.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                kv[k.strip()] = v.strip()
        if not kv and raw.strip().startswith("{"):
            kv = json.loads(raw)

        shot = kv.get("shot", "")
        prev = kv.get("prev", "")
        state_path = kv.get("state", "")
        last = kv.get("last", "")

        with ST.lock:
            ST.step += 1
            step = ST.step

        prompt = build_prompt(ARGS.profile, step, last, ST.history)

        # ---- 模式 A：读内存/显存状态（纯文本，不送图）----
        if state_path and os.path.exists(state_path):
            with open(state_path, encoding="utf-8", errors="replace") as f:
                state_text = f.read()
            if len(state_text) > ARGS.max_state_chars:
                state_text = state_text[: ARGS.max_state_chars] + "\n...（截断）"
            prompt += (
                "\n\n--- 下面是直接从 GBA 内存/显存读出的**游戏状态**（不是截图）---\n"
                "格式说明：frame=帧号；BGn=背景层(是否开启/色深/map 地址)；\n"
                "OAM=精灵表(每个精灵的屏幕坐标x,y与尺寸，战棋里通常就是单位)；\n"
                "GRID=背景图块网格(值=图块编号，相同编号=相同图案)；\n"
                "MEMDELTA=最近几十帧里发生变化的 RAM 区域。\n\n" + state_text
            )
            reply = llm_chat(prompt, None)

        # ---- 模式 B：视觉（送截图）----
        else:
            # 画面还在变 -> 是动画/过场，先让它跑完，不下指令
            if shot and prev:
                _, h1 = encode_frame(shot)
                _, h2 = encode_frame(prev)
                if h1 != h2:
                    return "THOUGHT: 画面仍在变化（动画/过场），等待\nSTABLE: 0\nWAIT: 12\nEND\n"
            b64, _ = encode_frame(shot)
            reply = llm_chat(prompt, b64)
        d = parse_decision(reply)
        acts = ST.anti_stall(d["actions"])

        if acts:
            ST.last_action = acts[0]
            ST.history.append(f"{step}: {d['screen']} -> {'+'.join(acts)}")
        else:
            ST.history.append(f"{step}: {d['screen']} -> 等待")

        log_jsonl(
            {
                "t": time.strftime("%H:%M:%S"),
                "step": step,
                "screen": d["screen"],
                "thought": d["thought"],
                "actions": acts,
                "wait": d["wait"],
                "raw": reply[:800],
            }
        )

        out = [f"THOUGHT: {d['thought']}", "STABLE: 1"]
        out += [f"ACT: {a}" for a in acts]
        out.append(f"WAIT: {d['wait']}")
        out.append("END")
        return "\n".join(out) + "\n"


ARGS = None


def main() -> None:
    global ARGS, SCALE
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080", help="llama.cpp server 地址")
    ap.add_argument("--model", default="local")
    ap.add_argument("--profile", default="strategy", choices=list(PROFILES))
    ap.add_argument("--scale", type=int, default=4, help="截图放大倍数")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--max-state-chars", type=int, default=6000, help="状态文本上限，防爆上下文")
    ap.add_argument("--no-think", action="store_true", default=True)
    ARGS = ap.parse_args()
    SCALE = ARGS.scale

    srv = ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler)
    print(f"[brain] listening http://127.0.0.1:{ARGS.port}", flush=True)
    print(f"[brain] backend={ARGS.url}  profile={ARGS.profile}  scale={SCALE}x", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n[brain] bye", flush=True)


if __name__ == "__main__":
    main()
