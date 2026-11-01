-- 定性实验：往表里写坐标后，游戏逻辑认不认？
-- 步骤：写 U17 到 (18,31) → 光标走过去 → 按 A → 截图
--   若弹出"M-3A2"的信息面板/菜单 = 游戏读这张表（只是渲染没刷新）
--   若无反应 = 表是纯副本，真身在别处
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_memmove2.txt"
local U    = 0x03002BE2
local K    = 17
local TX, TY = 18, 31

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/mq_" .. n .. ".png") end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function hold(k, f, g)
  for _ = 1, (f or 13) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 8)
end
local function tap(k, g) hold(k, 4, g or 30) end
local function rec(tag)
  local o = U + K * 24
  w(string.format("%-12s u17=(%d,%d) cursor=(%d,%d)", tag,
    memory.read_u8(o), memory.read_u8(o + 1), cur()))
end

-- 光标闭环走到目标
local function goto_cell(tx, ty)
  for _ = 1, 60 do
    local x, y = cur()
    if x == tx and y == ty then return true end
    local dx, dy = tx - x, ty - y
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, 13, 6)
  end
  return false
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(80)

  -- 清开场演出（光标可动即演出结束）
  for i = 1, 10 do
    local x0, y0 = cur()
    hold("Right", 13, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); w("演出结束于第" .. i .. "轮"); break end
    tap("A", 35)
  end
  rec("0-准备")

  -- 原位置 (19,29) 按 A，应该能选中 M-3A2
  w(">>> 基线：光标到原位置 (19,29) 按 A")
  goto_cell(19, 29); rec("1-到原位")
  tap("A", 40); shot("1_orig_A")
  tap("B", 30); tap("B", 30)

  -- 写坐标
  local o = U + K * 24
  memory.write_u8(o, TX); memory.write_u8(o + 1, TY)
  adv(30); rec("2-写完")
  shot("2_written")

  w(">>> 光标走到写入的新位置 (18,31) 按 A")
  local reached = goto_cell(TX, TY)
  rec("3-到新位")
  w("到达=" .. tostring(reached))
  shot("3_at_new")
  tap("A", 45); shot("4_new_A")
  adv(40); shot("5_new_A2")

  -- 顺便看原位置现在是什么
  w(">>> 光标回原位置 (19,29) 按 A")
  tap("B", 25)
  goto_cell(19, 29); rec("4-回原位")
  tap("A", 45); shot("6_orig_again")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
