-- 输入通路验证：按住 A 时，KEYINPUT 从 Lua 侧读到什么；PC 会不会离开等待循环
local OUT = "D:/prog/gba-ai/logs/probe_key.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function reg(n) local ok, v = pcall(emu.getregister, n); if ok and v then return v end return 0 end
local function ki() return memory.read_u16_le(0x04000130) % 1024 end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)

w("=== 空白 30 帧 ===")
for _ = 1, 30 do emu.frameadvance() end
w(string.format("  KEYINPUT=0x%03X R15=0x%08X", ki(), reg("R15")))

w("=== 按住 A：逐帧观察 ===")
pcall(joypad.set, { A = true }, 1)
for i = 1, 12 do
  emu.frameadvance()
  w(string.format("  f%-3d KEYINPUT=0x%03X R15=0x%08X R6=0x%08X", i, ki(), reg("R15"), reg("R6")))
end
pcall(joypad.set, {}, 1)
for i = 1, 10 do
  emu.frameadvance()
  w(string.format("  松手 f%-3d KEYINPUT=0x%03X R15=0x%08X", i, ki(), reg("R15")))
end

w("=== 按住 START 再试 ===")
pcall(joypad.set, { Start = true }, 1)
for i = 1, 12 do
  emu.frameadvance()
  w(string.format("  f%-3d KEYINPUT=0x%03X R15=0x%08X", i, ki(), reg("R15")))
end
pcall(joypad.set, {}, 1)
for _ = 1, 60 do emu.frameadvance() end
w(string.format("  60 帧后 R15=0x%08X IWRAM非零=%s", reg("R15"), (function()
  local ok, b = pcall(memory.readbyterange, 0x03000000, 0x1000)
  if not (ok and b) then return "?" end
  local nz = 0
  for j = 0, 4095 do if (b[j] or 0) ~= 0 then nz = nz + 1 end end
  return tostring(nz)
end)()))
pcall(client.screenshot, "D:/prog/gba-ai/shots/p3_after_key.png")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
