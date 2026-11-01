"""第一关一键复现入口。

用法（项目根目录）:
    python tools/play_stage1.py             # 完整: 出击编成表 → 部署 → 战斗 → 胜利
    python tools/play_stage1.py --fast      # 跳过部署, 直接用 states/stage1_v2_deployed.State
    python tools/play_stage1.py --speed 150 # 战斗回放速度% (默认 200; 100=原速最可看, 800=快进)

流程:
  1. 构建原生攻击桥 (lua/native_attack.lua, --load stage1_v2_deployed)
  2. 部署阶段: EmuHawk 跑 lua/deploy_v2.lua (美方编成表 → 写 20 单位军表 → 勾选 → 出击 → 存档点)
  3. 战斗阶段: EmuHawk 跑 lua/native_attack.lua, 发 AUTOCLEAR <speed>
     - 移动 = VM（汇编级落格，受移动力/燃料约束）；攻击 = 原生结算函数；占领 = 原生 FUN_08020b20
     - 战术：原生移动力 + 实际伤害集火 + 首都驻防 + 原生占领/全歼结算
  4. 轮询战报直到 VICTORY / FAIL, 全程打印攻击摘要

结束后模拟器窗口保留 (停在胜利画面), 看完手动关闭即可。
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUN = ROOT / "shots" / "native_attack"
EMU = ROOT / "tools" / "EmuHawk.exe"
ROM = ROOT / "roms" / "0219 - Daisenryaku.gba"


def close_project_emulators() -> None:
    """Only close this project's ROM/bridge instances, preserving other games."""
    result = subprocess.run([
        "powershell", "-NoProfile", "-Command",
        "Get-CimInstance Win32_Process -Filter \"Name='EmuHawk.exe'\" | "
        "Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"],
        capture_output=True, text=True)
    processes = json.loads(result.stdout or "[]")
    if isinstance(processes, dict):
        processes = [processes]
    for process in processes:
        command = (process.get("CommandLine") or "").replace("\\", "/").lower()
        if str(ROOT).replace("\\", "/").lower() in command:
            subprocess.run(["taskkill", "/PID", str(process["ProcessId"]), "/T"],
                           capture_output=True)
    time.sleep(1)


def launch(lua: Path, log_name: str) -> subprocess.Popen:
    out = open(ROOT / "logs" / log_name, "w", encoding="utf-8", errors="replace")
    proc = subprocess.Popen([str(EMU), str(ROM), f"--lua={lua}"],
                            cwd=str(ROOT), stdout=out, stderr=subprocess.STDOUT)
    out.close()
    (RUN / "emulator_pid.txt").write_text(str(proc.pid), encoding="ascii")
    return proc


def wait_deploy(proc: subprocess.Popen, state: Path, timeout: float) -> bool:
    """部署脚本跑完会自行退出; 等进程结束 + 存档点刷新。"""
    deadline = time.monotonic() + timeout
    started = time.time() - 2
    while time.monotonic() < deadline:
        if state.name.startswith("stage2") and (ROOT / "logs/stage2_deploy_error.txt").exists():
            return False
        if proc.poll() is not None:
            time.sleep(2)
            return proc.returncode == 0 and state.exists() and state.stat().st_mtime >= started
        time.sleep(2)
    return False


def read_reply() -> tuple[int, str]:
    p = RUN / "reply.txt"
    if not p.exists():
        return -1, ""
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    if not lines or not lines[0].startswith("seq="):
        return -1, ""
    try:
        return int(lines[0][4:]), "\n".join(lines[1:])
    except ValueError:
        return -1, ""


def send_command(seq: int, line: str) -> None:
    tmp = RUN / "command.tmp"
    tmp.write_text(f"seq={seq}\n{line}\n", encoding="utf-8")
    deadline = time.monotonic() + 5
    while True:
        try:
            tmp.replace(RUN / "command.txt")
            return
        except PermissionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.05)


def tail(path: Path, n: int = 3) -> list[str]:
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()[-n:]
    except OSError:
        return []


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="第一/二关一键部署与战斗")
    ap.add_argument("--stage", type=int, choices=[1, 2], default=1)
    ap.add_argument("--fast", action="store_true",
                    help="跳过部署，使用相应关卡的部署存档或 --state")
    ap.add_argument("--speed", type=int, default=200,
                    help="战斗回放速度%%（默认 200；100=原速最可看，800=快进）")
    ap.add_argument("--state", default=None,
                    help="--fast 模式的战场存档名（不含 .State）")
    ap.add_argument("--timeout", type=int, default=1800,
                    help="战斗等待上限秒数（默认 1800）")
    args = ap.parse_args(argv)
    default_state = "stage2_deployed" if args.stage == 2 else "stage1_v2_deployed"
    args.state = args.state or default_state
    stage_label = "第二关" if args.stage == 2 else "第一关"
    log_prefix = "stage2" if args.stage == 2 else "play"
    if not args.state.replace("_", "").replace("-", "").isalnum():
        ap.error("--state 只允许字母、数字、下划线和连字符")
    if not args.fast and args.state != default_state:
        ap.error("自定义 --state 需同时使用 --fast")
    if not 10 <= args.speed <= 1600 or args.timeout < 1:
        ap.error("--speed 范围为 10..1600，--timeout 必须大于 0")

    if os.name != "nt":
        print("本脚本依赖 Windows 上的 EmuHawk。")
        return 1

    if args.stage == 2 and not args.fast and not (ROOT / "states/stage2_pre_battle.State").exists():
        print("缺少第二关出击前存档 states/stage2_pre_battle.State。")
        return 1
    print(f"== {stage_label}一键复现 ==")
    close_project_emulators()

    # 1) 构建桥
    print(f"[1/3] 构建原生攻击桥 (--load {args.state})…")
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "native_attack.py"),
                        "--build", "--load", args.state, "--stage", str(args.stage)],
                       cwd=str(ROOT), capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode != 0:
        print(r.stderr)
        return 1

    # 2) 部署阶段
    deployed = ROOT / "states" / f"{args.state}.State"
    if not args.fast:
        if args.stage == 2:
            (ROOT / "logs/stage2_deploy_error.txt").unlink(missing_ok=True)
        print("[2/3] 保留16老兵 → 补齐4单位 → 自动部署 → 开始战斗…" if args.stage == 2 else
              "[2/3] 部署阶段：出击编成表 → 写军表 → 勾选 → 自动部署 → 开始战斗…")
        deploy_script = "deploy_stage2.lua" if args.stage == 2 else "deploy_v2.lua"
        proc = launch(ROOT / "lua" / deploy_script, f"{log_prefix}_deploy_emu.log")
        if not wait_deploy(proc, deployed, timeout=600):
            print(f"部署失败：看 logs/{'stage2_deploy' if args.stage == 2 else 'deploy_v2'}.txt")
            return 1
        print("部署完成：20 单位已上场。")
    else:
        print(f"[2/3] --fast：跳过部署，复用现有 {deployed.name}")
    if not deployed.exists():
        print("缺少部署存档，请去掉 --fast 运行。")
        return 1

    # 3) 战斗阶段
    print(f"[3/3] 战斗阶段：AUTOCLEAR @ {args.speed}% …")
    for name in ("error.txt", "reply.txt", "command.txt", "command.tmp"):
        (RUN / name).unlink(missing_ok=True)
    proc = launch(ROOT / "lua" / "native_attack.lua", f"{log_prefix}_battle_emu.log")

    # 等 READY (seq=0)
    deadline = time.monotonic() + 300
    ready_seq = -1
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            print(f"模拟器提前退出：看 logs/{log_prefix}_battle_emu.log")
            return 1
        ready_seq, ready_text = read_reply()
        if ready_seq == 0 and "READY" in ready_text:
            break
        time.sleep(0.3)
    if ready_seq != 0 or "READY" not in ready_text:
        print("桥未就绪（超时）。")
        return 1
    print("桥就绪，发射 AUTOCLEAR…")
    window = subprocess.run([
        "powershell", "-NoProfile", "-File", str(ROOT / "tools/window_diag.ps1"),
        "-GamePid", str(proc.pid), "-Show"], capture_output=True, text=True)
    (ROOT / f"logs/stage{args.stage}_window.json").write_text(window.stdout, encoding="utf-8")

    seq = ready_seq + 1
    send_command(seq, f"AUTOCLEAR {args.speed}")

    # 轮询战报
    battle_log = ROOT / "logs" / ("stage2_native_attack.txt" if args.stage == 2 else "native_attack.txt")
    seen = 0
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        cur_seq, text = read_reply()
        if cur_seq >= seq and text:
            print("=" * 60)
            print("战报:", text.strip().splitlines()[0])
            if text.startswith("OK VICTORY"):
                print(f"{stage_label}通关 ✔  模拟器窗口保留（胜利画面），看完手动关闭。")
                return 0
            print(f"未胜利：检查 logs/{'stage2_native_attack' if args.stage == 2 else 'native_attack'}.txt 与 shots/native_attack/state.txt")
            return 1
        lines = tail(battle_log, 100000)
        for line in lines[seen:]:
            if any(tag in line for tag in ("DIRECT", "TURN ", "ENDTURN", "CAP ", "VICTORY", "FAIL", "FATAL")):
                print("  …", line.split("] ", 1)[-1], flush=True)
        seen = len(lines)
        error_path = RUN / "error.txt"
        if error_path.exists():
            print("执行失败：", error_path.read_text(encoding="utf-8", errors="replace"))
            return 1
        if proc.poll() is not None:
            print(f"模拟器进程退出（异常）。看 logs/{log_prefix}_battle_emu.log")
            return 1
        time.sleep(2)
    print(f"超时（{args.timeout} 秒）；窗口保留，可查看日志和最新回合存档。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
