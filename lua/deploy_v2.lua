-- deploy_v2.lua —— 大军表部署：写池(20单位) → 勾选清单路径出击 → stage1_v2_deployed
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/deploy_v2.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/dv2_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end
local CTX = 0x03000480
local U   = 0x03002BE2
-- 军表 20 单位：M1A2×9 / M-109A6×4 / 軽歩兵×4 / 空降×2 / 補給×1（资金 1059 / 2500）
local ARMY = { {187,9}, {241,4}, {305,4}, {324,2}, {339,1} }
local COST = 9*90 + 4*40 + 4*9 + 2*9 + 35

local function state() return memory.read_u8(CTX) end
local function money() return memory.read_u32_le(CTX + 0x68) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function poolN()
  local n = 0
  for i = 0, 98 do if memory.read_u16_le(CTX + 0x188 + i * 4) ~= 0 then n = n + 1 end end
  return n
end
local function snap(tag)
  w(string.format("%-14s f=%-6d state=%d sub=%d ph=%d side=%d money=%d poolN=%d cur=(%d,%d)",
    tag, emu.framecount(), state(), memory.read_u8(CTX + 1),
    memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22), money(), poolN(), cur()))
end
local function mobile()
  local back = { Left = "Right", Right = "Left", Up = "Down", Down = "Up" }
  for _, k in ipairs({ "Left", "Right", "Up", "Down" }) do
    local x0, y0 = cur()
    press(k, 14, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then press(back[k], 14, 8); return true end
  end
  return false
end
local ok, err = xpcall(function()
  pcall(client.speedmode, 200)
  pcall(client.setsoundon, true)   -- 保留声音（原为 false：静音是旧调试脚本的习惯，会让窗口全程无声）
  adv(30)
  savestate.load(BASE .. "states/pre_battle_usa.State"); adv(60)
  snap("出击编成表")
  -- 写池
  for i = 0, 98 do
    local b = CTX + 0x188 + i * 4
    memory.write_u8(b, 0); memory.write_u8(b + 1, 0)
    memory.write_u8(b + 2, 0); memory.write_u8(b + 3, 0)
  end
  local slot = 0
  for _, e in ipairs(ARMY) do
    for _ = 1, e[2] do
      memory.write_u16_le(CTX + 0x188 + slot * 4, e[1]); slot = slot + 1
    end
  end
  memory.write_u32_le(CTX + 0x68, money() - COST)
  w(string.format("池写入 %d 单位, 扣款 %d -> %d", slot, COST, money()))
  -- 勾选清单路径
  press("B", 6, 60); press("A", 6, 90); press("A", 6, 120); press("A", 6, 120)
  snap("清单")
  press("A", 6, 40)   -- 垫防吞
  for i = 1, slot do
    press("A", 6, 55)
    if i < slot then press("Down", 6, 55) end
    if i == 1 or i == slot then shot("check" .. i) end
  end
  snap("已勾选"); shot("checked")
  press("Start", 6, 90); snap("确认框"); shot("dialog")
  press("A", 6, 120);    snap("已确认")
  adv(500);              snap("配置阶段"); shot("setup")
  press("Start", 6, 90); snap("总菜单")
  press("A", 6, 120);    snap("开始战斗")
  local ready = false
  for i = 1, 24 do
    adv(60)
    if state() == 7 and memory.read_u8(CTX + 1) == 1
        and memory.read_u8(CTX + 0x21) == 3 and memory.read_u8(CTX + 0x22) == 0 then
      ready = true; w("玩家操作阶段（第 " .. i .. " 探）"); break
    end
    press("A", 6, 40)
  end
  if not ready then error("未进入玩家操作阶段") end
  press("B", 6, 40); adv(30)
  memory.write_u8(CTX + 0xC55, 0)
  snap("第1回合")
  -- 单位 dump
  for _, side in ipairs({ "MY", "EN" }) do
    local base0 = (side == "MY") and U or (U + 0x600)
    local n, pos = 0, {}
    for k = 0, 63 do
      local b = base0 + k * 24 - 2
      local id = memory.read_u16_le(b)
      if id ~= 0 then
        n = n + 1
        pos[#pos + 1] = string.format("%d:(%d,%d)", id, memory.read_u8(b + 2), memory.read_u8(b + 3))
      end
    end
    w(side .. " " .. n .. ": " .. table.concat(pos, " "))
  end
  savestate.save(BASE .. "states/stage1_v2_deployed.State")
  w("已存 states/stage1_v2_deployed.State")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
