-- 自包含：邮箱发键 + 完整单位指令（不用 dofile）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/bot8.txt"

local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/b8_"..n..".png") end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function u0() return memory.read_u8(0x03002BE2), memory.read_u8(0x03002BE3) end

local function patch()
  memory.write_u16_le(MAIL, 0x3FF)
  for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
end
local function down(bits) memory.write_u16_le(MAIL, 0x3FF - bits) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function key(bits, frames)
  down(bits)
  for _ = 1, (frames or 1) do emu.frameadvance() end
  up(); adv(3)
end
local function tap(bits, wait) key(bits, 1); adv(wait or 8) end
local function holdUntil(bits, cond, maxf)
  down(bits)
  for _ = 1, (maxf or 60) do
    emu.frameadvance()
    if cond() then up(); adv(3); return true end
  end
  up(); adv(3); return false
end

say("== start ==")
pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

-- joypad 清横幅
local function mobile()
  local x0 = cur()
  for _ = 1, 14 do joypad.set({ Right = true }); emu.frameadvance() end
  joypad.set({})
  local x1 = cur()
  if x0 ~= x1 then
    for _ = 1, 14 do joypad.set({ Left = true }); emu.frameadvance() end
    joypad.set({}); return true
  end
  return false
end
local ready = false
for i = 1, 10 do
  if mobile() then ready = true; say("ready after " .. i); break end
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(45)
end
say("idle=" .. tostring(ready))
if not ready then say("ABORT"); pcall(client.exit); return end

patch()
say("patched")

-- 标定
for _, f in ipairs({ 1, 2, 3, 5, 8, 12 }) do
  local x0 = cur()
  key(RIGHT, f)
  local x1 = cur()
  say(string.format("  %2d 帧 → %d 格", f, x1 - x0))
  key(LEFT, f)
  for _ = 1, 8 do
    if cur() == x0 then break end
    key(x0 > cur() and RIGHT or LEFT, 1)
  end
end

-- 完整指令
local ux, uy = u0()
local t0 = os.clock()
say(string.format("unit0=(%d,%d)", ux, uy))
holdUntil(RIGHT, function() return select(1, cur()) >= ux end, 40)
holdUntil(LEFT,  function() return select(1, cur()) <= ux end, 40)
holdUntil(DOWN,  function() return select(2, cur()) >= uy end, 40)
holdUntil(UP,    function() return select(2, cur()) <= uy end, 40)
local cx, cy = cur()
say(string.format("导航 (%d,%d) 命中=%s", cx, cy, tostring(cx == ux and cy == uy)))
shot("01_at_unit")

tap(A, 10)
shot("02_menu")
tap(A, 10)
key(RIGHT, 6)
tap(A, 20); adv(40)
tap(A, 20); adv(20)
local nx, ny = u0()
say(string.format("unit0 (%d,%d)->(%d,%d) 用时 %.2fs", ux, uy, nx, ny, os.clock() - t0))
shot("03_after")
say("== done ==")
pcall(client.exit)
