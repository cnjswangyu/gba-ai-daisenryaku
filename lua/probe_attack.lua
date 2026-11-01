-- 探针：把 U0(M1A2) 瞬移到 E0(T-72B, 17,29) 邻格 (18,29)，摸清攻击菜单
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local OUT = B .. "logs/probe_attack.txt"
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, B .. "shots/atk_" .. n .. ".png") end
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
local function ga(x, y) return CTX + 0x3F60 + x * 4 + y * 0xC0 end
local function gr(x, y) local a = ga(x, y); return memory.read_u8(a), memory.read_u8(a + 1) end
local function unitxy(k) return memory.read_u8(U + k * STRIDE), memory.read_u8(U + k * STRIDE + 1) end

local function teleport(k, tx, ty)
  local ox, oy = unitxy(k)
  local g1 = ga(ox, oy)
  memory.write_u8(g1, 0); memory.write_u8(g1 + 1, 0)
  local g2 = ga(tx, ty)
  memory.write_u8(g2, 1); memory.write_u8(g2 + 1, k + 1)
  memory.write_u8(U + k * STRIDE, tx); memory.write_u8(U + k * STRIDE + 1, ty)
  memory.write_u8(CTX + 0x637E, tx); memory.write_u8(CTX + 0x637F, ty)
  memory.write_u8(CTX + 0x990, k)
  adv(4)
  return ox, oy
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

  local ux, uy = unitxy(0)
  w(string.format("U0(M1A2)=(%d,%d)  E0=(17,29)", ux, uy))
  local q1, q2 = gr(18, 29)
  w(string.format("(18,29) 格表=[%d,%d]", q1, q2))

  local ox, oy = teleport(0, 18, 29)
  w(string.format("瞬移 U0 (%d,%d)->(18,29) cursor=(%d,%d)", ox, oy, cur()))
  shot("00_teleported")

  w(">>> 按 A：看菜单项")
  hold("A", 4, 40); shot("01_menu")
  w(string.format("按A后 cursor=(%d,%d)", cur()))

  w(">>> DOWN 一次")
  hold("Down", 5, 25); shot("02_down")
  w(">>> A 确认")
  hold("A", 4, 40); shot("03_confirm")
  adv(60); shot("04_after")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
