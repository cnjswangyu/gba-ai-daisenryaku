"""Second scenario: retain veterans, fill 20 slots, deploy and fight visibly.

python tools/play_stage2.py --speed 200
python tools/play_stage2.py --fast --state stage2_t5 --speed 200
"""
from __future__ import annotations

import sys

from play_stage1 import main


if __name__ == "__main__":
    raise SystemExit(main(["--stage", "2", *sys.argv[1:]]))
