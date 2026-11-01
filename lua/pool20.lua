-- pool20.lua: 从 USA 出击编成表存档出发
--   1) 池写满 20 个美国陆上单位 (M1A1/M1A2/M-2A3/M-109A6/MIM-104A)
--   2) 全部标记"配"(flag=1), 选择计数=20
--   3) B→确认→state4 → A→state6 (列表重建)
--   4) START→A 自动部署 → 地图
--   5) dump 战场单位表 + 存档
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/pool20.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/p_" .. n .. ".png") end
local CTX = 0x03000480
local function st()  return memory.read_u8(CTX) end
local function sub() return memory.read_u8(CTX + 1) end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 6)
  joypad.set({})
  adv(gap or 40)
end
local function wait_st(s, cap)
  cap = cap or 600
  for i = 1, cap do
    if st() == s then return true end
    adv(1)
  end
  return false
end

-- 20 个单位: (id, 价格)
local BUY = {}
local function add(id, price, n) for _ = 1, n do BUY[#BUY + 1] = { id, price } end end
add(0x0BA, 70, 10)   -- M1A1 艾布拉姆斯 x10
add(0x0BB, 90, 4)    -- M1A2 艾布拉姆斯 x4
add(0x134, 56, 4)    -- M-2A3 步兵战车 x4
add(0x0F1, 40, 2)    -- M-109A6 自行火炮 x2
add(0x109, 75, 2)    -- MIM-104A 爱国者 SAM x2

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(30)
pcall(savestate.load, BASE .. "states/pre_battle_usa.State")
adv(60)
w(string.format("loaded: state=%d sub=%d", st(), sub()))
shot("00_list")

-- 1) 写池
local money = memory.read_u32_le(CTX + 0x68)
local spend = 0
for i = 1, 20 do
  local u = BUY[i]
  local base = CTX + 0x188 + (i - 1) * 4
  memory.write_u16_le(base, u[1])
  memory.write_u8(base + 2, 0)
  memory.write_u8(base + 3, 1)      -- 1 = 已选"配"
  spend = spend + u[2]
end
-- 清掉 20 以后的槽
for i = 20, 98 do
  memory.write_u16_le(CTX + 0x188 + i * 4, 0)
  memory.write_u8(CTX + 0x188 + i * 4 + 3, 0)
end
memory.write_u32_le(CTX + 0x68, money - spend)
memory.write_u32_le(0x020095B4, 20)   -- 已选计数
w(string.format("pool written: 20 units, spend=%d, money %d -> %d", spend, money, money - spend))
local n = 0
for i = 0, 98 do
  local id = memory.read_u16_le(CTX + 0x188 + i * 4)
  if id ~= 0 then n = n + 1 end
end
w("pool non-zero = " .. n .. ", count=" .. memory.read_u32_le(0x020095B4))
adv(30)

-- 2) B → 确认"停止部署" → 回 state4
press("B", 6, 50); adv(40); shot("01_b_dialog")
press("A", 6, 80); adv(60)
w(string.format("after B+A: state=%d sub=%d", st(), sub()))
shot("02_after_ba")

-- 3) A → state6 (列表重建)
if st() == 4 then
  press("A", 6, 80); adv(80)
end
w(string.format("at state6: state=%d sub=%d", st(), sub()))
shot("03_list20")
adv(40); shot("04_list20b")

-- 4) 出击: 若在列表按 START; 若弹对话框按 A
if st() == 6 then
  press("Start", 6, 80); adv(60); shot("05_start_dialog")
  press("A", 6, 100); adv(120)
  w(string.format("after START+A: state=%d sub=%d", st(), sub()))
  shot("06_map")
end
adv(150); shot("07_map2")

-- 5) dump 战场单位表 (player0 @ctx+0x2760, player1 @ctx+0x2D60, stride 24)
local function dump_units(tag, base)
  w("---- " .. tag .. " @0x" .. string.format("%08X", base) .. " ----")
  local n = 0
  for i = 0, 98 do
    local a = base + i * 24
    local id = memory.read_u16_le(a)
    if id ~= 0 then
      n = n + 1
      w(string.format("  [%02d] id=0x%03X x=%d y=%d hp=%d kind=%d",
        i, id, memory.read_u8(a + 2), memory.read_u8(a + 3),
        memory.read_u8(a + 4), memory.read_u8(a + 8)))
    end
  end
  w("  count = " .. n)
end
dump_units("player0 战场表", CTX + 0x2760)
dump_units("player1 战场表", CTX + 0x2D60)

local ok = pcall(savestate.save, BASE .. "states/battle_usa.State")
w("saved battle_usa.State = " .. tostring(ok))

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
