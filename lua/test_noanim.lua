-- 验证：patch 掉战斗演出的「等 A 确认」，看结算是否瞬间完成
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local f = io.open(B .. "logs/test_noanim.txt", "w")
local function w(s) f:write(s .. "\n"); f:flush() end

local MAIL, ROML = 0x03007F00, 0x080015F4
local KEYBIT = { A=0x1, B=0x2, Select=0x4, Start=0x8, Right=0x10, Left=0x20, Up=0x40, Down=0x80 }
local mailOK = false
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function hold(k, fr, g)
  if mailOK then
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    for _ = 1, (fr or 5) do emu.frameadvance() end
    memory.write_u16_le(MAIL, 0x3FF)
  else
    for _ = 1, (fr or 13) do joypad.set({ [k] = true }); emu.frameadvance() end
    joypad.set({})
  end
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
  memory.write_u16_le(MAIL, 0x3FF); mailOK = true
end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, B .. "shots/na_" .. n .. ".png") end
local function ga(x, y) return CTX + 0x3F60 + x * 4 + y * 0xC0 end
local function uxy(k) return memory.read_u8(U + k * STRIDE), memory.read_u8(U + k * STRIDE + 1) end
-- 记录起点 = U - 2，HP 在记录 +6 => U + k*24 + 4
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

-- 常量
local PC_BEQ = 0x08024006
w(string.format("patch 前 0x%08X = 0x%04X", PC_BEQ, memory.read_u16_le(PC_BEQ)))
memory.write_u16_le(PC_BEQ, 0xBF00)
w(string.format("patch 后 0x%08X = 0x%04X (BF00=nop)", PC_BEQ, memory.read_u16_le(PC_BEQ)))

-- 关回放
memory.write_u8(0x0300756F, 0)

w("E0 HP 初始 = " .. ehp(0))
local f0 = emu.framecount()
tp(0, 18, 29)
adv(6)
shot("00_ready")
w(string.format("瞬移后 cursor=(%d,%d) 帧差=%d", select(1, cur()), select(2, cur()), emu.framecount() - f0))

tap("A", 34);  shot("01_menu")
tap("Down", 24); shot("02_sel")
tap("A", 34);  shot("03_aim")
hold("Left", 5, 20); shot("04_target")
tap("A", 38);  shot("05_conf")
tap("A", 40);  shot("06_after")
adv(20)

local f1 = emu.framecount()
w(string.format("A 确认后 E0 HP = %d", ehp(0)))
shot("07_final")
adv(40)
w(string.format("再 40 帧后 E0 HP = %d", ehp(0)))
shot("08_settled")
w(string.format("全程耗时 = %d 帧（patch 前约 369）", emu.framecount() - f0))

-- 还原，避免影响后续
memory.write_u16_le(PC_BEQ, 0xD02D)
w(string.format("已还原 0x%08X = 0x%04X", PC_BEQ, memory.read_u16_le(PC_BEQ)))
f:close()
pcall(client.exit)
