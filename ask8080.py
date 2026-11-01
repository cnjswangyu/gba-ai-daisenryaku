#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""向本地 llama.cpp（8080）问一句话，可选带图。关掉 thinking，只要结论。

用法:
  python ask8080.py [-i 图] [-s 放大倍数] "问题"
  python ask8080.py -f prompt.txt
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import sys
import urllib.request

from PIL import Image


def img_b64(path: str, scale: int) -> str:
    im = Image.open(path).convert("RGB")
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt", nargs="?", default="")
    ap.add_argument("-f", "--file", help="prompt 文件")
    ap.add_argument("-i", "--image", help="附图")
    ap.add_argument("-s", "--scale", type=int, default=3)
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--max-tokens", type=int, default=700)
    ap.add_argument("--think", action="store_true", help="允许思考（默认关）")
    a = ap.parse_args()

    prompt = open(a.file, encoding="utf-8").read() if a.file else a.prompt
    if not prompt:
        print("需要 prompt", file=sys.stderr)
        raise SystemExit(2)

    content: list[dict] = [{"type": "text", "text": prompt}]
    if a.image:
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:image/png;base64,{img_b64(a.image, a.scale)}"},
        })

    payload = {
        "model": "local",
        "messages": [{"role": "user", "content": content}],
        "temperature": 0.3,
        "max_tokens": a.max_tokens,
        "stream": False,
    }
    if not a.think:
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    req = urllib.request.Request(
        f"{a.url}/v1/chat/completions",
        json.dumps(payload).encode(),
        {"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
    msg = d["choices"][0]["message"]
    print(msg.get("content", "").strip())


if __name__ == "__main__":
    main()
