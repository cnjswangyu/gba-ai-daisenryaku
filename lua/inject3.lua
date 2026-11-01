-- 把 IWRAM 里 5 处 KEYINPUT 字面量全指向 RAM 邮箱，再用邮箱直接发键
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/inject3.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/i3_"..n..".png"); say("shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
say(string.format("cursor=(%d,%d)", cur()))

memory.write_u16_le(MAIL, 0x3FF)
for _, a in ipairs(LITS) do
  local before = memory.read_u32_le(a)
  memory.write_u32_le(a, MAIL)
  say(string.format("patch 0x%08X: 0x%08X -> 0x%08X (读回 0x%08X)", a, before, MAIL, memory.read_u32_le(a)))
end

-- 发 RIGHT 40 帧
local x0, y0 = cur()
memory.write_u16_le(MAIL, 0x3FF - 0x10)
for _ = 1, 40 do emu.frameadvance() end
memory.write_u16_le(MAIL, 0x3FF)
adv(4)
local x1, y1 = cur()
say(string.format("hold RIGHT 40f: (%d,%d)->(%d,%d) %s", x0, y0, x1, y1, tostring(x0 ~= x1)))
shot("01_right")

-- 发 A
memory.write_u16_le(MAIL, 0x3FF - 0x01)
for _ = 1, 3 do emu.frameadvance() end
memory.write_u16_le(MAIL, 0x3FF)
adv(12)
shot("02_A")
say(string.format("after A cursor=(%d,%d)", cur()))
say("done")
pcall(client.exit)
