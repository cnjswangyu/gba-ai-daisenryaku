-- deploy_show.lua —— 阶段性成果演示：出击编成表 → 自动部署 → 真战场第 1 回合
-- 出击阶段用 joypad（实测邮箱补丁在出击态+部署转场会引发 EmuHawk 静默崩溃，两次复现）；
-- 战斗阶段再用邮箱/原生桥（战场态已验证稳定）。窗口保留供观看。
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/deploy_show.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/ds_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end

local CTX  = 0x03000480
local U    = 0x03002BE2

local function state() return memory.read_u8(CTX) end
local function money() return memory.read_u32_le(CTX + 0x68) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function snap(tag)
  w(string.format("%-14s f=%-6d state=%d sub=%d ph=%d side=%d money=%d cur=(%d,%d)",
    tag, emu.framecount(), state(), memory.read_u8(CTX + 1),
    memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22), money(), cur()))
end

local function units_dump(tag)
  for _, side in ipairs({ "MY", "EN" }) do
    local base0 = (side == "MY") and U or (U + 0x600)
    local n, pos = 0, {}
    for k = 0, 63 do
      local b = base0 + k * 24 - 2
      local id = memory.read_u16_le(b)
      if id ~= 0 then
        n = n + 1
        pos[#pos + 1] = string.format("%d:(%d,%d)", id,
          memory.read_u8(b + 2), memory.read_u8(b + 3))
      end
    end
    w(string.format("%s %d 单位: %s", side, n, table.concat(pos, " ")))
  end
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)     -- 演示用正常速度，全程可看
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/pre_battle.State")
  adv(60)
  snap("出击编成表"); shot("01_deploy_screen")

  -- ===== 走勾选清单路径（V1 已验证：勾选 = 部署选择）=====
  -- 默认军表 10 单位（74式MBT×3 + FH70×2 + 軽歩兵×4 + 補給車×1，含步兵）
  press("B", 6, 60)
  press("A", 6, 90)      -- -> state4
  press("A", 6, 120)     -- -> 入口框
  press("A", 6, 120)     -- -> 清单
  snap("清单界面"); shot("02_list")
  press("A", 6, 40)      -- 吞第一下 A（清单刚打开时首次按键会被吞，V1 实证）
  local poolN = 0
  for i = 0, 98 do
    if memory.read_u16_le(CTX + 0x188 + i * 4) ~= 0 then poolN = poolN + 1 end
  end
  w("清单勾选 " .. poolN .. " 行…")
  for i = 1, poolN do
    press("A", 6, 55)
    if i < poolN then press("Down", 6, 55) end
    if i == 1 or i == poolN then shot("03_check" .. i) end
  end
  snap("已全部勾选"); shot("04_checked")

  -- ===== START → 确认框 A（部署被勾选的单位）=====
  press("Start", 6, 90);  snap("出击确认框");  shot("05_confirm_dialog")
  press("A", 6, 120);     snap("已确认出击")
  adv(500);               snap("配置阶段");     shot("06_setup_phase")

  -- ===== 开始战斗：START 总菜单 → A（第一项「开始战斗」）=====
  press("Start", 6, 90);  snap("总菜单");       shot("07_start_menu")
  press("A", 6, 120);     snap("开始战斗")

  -- ===== 清横幅（自适应：进入玩家操作阶段立刻停手）=====
  local ready = false
  for i = 1, 24 do
    adv(60)
    if state() == 7 and memory.read_u8(CTX + 1) == 1
        and memory.read_u8(CTX + 0x21) == 3 and memory.read_u8(CTX + 0x22) == 0 then
      ready = true
      w("进入玩家操作阶段（第 " .. i .. " 探）")
      break
    end
    press("A", 6, 40)
  end
  if not ready then error("未进入玩家操作阶段") end
  press("B", 6, 40)                -- 防 A 过冲打开菜单
  adv(30)

  -- ===== 成果定格 =====
  memory.write_u8(CTX + 0xC55, 0)  -- 顺手关完整战斗演出（逆向成果之一）
  snap("第一回合战场"); shot("05_battle_turn1")
  units_dump("战场")
  savestate.save(BASE .. "states/stage1_ready2.State")
  w("已存 states/stage1_ready2.State —— 可以出击：✔")
end, function(e) w("ERROR: " .. tostring(e)); shot("error") end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
