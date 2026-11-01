-- 对照实验（修正格式化 bug）：补丁后 joypad 是否还生效
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/inject5.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/i5_"..n..".png") end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function mailKey(bits, frames)
  memory.write_u16_le(MAIL, 0x3FF - bits)
  for _ = 1, (frames or 1) do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(3)
end
local function padKey(tbl, frames)
  for _ = 1, (frames or 1) do joypad.set(tbl); emu.frameadvance() end
  joypad.set({}); adv(3)
end

say("== start ==")
pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

-- 未打补丁时，先记录 joypad 是否有效（基线）
local bx, by = cur()
padKey({ Right = true }, 30)
local ax, ay = cur()
say(string.format("baseline joypad RIGHT: (%d,%d)->(%d,%d) ok=%s", bx, by, ax, ay, tostring(bx ~= ax)))

-- 打补丁
memory.write_u16_le(MAIL, 0x3FF)
for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
say("patched iwram literals x5")

-- 补丁后 joypad
local cx, cy = cur()
padKey({ Right = true }, 30)
local dx, dy = cur()
say(string.format("after patch joypad RIGHT: (%d,%d)->(%d,%d) ok=%s", cx, cy, dx, dy, tostring(cx ~= dx)))

-- 补丁后邮箱
local ex, ey = cur()
mailKey(0x10, 40)
local fx, fy = cur()
say(string.format("after patch mailbox RIGHT: (%d,%d)->(%d,%d) ok=%s", ex, ey, fx, fy, tostring(ex ~= fx)))
shot("after")
say("== done ==")
pcall(client.exit)
