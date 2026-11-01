-- 单元测试：读内存拿单位坐标 → 移动光标过去 → A 下指令 → 移动 → 确认
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/war.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/wb_"..n..".png"); say("shot "..n) end
local function tap(k)
  joypad.set({ [k] = true }); emu.frameadvance(); joypad.set({}); adv(10); say("tap "..k)
end
local function hold(k, f)
  for _ = 1, (f or 12) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(16)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

-- 六角坐标每走一格 = ±2
local function step_dir(dx, dy)
  if dx > 0 then hold("Right", 12)
  elseif dx < 0 then hold("Left", 12)
  elseif dy > 0 then hold("Down", 12)
  else hold("Up", 12) end
end
local function move_to(tx, ty, maxn)
  for i = 1, (maxn or 30) do
    local cx, cy = cur()
    say(string.format("  cursor (%d,%d) -> (%d,%d)", cx, cy, tx, ty))
    if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then return true end
    if cx < tx then step_dir(2, 0)
    elseif cx > tx then step_dir(-2, 0)
    elseif cy < ty then step_dir(0, 2)
    else step_dir(0, -2) end
  end
  return false
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
tap("A"); adv(80)          -- 确认自动部署
shot("00_map")
say(string.format("cursor=(%d,%d)", cur()))

-- 读第一个单位坐标
local ux, uy = memory.read_u8(0x03002BE2), memory.read_u8(0x03002BE3)
say(string.format("unit0=(%d,%d) hp=%d", ux, uy, memory.read_u8(0x03002BE4)))

say("move_to unit0: " .. tostring(move_to(ux, uy)))
shot("01_on_unit")
tap("A"); shot("02_menu")
tap("A"); shot("03_move_mode")
hold("Right", 12); shot("04_step")
tap("A"); shot("05_commit")
adv(60); shot("06_after")
say("done")
pcall(client.exit)
