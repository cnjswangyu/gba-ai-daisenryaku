-- 用 R 键拍下我方四种兵种的详情页（坦克/自行炮/步兵/补给车）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/profiles.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START, R = 0x1, 0x2, 0x8, 0x100
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/pf_"..n..".png"); say("shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function unit(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2), memory.read_u8(o + 6)
end
local function patch()
  memory.write_u16_le(MAIL, 0x3FF)
  for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
end
local function down(bits) memory.write_u16_le(MAIL, 0x3FF - bits) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function key(bits, f) down(bits); for _ = 1, (f or 1) do emu.frameadvance() end; up(); adv(4) end
local function tap(bits, w) key(bits, 1); adv(w or 10) end
local function holdUntil(bits, cond, maxf)
  down(bits)
  for _ = 1, (maxf or 60) do emu.frameadvance(); if cond() then up(); adv(3); return true end end
  up(); adv(3); return false
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
local function mobilePad()
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
for i = 1, 10 do
  if mobilePad() then break end
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(45)
end
patch()

local targets = { { 0, "tank" }, { 3, "arty" }, { 5, "inf" }, { 9, "supply" } }
for _, t in ipairs(targets) do
  local i, name = t[1], t[2]
  local x, y, hp, tid = unit(i)
  if hp > 0 then
    holdUntil(RIGHT, function() return select(1, cur()) >= x end, 60)
    holdUntil(LEFT,  function() return select(1, cur()) <= x end, 60)
    holdUntil(DOWN,  function() return select(2, cur()) >= y end, 60)
    holdUntil(UP,    function() return select(2, cur()) <= y end, 60)
    local cx, cy = cur()
    say(string.format("%s u%d (%d,%d) cursor(%d,%d) type=%02X", name, i, x, y, cx, cy, tid))
    tap(R, 40)
    shot(name)
    tap(B, 20)
  end
end
say("done")
pcall(client.exit)
