-- 战场单位菜单探针：打开菜单看条目，进入「攻撃」看范围掩码地址
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa.State"
local OUT  = BASE .. "logs/menu_probe.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/mp_"..n..".png"); say("shot "..n) end
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
  for _ = 1, (maxf or 60) do
    emu.frameadvance()
    if cond() then up(); adv(3); return true end
  end
  up(); adv(3); return false
end
-- 找 0xF1 掩码样式区域
local function scanMasks(tag)
  say("-- scan " .. tag)
  for a = 0x03001000, 0x03001600, 4 do
    local n = 0
    for k = 0, 63 do
      local ok, v = pcall(memory.read_u8, a + k)
      if ok and v == 0xF1 then n = n + 1 end
    end
    if n >= 8 then say(string.format("   0x%08X  F1x%d", a, n)) end
  end
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

-- joypad 清横幅
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
for i = 1, 10 do
  say("mobilePad try " .. i)
  if mobilePad() then say("ready after " .. i); break end
  say("  not ready, press A")
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(45)
end
patch()
say(string.format("cursor=%d,%d", cur()))

-- 导航到单位 0（M1A2 @ 21,30）
local ux, uy = 21, 30
holdUntil(RIGHT, function() return select(1, cur()) >= ux end, 60)
holdUntil(LEFT,  function() return select(1, cur()) <= ux end, 60)
holdUntil(DOWN,  function() return select(2, cur()) >= uy end, 60)
holdUntil(UP,    function() return select(2, cur()) <= uy end, 60)
say(string.format("at unit: %d,%d", cur()))
shot("00_on_unit")
tap(A, 12); shot("01_menu")
-- 菜单条目逐项截图
tap(DOWN, 12); shot("02_menu_d1")
tap(DOWN, 12); shot("03_menu_d2")
tap(DOWN, 12); shot("04_menu_d3")
tap(DOWN, 12); shot("05_menu_d4")
tap(UP, 12); tap(UP, 12); tap(UP, 12); tap(UP, 12); shot("06_menu_up")
-- 回第一项，按 A 进入
tap(A, 14); shot("07_first_item")
-- 若第一项是移動，应有范围高亮；此时扫描掩码
scanMasks("after_first_item")
tap(B, 20); shot("08_back")
adv(40)
say("done")
pcall(client.exit)
