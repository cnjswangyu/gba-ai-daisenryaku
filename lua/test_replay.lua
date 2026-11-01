-- 定位「リプレイ」开关的内存变量：进设置 → 切到リプレイ → 快照 → A 切换 → 再快照 → diff
local B = "D:/prog/gba-ai/"
local CTX = 0x03000480
local OUT = B .. "logs/test_replay.txt"
local MAIL, ROML = 0x03007F00, 0x080015F4
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, B .. "shots/rp_" .. n .. ".png") end
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
local function snap(addr, len)
  local t = memory.readbyterange(addr, len)
  local c = {}
  for i = 0, len - 1 do c[i + 1] = string.char(t[i] or t[i + 1] or 0) end
  return table.concat(c)
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

  w(">>> 进设置：START -> RIGHT -> DOWN -> A")
  hold("Start", 4, 55)
  hold("Right", 5, 22)
  hold("Down", 5, 22)
  hold("A", 4, 80)
  adv(40); shot("00_settings")

  w(">>> DOWN x2 到「リプレイ」")
  hold("Down", 5, 18)
  hold("Down", 5, 25)
  shot("01_replay_sel")

  -- 快照 IWRAM + EWRAM 前 0x8000
  local iw0 = snap(0x03000000, 0x8000)
  local ew0 = snap(0x02000000, 0x8000)

  w(">>> LEFT 切换 ON->OFF")
  hold("Left", 5, 30)
  adv(20); shot("02_toggled")

  local iw1 = snap(0x03000000, 0x8000)
  local ew1 = snap(0x02000000, 0x8000)

  local n = 0
  for i = 1, 0x8000 do
    local a, b = iw0:byte(i), iw1:byte(i)
    if a ~= b then
      n = n + 1
      if n <= 20 then
        w(string.format("  IWRAM 0x%08X  %02X -> %02X", 0x03000000 + i - 1, a, b))
      end
    end
  end
  w("IWRAM 变化字节数=" .. n)
  n = 0
  for i = 1, 0x8000 do
    local a, b = ew0:byte(i), ew1:byte(i)
    if a ~= b then
      n = n + 1
      if n <= 20 then
        w(string.format("  EWRAM 0x%08X  %02X -> %02X", 0x02000000 + i - 1, a, b))
      end
    end
  end
  w("EWRAM(前32K) 变化字节数=" .. n)
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
