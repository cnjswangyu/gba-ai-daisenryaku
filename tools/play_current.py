"""Attach to the visible current game; play only that scenario, retaining its profile."""
from __future__ import annotations
import argparse
import ctypes
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
RUN = ROOT / 'shots/current_battle'

def reply():
    try:
        lines = (RUN / 'reply.txt').read_text(encoding='utf-8').splitlines()
        return int(lines[0].removeprefix('seq=')), '\n'.join(lines[1:])
    except (OSError, ValueError, IndexError):
        return -1, ''

def render_trace():
    result=subprocess.run([sys.executable,str(ROOT/'tools/battle_trace.py')],
                          cwd=ROOT,capture_output=True,text=True)
    if result.returncode==0:
        print(result.stdout.strip(),flush=True)
    else:
        print('轨迹页面生成失败，原始日志仍保留。',flush=True)

def main_legacy():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--speed', type=int, default=200)
    ap.add_argument('--pid', type=int, default=0)
    ap.add_argument('--timeout', type=int, default=1800)
    ap.add_argument('--check', action='store_true', help='仅接管并检查，不开始战斗')
    args = ap.parse_args()
    if not 10 <= args.speed <= 1600 or args.timeout <= 0:
        ap.error('speed: 10..1600; timeout must be positive')
    if os.name != 'nt':
        ap.error('Windows is required')
    # Global named mutex: two double-clicks must not create two controllers.
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.restype = ctypes.c_void_p
    handle = kernel.CreateMutexW(None, False, 'Local\\GbaAiPlayCurrent')
    if not handle or ctypes.get_last_error() == 183:
        raise RuntimeError('另一个 Play-Current 正在运行，请等待它结束。')
    try:
        print('接管当前可见游戏；不会载入固定开局存档。', flush=True)
        subprocess.run([sys.executable, str(ROOT/'tools/native_attack.py'), '--build', '--current'], cwd=ROOT, check=True)
        (RUN/'reply.txt').unlink(missing_ok=True)
        subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                        str(ROOT/'tools/attach_current.ps1'), '-GamePid', str(args.pid),
                        '-ScriptPath', str(ROOT/'lua/current_battle.lua')], cwd=ROOT, check=True, timeout=90)
        deadline = time.monotonic()+60
        while time.monotonic()<deadline:
            seq, text = reply()
            if seq == 0 and text.startswith('READY'):
                break
            error=RUN/'error.txt'
            if error.exists():
                raise RuntimeError(error.read_text(encoding='utf-8'))
            time.sleep(.2)
        else:
            raise TimeoutError('Lua 未就绪；查看模拟器 Lua Console。')
        if args.check:
            print('接管检查成功，未开始战斗。')
            return 0
        tmp=RUN/'command.tmp'
        tmp.write_text(f'seq=1\nCURRENT {args.speed}\n', encoding='utf-8')
        tmp.replace(RUN/'command.txt')
        deadline, seen = time.monotonic()+args.timeout, 0
        while time.monotonic()<deadline:
            seq, text = reply()
            if seq == 1:
                print(text, flush=True)
                render_trace()
                print('窗口与恢复存档保留。')
                return 0 if text.startswith('OK VICTORY') else 1
            log = ROOT/'logs/current_battle.txt'
            lines=log.read_text(encoding='utf-8', errors='replace').splitlines() if log.exists() else []
            for line in lines[seen:]:
                if any(tag in line for tag in ('CURRENT ', 'STRATEGY ', 'ENDGAME ', 'CLEANUP ', 'BLOCKED ', 'STALEMATE ', 'FINISHER ', 'RECOVER ', 'TURN ', 'ENDTURN', 'ORDER ', 'DEFEND ', 'CAPTURE ', 'VICTORY', 'FAIL', 'FATAL')):
                    print(line, flush=True)
            seen=len(lines)
            error=RUN/'error.txt'
            if error.exists():
                raise RuntimeError(error.read_text(encoding='utf-8'))
            time.sleep(.5)
        raise TimeoutError('等待超时；模拟器仍保留，请勿同时启动另一个控制器。')
    finally:
        kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        kernel.CloseHandle(handle)

def main():
    # Keep the familiar entry point, but never silently use the side-1-only bridge.
    if '--legacy-single-enemy' in sys.argv:
        sys.argv.remove('--legacy-single-enemy')
        print('注意：显式使用旧单敌方版本，不适合第三关等多阵营战场。',flush=True)
        return main_legacy()
    from play_current2 import main as main_multifaction
    return main_multifaction()

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(f'停止：{exc}', file=sys.stderr)
        sys.exit(1)
