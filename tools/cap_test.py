"""cap_test.py — 占领（CAP）命令端到端验证驱动
单进程内完成：启动 EmuHawk(bridge) → 等待 READY → 发命令序列 → 收集回复 → 关闭。
用法: python tools/cap_test.py "<命令1>" "<命令2>" ...
"""
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYS = ROOT / "shots" / "native_attack"
EMU = ROOT / "tools" / "EmuHawk.exe"
ROM = ROOT / "roms" / "0219 - Daisenryaku.gba"
LUA = ROOT / "lua" / "native_attack.lua"
LOG = ROOT / "logs" / "cap_test_emu.log"


def kill_emus():
    subprocess.run(["taskkill", "/IM", "EmuHawk.exe", "/F"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_reply(seq, timeout):
    deadline = time.monotonic() + timeout
    rp = SYS / "reply.txt"
    while time.monotonic() < deadline:
        if rp.exists():
            txt = rp.read_text(encoding="utf-8", errors="replace")
            if txt.startswith(f"seq={seq}\n"):
                return txt.splitlines()[1]
        ep = SYS / "error.txt"
        if ep.exists():
            return "ERR " + ep.read_text(encoding="utf-8", errors="replace")[:200]
        time.sleep(0.25)
    return "TIMEOUT"


def send(seq, line):
    tmp = SYS / "command.tmp"
    tmp.write_text(f"seq={seq}\n{line}\n", encoding="utf-8")
    tmp.replace(SYS / "command.txt")
    return wait_reply(seq, 180)


def main() -> int:
    cmds = sys.argv[1:] or ["SNAP", "POSITION 13 17 29", "CAP 13", "CAP 13", "CAP 0"]
    kill_emus()
    for f in ("reply.txt", "error.txt", "command.txt", "command.tmp"):
        p = SYS / f
        if p.exists():
            p.unlink()
    with open(LOG, "wb") as logf:
        proc = subprocess.Popen([str(EMU), str(ROM), f"--lua={LUA}"],
                                cwd=str(ROOT), stdout=logf, stderr=logf)
    try:
        print("[wait] bridge READY ...", flush=True)
        r = wait_reply(0, 240)
        print("[ready]", r, flush=True)
        if r == "TIMEOUT":
            return 2
        for i, c in enumerate(cmds, start=1):
            out = send(i, c)
            print(f"[{i}] {c} -> {out}", flush=True)
        st = SYS / "state.txt"
        if st.exists():
            txt = st.read_text(encoding="utf-8", errors="replace")
            for line in txt.splitlines():
                if line.startswith(("MY ", "EN ", "CTX")):
                    print("[state]", line[:300], flush=True)
    finally:
        proc.terminate()
        time.sleep(1)
        kill_emus()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
