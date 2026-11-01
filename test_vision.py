#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""单图视觉测试：走 OpenAI 兼容接口（llama.cpp server）。

用法:
  python test_vision.py <image> [prompt] [--url http://127.0.0.1:8080] [--scale 4] [--json]
"""
import argparse
import base64
import io
import json
import time
import urllib.request

from PIL import Image


def b64_of(path: str, scale: int) -> tuple[str, tuple[int, int]]:
    im = Image.open(path).convert("RGB")
    big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    buf = io.BytesIO()
    big.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode(), big.size


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("prompt", nargs="?", default=(
        "这是一台 Game Boy Advance 的画面。描述你看到的内容，"
        "并逐字读出画面上所有可见文字（包括很小的字）。"
    ))
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--model", default="local")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--json", action="store_true", help="要求输出 JSON 对象")
    a = ap.parse_args()

    b64, size = b64_of(a.image, a.scale)
    print(f"送图尺寸: {size}  base64 {len(b64)//1024} KB")

    payload = {
        "model": a.model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": a.prompt},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{b64}"},
                    },
                ],
            }
        ],
        "temperature": 0.1,
        "max_tokens": 400,
        "stream": False,
    }
    if a.json:
        payload["response_format"] = {"type": "json_object"}

    req = urllib.request.Request(
        f"{a.url}/v1/chat/completions",
        json.dumps(payload).encode(),
        {"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
    dt = time.time() - t0

    msg = d["choices"][0]["message"]
    print(f"\n--- 耗时 {dt:.2f}s ---")
    if msg.get("reasoning_content"):
        print("[thinking]", msg["reasoning_content"][:600])
    print(msg.get("content", ""))


if __name__ == "__main__":
    main()
