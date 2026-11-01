"""Continue a deployed battle with the visible driver used by Play-Stage1.cmd.

Example: python tools/run_battle.py --speed 200 --state stage1_v2_deployed
The verified result remains visible; unrelated emulators are left alone.
"""
from __future__ import annotations

import sys

from play_stage1 import main


if __name__ == "__main__":
    raise SystemExit(main(["--fast", *sys.argv[1:]]))
