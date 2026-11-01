"""Assemble the bridge's unmodified emulator screenshots into a watchable GIF."""
from pathlib import Path
import argparse

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("recording")
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--append", action="append", default=[], help="Append another recorded segment")
    ap.add_argument("--session", choices=["first_clear", "native_attack"], default="first_clear")
    args = ap.parse_args()
    session = ROOT / "shots" / args.session
    frames = sorted((session / "frames").glob(args.recording + "_*.png"))
    for segment in args.append:
        frames.extend(sorted((session / "frames").glob(segment + "_*.png")))
    if not frames:
        ap.error("No captured emulator frames")
    images = []
    for path in frames:
        with Image.open(path) as source:
            images.append(source.resize((source.width * args.scale, source.height * args.scale),
                                        Image.Resampling.NEAREST).convert("RGB"))
    out = session / (args.recording + ".gif")
    images[0].save(out, save_all=True, append_images=images[1:],
                   duration=100, loop=0, optimize=True)
    print(f"{out} | {len(frames)} frames | {out.stat().st_size} bytes")
