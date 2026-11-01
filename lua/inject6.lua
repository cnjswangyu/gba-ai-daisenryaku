-- 决定性实验：先清横幅到真正空闲，再对比 joypad / 邮箱
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/inject6.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/i6_"..n..".png") end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function padTap(bits, frames)
  for _ = 1, (frames or 3) do joypad.set(bits); emu.frameadvance() end
  joypad.set({}); adv(5)
end
local function padRight(n) return padTap({ Right = true }, n) end

local function mobile()
  local x0 = cur()
  padRight(14)
  local x1 = cur()
  if x0 ~= x1 then padTap({ Left = true }, 14); return true end
  return false
end

local function mailRight(frames)
  memory.write_u16_le(MAIL, 0x3FF - 0x10)
  for _ = 1, frames do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(3)
end

say("== start ==")
pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

-- 清横幅：A 连按直到光标能动
local ready = false
for i = 1, 10 do
  if mobile() then ready = true; say("ready after " .. i); break end
  padTap({ A = true }, 5); adv(45)
end
local x0, y0 = cur()
say(string.format("idle=%s cursor=(%d,%d)", tostring(ready), x0, y0))
if not ready then say("ABORT: 无法进入空闲态"); pcall(client.exit); return end

-- 1) 基线 joypad
local bx, by = cur(); padRight(30); local ax, ay = cur()
say(string.format("1) joypad RIGHT30: (%d,%d)->(%d,%d) ok=%s", bx, by, ax, ay, tostring(bx ~= ax)))
padTap({ Left = true }, 30)

-- 2) 打补丁（IWRAM 5 处 + ROM 1 处）
memory.write_u16_le(MAIL, 0x3FF)
for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
memory.write_u32_le(0x080015F4, MAIL)
say("patched 5xIWRAM + ROM literal")

-- 3) 补丁后 joypad
local cx, cy = cur(); padRight(30); local dx, dy = cur()
say(string.format("2) after patch joypad: (%d,%d)->(%d,%d) ok=%s", cx, cy, dx, dy, tostring(cx ~= dx)))

-- 4) 邮箱
local ex, ey = cur(); mailRight(40); local fx, fy = cur()
say(string.format("3) mailbox RIGHT40: (%d,%d)->(%d,%d) ok=%s", ex, ey, fx, fy, tostring(ex ~= fx)))
shot("after")
say("== done ==")
pcall(client.exit)
