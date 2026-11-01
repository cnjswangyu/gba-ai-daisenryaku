"""Use R preview on the live deployment screen and export a full terrain diagram."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

from native_attack import bridge, RUN

ROOT = Path(__file__).resolve().parent.parent


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="shots/map_overview")
    parser.add_argument("--title", default="战场全图：地形、首都与部队部署")
    parser.add_argument("--data-only", action="store_true", help="只刷新数据与全图，不按 R")
    args = parser.parse_args()
    bridge.DIR = RUN
    if not args.data_only:
        bridge.command("VIEWMAP", 20)
    bridge.command("MAPDATA", 20)
    subprocess.run([sys.executable, str(ROOT / "tools/map_overview.py"),
                    "--output", args.output, "--title", args.title], cwd=ROOT, check=True)
