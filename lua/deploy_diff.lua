-- deploy_diff.lua —— 按 A 前后全 IWRAM diff, 定位"残り"计数器与选择状态
local BASE = "D:/prog/gba-ai/"
local STATE = BASE .. "states/pre_battle.State"
local OUT = BASE .. "logs/deploy_diff.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s; print(s) end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 5); joypad.set({}); adv(gap or 30)
end
local function snap()
  local t = {}
  for a = 0x03000000, 0x03007FFF do t[#t + 1] = memory.read_u8(a) end
  return t
end
local function diff(a, b, tag)
  w("---- diff " .. tag .. " ----")
  local n = 0
  for i = 1, #a do
    if a[i] ~= b[i] then
      n = n + 1
      if n <= 60 then
        w(string.format("  0x%08X: %02X -> %02X", 0x03000000 + i - 1, a[i], b[i]))
      end
    end
  end
  w(string.format("  共 %d 字节变化", n))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
w("load=" .. tostring(pcall(savestate.load, STATE)))
adv(60)
local s0 = snap()
w("初始: money(ctx+0x68)=" .. memory.read_u32_le(0x03000480 + 0x68) ..
  " ctx+0x24=" .. memory.read_u32_le(0x03000480 + 0x24))

-- 光标下移到第 2 行, 按 A 选择
press("Down", 5, 30)
local s1 = snap()
press("A", 5, 40)
local s2 = snap()
diff(s0, s2, "Down + A (选择第2行)")

-- 再按 A 取消选择
press("A", 5, 40)
local s3 = snap()
diff(s2, s3, "再按 A (取消选择)")

-- 扫 ctx 附近找 19/14 计数器: 现在应是 18
w("---- ctx 区关键字段 ----")
for a = 0x03000400, 0x03000700 do
  local v = memory.read_u8(a)
  if v >= 10 and v <= 30 then
    w(string.format("  0x%08X = %d", a, v))
  end
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
