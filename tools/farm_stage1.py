"""Replay scenario 1 with the same commander until the next native promotion.

python tools/farm_stage1.py --speed 400
python tools/farm_stage1.py --continue --completed 1 --speed 400
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

import play_stage1 as driver

ROOT, RUN = driver.ROOT, driver.RUN
LOG = ROOT / "logs/native_attack.txt"
JOURNAL = ROOT / "logs/farm_stage1_commands.jsonl"


def command(line: str, timeout: float = 180) -> str:
    previous, _ = driver.read_reply()
    seq = max(0, previous) + 1
    driver.send_command(seq, line)
    deadline, seen = time.monotonic() + timeout, len(driver.tail(LOG, 100000))
    while time.monotonic() < deadline:
        got, reply = driver.read_reply()
        if got == seq:
            print(reply.splitlines()[0], flush=True)
            with JOURNAL.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps({"time": time.time(), "command": line, "reply": reply}, ensure_ascii=False) + "\n")
            if not reply.startswith("OK "):
                raise RuntimeError(reply)
            return reply
        lines = driver.tail(LOG, 100000)
        for entry in lines[seen:]:
            if any(tag in entry for tag in ("TURN ", "ENDTURN", "FARM ", "CREDITED", "PROMOTED", "FATAL", "FAIL")):
                print(entry, flush=True)
        seen = len(lines)
        error = RUN / "error.txt"
        if error.exists():
            raise RuntimeError(error.read_text(encoding="utf-8"))
        time.sleep(.3)
    raise TimeoutError(f"Still pending: {line}; emulator and checkpoints retained")


def profile() -> dict:
    reply = command("PROFILE")
    return {key: int(value) for key, value in re.findall(r"(rank|points|money|state)=(\d+)", reply)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--speed", type=int, default=200)
    ap.add_argument("--continue", dest="continue_live", action="store_true", help="接着运行中的同一档案，不载入开局存档")
    ap.add_argument("--completed", type=int, default=0, help="--continue 时已经刷完的局数")
    ap.add_argument("--max-runs", type=int, default=12)
    args = ap.parse_args()
    if not 10 <= args.speed <= 1600 or args.completed < 0 or args.max_runs <= args.completed:
        ap.error("速度需10..1600，局数需为有效非负值且小于上限")
    completed = args.completed
    if not args.continue_live:
        result = subprocess.run([sys.executable, "-u", str(ROOT / "tools/play_stage1.py"),
                                 "--speed", str(args.speed)], cwd=ROOT)
        if result.returncode:
            return result.returncode
        completed = 1
    current = profile()
    starting_rank, target_rank = current["rank"], current["rank"] + 1
    history = [{"round": completed, **current, "kind": "credited_start_checkpoint"}]
    print(f"FARM: completed={completed} rank={starting_rank}; target={target_rank}; points={current['points']}", flush=True)
    while completed < args.max_runs:
        before = current["points"]
        if current["state"] == 8:
            command(f"REPLAYFIRST {args.speed}", 240)
        elif current["state"] != 7:
            raise RuntimeError("Continue requires a credited result or a ready battle checkpoint")
        ready = profile()
        if ready["points"] != before or ready["rank"] != starting_rank:
            raise RuntimeError("Commander continuity check failed before replay")
        number = completed + 1
        prefix = f"farm_stage1_round{number:02d}"
        command(f"PREFIX {prefix}")
        victory = command(f"AUTOCLEAR {args.speed}", 1200)
        if not victory.startswith("OK VICTORY"):
            raise RuntimeError(victory)
        current = profile()
        if current["points"] <= before:
            raise RuntimeError("Victory appeared but native points were not credited")
        completed = number
        command(f"SAVE {prefix}_credited")
        shutil.copyfile(RUN / "current.png", ROOT / f"shots/{prefix}.png")
        history.append({"round": completed, "earned": current["points"] - before, **current})
        summary = {"starting_rank": starting_rank, "target_rank": target_rank,
                   "completed_rounds": completed, "history": history,
                   "promoted": current["rank"] >= target_rank}
        (ROOT / "logs/farm_stage1_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"FARM ROUND {completed}: earned={current['points']-before} total={current['points']} rank={current['rank']}", flush=True)
        if current["rank"] >= target_rank:
            command("SAVE farm_rank_promotion")
            shutil.copyfile(RUN / "current.png", ROOT / "shots/farm_rank_promotion.png")
            shutil.copyfile(LOG, ROOT / "logs/farm_stage1_full.txt")
            print("PROMOTED: 原生军衔已升级，窗口与晋升存档保留。", flush=True)
            return 0
    print("达到本次局数上限，尚未晋升；进度和档案均已保留。", flush=True)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
