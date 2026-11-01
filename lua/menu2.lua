-- 战场单位菜单探针 v2：在真战场（battle_usa_live.State）里看 A 菜单条目
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_live.State"
local OUT  = BASE .. "logs/menu2.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/m2_"..n..".png"); say("shot "..n) end
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
shot("00_map")

-- 选单位 0（M1A2 @ 21,30）
local ux, uy = 21, 30
holdUntil(RIGHT, function() return select(1, cur()) >= ux end, 60)
holdUntil(LEFT,  function() return select(1, cur()) <= ux end, 60)
holdUntil(DOWN,  function() return select(2, cur()) >= uy end, 60)
holdUntil(UP,    function() return select(2, cur()) <= uy end, 60)
say(string.format("on unit %d,%d", cur()))
shot("01_on_unit")
tap(A, 15); shot("02_menu")            -- 单位菜单
tap(DOWN, 15); shot("03_d1")
tap(DOWN, 15); shot("04_d2")
tap(DOWN, 15); shot("05_d3")
tap(DOWN, 15); shot("06_d4")
-- 回第一项，进入
for _ = 1, 6 do tap(UP, 12) end
shot("07_back_top")
tap(A, 25); shot("08_first")           -- 第一项（应=移動）
-- 移動模式下扫描掩码
say("-- mask scan after 移動")
for a = 0x030010A0, 0x03001100, 4 do
  local n = 0
  for k = 0, 47 do
    local ok, v = pcall(memory.read_u8, a + k)
    if ok and v == 0xF1 then n = n + 1 end
  end
  if n >= 4 then say(string.format("   0x%08X F1x%d/48", a, n)) end
end
tap(B, 30); shot("09_back")
adv(40)
say("done")
pcall(client.exit)
