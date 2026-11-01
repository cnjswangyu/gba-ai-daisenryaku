"""v2_battle_test.py — 端到端验证 v2 会同时对两个敌对阵营开火。

用 states/v2_fixture.State（蓝=我方40 / 红阵营1×2 / 绿阵营2×2），跑 v2 的 CURRENT，
然后统计日志里 (side1) 与 (side2) 的攻击条目。任一方没被打到就判失败。

用法: python tools/v2_battle_test.py [--speed 800] [--limit 400]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYS = ROOT / "shots" / "native_attack"
EMU = ROOT / "tools" / "EmuHawk.exe"
ROM = ROOT / "roms" / "0219 - Daisenryaku.gba"
TEST_LUA = ROOT / "lua" / "current_battle2_battletest.lua"
LOG = ROOT / "logs" / "current_battle2.txt"


def kill_emus() -> None:
    subprocess.run(["taskkill", "/IM", "EmuHawk.exe", "/F"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def make_test_script(state: str) -> None:
    src = (ROOT / "lua/current_battle2.lua").read_text(encoding="utf-8")
    attach = ('for i=1,8 do assert(r8(HOOK+i-1)==original[i],"Previous combat hook is active; '
              'finish the old controller or load a safe checkpoint") end\n restore_keyboard() '
              '-- attach: never load a fixed state')
    assert attach in src, "找不到接管现场那一行"
    src = src.replace(attach, 'adv(20); savestate.load(LOAD_STATE); adv(40); restore_keyboard()')
    src = src.replace('local RUN=BASE .. "shots/current_battle2/"', 'local RUN=BASE .. "shots/native_attack/"')
    TEST_LUA.write_text(src, encoding="utf-8")


def send(seq: int, line: str) -> None:
    tmp, dst = SYS / "command.tmp", SYS / "command.txt"
    payload = f"seq={seq}\n{line}\n"
    for _ in range(120):
        try:
            tmp.write_text(payload, encoding="utf-8")
            tmp.replace(dst)
            return
        except (PermissionError, OSError):
            dst.write_text("", encoding="utf-8")
            time.sleep(0.25)
    raise RuntimeError("命令文件写不进去")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default="v2_fixture")
    ap.add_argument("--speed", default="800")
    ap.add_argument("--limit", type=float, default=400)
    args = ap.parse_args()

    print(f"[build] v2 桥 (LOAD_STATE={args.state})", flush=True)
    subprocess.run([sys.executable, str(ROOT / "tools/native_attack.py"),
                    "--build", "--current2", "--load", args.state], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    make_test_script(args.state)
    kill_emus()
    LOG.write_text("", encoding="utf-8")
    for f in ("reply.txt", "error.txt", "command.txt", "command.tmp"):
        (SYS / f).unlink(missing_ok=True)
    with open(ROOT / "logs/v2_battle_test_emu.log", "wb") as logf:
        proc = subprocess.Popen([str(EMU), str(ROM), f"--lua={TEST_LUA}"],
                                cwd=str(ROOT), stdout=logf, stderr=logf)
    try:
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            rp = SYS / "reply.txt"
            if rp.exists() and rp.read_text(encoding="utf-8", errors="replace").startswith("seq=0\n"):
                break
            if (SYS / "error.txt").exists():
                print("ERR", (SYS / "error.txt").read_text(encoding="utf-8", errors="replace")[:300])
                return 2
            time.sleep(0.3)
        else:
            print("TIMEOUT waiting READY")
            return 2
        print("[run] CURRENT", args.speed, flush=True)
        send(1, f"CURRENT {args.speed}")
        t0 = time.monotonic()
        seen, done = 0, None
        while time.monotonic() - t0 < args.limit:
            seq, _ = -1, ""
            try:
                lines = (SYS / "reply.txt").read_text(encoding="utf-8").splitlines()
                seq = int(lines[0].removeprefix("seq="))
            except Exception:
                pass
            if seq == 1:
                done = "battle finished"
                break
            if LOG.exists():
                rows = LOG.read_text(encoding="utf-8", errors="replace").splitlines()
                for row in rows[seen:]:
                    if any(t in row for t in ("FACTION", "SIDES", "DIRECT", "ORDER U", "ENDTURN",
                                              "VICTORY", "FAIL", "FATAL", "CAPTURE")):
                        print("  " + row[:150], flush=True)
                seen = len(rows)
            time.sleep(1.0)
        txt = LOG.read_text(encoding="utf-8", errors="replace") if LOG.exists() else ""
        (ROOT / "logs/v2_battle_test_digest.txt").write_text(txt, encoding="utf-8")
        hits = {}
        for m in re.finditer(r"DIRECT U\d+ -> E(\d+)\(side(\d+)\)", txt):
            hits.setdefault(int(m.group(2)), set()).add(int(m.group(1)))
        print(f"\n[结果] {'战斗结束' if done else '到达时间上限'}  攻击目标阵营统计={ {k: len(v) for k, v in hits.items()} }")
        ok = 1 in hits and 2 in hits
        print(("PASS" if ok else "FAIL") + ": 必须同时攻击 side1 与 side2（多阵营）")
        return 0 if ok else 1
    finally:
        proc.terminate()
        time.sleep(1)
        kill_emus()


if __name__ == "__main__":
    raise SystemExit(main())
