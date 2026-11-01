-- 配置阶段散开部队：逐单位「更换位置」到预设阵位，验证坐标，再开始战斗
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/turn1.State"     -- 配置阶段
local DST   = BASE .. "states/battle_spread.State"
local OUT   = BASE .. "logs/spread.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/sp_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(16)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function unit(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2), memory.read_u8(o + 6)
end
local function move_to(tx, ty, maxn)
  for _ = 1, (maxn or 24) do
    local cx, cy = cur()
    if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then return true end
    if cx < tx then hold("Right", 14) elseif cx > tx then hold("Left", 14)
    elseif cy < ty then hold("Down", 14) else hold("Up", 14) end
  end
  return false
end

-- 目标阵位：以首都(21,30)为中心散成两排，坦克在东北、炮兵居中、步兵两侧
local TARGETS = {
  { 25, 27 }, { 27, 29 }, { 25, 31 }, { 23, 27 }, { 27, 27 },
  { 23, 33 }, { 25, 33 }, { 19, 27 }, { 19, 33 }, { 21, 35 },
}

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00_start")

for i = 0, 9 do
  local x, y, hp, tid = unit(i)
  local tx, ty = TARGETS[i + 1][1], TARGETS[i + 1][2]
  if hp > 0 then
    move_to(x, y)
    tap("A", 40)        -- 菜单：更换位置 / 解散
    tap("A", 40)        -- 更换位置
    for _ = 1, 10 do    -- 朝目标走（最多 10 格），走不动就算了
      local cx, cy = cur()
      if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then break end
      if cx < tx then hold("Right", 14) elseif cx > tx then hold("Left", 14)
      elseif cy < ty then hold("Down", 14) else hold("Up", 14) end
    end
    tap("A", 70)        -- 确认放置
    adv(40)
    local nx, ny = unit(i)
    say(string.format("u%d (%d,%d)->(%d,%d) 目标(%d,%d) %s", i, x, y, nx, ny, tx, ty,
      (math.abs(nx - tx) <= 1 and math.abs(ny - ty) <= 1) and "OK" or "未到位"))
  end
end
shot("01_spread")

-- 开始战斗：先取消选中，START → 第一项
tap("B", 40)
tap("Start", 70)
shot("02_menu")
tap("A", 120)     -- 开始战斗
adv(150)
shot("03_battle")
say("save=" .. tostring(pcall(savestate.save, DST)))
say("done")
pcall(client.exit)
