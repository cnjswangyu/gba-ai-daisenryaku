-- 直接注入输入状态：写 0x0300048C(+0xC 新按下) / 0x0300048E(+0xE 按住)，不再走 KEYINPUT
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/inject.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/inj_"..n..".png"); say("shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

-- 直接注入：bits 见 HANDOFF（A=0x1 B=0x2 Start=0x8 Right=0x10 Left=0x20 Up=0x40 Down=0x80 R=0x100 L=0x200）
local PTR = 0x03000480
local function inject(bits, frames)
  for _ = 1, (frames or 2) do
    memory.write_u16_le(PTR + 0x0C, bits)   -- 本帧新按下
    memory.write_u16_le(PTR + 0x0E, bits)   -- 持续按住
    emu.frameadvance()
  end
  memory.write_u16_le(PTR + 0x0C, 0)
  memory.write_u16_le(PTR + 0x0E, 0)
  adv(6)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
-- 用正常按键清横幅
for _ = 1, 4 do
  local x0 = cur()
  joypad.set({ Right = true }); emu.frameadvance(); joypad.set({})
  local x1 = cur()
  joypad.set({ Left = true }); emu.frameadvance(); joypad.set({})
  if x0 ~= x1 then break end
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end; joypad.set({}); adv(40)
end
say(string.format("idle cursor=(%d,%d)", cur()))

-- 测试 1：注入 Right 一点
local x0, y0 = cur()
inject(0x0010, 2)
local x1, y1 = cur()
say(string.format("注入 RIGHT → (%d,%d)  变化=%s", x1, y1, tostring(x0 ~= x1 or y0 ~= y1)))
shot("01_right")

-- 测试 2：注入 A（应弹出单位菜单）
inject(0x0001, 2)
adv(20)
shot("02_A")
say("注入 A 完成")
say("done")
pcall(client.exit)
