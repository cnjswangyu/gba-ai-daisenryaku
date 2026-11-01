-- 逐步验证邮箱补丁：每一步都立刻写日志，出错也不会静默
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/dbg.txt"
local MAIL = 0x03007F00
local LIT  = 0x080015F4

local function say(s)
  local f = io.open(OUT, "a")
  if f then f:write(s, "\n"); f:close() end
end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

say("== start ==")
pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
local x, y = cur()
say(string.format("cursor=(%d,%d)", x, y))

-- 1) 初始化邮箱
local ok = pcall(memory.write_u16_le, MAIL, 0x3FF)
say("init mailbox ok=" .. tostring(ok) .. " read=" .. tostring(memory.read_u16_le(MAIL)))

-- 2) 打补丁
local ok2 = pcall(memory.write_u32_le, LIT, MAIL)
say("patch ok=" .. tostring(ok2) .. " read=" .. tostring(memory.read_u32_le(LIT)))

-- 3) 用邮箱按住 RIGHT 40 帧
memory.write_u16_le(MAIL, 0x3FF - 0x10)
for _ = 1, 40 do emu.frameadvance() end
memory.write_u16_le(MAIL, 0x3FF)
adv(4)
local x2, y2 = cur()
say(string.format("hold RIGHT 40f -> (%d,%d) changed=%s", x2, y2, tostring(x2 ~= x)))

-- 4) 用邮箱点 A
memory.write_u16_le(MAIL, 0x3FF - 0x01)
for _ = 1, 3 do emu.frameadvance() end
memory.write_u16_le(MAIL, 0x3FF)
adv(10)
pcall(client.screenshot, BASE .. "shots/dbg_A.png")
local x3, y3 = cur()
say(string.format("after A -> (%d,%d)", x3, y3))

-- 5) 还原补丁，保持 ROM 干净
pcall(memory.write_u32_le, LIT, 0x04000130)
say("restored=" .. tostring(memory.read_u32_le(LIT)))
say("== done ==")
pcall(client.exit)
