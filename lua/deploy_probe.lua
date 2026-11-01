-- deploy_probe.lua —— 实测出击编成表: A 键行为 / 残り19 / 加单位路径
local BASE = "D:/prog/gba-ai/"
local STATE = BASE .. "states/pre_battle.State"
local OUT = BASE .. "logs/deploy_probe.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s; print(s) end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/dp_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 5); joypad.set({}); adv(gap or 30)
end

local CTX = 0x03000480
local function dump_ctx(tag)
  w(string.format("---- %s ----", tag))
  w(string.format("  state=%d substep=%d phase=%d money=%d",
    memory.read_u8(CTX), memory.read_u8(CTX + 1), memory.read_u32_le(CTX + 8),
    memory.read_u32_le(CTX + 0x68)))
  -- 99 个部署槽
  local n = 0
  local ids = {}
  for i = 0, 98 do
    local v = memory.read_u32_le(CTX + 0x188 + i * 4)
    if v ~= 0 then
      n = n + 1
      if n <= 14 then ids[#ids + 1] = string.format("%d:id=%04X st=%04X", i, v & 0xFFFF, v >> 16) end
    end
  end
  w(string.format("  槽数=%d: %s", n, table.concat(ids, " ")))
  -- ctx+0x2b 区域(每玩家 0xC)
  local s = ""
  for i = 0, 0x20 do s = s .. string.format("%02X ", memory.read_u8(CTX + 0x20 + i)) end
  w("  ctx+0x20: " .. s)
  -- 找 部隊数/残り 计数器: 扫 ctx+0x00-0x100 的 u16
  local cnt = {}
  for a = 0x00, 0x100, 2 do
    local v = memory.read_u16_le(CTX + a)
    if v == 10 or v == 19 or v == 29 then cnt[#cnt + 1] = string.format("+%02X=%d", a, v) end
  end
  w("  含10/19/29的字段: " .. table.concat(cnt, " "))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
w("load=" .. tostring(pcall(savestate.load, STATE)))
adv(60)
dump_ctx("初始(编成表, 日本, 10单位)")
shot("00_init")

-- 1. 光标下移
press("Down", 5, 30)
dump_ctx("按 DOWN 后")
shot("01_down")

-- 2. 按 A (选择?)
press("A", 5, 40)
dump_ctx("按 A 后")
shot("02_a")

-- 3. 再下移+ A 几次
for i = 3, 6 do
  press("Down", 5, 25)
  press("A", 5, 35)
end
dump_ctx("又按 4 次 Down+A 后")
shot("03_more")

-- 4. 一路下移看列表是否滚动超过 10 行
for i = 1, 12 do press("Down", 5, 18) end
dump_ctx("连按 12 次 DOWN 后")
shot("04_scroll")

-- 5. 再按 A 看反应
press("A", 5, 40)
dump_ctx("底部按 A 后")
shot("05_a_bottom")

-- 6. 回到顶部再按 A 第一行
for i = 1, 20 do press("Up", 5, 15) end
press("A", 5, 40)
dump_ctx("回顶部按 A 后")
shot("06_a_top")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
