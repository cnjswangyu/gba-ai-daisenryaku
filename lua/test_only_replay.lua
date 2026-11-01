-- 只关「リプレイ」一项，其余保持 ON，验证是否就是它在控制战斗演出
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local f = io.open(B .. "logs/test_only_replay.txt", "w")
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
local function shot(n) pcall(client.screenshot, B .. "shots/or_" .. n .. ".png") end
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
local function cfg() local t = {} for i = 0, 7 do t[#t+1] = string.format("%02X", memory.read_u8(0x0300756C + i)) end return table.concat(t, " ") end

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

-- 进设置，只关リプレイ
hold("Start", 5, 45)
hold("Right", 5, 22)
hold("Down", 5, 22)
hold("A", 5, 70); adv(30)
w("进设置: " .. cfg())
hold("Down", 5, 18); hold("Down", 5, 18)   -- 到リプレイ
hold("Left", 5, 22)                        -- OFF
w("关リプレイ后: " .. cfg())
hold("Down", 5, 16); hold("Down", 5, 16)   -- 到設定完了
hold("A", 5, 80); adv(30)
shot("00_saved")
for i = 1, 4 do tap("B", 18) end
adv(25)
w("退出后: " .. cfg())

w("E0 HP 初始 = " .. ehp(0))
tp(0, 18, 29)
adv(4)
tap("A", 30); tap("Down", 22); tap("A", 30)
hold("Left", 5, 16)
shot("01_target")
local fA = emu.framecount()
tap("A", 34)          -- 选定
tap("A", 22)          -- 确认
shot("02_confirm_0")  -- 确认后立即
for i = 1, 6 do
  adv(4)
  shot(string.format("03_f%02d", i))
end
w(string.format("确认后 24 帧: E0 HP=%d  光标(%d,%d)", ehp(0), select(1, cur()), select(2, cur())))
adv(40)
shot("04_settled")
w(string.format("确认后 64 帧: E0 HP=%d  光标(%d,%d)  总耗时 %d 帧",
  ehp(0), select(1, cur()), select(2, cur()), emu.framecount() - fA))
f:close()
pcall(client.exit)
