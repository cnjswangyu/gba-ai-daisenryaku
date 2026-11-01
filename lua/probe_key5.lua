-- 按官方示例的完整表（含 Power 等）逐帧注入，看 KEYINPUT 是否变化
local OUT = "D:/prog/gba-ai/logs/probe_key5.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function ki() return memory.read_u16_le(0x04000130) % 1024 end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
for _ = 1, 40 do emu.frameadvance() end

local function full(pressA)
  return {
    A = pressA, B = false, Down = false, L = false, Left = false,
    Power = false, R = false, Right = false, Select = false, Start = false, Up = false,
  }
end

-- 1) 完整表 + 每帧设置
for i = 1, 10 do
  joypad.set(full(true), 1)
  emu.frameadvance()
  w(string.format("  full+A f%-2d KEYINPUT=0x%03X", i, ki()))
end
joypad.set(full(false), 1)
for _ = 1, 3 do emu.frameadvance() end

-- 2) 不传 controller 参数
for i = 1, 6 do
  joypad.set(full(true))
  emu.frameadvance()
  w(string.format("  no-controller f%-2d KEYINPUT=0x%03X", i, ki()))
end
joypad.set(full(false))

-- 3) 在 event.onframestart 里设置
local got = 0
event.onframestart(function()
  got = got + 1
  joypad.set(full(true), 1)
end, "probe")
for i = 1, 10 do
  emu.frameadvance()
  w(string.format("  onframestart f%-2d KEYINPUT=0x%03X cb=%d", i, ki(), got))
end
event.unregisterbyid("probe", "probe")
joypad.set(full(false))

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
