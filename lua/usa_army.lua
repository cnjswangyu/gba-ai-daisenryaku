-- USA 完整出击流程: 写20单位池(全车辆) → 回state4 → 重进state6 → 入口对话框A → 自动部署界面
-- → 逐个A勾选20个单位 → START → A确认 → 战场 → 存 battle_usa.State
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/usa_army.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/ar_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 60)
end

local CTX = 0x03000480

-- 目标编成: {id, 数量}
local ARMY = {
  {187, 10},  -- M1A2 艾布拉姆斯 (坦克)
  {241,  4},  -- M-109A6 圣骑士 (自走炮)
  {208,  2},  -- M-901 ITV (反坦克导弹车)
  {339,  2},  -- 补给车
  {290,  2},  -- M-3A2 布雷德里 (侦察)
}
local PRICE = {187, 241, 208, 339, 290}  -- 同 ARMY 顺序单价
PRICE = {[187]=90, [241]=40, [208]=15, [339]=35, [290]=48}

local function dump_pool(tag)
  local n = 0
  local parts = {}
  for i = 0, 30 do
    local b0 = memory.read_u8(CTX+0x188+i*4)
    local b1 = memory.read_u8(CTX+0x188+i*4+1)
    local b2 = memory.read_u8(CTX+0x188+i*4+2)
    local b3 = memory.read_u8(CTX+0x188+i*4+3)
    if b0 ~= 0 or b1 ~= 0 then
      n = n + 1
      parts[#parts+1] = string.format("%d:%02X", b0 + b1*256, b3)
    end
  end
  w(string.format("%-12s state=%d sub=%d money=%d poolcount=%d pool=[%s]",
    tag, memory.read_u8(CTX), memory.read_u8(CTX+1),
    memory.read_u32_le(CTX+0x68), n, table.concat(parts, " ")))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/pre_battle_usa.State")
  adv(60)
  dump_pool("loaded"); shot("00_before")

  -- 1) 写池: 先清 0..98, 再按编成写入
  local cost = 0
  for i = 0, 98 do
    memory.write_u8(CTX+0x188+i*4,   0)
    memory.write_u8(CTX+0x188+i*4+1, 0)
    memory.write_u8(CTX+0x188+i*4+2, 0)
    memory.write_u8(CTX+0x188+i*4+3, 0)
  end
  local slot = 0
  for _, e in ipairs(ARMY) do
    local id, qty = e[1], e[2]
    cost = cost + PRICE[id] * qty
    for _ = 1, qty do
      memory.write_u16_le(CTX+0x188+slot*4, id)
      memory.write_u8(CTX+0x188+slot*4+2, 0)   -- LV/经验 0 = E
      memory.write_u8(CTX+0x188+slot*4+3, 0)   -- flag 0 = 未选
      slot = slot + 1
    end
  end
  w(string.format("army written: %d units, cost=%d", slot, cost))
  -- 2) 扣钱
  local money = memory.read_u32_le(CTX+0x68)
  memory.write_u32_le(CTX+0x68, money - cost)
  dump_pool("afterWrite")

  -- 3) 中间存档(可重试导航)
  savestate.save(BASE .. "states/pre_battle_usa20.State")
  adv(30)

  -- 4) B 中止 → A 确认 → state4
  press("B", 6, 60)
  w("afterB state=" .. memory.read_u8(CTX)); shot("01_B")
  press("A", 6, 90)
  w("afterBA state=" .. memory.read_u8(CTX)); shot("02_state4")

  -- 5) state4 项0(部署军力) → state6 + 入口对话框
  press("A", 6, 120)
  w("afterA2 state=" .. memory.read_u8(CTX)); shot("03_entry_dialog")

  -- 6) A 确认电脑自动部署 → 自动部署界面
  press("A", 6, 120)
  w("afterA3 state=" .. memory.read_u8(CTX)); shot("04_autodeploy")

  -- 7) 逐个勾选: A 选当前行, Down 下一行 (20个单位)
  for i = 1, 20 do
    press("A", 6, 55)
    if i % 5 == 0 or i == 1 then
      w(string.format("  checked #%d (f=%d)", i, emu.framecount()))
      shot(string.format("05_check%02d", i))
    end
    if i < 20 then press("Down", 6, 55) end
  end
  shot("06_all_checked")

  -- 8) START → 确认框 → A → 开战
  press("Start", 8, 120)
  w("afterStart state=" .. memory.read_u8(CTX)); shot("07_start_dialog")
  press("A", 8, 180)
  w("afterA4 state=" .. memory.read_u8(CTX)); shot("08_after_confirm")

  adv(200)
  w("final state=" .. memory.read_u8(CTX) .. " sub=" .. memory.read_u8(CTX+1))
  shot("09_battle")

  -- 9) 战场存档
  local sv = savestate.save(BASE .. "states/battle_usa.State")
  w("savestate.save battle_usa.State = " .. tostring(sv))

  -- 10) 战场单位表 dump
  local n = 0
  for i = 0, 63 do
    if memory.read_u16_le(CTX+0x2760+i*24) ~= 0 then n = n + 1 end
  end
  w("battle table units = " .. n)
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
