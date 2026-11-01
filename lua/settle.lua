-- 验证：移动确认后按 A(待機) 而不是 B，单位坐标是否保留、光标是否恢复可动
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/settle.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/st_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 20)
end
local function step1(dir)
  for _ = 1, 14 do joypad.set({ [dir] = true }); emu.frameadvance() end
  joypad.set({}); adv(6)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function u0() return memory.read_u8(0x03002BE2), memory.read_u8(0x03002BE3) end
local function u0raw() return memory.read_u8(0x03002BE2), memory.read_u8(0x03002BE3) end
-- 关键状态位（上一步差分得出）
local function flags()
  return string.format("flag0490=%d ab4=%d f6803=%d f6808=%d",
    memory.read_u8(0x03000490), memory.read_u8(0x03005AB4),
    memory.read_u8(0x03006803), memory.read_u8(0x03006808))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
for _ = 1, 4 do
  local x0 = cur(); step1("Right"); local x1 = cur(); step1("Left")
  if x0 ~= x1 then break end
  tap("A", 60)
end
say(string.format("idle: unit0=(%d,%d) %s", u0(), flags()))

-- 选中 → 移動 → 走两格 → A 确认
local x, y = u0()
tap("A", 20); tap("A", 20)
step1("Right"); step1("Right")
say(string.format("移动中: cursor=(%d,%d) unit0=(%d,%d)", cur(), u0()))
tap("A", 40)
say(string.format("A确认后: unit0=(%d,%d) %s", u0(), flags()))
shot("01_committed")

-- 关键：按 A 待机（不按 B）
tap("A", 40)
say(string.format("再按A: unit0=(%d,%d) %s", u0(), flags()))
adv(30)
shot("02_wait")

-- 检查光标是否恢复可动
local bx, by = cur()
step1("Right")
local ax, ay = cur()
say(string.format("光标 %s -> %s  可动=%s", string.format("(%d,%d)", bx, by),
  string.format("(%d,%d)", ax, ay), tostring(ax ~= bx or ay ~= by)))
say(string.format("最终 unit0=(%d,%d) %s", u0(), flags()))
shot("03_after")
say("done")
pcall(client.exit)
