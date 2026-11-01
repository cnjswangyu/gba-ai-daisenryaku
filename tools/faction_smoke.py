"""faction_smoke.py — v2 桥的端到端冒烟测试（多阵营识别）

做法：把 v2 脚本的「接管现场」改成「载入指定存档」，然后：
  1. 期望 `MY` = 我方单位数，`EN` = **所有敌对阵营之和**（不再是单一阵营）
  2. 每行 `E...` 末尾带 `sideN`，可直接核对来自哪一（几）个阵营
  3. 日志里应当出现 SIDES player=.. foes=[..] 之类信息（由战术模块打印）

默认用 221519_ready（军事演习3：蓝=40 / 红=27 / 绿=28，红绿都是敌对）。
用法: python tools/faction_smoke.py [state_basename]
"""
from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYS = ROOT / "shots" / "native_attack"
EMU = ROOT / "tools" / "EmuHawk.exe"
ROM = ROOT / "roms" / "0219 - Daisenryaku.gba"
TEST_LUA = ROOT / "lua" / "current_battle2_smoke.lua"

EXPECT = {
    # state 名 -> (我方差, 敌方阵营集合)
    "current_20261018_221519_ready": (0, {1, 2}),
    "current_20261018_224007_ready": (0, {1}),
}


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
    src = src.replace("states/current_", f"states/{state[:len('current_')]}" if False else "states/current_")
    TEST_LUA.write_text(src, encoding="utf-8")


def main() -> int:
    state = sys.argv[1] if len(sys.argv) > 1 else "current_20261018_221519_ready"
    print(f"[build] v2 桥脚本 (LOAD_STATE={state})", flush=True)
    subprocess.run([sys.executable, str(ROOT / "tools" / "native_attack.py"),
                    "--build", "--current2", "--load", state], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    make_test_script(state)
    kill_emus()
    for f in ("reply.txt", "error.txt", "command.txt", "command.tmp"):
        (SYS / f).unlink(missing_ok=True)
    with open(ROOT / "logs/faction_smoke_emu.log", "wb") as logf:
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
        tmp, dst = SYS / "command.tmp", SYS / "command.txt"
        for _ in range(120):
            try:
                tmp.write_text("seq=1\nSNAP\n", encoding="utf-8")
                tmp.replace(dst)
                break
            except (PermissionError, OSError):
                dst.write_text("", encoding="utf-8")
                time.sleep(0.25)
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            rp = SYS / "reply.txt"
            if rp.exists() and rp.read_text(encoding="utf-8", errors="replace").startswith("seq=1\n"):
                break
            time.sleep(0.3)
        txt = (SYS / "state.txt").read_text(encoding="utf-8", errors="replace")
        (ROOT / "logs/faction_smoke_state.txt").write_text(txt, encoding="utf-8")
        my = re.search(r"^MY (\d+)$", txt, re.M)
        en = re.search(r"^EN (\d+)$", txt, re.M)
        sides = sorted({int(m) for m in re.findall(r"^E\d+ id\d+ .* side(\d+)$", txt, re.M)})
        ctx = re.search(r"^CTX .*$", txt, re.M)
        print(f"MY={my.group(1) if my else '?'}  EN={en.group(1) if en else '?'}  enemy_sides={sides}")
        print("CTX:", ctx.group(0) if ctx else "(无)")
        want_player, want_foes = EXPECT.get(state, (None, None))
        if want_foes is not None:
            ok = set(sides) == want_foes
            print(("PASS" if ok else "FAIL") + f": 敌方阵营 {sides} vs 期望 {sorted(want_foes)}")
            return 0 if ok else 1
        return 0
    finally:
        proc.terminate()
        time.sleep(1)
        kill_emus()


if __name__ == "__main__":
    raise SystemExit(main())
