"""Build and control an isolated BizHawk session for the first scenario.

Original savestates are never overwritten. The Lua bridge reuses the existing
game controls, and accepts one numbered command at a time for inspection.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "shots" / "first_clear"

TAIL = r'''
-- Isolated interactive investigation; original states remain intact.
local RUN = BASE .. "shots/first_clear/"
local function writefile(path, text)
  local f = assert(io.open(path, "w")); f:write(text); f:close()
end
local function inspect(seq, result)
  local extra = {}
  extra[#extra+1] = string.format("CTX state=%d sub=%d phase=%d side=%d turnbyte=%d player=%d result=%d",
    r8(CTX), r8(CTX+1), r8(CTX+0x21), r8(CTX+0x22), r8(CTX+0x20),
    r8(CTX+0x990), r8(CTX+0x2C))
  for _, side in ipairs({"MY", "EN"}) do
    for _, u in ipairs(all_units(side)) do
      local a = U + ((side == "EN") and PB or 0) + u.idx * STRIDE - 2
      local bytes = {}
      for i=0,23 do bytes[#bytes+1] = string.format("%02X", r8(a+i)) end
      extra[#extra+1] = side .. u.idx .. " RAW " .. table.concat(bytes," ")
    end
  end
  pcall(client.screenshot, RUN .. "current.png")
  pcall(client.screenshot, RUN .. string.format("%04d.png",seq))
  writefile(RUN .. "state.txt", build_state() .. table.concat(extra,"\n") .. "\n")
  writefile(RUN .. "reply.txt", "seq=" .. seq .. "\n" .. result .. "\n")
  log("COMMAND " .. seq .. " " .. result)
end
local function main()
  pcall(client.speedmode, 400)
  pcall(client.frameskip, 3)
  pcall(client.setsoundon, true)
  adv(20)
  assert(savestate.load(LOAD_STATE) ~= false, "load failed")
  adv(40)
  patch_mail()
  if r8(CTX)==7 and r8(CTX+1)==1 then ensure_map() end
  local seq = 0
  inspect(seq, "READY")
  while true do
    local f=io.open(RUN .. "command.txt", "r")
    local txt=f and f:read("*a") or ""
    if f then f:close() end
    local id, line=txt:match("seq=(%d+)\n([^\r\n]+)")
    id=tonumber(id)
    if id and id>seq then
      seq=id; step=seq
      local cmd, rest=line:match("^(%S+)%s*(.*)$")
      local result="OK " .. line
      if cmd=="KEY" then
        local key, frames, gap=rest:match("(%S+)%s+(%d+)%s+(%d+)")
        hold(key, tonumber(frames)); adv(tonumber(gap))
      elseif cmd=="SPEED" then pcall(client.speedmode, tonumber(rest) or 400)
      elseif cmd=="RECORD" then
        if rest=="OFF" then recordName=nil
        else
          assert(rest:match("^[%w_%-]+$"), "invalid recording name")
          recordName=rest; recordTick=0; recordFrame=0
        end
      elseif cmd=="ADV" then adv(tonumber(rest) or 1)
      elseif cmd=="FOCUS" then
        local x,y=rest:match("(%d+)%s+(%d+)")
        x=tonumber(x); y=tonumber(y)
        memory.write_u8(CTX+0x637E,x); memory.write_u8(CTX+0x637F,y)
        adv(4)
      elseif cmd=="POSITION" then
        local k,x,y=rest:match("(%d+)%s+(%d+)%s+(%d+)")
        local ok,msg=teleport_mem(tonumber(k),tonumber(x),tonumber(y))
        result=(ok and "OK " or "FAIL ") .. msg
      elseif cmd=="SAVE" then
        assert(rest:match("^[%w_%-]+$"), "invalid save name")
        savestate.save(BASE .. "states/" .. rest .. ".State")
      elseif cmd=="LOAD" then
        assert(rest:match("^[%w_%-]+$"), "invalid save name")
        savestate.load(BASE .. "states/" .. rest .. ".State")
        adv(20); patch_mail()
      elseif cmd=="MAP" then to_map()
      elseif cmd=="READ" then
        local addr,n=rest:match("(%S+)%s+(%d+)")
        addr=tonumber(addr); n=tonumber(n)
        local out={}
        for i=0,n-1 do out[#out+1]=string.format("%02X",r8(addr+i)) end
        result="OK READ " .. table.concat(out," ")
      elseif cmd=="EXIT" then
        inspect(seq,result); if logf then logf:close() end; client.exit(); return
      elseif cmd~="SNAP" then
        local attacker,target=rest:match("^(%d+)%s+(%d+)$")
        local u=attacker and unit("MY",tonumber(attacker))
        if cmd=="ATTACK" and u and u.id~=187 then
          result="FAIL 自动攻击仅对已验证菜单的 M1A2 开放，请用 KEY 检查其它兵种菜单"
        else
          to_map()
          results={}; run_directive(line); result=table.concat(results,"\n")
          if cmd=="ATTACK" then
            for i=1,30 do
              if r8(CTX)~=7 or r8(CTX+1)==2 then break end
              local e=target and unit("EN",tonumber(target))
              if #all_units("EN")==0 then tap("A",30)
              elseif e and e.hp==0 then tap("A",30)
              else to_map(); adv(35); break end
            end
          end
        end
      end
      inspect(seq,result)
    else
      client.sleep(15)
      emu.yield()
    end
  end
end
local ok, err=xpcall(main, debug.traceback)
if not ok then log("FATAL " .. tostring(err)); writefile(RUN .. "error.txt", tostring(err)) end
'''


def build(load: str) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    (DIR / "frames").mkdir(exist_ok=True)
    src = (ROOT / "lua" / "usa_ai_state.lua").read_text(encoding="utf-8")
    prefix = src.split("-- ============ 启动 ============")[0]
    prefix = prefix.replace('BASE .. "logs/usa_ai_state.txt"', 'BASE .. "logs/first_clear.txt"')
    prefix = prefix.replace('BASE .. "states/battle_usa_ready.State"', f'BASE .. "states/{load}.State"')
    prefix = prefix.replace("emu.frameadvance()", "controlled_frame()")
    recorder = r'''
local recordName, recordTick, recordFrame = nil, 0, 0
local function controlled_frame()
  emu.frameadvance()
  if recordName then
    recordTick=recordTick+1
    if recordTick%6==0 then
      recordFrame=recordFrame+1
      client.screenshot(string.format("D:/prog/gba-ai/shots/first_clear/frames/%s_%05d.png",recordName,recordFrame))
    end
  end
end
'''
    # Record+7 is U+5, not U+7 (U points at the x coordinate).
    prefix = prefix.replace("st = r8(base + 7)", "st = r8(base + 5)")
    prefix = prefix.replace("acted = (r8(base + 7)", "acted = (r8(base + 5)")
    (ROOT / "lua" / "first_clear.lua").write_text(recorder + prefix + TAIL, encoding="utf-8")
    (DIR / "command.txt").write_text("", encoding="utf-8")
    print(ROOT / "lua" / "first_clear.lua")


def command(line: str, timeout: float, full: bool = False) -> None:
    reply = DIR / "reply.txt"
    seq = 1
    if reply.exists():
        seq = int(reply.read_text(encoding="utf-8").splitlines()[0].split("=")[1]) + 1
    tmp = DIR / "command.tmp"
    tmp.write_text(f"seq={seq}\n{line}\n", encoding="utf-8")
    # Windows Lua stdio may briefly hold command.txt without FILE_SHARE_DELETE.
    replace_deadline = time.monotonic() + 3
    while True:
        try:
            tmp.replace(DIR / "command.txt")
            break
        except PermissionError:
            if time.monotonic() >= replace_deadline:
                raise
            time.sleep(0.02)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if reply.exists():
            text = reply.read_text(encoding="utf-8")
            if text.startswith(f"seq={seq}\n"):
                print(text)
                state = (DIR / "state.txt").read_text(encoding="utf-8")
                with (DIR / "journal.jsonl").open("a", encoding="utf-8") as journal:
                    journal.write(json.dumps({"time": time.time(), "command": line,
                                              "reply": text, "state": state},
                                             ensure_ascii=False) + "\n")
                if full:
                    print(state)
                else:
                    print(" | ".join(s for s in state.splitlines()
                                     if s.startswith(("step=", "MY ", "EN ", "CTX "))))
                return
        error = DIR / "error.txt"
        if error.exists():
            raise RuntimeError(error.read_text(encoding="utf-8"))
        time.sleep(0.1)
    raise TimeoutError(f"Command {seq} is still pending: {line}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", nargs="*")
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--load", default="first_clear_start")
    ap.add_argument("--timeout", type=float, default=45)
    ap.add_argument("--full", action="store_true")
    args = ap.parse_args()
    if args.build:
        if not args.load.replace("_", "").replace("-", "").isalnum():
            ap.error("--load must be a savestate basename")
        build(args.load)
    else:
        command(" ".join(args.command), args.timeout, args.full)
