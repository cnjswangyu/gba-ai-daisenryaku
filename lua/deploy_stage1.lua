-- deploy_stage1.lua —— 派兵（出击编成）逆向探针 + 第一关「含步兵」出击执行
--
-- 目标：
--   1) 逆向记录出击编成表的内存布局与导航状态机（差分日志 + 截图）
--   2) 写一个含步兵的新军表，确认出击，保存战场存档点
--
-- 已知布局（HANDOFF §0.7 + usa_army.lua 实证）：
--   池      = ctx+0x188，99 槽 × 4B：+0/+1 u16 单位ID，+2 LV，+3 选择标志
--   资金    = ctx+0x68 u32
--   state   = ctx+0x00（4=部署菜单/6=出击编成表/7=战场），ctx+0x01 substep
--   state6 handler = 0x080099B8；清单生成 FUN_08009348；渲染 FUN_08009554
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/deploy_stage1.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/deploy_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 60)
end

local CTX = 0x03000480
local U   = 0x03002BE2

-- 目标军表：{id, 数量, 名称}（id = lua/unitdb.tsv 首列）
local ARMY = {
  {187, 6, "M1A2坦克"},
  {241, 2, "M-109A6自走炮"},
  {208, 2, "M-901反坦克导弹"},
  {305, 4, "軽歩兵"},
  {324, 2, "空降傘兵"},
  {339, 1, "補給車"},
}
local PRICE = { [187] = 90, [241] = 40, [208] = 15, [305] = 9, [324] = 9, [339] = 35 }

local function money() return memory.read_u32_le(CTX + 0x68) end

-- 全量池快照（逆向证据）
local function pool_dump(tag)
  local lines = {}
  for i = 0, 98 do
    local b = CTX + 0x188 + i * 4
    local id = memory.read_u16_le(b)
    if id ~= 0 then
      lines[#lines + 1] = string.format("  slot%02d id=%d(0x%03X) lv=%d flag=%d",
        i, id, id, memory.read_u8(b + 2), memory.read_u8(b + 3))
    end
  end
  w(string.format("--- %s: %d 个单位 ---", tag, #lines))
  for _, l in ipairs(lines) do w(l) end
end

local function pool_digest()
  local n, ids = 0, {}
  for i = 0, 98 do
    local id = memory.read_u16_le(CTX + 0x188 + i * 4)
    local fl = memory.read_u8(CTX + 0x188 + i * 4 + 3)
    if id ~= 0 then
      n = n + 1
      if #ids < 24 then
        ids[#ids + 1] = id .. (fl ~= 0 and ("*" .. fl) or "")
      end
    end
  end
  return n, table.concat(ids, ",")
end

local function snap(tag)
  local n, ids = pool_digest()
  w(string.format("%-18s f=%-6d state=%d sub=%d ph=%d side=%d player=%d money=%d poolN=%d pool=[%s]",
    tag, emu.framecount(), memory.read_u8(CTX), memory.read_u8(CTX + 1),
    memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22), memory.read_u8(CTX + 0x990),
    money(), n, ids))
end

local function state() return memory.read_u8(CTX) end

-- ============ 导航：到 state4（部署军力菜单） ============
local function goto_state4()
  if state() == 4 then snap("already_state4"); return true end
  press("B", 6, 60); snap("afterB")
  press("A", 6, 90); snap("afterBA")
  if state() == 4 then return true end
  -- 兜底：再试一轮
  press("B", 6, 60); snap("afterB2")
  press("A", 6, 90); snap("afterBA2")
  return state() == 4
end

-- ============ 导航：出击全流程，返回是否到达战场(state7) ============
local function navigate_to_battle(tag)
  if not goto_state4() then w("!! 到不了 state4，中止"); return false end
  shot(tag .. "_state4")
  press("A", 6, 120); snap(tag .. "_entry_dialog"); shot(tag .. "_entry")
  if state() ~= 6 then w("!! 没有进入出击编成表 state6，当前 state=" .. state()); return false end
  press("A", 6, 120); snap(tag .. "_autodeploy"); shot(tag .. "_autodeploy")

  -- 逐个勾选（池里 17 个非空槽 = 17 行）
  local n = pool_digest()
  for i = 1, n do
    press("A", 6, 55)
    if i == 1 or i == n or i % 5 == 0 then
      w(string.format("  checked #%d/%d (f=%d)", i, n, emu.framecount()))
      shot(string.format("%s_check%02d", tag, i))
    end
    if i < n then press("Down", 6, 55) end
  end
  snap(tag .. "_all_checked"); shot(tag .. "_checked")

  press("Start", 8, 120); snap(tag .. "_start_dialog"); shot(tag .. "_start")
  press("A", 8, 180); snap(tag .. "_confirmed"); shot(tag .. "_confirm")
  adv(200); snap(tag .. "_transition")
  adv(150); snap(tag .. "_map"); shot(tag .. "_battle")
  return state() == 7
end

-- ============ 战场单位 dump ============
local function battle_dump(tag)
  w(string.format("--- %s 战场单位 ---", tag))
  for _, side in ipairs({ "MY", "EN" }) do
    local base0 = (side == "MY") and U or (U + 0x600)
    local cnt = 0
    for k = 0, 63 do
      local b = base0 + k * 24 - 2
      local id = memory.read_u16_le(b)
      if id ~= 0 then
        cnt = cnt + 1
        w(string.format("  %s%02d id=%-4d x=%-2d y=%-2d hp=%-3d fuel=%-3d ammo=%-2d st=%d",
          side, k, id, memory.read_u8(b + 2), memory.read_u8(b + 3),
          memory.read_u8(b + 6), memory.read_u8(b + 4), memory.read_u8(b + 8),
          memory.read_u8(b + 7)))
      end
    end
    w(string.format("  %s 合计 %d", side, cnt))
  end
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)

  -- 1) 选存档点：优先 pre_battle（1500 资金默认池），不行用 pre_battle_usa（2500）
  local chosen = nil
  for _, name in ipairs({ "pre_battle", "pre_battle_usa" }) do
    savestate.load(BASE .. "states/" .. name .. ".State")
    adv(60)
    local n = pool_digest()
    w(string.format("候选存档 %s: state=%d money=%d poolN=%d", name, state(), money(), n))
    if not chosen and state() == 6 and money() >= 800 then chosen = name end
  end
  if not chosen then error("两个候选存档都不可用") end
  savestate.load(BASE .. "states/" .. chosen .. ".State")
  adv(60)
  snap("loaded_" .. chosen)
  pool_dump("original_pool")

  -- 2) 写新池（含步兵）
  for i = 0, 98 do
    local b = CTX + 0x188 + i * 4
    memory.write_u8(b, 0); memory.write_u8(b + 1, 0)
    memory.write_u8(b + 2, 0); memory.write_u8(b + 3, 0)
  end
  local slot, cost = 0, 0
  for _, e in ipairs(ARMY) do
    local id, qty = e[1], e[2]
    cost = cost + (PRICE[id] or 0) * qty
    for _ = 1, qty do
      memory.write_u16_le(CTX + 0x188 + slot * 4, id)
      memory.write_u8(CTX + 0x188 + slot * 4 + 2, 0)  -- LV 0 = E
      memory.write_u8(CTX + 0x188 + slot * 4 + 3, 0)  -- flag 0 = 未选
      slot = slot + 1
    end
  end
  w(string.format("新军表：%d 个单位，标价 %d（当前资金 %d，先不手动扣钱，看游戏自己扣不扣）",
    slot, cost, money()))
  -- 回读校验
  local bad = 0
  local si = 0
  for _, e in ipairs(ARMY) do
    for _ = 1, e[2] do
      if memory.read_u16_le(CTX + 0x188 + si * 4) ~= e[1] then bad = bad + 1 end
      si = si + 1
    end
  end
  w("回读校验：不一致 " .. bad .. " 处")
  snap("after_pool_write")
  pool_dump("new_pool")
  savestate.save(BASE .. "states/stage1_ready.State")
  w("已存 states/stage1_ready.State")

  -- 3) 第一次导航：不手动扣钱（差分看游戏是否自己扣）
  local done = navigate_to_battle("try1_nodeduct")
  if done then
    w(string.format("出击成功（游戏未手动扣钱路径）。最终资金 %d", money()))
  else
    -- 4) 失败兜底：手动扣钱重来
    w("第一次未到战场，回退到 stage1_ready 并手动扣钱重试")
    savestate.load(BASE .. "states/stage1_ready.State")
    adv(60)
    local m = money()
    memory.write_u32_le(CTX + 0x68, m - cost)
    w(string.format("手动扣钱：%d -> %d", m, m - cost))
    snap("after_manual_deduct")
    done = navigate_to_battle("try2_deduct")
    if not done then error("第二次导航仍未到战场") end
  end

  adv(120)
  snap("final")
  battle_dump("stage1")
  savestate.save(BASE .. "states/stage1_deployed.State")
  w("已存 states/stage1_deployed.State（第一关含步兵出击完成）")
  shot("final_battle")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
