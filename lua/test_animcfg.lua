-- 找出控制「战斗演出」的开关：把 0x0300756C 附近一排全置 0，攻击看演出是否消失
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local f = io.open(B .. "logs/test_animcfg.txt", "w")
local function w(s) f:write(s .. "\n"); f:flush() end

local MAIL, ROML = 0x03007F00, 0x080015F4
local KEYBIT = { A=0x1, B=0x2, Select=0x4, Start=0x8, Right=0x10, Left=0x20, Up=0x40, Down=0x80 }
local mailOK = false
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function down(k) memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0)) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function hold(k, fr, g)
  if mailOK then down(k); for _ = 1, (fr or 5) do emu.frameadvance() end; up()
  else for _ = 1, (fr or 13) do joypad.set({ [k] = true }); emu.frameadvance() end; joypad.set({}) end
  adv(g or 8)
end
local function tap(k, g) hold(k, 4, g or 30) end
local function patch_mail()
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  local rv = memory.read_u32_le(ROML)
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  if rv == 0x04000130 then memory.write_u32_le(ROML, MAIL) end
  up(); mailOK = true
end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, B .. "shots/ac_" .. n .. ".png") end
local function ga(x, y) return CTX + 0x3F60 + x * 4 + y * 0xC0 end
local function uxy(k) return memory.read_u8(U + k * STRIDE), memory.read_u8(U + k * STRIDE + 1) end
local function ehp(k) return memory.read_u8(0x03002BE0 + 0x600 + k * 24 + 6) end
local function tp(k, tx, ty)
  local ox, oy = uxy(k)
  local g1 = ga(ox, oy); memory.write_u8(g1, 0); memory.write_u8(g1 + 1, 0)
  local g2 = ga(tx, ty); memory.write_u8(g2, 1); memory.write_u8(g2 + 1, k + 1)
  memory.write_u8(U + k * STRIDE, tx); memory.write_u8(U + k * STRIDE + 1, ty)
  memory.write_u8(CTX + 0x637E, tx); memory.write_u8(CTX + 0x637F, ty)
  memory.write_u8(CTX + 0x990, k)
  adv(4)
end

pcall(client.speedmode, 0)
adv(20)
pcall(savestate.load, B .. "states/battle_usa_ready.State")
adv(60)
for i = 1, 10 do
  local x0, y0 = cur(); hold("Right", 13, 8)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); break end
  tap("A", 35)
end
patch_mail()

-- 先读这一排当前值
local row = {}
for i = 0, 15 do row[#row + 1] = string.format("%02X", memory.read_u8(0x0300756C + i)) end
w("0x0300756C 起 16 字节: " .. table.concat(row, " "))

-- 全部置 0
for i = 0, 15 do memory.write_u8(0x0300756C + i, 0) end
local row2 = {}
for i = 0, 15 do row2[#row2 + 1] = string.format("%02X", memory.read_u8(0x0300756C + i)) end
w("置 0 后:            " .. table.concat(row2, " "))

w("E0 HP 初始 = " .. ehp(0))
local f0 = emu.framecount()
tp(0, 18, 29)
adv(4)
tap("A", 30)
tap("Down", 22)
tap("A", 30)
hold("Left", 5, 18)
shot("00_target")
local fA = emu.framecount()
tap("A", 36)
tap("A", 30)
shot("01_after_confirm")
local hpSeen = ehp(0)
for i = 1, 40 do
  adv(5)
  if ehp(0) ~= hpSeen then
    w(string.format("HP 在确认后 %d 帧变化 -> %d", emu.framecount() - fA, ehp(0)))
    hpSeen = ehp(0)
    break
  end
end
if ehp(0) == 12 then w("!! HP 未变化") end
shot("02_after")
adv(30)
shot("03_settled")
w(string.format("确认后总耗时 = %d 帧；最终 E0 HP=%d；光标 (%d,%d)",
  emu.framecount() - fA, ehp(0), select(1, cur()), select(2, cur())))
f:close()
pcall(client.exit)
