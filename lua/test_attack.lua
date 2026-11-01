-- 攻击全流程实测：瞬移到敌邻格 → A → DOWN(攻撃) → A → 方向选目标 → A → 确认 → 结算
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local OUT = B .. "logs/test_attack.txt"
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, B .. "shots/ak_" .. n .. ".png") end
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
local function unitxy(k) return memory.read_u8(U + k * STRIDE), memory.read_u8(U + k * STRIDE + 1) end
local function ehp(k)
  local a = 0x03002BE0 + 0x600 + k * 24
  return memory.read_u8(a + 6)
end

local function teleport(k, tx, ty)
  local ox, oy = unitxy(k)
  local g1 = ga(ox, oy); memory.write_u8(g1, 0); memory.write_u8(g1 + 1, 0)
  local g2 = ga(tx, ty); memory.write_u8(g2, 1); memory.write_u8(g2 + 1, k + 1)
  memory.write_u8(U + k * STRIDE, tx); memory.write_u8(U + k * STRIDE + 1, ty)
  memory.write_u8(CTX + 0x637E, tx); memory.write_u8(CTX + 0x637F, ty)
  memory.write_u8(CTX + 0x990, k)
  adv(4)
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

  w(string.format("E0 HP 初始=%d", ehp(0)))
  teleport(0, 18, 29)
  local cx0, cy0 = cur()
  w(string.format("瞬移 U0 到 (18,29) cursor=(%d,%d) E0HP=%d", cx0, cy0, ehp(0)))
  shot("00_ready")

  w(">>> A 打开菜单")
  hold("A", 4, 40); shot("01_menu")
  w(">>> DOWN 选「攻撃」")
  hold("Down", 5, 30); shot("02_attack_sel")
  w(">>> A 进入瞄准")
  hold("A", 4, 40); shot("03_aiming")
  w(">>> Left 瞄准左邻的敌人")
  hold("Left", 5, 30); shot("04_target")
  w(">>> A 选定目标")
  hold("A", 4, 45); shot("05_confirm1")
  local cx1, cy1 = cur()
  w(string.format("  cursor=(%d,%d) E0HP=%d", cx1, cy1, ehp(0)))
  w(">>> A 确认框")
  hold("A", 4, 45); shot("06_confirm2")
  adv(120); shot("07_after120")
  w(string.format("  120帧后 E0HP=%d", ehp(0)))
  adv(240); shot("08_after360")
  w(string.format("  360帧后 E0HP=%d", ehp(0)))
  w(">>> A 跳过剩余演出")
  hold("A", 4, 60); shot("09_skip")
  adv(120); shot("10_final")
  w(string.format("  最终 E0HP=%d  我方 U0 HP=%d", ehp(0), memory.read_u8(U + 0 * STRIDE + 4)))
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
