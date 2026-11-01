-- 探针：移動到敌军相邻格，看移动后弹出的菜单（攻撃/待機）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_live.State"
local OUT  = BASE .. "logs/menu3.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/m3_"..n..".png"); say("shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function patch()
  memory.write_u16_le(MAIL, 0x3FF)
  for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
end
local function down(bits) memory.write_u16_le(MAIL, 0x3FF - bits) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function key(bits, frames)
  down(bits); for _ = 1, (frames or 1) do emu.frameadvance() end; up(); adv(3)
end
local function tap(bits, wait) key(bits, 1); adv(wait or 10) end
local function holdUntil(bits, cond, maxf)
  down(bits)
  for _ = 1, (maxf or 80) do
    emu.frameadvance()
    if cond() then up(); adv(3); return true end
  end
  up(); adv(3); return false
end
local function mobilePad()
  local x0 = select(1, cur())
  for _ = 1, 14 do joypad.set({ Right = true }); emu.frameadvance() end
  joypad.set({})
  local x1 = select(1, cur())
  if x0 ~= x1 then
    for _ = 1, 14 do joypad.set({ Left = true }); emu.frameadvance() end
    joypad.set({}); return true
  end
  return false
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
for i = 1, 12 do
  if mobilePad() then say("ready after " .. i); break end
  say("  banner? press A")
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(50)
end
patch()
say(string.format("cursor=%d,%d", cur()))

-- 选 M1A2 (21,30)
local ux, uy = 21, 30
holdUntil(RIGHT, function() return select(1, cur()) >= ux end, 60)
holdUntil(LEFT,  function() return select(1, cur()) <= ux end, 60)
holdUntil(DOWN,  function() return select(2, cur()) >= uy end, 60)
holdUntil(UP,    function() return select(2, cur()) <= uy end, 60)
say(string.format("on unit %d,%d", cur()))
shot("00_on_unit")
tap(A, 15); shot("01_menu")     -- 移動/解散
tap(A, 20); shot("02_move_mode") -- 移動 → 范围高亮
-- 向西走 3 格 → (18,30)，与敌军 (17,29) 相邻
for i = 1, 3 do key(LEFT, 5); adv(8) end
say(string.format("dest cursor=%d,%d", cur()))
shot("03_dest")
tap(A, 40); shot("04_after_confirm")   -- 确认落点
adv(60)
shot("05_after_move")
-- 若弹出菜单，逐项截图
tap(DOWN, 15); shot("06_d1")
tap(DOWN, 15); shot("07_d2")
for _ = 1, 4 do tap(UP, 12) end
say("done")
pcall(client.exit)
