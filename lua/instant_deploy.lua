-- instant_deploy.lua —— 瞬间配置出击：内存直写军表 + 最短触发路径 + 动画快进
--
-- 证据链（本次逆向结论，详见 logs/deploy_stage1.txt 差分与 logs/deploy_chain.c）：
--   1) 军表 = ctx+0x188，99 槽×4B（+0/+1 u16 单位ID、+2 LV、+3 flag）——内存直写即配置，0 按键
--   2) 资金 = ctx+0x68；游戏在出击全流程不扣钱（try1/try2 差分），扣钱发生在购买界面
--   3) 逐行勾选（17 次 A）不改变任何持久状态（勾选后 flag 全 0，确认后 flag=部署序号 1..N）
--      → 出击编成表(state6) 直接 START→确认A 就会自动部署全部池单位（enter_battle.lua 实证）
--   4) Ghidra FUN_080099b8：确认框出口写 ctx+0=1, ctx+1=1（本脚本实验 A 验证能否直跳）
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/instant_deploy.txt"
local fh = io.open(OUT, "w")
local T0 = os.clock()
local function w(s)
  if fh then fh:write(string.format("[%.1fs] %s\n", os.clock() - T0, s)); fh:flush() end
end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/id_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 60)
end

local CTX = 0x03000480
local U   = 0x03002BE2
local COST = 739

local function money() return memory.read_u32_le(CTX + 0x68) end
local function state() return memory.read_u8(CTX) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function poolN()
  local n = 0
  for i = 0, 98 do if memory.read_u16_le(CTX + 0x188 + i * 4) ~= 0 then n = n + 1 end end
  return n
end
local function snap(tag)
  w(string.format("%-16s f=%-6d state=%d sub=%d ph=%d side=%d money=%d poolN=%d",
    tag, emu.framecount(), state(), memory.read_u8(CTX + 1),
    memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22), money(), poolN()))
end
local function mobile()
  local back = { Left = "Right", Right = "Left", Up = "Down", Down = "Up" }
  for _, k in ipairs({ "Left", "Right", "Up", "Down" }) do
    local x0, y0 = cur()
    press(k, 14, 8)          -- 战场光标 joypad 需 ~13-14 帧才走 1 格
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then
      press(back[k], 14, 8)  -- 走回原格
      return true
    end
  end
  return false
end
-- 等到战场可操作：轮询 state 轨迹（6→7 翻转点），每 4 轮截图
local function wait_map(tag)
  for i = 1, 40 do
    adv(60)
    local st, sb = state(), memory.read_u8(CTX + 1)
    local x, y = cur()
    w(string.format("%s r%02d state=%d sub=%d cur=(%d,%d)", tag, i, st, sb, x, y))
    if i % 4 == 0 then shot(tag .. "_w" .. i) end
    if st == 7 and sb == 1 then
      for j = 1, 10 do
        if mobile() then w(tag .. ": 战场可操作（state7 后第 " .. j .. " 探）"); return true end
        press("A", 6, 40)
      end
      return mobile()
    end
    press("A", 6, 40)
  end
  return false
end
local function battle_dump(tag)
  for _, side in ipairs({ "MY", "EN" }) do
    local base0 = (side == "MY") and U or (U + 0x600)
    local cnt, ids = 0, {}
    for k = 0, 63 do
      local b = base0 + k * 24 - 2
      local id = memory.read_u16_le(b)
      if id ~= 0 then
        cnt = cnt + 1
        ids[#ids + 1] = string.format("%d(%d,%d)", id,
          memory.read_u8(b + 2), memory.read_u8(b + 3))
      end
    end
    w(string.format("%s %d: %s", side, cnt, table.concat(ids, " ")))
  end
end
local function flag_dump()
  local t = {}
  for i = 0, 20 do
    local id = memory.read_u16_le(CTX + 0x188 + i * 4)
    if id ~= 0 then t[#t + 1] = id .. "*" .. memory.read_u8(CTX + 0x188 + i * 4 + 3) end
  end
  w("pool flags: " .. table.concat(t, ","))
end

local ok, err = xpcall(function()
  pcall(client.setsoundon, false)
  pcall(client.speedmode, 800)          -- 全程快进，进战场后降速
  adv(30)

  -- ===== 实验 A：状态直跳（已否决：触发剧本重置，池被恢复默认军表）=====
  -- 保留结论：写 ctx+0=1,ctx+1=1 确实切换状态机（state 6→1 实测生效），
  -- 但 state1 处理器重载剧本数据，军表丢失，不可用作出击入口。

  -- ===== 实验 B：最短按键路径（共 6 键，全程 800% 快进）=====
  -- 出击编成表 START→A 确认自动部署 → 配置阶段(state6，光标钉首都，非卡死)
  -- → START 总菜单第一项「开始战斗」→A → 清演習标题/第1ターン横幅 → 真战斗 state7
  savestate.load(BASE .. "states/stage1_ready.State")
  adv(60)
  memory.write_u32_le(CTX + 0x68, money() - COST)
  snap("B_loaded")
  press("Start", 6, 90); snap("B_deploy_dialog"); shot("B_dialog")
  press("A", 6, 120);    snap("B_deploy_confirmed")
  adv(450);              snap("B_setup_phase"); shot("B_setup")
  press("Start", 6, 90); snap("B_menu");         shot("B_menu")
  press("A", 6, 120);    snap("B_battle_start")  -- 第一项「开始战斗」
  -- 自适应清横幅：一旦进入玩家操作阶段立刻停手，防止 A 过冲打开首都菜单
  local okph = false
  for i = 1, 24 do
    adv(60)
    local ph, sd = memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22)
    if state() == 7 and memory.read_u8(CTX + 1) == 1 and ph == 3 and sd == 0 then
      okph = true; w("进入玩家操作阶段（第 " .. i .. " 探，f=" .. emu.framecount() .. "）")
      break
    end
    press("A", 6, 40)
  end
  if not okph then error("未进入玩家操作阶段") end
  -- A 可能过冲打开了菜单：先 B 关掉，再测光标
  press("B", 6, 40)
  local okm = false
  for j = 1, 6 do
    if mobile() then okm = true; w("光标可动（第 " .. j .. " 探）"); break end
    press("B", 6, 40)
  end
  if not okm then shot("B_stuck"); error("光标不可动") end

  -- ===== 战场收尾 =====
  pcall(client.speedmode, 100)
  adv(30)
  memory.write_u8(CTX + 0xC55, 0)       -- 关完整战斗演出
  snap("battle_ready"); shot("battle")
  battle_dump("stage1")
  flag_dump()
  local cx, cy = cur()
  w(string.format("光标 (%d,%d)  演出开关=%d", cx, cy, memory.read_u8(CTX + 0xC55)))
  savestate.save(BASE .. "states/stage1_deployed.State")
  w("已存 states/stage1_deployed.State")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
