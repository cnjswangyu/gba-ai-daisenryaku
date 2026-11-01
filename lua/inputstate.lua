-- 读游戏自己的输入结构：0x02007060 是指针，*ptr+0xC=本帧新按下, +0xE=持续按住
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/inputstate.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 50)
end
local function u32(a) return memory.read_u32_le(a) end
local function u16(a) return memory.read_u16_le(a) end

local function dump(tag)
  local p = u32(0x02007060)
  local newb, held = -1, -1
  if p and p > 0x02000000 and p < 0x03008000 then
    newb = u16(p + 0xC)
    held = u16(p + 0xE)
  end
  say(string.format("%-14s ptr=0x%08X  new=0x%04X  held=0x%04X  KEYINPUT=0x%03X",
    tag, p, newb, held, u16(0x04000130) % 1024))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

dump("boot")

-- 按住 RIGHT 连续观察
joypad.set({ Right = true })
for i = 1, 8 do
  adv(1)
  dump("holdR_f" .. i)
end
joypad.set({})
for i = 1, 3 do adv(1); dump("release" .. i) end

-- 按住 A 观察
joypad.set({ A = true })
for i = 1, 4 do adv(1); dump("holdA_f" .. i) end
joypad.set({})
adv(5)
say("done")
pcall(client.exit)
