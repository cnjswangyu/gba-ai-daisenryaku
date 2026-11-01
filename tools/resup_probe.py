"""resup_probe.py — 回合边界「城市补给（回 HP / 加油 / 补弹）」行为验证

单进程完成：build 桥(--load <state>) → 启动 EmuHawk → SNAP → ENDTURN → SNAP → 对比。

用法：
    python tools/resup_probe.py --state resup_test   --map logs/resup_test_map.txt
    python tools/resup_probe.py --state resup_matrix --map logs/resup_matrix_map.txt

--map 文件每行： 槽 \t x \t y \t 地形 \t 归属说明
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
LUA = ROOT / "lua" / "native_attack.lua"
LOGDIR = ROOT / "logs"


def kill_emus() -> None:
    subprocess.run(["taskkill", "/IM", "EmuHawk.exe", "/F"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_reply(seq: int, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    rp = SYS / "reply.txt"
    while time.monotonic() < deadline:
        if rp.exists():
            txt = rp.read_text(encoding="utf-8", errors="replace")
            if txt.startswith(f"seq={seq}\n"):
                return "\n".join(txt.splitlines()[1:])
        ep = SYS / "error.txt"
        if ep.exists():
            return "ERR " + ep.read_text(encoding="utf-8", errors="replace")[:300]
        time.sleep(0.25)
    return "TIMEOUT"


def send(seq: int, line: str, timeout: float = 900) -> str:
    tmp = SYS / "command.tmp"
    dst = SYS / "command.txt"
    payload = f"seq={seq}\n{line}\n"
    for _ in range(120):
        try:
            tmp.write_text(payload, encoding="utf-8")
            tmp.replace(dst)
            break
        except (PermissionError, OSError):
            dst.write_text("", encoding="utf-8")
            time.sleep(0.25)
    else:
        return "LOCKED"
    return wait_reply(seq, timeout)


UNIT_RE = re.compile(
    r"U(\d+) id(\d+) .* x(\d+) y(\d+) hp(\d+)/(\d+) f(\d+) st(\d+) act(\d+) ammo(\d+)")


def parse_units(txt: str) -> dict[int, dict]:
    out: dict[int, dict] = {}
    for line in txt.splitlines():
        m = UNIT_RE.match(line)
        if m:
            out[int(m.group(1))] = dict(id=int(m.group(2)), x=int(m.group(3)), y=int(m.group(4)),
                                        hp=int(m.group(5)), maxhp=int(m.group(6)), fuel=int(m.group(7)),
                                        st=int(m.group(8)), acted=int(m.group(9)), ammo=int(m.group(10)))
    return out


def snapshot(path: Path) -> dict[int, dict]:
    txt = (SYS / "state.txt").read_text(encoding="utf-8", errors="replace")
    path.write_text(txt, encoding="utf-8")
    return parse_units(txt)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default="resup_test")
    ap.add_argument("--map", default="")
    args = ap.parse_args()

    plan: list[tuple[int, int, int, int, str]] = []
    if args.map:
        for line in (ROOT / args.map).read_text(encoding="utf-8").splitlines():
            p = line.split("\t")
            if len(p) >= 5:
                plan.append((int(p[0]), int(p[1]), int(p[2]), int(p[3], 16), p[4]))

    print(f"[build] 桥 --load {args.state}", flush=True)
    subprocess.run([sys.executable, str(ROOT / "tools" / "native_attack.py"),
                    "--build", "--load", args.state], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    kill_emus()
    for f in ("reply.txt", "error.txt", "command.txt", "command.tmp"):
        (SYS / f).unlink(missing_ok=True)
    with open(LOGDIR / "resup_emu.log", "wb") as logf:
        proc = subprocess.Popen([str(EMU), str(ROM), f"--lua={LUA}"],
                                cwd=str(ROOT), stdout=logf, stderr=logf)
    try:
        print("[wait] 桥 READY ...", flush=True)
        r = wait_reply(0, 300)
        if r == "TIMEOUT":
            print("[ready] TIMEOUT")
            return 2
        send(1, "SNAP")
        before = snapshot(LOGDIR / "resup_before.txt")
        print("[run] ENDTURN ...", flush=True)
        t0 = time.monotonic()
        out = send(2, "ENDTURN")
        print(f"[endturn] {out.strip()[:200]}  ({time.monotonic()-t0:.0f}s)", flush=True)
        send(3, "SNAP")
        after = snapshot(LOGDIR / "resup_after.txt")

        rows = plan if plan else [(k, 0, 0, 0, "") for k in sorted(before)]
        print("槽 | 地形 | 归属 | 单位 | 位置 | HP | 燃料 | 弹药 | 结论", flush=True)
        for slot, x, y, terr, own in rows:
            b, a = before.get(slot), after.get(slot)
            if not b or not a:
                print(f"{slot:2} | 0x{terr:02X} | {own} | (无单位)", flush=True)
                continue
            resup = a["hp"] > b["hp"] or a["fuel"] > b["fuel"] or a["ammo"] > b["ammo"]
            same_pos = (a["x"], a["y"]) == b["x"], b["y"]
            mark = "★补给" if resup else ("—" if same_pos else "移动了")
            print(f"{slot:2} | 0x{terr:02X} | {own} | id{b['id']:3} | "
                  f"({a['x']},{a['y']}) | {b['hp']}->{a['hp']} | {b['fuel']}->{a['fuel']} | "
                  f"{b['ammo']}->{a['ammo']} | {mark}", flush=True)
        return 0
    finally:
        proc.terminate()
        time.sleep(1)
        kill_emus()


if __name__ == "__main__":
    raise SystemExit(main())
