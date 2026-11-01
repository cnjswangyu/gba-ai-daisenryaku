-- 探针 v6：完整移动流程（3帧A），贴到敌军(17,29)旁，看移动后菜单
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_live.State"
local OUT  = BASE .. "logs/menu6.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/m6_"..n..".png"); say("  shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function u0()
  local o = 0x03002BE2
  return memory.read_u8(o), memory.read_u8(o+1), memory.read_u8(o+2),
         memory.read_u8(o+4), memory.read_u8(o+5)
end
local function dumpu(tag)
  local x, y, f, hp, acted = u0()
  say(string.format("%s u0=(%d,%d) fuel=%d hp=%d acted=%d cursor=(%d,%d)",
    tag, x, y, f, hp, acted, cur()))
end
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
local function tapA(wait) key(A, 3); adv(wait or 15) end   -- A 按 3 帧
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
dumpu("start")

holdUntil(RIGHT, function() return select(1, cur()) >= 21 end, 60)
holdUntil(LEFT,  function() return select(1, cur()) <= 21 end, 60)
holdUntil(DOWN,  function() return select(2, cur()) >= 30 end, 60)
holdUntil(UP,    function() return select(2, cur()) <= 30 end, 60)
dumpu("on_unit")
tapA(15); shot("01_menu")       -- 单位菜单
tapA(20); shot("02_move")       -- 進入移動
dumpu("move_mode")
holdUntil(LEFT, function() return select(1, cur()) <= 18 end, 120)
dumpu("dest"); shot("03_dest")
tapA(50); dumpu("confirm1"); shot("04_confirm1")
adv(60); dumpu("wait1"); shot("05_wait1")
tapA(50); dumpu("confirm2"); shot("06_confirm2")
adv(80); dumpu("wait2"); shot("07_wait2")
-- 若有菜单，逐项
key(DOWN, 3); adv(15); shot("08_d1")
key(DOWN, 3); adv(15); shot("09_d2")
say("done")
pcall(client.exit)
