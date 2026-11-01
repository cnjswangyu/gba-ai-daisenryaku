-- 爆破实验 1：把移动范围掩码全填"可达"，看能不能走到任意格
-- 掩码 = ctx+0x0C5D + y*0x30 + x，可达位 = 0x10 << 玩家
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_mask.txt"
local CTX  = 0x03000480
local MASK = 0x0C5D          -- ctx 偏移
local SIZE = 0x900           -- 2304 = 48*48
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/mk_" .. n .. ".png") end
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80 }
local mailOK = false
local function hold(k, f, g)
  if mailOK then
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    for _ = 1, (f or 5) do emu.frameadvance() end
    memory.write_u16_le(MAIL, 0x3FF)
  else
    for _ = 1, (f or 13) do joypad.set({ [k] = true }); emu.frameadvance() end
    joypad.set({})
  end
  adv(g or 8)
end
local function patch_mail()
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  local rv = memory.read_u32_le(ROML)
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  if rv == 0x04000130 then memory.write_u32_le(ROML, MAIL) end
  memory.write_u16_le(MAIL, 0x3FF)
  mailOK = true
end
local function u17() local o = 0x03002BE0 + 17 * 24; return memory.read_u8(o + 2), memory.read_u8(o + 3) end
local function stat()
  local n, reach = 0, 0
  for i = 0, SIZE - 1 do
    local v = memory.read_u8(CTX + MASK + i)
    if v ~= 0 then n = n + 1 end
    if v % 32 >= 16 then reach = reach + 1 end   -- bit4
  end
  return n, reach
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(30)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(70)
  for i = 1, 10 do
    local x0, y0 = cur()
    hold("Right", 13, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); break end
    hold("A", 4, 35)
  end
  patch_mail()

  -- 光标到 U17 (19,29)
  for _ = 1, 60 do
    local x, y = cur()
    if x == 19 and y == 29 then break end
    local dx, dy = 19 - x, 29 - y
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, 5, 4)
  end
  w(string.format("光标到 U17 位置 (%d,%d)", cur()))

  -- 选中 → 菜单① → 移動
  hold("A", 4, 35); hold("A", 4, 35); hold("A", 4, 45)
  w(string.format("进寻路态 cursor=(%d,%d)", cur()))
  local n0, r0 = stat()
  w(string.format("掩码初始: 非零 %d / bit4(可达) %d", n0, r0))
  shot("01_range")

  -- 爆破：把 bit4（玩家0可达）全置 1
  for i = 0, SIZE - 1 do
    local a = CTX + MASK + i
    memory.write_u8(a, memory.read_u8(a) | 0x10)
  end
  adv(2)
  local n1, r1 = stat()
  w(string.format("填充后: 非零 %d / bit4 %d", n1, r1))
  shot("02_filled")

  -- 往远处走（目标是 30,26，原来肯定不可达）
  local TX, TY = 30, 26
  for _ = 1, 40 do
    local x, y = cur()
    if x == TX and y == TY then break end
    local dx, dy = TX - x, TY - y
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, 5, 4)
    -- 每走一步都补填，防止游戏重算覆盖
    for i = 0, SIZE - 1 do
      local a = CTX + MASK + i
      memory.write_u8(a, memory.read_u8(a) | 0x10)
    end
  end
  w(string.format("走到 (%d,%d)", cur()))
  shot("03_moved")
  local m1, m2 = stat()
  w(string.format("走完掩码: 非零 %d / bit4 %d", m1, m2))

  -- 确认移动
  hold("A", 4, 50)
  hold("A", 4, 40)
  adv(60)
  local ux, uy = u17()
  w(string.format("确认后 U17=(%d,%d)", ux, uy))
  shot("04_confirmed")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
