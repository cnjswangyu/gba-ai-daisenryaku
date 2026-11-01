-- 定位单位记录里的"剩余机动力"等字段：移动前后逐字段对比
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/mp.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80
local U, STRIDE, N = 0x03002BE2, 24, 10

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function rec(i)
  local o = U + i * STRIDE
  local t = {}
  for k = 0, STRIDE - 1 do t[k + 1] = memory.read_u8(o + k) end
  return t
end
local function patch()
  memory.write_u16_le(MAIL, 0x3FF)
  for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
end
local function down(bits) memory.write_u16_le(MAIL, 0x3FF - bits) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function key(bits, f) down(bits); for _ = 1, (f or 1) do emu.frameadvance() end; up(); adv(3) end
local function tap(bits, w) key(bits, 1); adv(w or 8) end
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

local before = {}
for i = 0, N - 1 do before[i] = rec(i) end
say("=== 移动前 ===")
for i = 0, N - 1 do
  say(string.format("u%d: %s", i, table.concat(before[i], " ", 1, 12)))
end

-- 移动 u0 两格
local x, y = before[0][1], before[0][2]
holdUntil(RIGHT, function() return select(1, cur()) >= x end, 60)
holdUntil(LEFT,  function() return select(1, cur()) <= x end, 60)
holdUntil(DOWN,  function() return select(2, cur()) >= y end, 60)
holdUntil(UP,    function() return select(2, cur()) <= y end, 60)
tap(A, 10); tap(A, 10)
key(RIGHT, 5); key(RIGHT, 5)
tap(A, 30); adv(40)
tap(A, 20); adv(20)

local after = {}
for i = 0, N - 1 do after[i] = rec(i) end
say("=== 移动后 ===")
for i = 0, N - 1 do
  say(string.format("u%d: %s", i, table.concat(after[i], " ", 1, 12)))
end
say("=== 逐字段变化（u0）===")
for k = 1, STRIDE do
  if before[0][k] ~= after[0][k] then
    say(string.format("  +%d: %d -> %d", k - 1, before[0][k], after[0][k]))
  end
end
say("done")
pcall(client.exit)
