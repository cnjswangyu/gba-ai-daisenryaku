"""Render the bridge's read-only MAPDATA dump using the ROM movement tables.

python tools/native_attack.py MAPDATA
python tools/map_overview.py --output shots/stage2_map
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import struct

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent


def grade(exp: int) -> str:
    return "A" if exp >= 240 else "B" if exp >= 150 else "C" if exp >= 80 else "D" if exp >= 30 else "E"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, default=ROOT / "shots/native_attack/map.json")
    ap.add_argument("--output", type=Path, default=ROOT / "shots/map_overview")
    ap.add_argument("--title", default="战场全图：地形、首都与部队部署")
    args = ap.parse_args()
    data = json.loads(args.input.read_text(encoding="utf-8"))
    rom = (ROOT / "roms/0219 - Daisenryaku.gba").read_bytes()
    tmap = struct.unpack_from("<I", rom, 0x26D4)[0] - 0x08000000

    def cost(terrain: int, category: int) -> int:
        if 0x10 <= terrain < 0x29:
            return rom[0x46FC6 + terrain - 0x10 + category * 5]
        return rom[0x46F26 + rom[tmap + terrain] + category * 16]

    land = [c for c in data["cells"] if c[2] != 0x0C]
    xmin, xmax = max(0, min(c[0] for c in land) - 1), min(47, max(c[0] for c in land) + 1)
    ymin, ymax = max(0, min(c[1] for c in land) - 1), min(47, max(c[1] for c in land) + 1)
    sx, sy, margin = 37, 32, 52
    plot_width = (xmax - xmin + 2) * sx + margin * 2
    height = max(720, (ymax - ymin + 2) * sy + 130)
    img = Image.new("RGB", (plot_width + 360, height), "#f1f5f9")
    draw = ImageDraw.Draw(img)
    font_path = "C:/Windows/Fonts/msyh.ttc"
    font = ImageFont.truetype(font_path, 17)
    small = ImageFont.truetype(font_path, 12)
    title = ImageFont.truetype(font_path, 25)
    draw.text((25, 14), args.title, font=title, fill="#0f172a")
    draw.text((25, 52), "来自 MAPDATA 实时内存；包含敌方单位数据，通行耗费读取原 ROM。", font=font, fill="#334155")

    def point(x: int, y: int) -> tuple[float, float]:
        return margin + (x - xmin + (y % 2) * .5) * sx, 112 + (y - ymin) * sy

    for x, y, terrain, durability, owner, flags in data["cells"]:
        if not xmin <= x <= xmax or not ymin <= y <= ymax:
            continue
        cx, cy = point(x, y)
        cls = rom[tmap + terrain]
        if terrain == 0x0C:
            fill = "#79b9e8"
        elif 0x10 <= terrain < 0x29:
            fill = "#fee2e2" if owner == 2 else "#bfdbfe" if owner == 1 else "#e2e8f0"
        elif not cost(terrain, 2) and not cost(terrain, 4):
            fill = "#94a3b8"
        else:
            fill = "#42845f" if cls == 4 else "#b5d9a8"
        vertices = [(cx, cy - 21), (cx + sx / 2, cy - 10.5), (cx + sx / 2, cy + 10.5),
                    (cx, cy + 21), (cx - sx / 2, cy + 10.5), (cx - sx / 2, cy - 10.5)]
        draw.polygon(vertices, fill=fill, outline="#ffffff")
        if terrain == 0x10:
            draw.ellipse((cx - 13, cy - 13, cx + 13, cy + 13), fill="#b91c1c" if owner == 2 else "#1d4ed8")
            draw.text((cx, cy), "HQ", anchor="mm", font=small, fill="white")
        elif 0x10 <= terrain < 0x29:
            draw.text((cx, cy), "城" if terrain == 0x11 else "村", anchor="mm", font=small, fill="#334155")
    for unit in data["units"]:
        cx, cy = point(unit["x"], unit["y"])
        color = "#b91c1c" if unit["side"] else "#1d4ed8"
        draw.ellipse((cx - 13, cy - 11, cx + 13, cy + 11), fill=color, outline="white", width=1)
        draw.text((cx, cy), ("E" if unit["side"] else "U") + str(unit["slot"]), anchor="mm", font=small, fill="white")
    for x in range(xmin, xmax + 1, 2):
        draw.text((point(x, ymin)[0], 82), str(x), anchor="mm", font=small, fill="#334155")
    for y in range(ymin, ymax + 1):
        draw.text((20, point(xmin, y)[1]), str(y), anchor="mm", font=small, fill="#334155")

    names = {187: "M1A2", 188: "T-72B", 241: "M-109A6", 243: "2S3", 235: "2A65", 211: "BRDM-3A 反坦克车",
             291: "BRDM-2 侦察车", 301: "轻步兵", 305: "轻步兵", 324: "空降兵", 339: "补给车", 340: "补给车"}
    tx, ty = plot_width + 12, 100
    def line(text: str, color: str = "#334155", step: int = 29) -> None:
        nonlocal ty
        draw.text((tx, ty), text, font=font, fill=color)
        ty += step

    line(f"敌军：{sum(u['side']==1 for u in data['units'])} 单位", "#b91c1c")
    for uid, count in Counter(u["id"] for u in data["units"] if u["side"] == 1).items():
        line(f"{names.get(uid, str(uid))} × {count}")
    ty += 15
    line(f"当前军表：{len(data['roster'])} 单位", "#1d4ed8")
    for uid, count in Counter(u["id"] for u in data["roster"]).items():
        line(f"{names.get(uid, str(uid))} × {count}")
    ty += 15
    line("当前老兵经验（前 3）：", "#0f172a")
    for u in sorted(data["roster"], key=lambda item: item["exp"], reverse=True)[:3]:
        line(f"槽{u['slot']} {names.get(u['id'], u['id'])}：{u['exp']} / {grade(u['exp'])}")
    ty += 15
    line("绿：可通行；深绿：高移耗")
    line("灰：履带/步兵均不可通行")
    line("蓝：0C 水面；灰白：中立城村")
    for x, y, terrain, durability, owner, flags in data["cells"]:
        if terrain == 0x10:
            line(f"{'我方' if owner == 1 else '敌/其他'}首都：({x},{y})")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    img.save(args.output.with_suffix(".png"))
    print(args.output.with_suffix(".png"))
    print("Roster experience:", [(u["slot"], u["exp"], grade(u["exp"])) for u in data["roster"]])


if __name__ == "__main__":
    main()
