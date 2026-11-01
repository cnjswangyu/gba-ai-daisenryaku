-- 爆破实验 2：直接改 ROM 兵种表的移动力（+0x0D），让单位能走半张地图
-- 兵种条目 = 0x08798A98 + (id-1)*0x5C，+0x0D = speed
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_speedpatch.txt"
local CTX  = 0x03000480
local TBL, STRIDE, SPD_OFF = 0x08798A98, 0x5C, 0x0D
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/sp_" .. n .. ".png") end
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80 }
local mailOK = false
local function hold(k, f, g)
  if mailOK then
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    for _ = 1, (f or 5) do emu.frameadvance() end
    memory.write_u16_le(MAIL, 0x3FF)
  else
    for _ = 1, (f or 13) do joypad.set({ [k ] = true }); emu.frameadvance() end
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
local function unitrec(k) local o = 0x03002BE0 + k * 24; return memory.read_u8(o + 2), memory.read_u8(o + 3), memory.read_u16_le(o) end
local function goto_cell(tx, ty, frames)
  for _ = 1, 90 do
    local x, y = cur()
    if x == tx and y == ty then return true end
    local dx, dy = tx - x, ty - y
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, frames or 5, 4)
  end
  return false
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

  -- 改 M-3A2(id 290) 与其同类的移动力
  local function set_speed(id, v)
    local a = TBL + (id - 1) * STRIDE + SPD_OFF
    local old = memory.read_u8(a)
    w(string.format("兵种 %d speed @0x%08X: %d -> %d", id, a, old, v))
    memory.write_u8(a, v)
    return old
  end
  set_speed(290, 30)
  set_speed(187, 30)   -- 顺带把 M1A2 也改了

  -- 选中 U17
  goto_cell(19, 29)
  w(string.format("光标到 U17 (%d,%d)", cur()))
  hold("A", 4, 35); hold("A", 4, 35); hold("A", 4, 45)
  w(string.format("进寻路态 (%d,%d)", cur()))
  shot("01_range")

  -- 走远：目标 (30,24)
  local TX, TY = 30, 24
  local reached = goto_cell(TX, TY, 5)
  local cx, cy = cur()
  w(string.format("走到 (%d,%d) 到达=%s", cx, cy, tostring(reached)))
  shot("02_far")

  hold("A", 4, 50)
  hold("A", 4, 40)
  adv(60)
  local ux, uy, uid = unitrec(17)
  w(string.format("确认后 U17= id%d (%d,%d)", uid, ux, uy))
  shot("03_confirmed")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
