-- 速度标定：测"按住多少帧走一格"，为一次长按走多格做准备
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/speed.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(14)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
for _ = 1, 6 do
  local x0 = cur(); hold("Right", 12); local x1 = cur(); hold("Left", 12)
  if x0 ~= x1 then break end
  tap("A", 100)
end
say(string.format("起点 (%d,%d)", cur()))

for _, f in ipairs({ 4, 6, 8, 10, 12, 16, 20, 24, 30, 40 }) do
  local x0, y0 = cur()
  hold("Right", f)
  local x1, y1 = cur()
  say(string.format("  按 %2d 帧 → x %d→%d  (%d 格)", f, x0, x1, math.abs(x1 - x0) // 2))
  hold("Left", (x1 - x0) > 0 and f or 4)   -- 退回
  local x2 = cur()
  if x2 ~= x0 then
    -- 退不回去就用循环退
    for _ = 1, 10 do
      local xa = cur(); if xa == x0 then break end; hold("Left", 12)
    end
  end
end
say("done")
pcall(client.exit)
