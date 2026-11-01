-- deploy_finish.lua —— 从 stage1_ready.State 完成出击并保存战场存档点
-- 修正 deploy_stage1.lua 的误判：出击确认后游戏先播自动部署+开场演出，
-- 此时 state 仍是 6；要等光标可动（mobile）才算真正进入战场。
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/deploy_finish.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/df_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 60)
end

local CTX = 0x03000480
local U   = 0x03002BE2
local COST = 739  -- 187*6 + 241*2 + 208*2 + 305*4 + 324*2 + 339*1

local function money() return memory.read_u32_le(CTX + 0x68) end
local function state() return memory.read_u8(CTX) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function poolN()
  local n = 0
  for i = 0, 98 do if memory.read_u16_le(CTX + 0x188 + i * 4) ~= 0 then n = n + 1 end end
  return n
end
local function snap(tag)
  w(string.format("%-18s f=%-6d state=%d sub=%d ph=%d side=%d money=%d poolN=%d",
    tag, emu.framecount(), state(), memory.read_u8(CTX + 1),
    memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22), money(), poolN()))
end

local function mobile()
  local x0, y0 = cur()
  press("Right", 8, 8)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then press("Left", 8, 8); return true end
  return false
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/stage1_ready.State")
  adv(60)
  snap("loaded")
  -- 手动扣钱（实测游戏在整个出击流程里不扣钱，扣钱发生在购买时的池写入）
  local m = money()
  memory.write_u32_le(CTX + 0x68, m - COST)
  w(string.format("扣钱 %d -> %d", m, m - COST))

  -- 导航：B → A(到state4) → A(出击编成表+入口框) → A(自动部署界面) → 勾选17行 → START → A
  press("B", 6, 60); snap("afterB")
  press("A", 6, 90); snap("afterBA")
  press("A", 6, 120); snap("entry_dialog"); shot("entry")
  press("A", 6, 120); snap("autodeploy"); shot("autodeploy")
  for i = 1, 17 do
    press("A", 6, 55)
    if i < 17 then press("Down", 6, 55) end
  end
  snap("all_checked"); shot("checked")
  press("Start", 8, 120); snap("start_dialog"); shot("start")
  press("A", 8, 180); snap("confirmed"); shot("confirm")
  adv(300); snap("after_deploy_anim"); shot("deployed")

  -- 开场演出：逐段按 A 直到光标可动
  local reach = false
  for i = 1, 14 do
    if mobile() then reach = true; w("光标可动（第 " .. i .. " 轮）"); break end
    w("演出中，按 A 推进 #" .. i)
    press("A", 6, 60)
  end
  if not reach then error("14 轮后光标仍不可动") end
  adv(30)
  snap("battle_ready"); shot("battle")

  -- 单位表 dump
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
    w(string.format("%s 合计 %d", side, cnt))
  end
  w(string.format("最终: state=%d sub=%d ph=%d side=%d money=%d animation=%d",
    state(), memory.read_u8(CTX + 1), memory.read_u8(CTX + 0x21),
    memory.read_u8(CTX + 0x22), money(), memory.read_u8(CTX + 0xC55)))

  savestate.save(BASE .. "states/stage1_deployed.State")
  w("已存 states/stage1_deployed.State")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
