"""接管当前可见战局的 v2 控制器：多阵营（红/蓝/绿…）+ 城市补给战术。

和 v1（tools/play_current.py）的区别：
  * 攻击/反击/占领/敌首都 全部按「目标阵营」参数化 —— 遇到 红方+黑方 这种多阵营地图不再只打一方；
  * 战术会利用城市补给：回合开始站在自家 0x10 首都 / 0x11 市街 / 0x14 村落 上，HP/燃料/弹药补满；
  * 缺编（残血/缺油/没弹）的单位会主动回城补给，满编单位不会被钉在城里；
  * 开局打印所有阵营（名称/资金/敌对关系）。

用法：
  python tools/play_current2.py                 # 接管当前窗口并开打
  python tools/play_current2.py --check         # 只接管并检查，不开打
  python tools/play_current2.py --speed 800     # 战斗速度（10..1600）
  python tools/play_current2.py --pid 12345     # 指定模拟器进程
"""
from __future__ import annotations
import argparse
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
RUN = ROOT / 'shots/current_battle2'
LOG = ROOT / 'logs/current_battle2.txt'
MUTEX = 'Local\\GbaAiPlayCurrent2V2'


def reply():
    try:
        lines = (RUN / 'reply.txt').read_text(encoding='utf-8').splitlines()
        return int(lines[0].removeprefix('seq=')), '\n'.join(lines[1:])
    except (OSError, ValueError, IndexError):
        return -1, ''


def render_trace():
    result = subprocess.run([sys.executable, str(ROOT / 'tools/battle_trace.py'),
                             '--log',str(LOG),'--state',str(RUN/'state.txt'),
                             '--output',str(RUN/'trajectory.html')],
                            cwd=ROOT, capture_output=True, text=True)
    if result.returncode == 0:
        print(result.stdout.strip(), flush=True)
    else:
        print('轨迹页面生成失败，原始日志仍保留。', flush=True)


def send(seq: int, line: str) -> None:
    tmp, dst = RUN / 'command.tmp', RUN / 'command.txt'
    payload = f'seq={seq}\n{line}\n'
    for _ in range(120):
        try:
            tmp.write_text(payload, encoding='utf-8')
            tmp.replace(dst)
            return
        except (PermissionError, OSError):
            dst.write_text('', encoding='utf-8')
            time.sleep(0.25)
    raise RuntimeError('无法写入命令文件（被占用）')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--speed', type=int, default=200)
    ap.add_argument('--pid', type=int, default=0)
    ap.add_argument('--timeout', type=int, default=3600)
    ap.add_argument('--check', action='store_true', help='仅接管并检查，不开始战斗')
    args = ap.parse_args()
    if not 10 <= args.speed <= 1600 or args.timeout <= 0:
        ap.error('speed: 10..1600; timeout must be positive')
    if os.name != 'nt':
        ap.error('Windows is required')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.restype = ctypes.c_void_p
    handle = kernel.CreateMutexW(None, False, MUTEX)
    if not handle or ctypes.get_last_error() == 183:
        raise RuntimeError('另一个 Play-Current2 正在运行，请等待它结束。')
    try:
        print('接管当前可见战局（v2：多阵营 + 城市补给）；不会载入固定开局存档。', flush=True)
        try:
            audio = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                    '-File', str(ROOT/'tools/audio_diag.ps1'), '-UnmuteEmulator'],
                                   capture_output=True, text=True, timeout=15)
            if audio.returncode == 0:
                rows = json.loads(audio.stdout or '[]')
                if isinstance(rows, dict):
                    rows = [rows]
                if any(row.get('Changed') for row in rows):
                    print('已恢复模拟器的 Windows 独立音量。', flush=True)
            else:
                print('Windows 独立音量检查未完成；可手动检查音量混合器。', flush=True)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            print('Windows 独立音量检查未完成；继续接管。', flush=True)
        subprocess.run([sys.executable, str(ROOT / 'tools/native_attack.py'),
                        '--build', '--current2'], cwd=ROOT, check=True)
        RUN.mkdir(parents=True, exist_ok=True)
        (RUN / 'reply.txt').unlink(missing_ok=True)
        subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                        str(ROOT / 'tools/attach_current.ps1'), '-GamePid', str(args.pid),
                        '-ScriptPath', str(ROOT / 'lua/current_battle2.lua')],
                       cwd=ROOT, check=True, timeout=90)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            seq, text = reply()
            if seq == 0 and text.startswith('READY'):
                break
            error = RUN / 'error.txt'
            if error.exists():
                raise RuntimeError(error.read_text(encoding='utf-8'))
            time.sleep(.2)
        else:
            raise TimeoutError('Lua 未就绪；查看模拟器 Lua Console。')
        if args.check:
            print('接管检查成功，未开始战斗。')
            return 0
        send(1, f'CURRENT {args.speed}')
        deadline, seen = time.monotonic() + args.timeout, 0
        last_tick=time.monotonic()
        while time.monotonic() < deadline:
            tick=time.monotonic()
            manual=RUN/'manual_wait.txt'
            if manual.exists() and manual.read_text(encoding='utf-8',errors='replace').strip():
                deadline+=tick-last_tick
            last_tick=tick
            seq, text = reply()
            if seq == 1:
                print(text, flush=True)
                render_trace()
                print('窗口与恢复存档保留。')
                return 0 if text.startswith('OK VICTORY') else 1
            lines = LOG.read_text(encoding='utf-8', errors='replace').splitlines() if LOG.exists() else []
            for line in lines[seen:]:
                if any(tag in line for tag in ('CURRENT ', 'STRATEGY ', 'REPLAN ', 'CAPTURE_SWAP ', 'OFFENSE ', 'SUPPLY_SWAP ', 'WAIT_FIRE ', 'WAIT_REASON ', 'MANUAL_', 'EVAL ', 'FIREPLAN ', 'PLAN ', 'DEADLINE ', 'FACTIONS', 'FACTION ', 'SIDES ',
                                               'TURN ', 'ENDTURN', 'ORDER ', 'DEFEND ', 'CAPTURE ',
                                               'DIRECT', 'VICTORY', 'FAIL', 'FATAL')):
                    print(line, flush=True)
            seen = len(lines)
            error = RUN / 'error.txt'
            if error.exists():
                raise RuntimeError(error.read_text(encoding='utf-8'))
            time.sleep(.5)
        raise TimeoutError('等待超时；模拟器仍保留，请勿同时启动另一个控制器。')
    finally:
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        kernel.CloseHandle(handle)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(f'停止：{exc}', file=sys.stderr)
        sys.exit(1)
