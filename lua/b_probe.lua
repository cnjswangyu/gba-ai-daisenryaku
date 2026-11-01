-- b_probe.lua: 从 USA 编成表存档出发, 测 B 键回退路径, 存 state4 锚点
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/b_probe.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/bp_" .. n .. ".png") end
local CTX = 0x03000480
local function st()  return memory.read_u8(CTX) end
local function sub() return memory.read_u8(CTX + 1) end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 6)
  joypad.set({})
  adv(gap or 40)
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(30)
pcall(savestate.load, BASE .. "states/pre_battle_usa.State")
adv(60)
w(string.format("loaded: state=%d sub=%d pool0=0x%03X", st(), sub(), memory.read_u16_le(CTX + 0x188)))
shot("00_at_state6")

-- B 取消自动部署对话框(若开着)
press("B", 6, 50); adv(30)
w(string.format("after B#1: state=%d sub=%d", st(), sub()))
shot("01_after_b1")

-- 再按 B: 列表的返回
press("B", 6, 50); adv(40)
w(string.format("after B#2: state=%d sub=%d", st(), sub()))
shot("02_after_b2")

-- 若弹确认框, 按 A 确认
if st() == 6 then
  press("A", 6, 60); adv(40)
  w(string.format("after A(confirm): state=%d sub=%d", st(), sub()))
  shot("03_after_confirm")
end

w(string.format("final: state=%d sub=%d money=%d", st(), sub(), memory.read_u32_le(CTX + 0x68)))
-- 池还在吗
local n = 0
for i = 0, 98 do
  if memory.read_u16_le(CTX + 0x188 + i * 4) ~= 0 then n = n + 1 end
end
w("pool non-zero = " .. n)

if st() == 4 then
  local ok = pcall(savestate.save, BASE .. "states/pre_battle_usa4.State")
  w("saved pre_battle_usa4.State = " .. tostring(ok))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
