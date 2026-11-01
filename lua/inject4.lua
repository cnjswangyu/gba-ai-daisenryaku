-- 对照实验：打补丁后，joypad 还有效吗？
--   还能量 → 补丁没生效（游戏仍读真 KEYINPUT）
--   不动了 → 补丁生效，改用邮箱发键（并先用邮箱清横幅）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/inject4.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/i4_"..n..".png"); say("shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function mailKey(bits, frames)
  memory.write_u16_le(MAIL, 0x3FF - bits)
  for _ = 1, (frames or 1) do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(3)
end
local function padKey(bits, frames)   -- bits 用 joypad 表
  for _ = 1, (frames or 1) do joypad.set(bits); emu.frameadvance() end
  joypad.set({}); adv(3)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

-- 先打补丁
memory.write_u16_le(MAIL, 0x3FF)
for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
say("5 处字面量已改指邮箱")

-- A) joypad 测：按 RIGHT 30 帧
local x0 = cur()
padKey({ Right = true }, 30)
local x1 = cur()
say(string.format("A) joypad RIGHT 30f: (%d,%d)->(%d,%d) 有效=%s", x0, cur()))

-- B) 邮箱测：RIGHT 40 帧
local x2 = cur()
mailKey(0x10, 40)
local x3 = cur()
say(string.format("B) 邮箱 RIGHT 40f: (%d,%d)->(%d,%d) 有效=%s", x2, cur()))

-- C) 用邮箱清横幅（连按 A 几次）
for i = 1, 4 do
  mailKey(0x08, 2)   -- START
  adv(40)
  mailKey(0x01, 2)   -- A
  adv(40)
  local xa = cur(); mailKey(0x10, 30); local xb = cur()
  say(string.format("C%d) 清横幅后 moving=%s cursor=(%d,%d)", i, tostring(xa ~= xb), xb, select(2, cur())))
  if xa ~= xb then break end
end
shot("final")
say("done")
pcall(client.exit)
