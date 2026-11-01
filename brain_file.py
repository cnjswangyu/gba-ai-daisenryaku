#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
文件握手版大脑：不占端口、不依赖 BizHawk 的 HTTP 功能。

工作方式：
    BizHawk(Lua) 写 shots/state.txt  ->  本脚本轮询发现 step 变化
    -> 调本地 llama.cpp 模型分析纯文本状态  ->  写 shots/action.txt

action.txt 格式：
    step=3
    THOUGHT: ...
    ACT: A
    WAIT: 24
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import time
from types import SimpleNamespace

import brain

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HERE, "shots", "state.txt")
ACTION = os.path.join(HERE, "shots", "action.txt")
SHOT = os.path.join(HERE, "shots", "cur.png")
LOG = os.path.join(HERE, "logs", "brain_file.log")


def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--model", default="local")
    ap.add_argument("--profile", default="strategy")
    ap.add_argument("--max-state-chars", type=int, default=6000)
    ap.add_argument("--vision", action="store_true",
                    help="同时把 shots/cur.png 送给视觉模型（Lua 侧每步会存图）")
    a = ap.parse_args()

    brain.ARGS = SimpleNamespace(  # type: ignore[assignment]
        url=a.url, model=a.model, profile=a.profile,
        no_think=True, max_state_chars=a.max_state_chars,
    )

    log(f"watching {STATE} -> {ACTION}")
    last_step = -1
    idle_since = time.time()

    while True:
        try:
            if not os.path.exists(STATE):
                time.sleep(0.2)
                continue
            with open(STATE, encoding="utf-8", errors="replace") as f:
                text = f.read()
            m = re.search(r"step=(\d+)", text)
            if not m:
                time.sleep(0.2)
                continue
            step = int(m.group(1))
            if step == last_step:
                if time.time() - idle_since > 2:
                    time.sleep(0.2)
                continue

            last_step = step
            idle_since = time.time()

            # 历史只保留最近几条，避免上下文膨胀
            hist = getattr(brain.ST, "history", [])
            prompt = brain.build_prompt(a.profile, step, "", hist)

            img_b64 = None
            if a.vision:
                try:
                    img_b64, _h = brain.encode_frame(SHOT)
                    prompt += (
                        "\n\n--- 下面是当前 GBA 画面截图（原始 240x160，已放大）---\n"
                        "以图为准：图上看不清的东西不要编。\n"
                    )
                except Exception as e:  # noqa: BLE001
                    log(f"读图失败，退回纯文本: {e!r}")
                    a.vision = False

            if not a.vision:
                prompt += (
                    "\n\n--- 下面是直接从 GBA 内存/显存读出的**游戏状态**（不是截图）---\n"
                    "格式说明：step/frame=步数与帧号；GFXMODE=显示模式(>=3 是位图，没有 tilemap)；\n"
                    "GRID=背景图块网格(30 列 x 20 行，0=空，相同编号=同一图案，可据此判断界面布局)；\n"
                    "OAM=精灵表(每个精灵的屏幕像素坐标，战棋类里通常就是一个单位/光标)；\n"
                    "MEM=当前有数据的 RAM 区域。\n\n" + text[: a.max_state_chars]
                )

            t0 = time.time()
            reply = brain.llm_chat(prompt, img_b64)
            d = brain.parse_decision(reply)
            acts = brain.ST.anti_stall(d["actions"])
            log(f"step {step}: {d['screen']} | {d['thought'][:70]} | {acts} ({time.time()-t0:.1f}s)")

            if acts:
                brain.ST.last_action = acts[0]
                hist.append(f"{step}: {d['screen']} -> {'+'.join(acts)}")
            else:
                hist.append(f"{step}: {d['screen']} -> 等待")
            del hist[:-8]

            out = [f"step={step}", f"THOUGHT: {d['thought']}"]
            out += [f"ACT: {x}" for x in acts]
            out.append(f"WAIT: {d['wait']}")
            out.append("END")

            tmp = ACTION + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write("\n".join(out) + "\n")
            os.replace(tmp, ACTION)   # 原子替换，Lua 不会读到半个文件
            brain.log_jsonl(
                {"t": time.strftime("%H:%M:%S"), "step": step, "screen": d["screen"],
                 "thought": d["thought"], "actions": acts, "wait": d["wait"], "raw": reply[:600]}
            )
        except KeyboardInterrupt:
            log("bye")
            return
        except Exception as e:  # noqa: BLE001
            log(f"error: {e!r}")
            time.sleep(1)


if __name__ == "__main__":
    main()
