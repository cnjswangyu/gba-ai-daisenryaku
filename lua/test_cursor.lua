-- 爆破实验：战场光标 0x030067FE/FF 能不能直接写？能写就不用按方向键导航了
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_cursor.txt"
local CX, CY = 0x030067FE, 0x030067FF
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CX), memory.read_u8(CY) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/cu_" .. n .. ".png") end
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
  w(string.format("0-准备 cursor=(%d,%d)", cur()))
  shot("00_orig")

  w(">>> 写光标 (18,31)")
  memory.write_u8(CX, 18); memory.write_u8(CY, 31)
  adv(2);  w(string.format("1-2帧后 (%d,%d)", cur()))
  adv(30); w(string.format("2-32帧后 (%d,%d)", cur())); shot("01_w18_31")

  w(">>> 写光标 (25,20) 远处")
  memory.write_u8(CX, 25); memory.write_u8(CY, 20)
  adv(30); w(string.format("3-远处 (%d,%d)", cur())); shot("02_w25_20")

  w(">>> 写光标 (5,5) 地图角落")
  memory.write_u8(CX, 5); memory.write_u8(CY, 5)
  adv(30); w(string.format("4-角落 (%d,%d)", cur())); shot("03_w5_5")

  w(">>> 写非法值 (200,200)")
  memory.write_u8(CX, 200); memory.write_u8(CY, 200)
  adv(30); w(string.format("5-非法 (%d,%d)", cur())); shot("04_w200")

  w(">>> 恢复 (21,30) 再按 Right 验证按键仍有效")
  memory.write_u8(CX, 21); memory.write_u8(CY, 30); adv(10)
  hold("Right", 5, 10)
  w(string.format("6-按Right后 (%d,%d)", cur()))
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
