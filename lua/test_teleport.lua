-- 终局验证：不按方向键，直接改「格表 + 单位表」把单位传送过去，看游戏认不认
-- 格表 = ctx+0x3F60 + x*4 + y*0xC0 ; +0 阵营 +1 槽号(1-based)
-- 单位表 = ctx+0x2160 + 阵营*0x600 + (槽号-1)*0x18 ; +0 id +2 x +3 y
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_teleport.txt"
local CTX, GRID = 0x03000480, 0x3F60
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/tp_" .. n .. ".png") end
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

local function gaddr(x, y) return CTX + GRID + x * 4 + y * 0xC0 end
local function grec(x, y)
  local a = gaddr(x, y)
  return memory.read_u8(a), memory.read_u8(a + 1)
end
local function uaddr(side, k) return 0x03002BE0 + (side == "MY" and 0 or 0x600) + k * 24 end
local function uxy(side, k)
  local a = uaddr(side, k)
  return memory.read_u8(a + 2), memory.read_u8(a + 3)
end

-- 传送：清旧格 → 写新格 → 改单位表坐标
local function teleport(side, k, tx, ty)
  local camp = (side == "MY") and 1 or 2
  local ox, oy = uxy(side, k)
  memory.write_u8(gaddr(ox, oy), 0)
  memory.write_u8(gaddr(ox, oy) + 1, 0)
  memory.write_u8(gaddr(tx, ty), camp)
  memory.write_u8(gaddr(tx, ty) + 1, k + 1)
  local a = uaddr(side, k)
  memory.write_u8(a + 2, tx)
  memory.write_u8(a + 3, ty)
  return ox, oy
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

  local x, y = uxy("MY", 17)
  local g1, g2 = grec(x, y)
  local c1, c2 = cur()
  w(string.format("准备: U17=(%d,%d) 旧格=[%d,%d] cursor=(%d,%d)", x, y, g1, g2, c1, c2))

  local TX, TY = 24, 26
  w(string.format(">>> 传送 U17 -> (%d,%d)（纯内存，不按方向键）", TX, TY))
  local ox, oy = teleport("MY", 17, TX, TY)
  adv(10)
  local o1, o2 = grec(ox, oy)
  local n1, n2 = grec(TX, TY)
  local u1, u2 = uxy("MY", 17)
  w(string.format("写完: 旧格(%d,%d)=[%d,%d] 新格(%d,%d)=[%d,%d] 单位表=(%d,%d)",
    ox, oy, o1, o2, TX, TY, n1, n2, u1, u2))
  shot("01_after_write")
  adv(60)
  local m1, m2 = grec(TX, TY)
  local v1, v2 = uxy("MY", 17)
  w(string.format("60帧后: 新格=[%d,%d] 单位表=(%d,%d)", m1, m2, v1, v2))
  shot("02_after60")

  -- 光标直接写过去（这里只作观察用，真正按 A 靠格表判定）
  memory.write_u8(CTX + 0x637E, TX)
  memory.write_u8(CTX + 0x637F, TY)
  -- 光标会被游戏重算，所以用按键方式过去：先看游戏把它放哪
  adv(10)
  w(string.format("写光标后 cursor=(%d,%d)", cur()))

  -- 用按键把光标走到新位置（这次只是为了验证格表判定）
  for _ = 1, 80 do
    local cx, cy = cur()
    if cx == TX and cy == TY then break end
    local dx, dy = TX - cx, TY - cy
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, 5, 4)
  end
  w(string.format("光标到 (%d,%d)", cur()))
  shot("03_at_target")

  w(">>> 在新位置按 A：若弹出 M-3A2 菜单，说明格表传送成功")
  hold("A", 4, 45); shot("04_A1")
  hold("A", 4, 45); shot("05_A2")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
