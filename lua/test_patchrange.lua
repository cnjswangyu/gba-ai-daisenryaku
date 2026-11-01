-- 爆破实验 3：patch FUN_08002494（光标格合法性检查）→ 永远返回 1
-- 这样寻路可以停在任意格，不受移动力/地形限制
local B = "D:/prog/gba-ai/"
local CTX = 0x03000480
local TARGET = 0x08002494
local OUT = B .. "logs/test_patchrange.txt"
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, B .. "shots/pr_" .. n .. ".png") end
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
local function goto_cell(tx, ty, maxit)
  for _ = 1, (maxit or 90) do
    local x, y = cur()
    if x == tx and y == ty then return true end
    local dx, dy = tx - x, ty - y
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, 5, 4)
  end
  return false
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(30)
  w("load=" .. tostring(pcall(savestate.load, B .. "states/battle_usa_ready.State")))
  adv(70)
  for i = 1, 10 do
    local x0, y0 = cur()
    hold("Right", 13, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); break end
    hold("A", 4, 35)
  end
  patch_mail()

  -- 备份原指令并 patch：movs r0,#1 ; bx lr
  local orig = {}
  for i = 0, 3 do orig[i] = memory.read_u8(TARGET + i) end
  w(string.format("原指令 @0x%08X: %02X %02X %02X %02X", TARGET, orig[0], orig[1], orig[2], orig[3]))
  memory.write_u8(TARGET + 0, 0x01)
  memory.write_u8(TARGET + 1, 0x20)
  memory.write_u8(TARGET + 2, 0x70)
  memory.write_u8(TARGET + 3, 0x47)
  w("已 patch 为 movs r0,#1 ; bx lr")

  -- 选中 U17 → 寻路
  goto_cell(19, 29)
  local a1, a2 = cur()
  w(string.format("光标到 U17 (%d,%d)", a1, a2))
  hold("A", 4, 35); hold("A", 4, 35); hold("A", 4, 45)
  w(string.format("进寻路态 (%d,%d)", cur()))
  shot("01_range")

  -- 走 11 格（超移动力 6）
  local reached = goto_cell(30, 24, 120)
  local gx, gy = cur()
  w(string.format("走到 (%d,%d) 到达=%s", gx, gy, tostring(reached)))
  shot("02_far")

  hold("A", 4, 50)
  hold("A", 4, 40)
  adv(60)
  local ux, uy = u17()
  w(string.format("确认后 U17=(%d,%d)  （原 19,29）", ux, uy))
  shot("03_confirmed")

  -- 恢复原指令（不影响存档，只是干净退出）
  for i = 0, 3 do memory.write_u8(TARGET + i, orig[i]) end
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
