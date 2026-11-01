-- 测 L / R 是否在战场直接切换选中单位（若可行，选单位就不再需要坐标导航）
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/lr.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 25)
end
local function holdFrames(k, f)
  for _ = 1, f do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(6)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
for _ = 1, 4 do
  local x0 = cur(); holdFrames("Right", 10); local x1 = cur(); holdFrames("Left", 10)
  if x0 ~= x1 then break end
  tap("A", 60)
end
say(string.format("起点 (%d,%d)", cur()))

for i = 1, 6 do
  tap("R", 30); say(string.format("R%d -> (%d,%d)", i, cur()))
end
for i = 1, 6 do
  tap("L", 30); say(string.format("L%d -> (%d,%d)", i, cur()))
end
say("done")
pcall(client.exit)
