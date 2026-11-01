-- 通用输入测试：按住全部按键，看 KEYINPUT 是否变化
local OUT = "D:/prog/gba-ai/logs/probe_key2.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function ki() return memory.read_u16_le(0x04000130) % 1024 end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
for _ = 1, 40 do emu.frameadvance() end
w("基线 KEYINPUT=0x" .. string.format("%03X", ki()))

local all = { A = true, B = true, Start = true, Select = true, Up = true, Down = true, Left = true, Right = true, L = true, R = true }
pcall(joypad.set, all, 1)
for i = 1, 6 do
  emu.frameadvance()
  w(string.format("  全按下 f%d KEYINPUT=0x%03X", i, ki()))
end
pcall(joypad.set, {}, 1)
for i = 1, 3 do emu.frameadvance() end
w(string.format("  松开 KEYINPUT=0x%03X", ki()))

-- 试试 getgamepad 回读
local ok, gp = pcall(joypad.get, 1)
w("joypad.get(1) ok=" .. tostring(ok) .. " type=" .. type(gp))
if ok and type(gp) == "table" then
  local t = {}
  for k, v in pairs(gp) do t[#t + 1] = tostring(k) .. "=" .. tostring(v) end
  w("  " .. table.concat(t, " "))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
