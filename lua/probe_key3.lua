-- 输入注入方式对比：不同 speedmode / 不同写法下 KEYINPUT 是否变化
local OUT = "D:/prog/gba-ai/logs/probe_key3.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function ki() return memory.read_u16_le(0x04000130) % 1024 end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

local function trial(label, setup)
  pcall(joypad.set, {}, 1)
  adv(5)
  local before = ki()
  local ok = pcall(setup)
  local seq = {}
  for i = 1, 4 do
    adv(1)
    seq[#seq + 1] = string.format("%03X", ki())
  end
  pcall(joypad.set, {}, 1)
  adv(3)
  w(string.format("%-28s before=%03X during=%s  setup_ok=%s  reset=%03X",
    label, before, table.concat(seq, ","), tostring(ok), ki()))
end

pcall(client.setsoundon, false)

-- A: 默认速度（不调 speedmode）
trial("默认速度 + joypad.set", function() joypad.set({ A = true }, 1) end)

-- B: speedmode 100
pcall(client.speedmode, 100)
trial("speedmode(100) + joypad.set", function() joypad.set({ A = true }, 1) end)

-- C: speedmode 0
pcall(client.speedmode, 0)
trial("speedmode(0) + joypad.set", function() joypad.set({ A = true }, 1) end)

-- D: joypad.setanalog 无关，改试 set 后连续两帧再读
trial("set+双帧保持", function()
  joypad.set({ A = true }, 1)
  emu.frameadvance()
  joypad.set({ A = true }, 1)
end)

-- E: 看 joypad.get 是否回读到注入值
pcall(joypad.set, { A = true }, 1)
adv(1)
local okg, g = pcall(joypad.get, 1)
local dump = {}
if okg and type(g) == "table" then
  for k, v in pairs(g) do dump[#dump + 1] = tostring(k) .. "=" .. tostring(v) end
end
w("joypad.get(1) 内容: " .. table.concat(dump, " "))
pcall(joypad.set, {}, 1)

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
