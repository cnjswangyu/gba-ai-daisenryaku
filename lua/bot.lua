-- 战斗 bot v1：读内存 → 光标导航 → 逐单位「移動」→ 探结束回合
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/bot.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/bot_"..n..".png") end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(18)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function unit(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2), memory.read_u8(o + 6)
end

local function move_to(tx, ty, maxn)
  for _ = 1, (maxn or 30) do
    local cx, cy = cur()
    if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then return true end
    if cx < tx then hold("Right", 14)
    elseif cx > tx then hold("Left", 14)
    elseif cy < ty then hold("Down", 14)
    else hold("Up", 14) end
  end
  return false
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

-- 清横幅：连按 A 直到光标能动
for i = 1, 6 do
  local x0, y0 = cur()
  hold("Right", 12)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then hold("Left", 12); say("ready after " .. i); break end
  tap("A", 100)
end
shot("00_ready")

for i = 0, 9 do
  local x, y, hp, tid = unit(i)
  if hp > 0 then
    say(string.format("unit%d (%d,%d) hp=%d type=%02X", i, x, y, hp, tid))
    move_to(x, y)
    tap("A", 40)          -- 单位菜单
    tap("A", 40)          -- 移動
    hold("Right", 14)     -- 向目标走一格
    hold("Right", 14)
    tap("A", 60)          -- 确认移动
    adv(60)
    tap("A", 40)          -- 待机/确认
  end
end
shot("01_after_units")

tap("B", 40)
tap("Start", 80)
shot("02_menu")
say("done")
pcall(client.exit)
