-- 打补丁：让游戏的输入函数从 RAM 邮箱读键值（0x03007F00），按键由我们直接写
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/inject2.txt"
local MAIL  = 0x03007F00
local LIT   = 0x080015F4

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/ip_"..n..".png"); say("shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

-- bits: A=0x1 B=0x2 Select=0x4 Start=0x8 Right=0x10 Left=0x20 Up=0x40 Down=0x80 R=0x100 L=0x200
local function key(bits, frames)
  memory.write_u16_le(MAIL, 0x3FF ~ bits)   -- 反相：按下位补 0
  for _ = 1, (frames or 1) do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(2)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

-- 打补丁 + 初始化邮箱
memory.write_u16_le(MAIL, 0x3FF)
memory.write_u32_le(LIT, MAIL)
say(string.format("补丁: 0x%08X -> 0x%08X, 读回 0x%08X", LIT, MAIL, memory.read_u32_le(LIT)))

-- 用正常按键清横幅（此时补丁已生效，正常按键无效，所以改用邮箱）
for _ = 1, 5 do
  local x0 = cur(); key(0x0010, 2); local x1 = cur(); key(0x0020, 2)
  if x0 ~= x1 then key(0x0020, 2); say("空闲"); break end
  key(0x0008, 2)   -- START 清横幅
  adv(50)
end
say(string.format("起点 cursor=(%d,%d)", cur()))

-- 测速：按住 RIGHT 60 帧（邮箱保持，不松开）
local x0 = cur()
memory.write_u16_le(MAIL, 0x3FF ~ 0x10)
for _ = 1, 60 do emu.frameadvance() end
memory.write_u16_le(MAIL, 0x3FF)
adv(4)
local x1 = cur()
say(string.format("按住RIGHT 60帧: (%d,%d) -> (%d,%d) 走了 %d", x0, cur()))
shot("01_hold60")

-- 测 A：点一下应弹单位菜单
key(0x0001, 1)
adv(10)
shot("02_A")
say("A 已注入")
say("done")
pcall(client.exit)
