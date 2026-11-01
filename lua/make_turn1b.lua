-- 造一个"第1回合可自由操作"的存档点：清掉所有模态，验证光标能动
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local DST   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/mk_turn1b.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/t1b_"..n..".png") end
local function tap(k, g)
  joypad.set({ [k] = true }); emu.frameadvance(); joypad.set({}); adv(g or 30)
end
local function hold(k, f)
  for _ = 1, (f or 12) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(18)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

-- 依次清掉确认框/横幅，最多试 4 次
for i = 1, 4 do
  local x0, y0 = cur()
  hold("Right", 12)
  local x1, y1 = cur()
  say(string.format("try%d: cursor (%d,%d) -> (%d,%d)", i, x0, y0, x1, y1))
  if x0 ~= x1 or y0 ~= y1 then
    hold("Left", 12)     -- 退回原位
    break
  end
  tap("A", 90)
end

say("final cursor=" .. string.format("(%d,%d)", cur()))
shot("00_ready")
say("save=" .. tostring(pcall(savestate.save, DST)))
say("done")
pcall(client.exit)
