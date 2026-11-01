"""Build the release highlight video from recorded BizHawk frames.

Frames are the emulator's own 240x160 screenshots; they are scaled 3x with
nearest-neighbour so the GBA pixel grid stays intact.

Requires: pillow, imageio-ffmpeg (bundles an ffmpeg build with libx264).

python tools/make_release_video.py            # -> media/highlight.mp4
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

try:
    import imageio_ffmpeg
except ImportError:  # pragma: no cover
    sys.exit("install imageio-ffmpeg first: python -m pip install imageio-ffmpeg")

ROOT = Path(__file__).resolve().parent.parent
FRAMES = ROOT / "shots/first_clear/frames"
OUT = ROOT / "media/highlight.mp4"
W, H = 720, 480
FPS = 10

# One continuous story: tank attack -> infantry clean-up -> capital capture -> results.
SEGMENTS = ["turn2_tank", "turn2_infantry_finish", "turn3_capital", "final_victory"]

BG = (15, 23, 42)
BLUE = (96, 165, 250)
WHITE = (226, 232, 240)
GREY = (148, 163, 184)
FONT_CN = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"


def ffmpeg_encoder() -> subprocess.Popen:
    cmd = [
        imageio_ffmpeg.get_ffmpeg_exe(), "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(OUT),
    ]
    return subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def card(title: str, lines: list[tuple[str, int, tuple[int, int, int], int]], hold: int) -> list[np.ndarray]:
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # hex-grid hint borrowed from the game map
    for row in range(6):
        for col in range(11):
            cx = 40 + col * 64 + (32 if row % 2 else 0)
            cy = 40 + row * 72
            pts = [(cx + 26 * np.cos(np.pi / 3 * i), cy + 26 * np.sin(np.pi / 3 * i))
                   for i in range(6)]
            d.polygon(pts, outline=(30, 41, 59))
    title_font = FONT_CN if any(ord(ch) > 0x2E80 for ch in title) else FONT_BOLD
    d.text((36, 120), title, font=ImageFont.truetype(title_font, 76), fill=WHITE)
    y = 232
    for text, size, color, gap in lines:
        d.text((40, y), text, font=ImageFont.truetype(FONT_CN, size), fill=color)
        y += size + gap
    arr = np.asarray(img, dtype=np.uint8)
    return [arr.copy() for _ in range(hold)]


def scaled(path: Path) -> np.ndarray:
    with Image.open(path) as im:
        im = im.convert("RGB").resize((W, H), Image.Resampling.NEAREST)
        return np.asarray(im, dtype=np.uint8)


def main() -> int:
    enc = ffmpeg_encoder()
    assert enc.stdin is not None
    written = 0

    def emit(arr: np.ndarray) -> None:
        nonlocal written
        enc.stdin.write(arr.tobytes())
        written += 1

    for arr in card("GBA AI", [
        ("逆向 > 建模：直接调用游戏原生的移动 / 战斗 / 占领 / 补给函数", 22, BLUE, 14),
        ("No pixel reading · No reimplemented rules · BizHawk + Lua + Python", 18, GREY, 0),
    ], hold=15):
        emit(arr)

    for segment in SEGMENTS:
        files = sorted(FRAMES.glob(f"{segment}_*.png"))
        if not files:
            raise SystemExit(f"missing frames: {segment}")
        for path in files:
            emit(scaled(path))

    for arr in card("大 勝 利", [
        ("第 3 回合 · 剩 16 单位 · 1706 P", 30, WHITE, 18),
        ("全程由脚本调用原生战斗结算，非模拟规则", 20, GREY, 0),
    ], hold=20):
        emit(arr)

    enc.stdin.close()
    if enc.wait() != 0:
        raise SystemExit("ffmpeg failed")
    print(f"{OUT} | {written} frames | {OUT.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
