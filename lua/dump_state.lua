-- 导出战场状态：双方单位、资金、首都，供 tools/advise.py 做收益评估
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/state_dump.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80
local U, STRIDE, SLOTS, PB = 0x03002BE2, 24, 64, 0x600

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function patch()
  memory.write_u16_le(MAIL, 0x3FF)
  for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
end
local function down(bits) memory.write_u16_le(MAIL, 0x3FF - bits) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function key(bits, f) down(bits); for _ = 1, (f or 1) do emu.frameadvance() end; up(); adv(3) end

local function units(base, side)
  for k = 0, SLOTS - 1 do
    local o = base + k * STRIDE
    local x, y, fuel, attr, acted, kind = memory.read_u8(o), memory.read_u8(o+1),
      memory.read_u8(o+2), memory.read_u8(o+4), memory.read_u8(o+5), memory.read_u8(o+6)
    if x > 0 and x < 64 and y > 0 and y < 64 and fuel > 0 then
      say(string.format("UNIT %s %d %d %d %d %d %d %d", side, k, x, y, fuel, attr, acted, kind))
    end
  end
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
sa = pcall(savestate.load, SRC)
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

say("# load=" .. tostring(sa))
-- 势力表：资金 + 首都
for p = 0, 1 do
  local o = 0x030004A4 + p * 12
  local funds = memory.read_u32_le(o)
  local x, y = memory.read_u8(o+7), memory.read_u8(o+8)
  say(string.format("FACTION %d funds=%d capital=%d,%d", p, funds, x, y))
end
say(string.format("CURSOR %d %d", cur()))
units(U, "US")
units(U + PB, "EN")
say("END")
pcall(client.exit)
