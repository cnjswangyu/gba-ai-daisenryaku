-- 按正规流程：进设置 -> 关リプレイ -> 設定完了保存 -> 退出 -> 攻击，看动画是否消失
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local f = io.open(B .. "logs/test_cfgsave.txt", "w")
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
local function shot(n) pcall(client.screenshot, B .. "shots/cf_" .. n .. ".png") end
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
local function sram() local t = {} for i = 0, 7 do t[#t+1] = string.format("%02X", memory.read_u8(0x0E000010 + i)) end return table.concat(t, " ") end

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
w("SRAM 配置(初始) = " .. sram())

-- ===== 进设置界面 =====
w(">>> START 打开总菜单")
hold("Start", 5, 50)
shot("00_menu")
w(">>> RIGHT 切到右列")
hold("Right", 5, 25); shot("01_right")
w(">>> DOWN 到「选项设定」")
hold("Down", 5, 25); shot("02_down")
w(">>> A 进入")
hold("A", 5, 80); adv(40); shot("03_settings")

-- 逐行看这 4 项的值
local base = 0x0300756C
local r = {}
for i = 0, 7 do r[#r+1] = string.format("%02X", memory.read_u8(base + i)) end
w("进设置后 0x0300756C..73 = " .. table.concat(r, " "))

w(">>> DOWN x2 -> リプレイ")
hold("Down", 5, 20); hold("Down", 5, 20); shot("04_on_replay")
w(">>> LEFT 关闭")
hold("Left", 5, 25); adv(15); shot("05_replay_off")
local r2 = {}
for i = 0, 7 do r2[#r2+1] = string.format("%02X", memory.read_u8(base + i)) end
w("关掉后 0x0300756C..73 = " .. table.concat(r2, " "))

w(">>> 把其余项也一并关掉（音楽/効果音/自動補給），只留设定")
hold("Up", 5, 18); hold("Left", 5, 20)      -- 効果音 OFF
hold("Up", 5, 18); hold("Left", 5, 20)      -- 音楽 OFF
hold("Down", 5, 18); hold("Down", 5, 18); hold("Down", 5, 18)
hold("Left", 5, 20)                          -- 自動補給 OFF
shot("06_all_off")
local r3 = {}
for i = 0, 7 do r3[#r3+1] = string.format("%02X", memory.read_u8(base + i)) end
w("全关后 0x0300756C..73 = " .. table.concat(r3, " "))

w(">>> DOWN 到「設定完了」并 A 保存")
for i = 1, 4 do hold("Down", 5, 14) end
shot("07_on_done")
hold("A", 5, 90); adv(40); shot("08_saved")
w("SRAM 配置(保存后) = " .. sram())

-- 退出到地图
for i = 1, 4 do tap("B", 20) end
adv(30)
w(">>> 回到地图，准备攻击")

w("E0 HP 初始 = " .. ehp(0))
local f0 = emu.framecount()
tp(0, 18, 29)
adv(4)
tap("A", 30); tap("Down", 22); tap("A", 30)
hold("Left", 5, 18)
shot("09_target")
local fA = emu.framecount()
tap("A", 36)
tap("A", 30)
shot("10_after_confirm")   -- 关键：这一帧还有没有对阵画面
local hpSeen = ehp(0)
local changed = nil
for i = 1, 50 do
  adv(4)
  if ehp(0) ~= hpSeen then changed = emu.framecount() - fA; hpSeen = ehp(0); break end
end
w(string.format("HP 变化: %s（确认后帧数）；E0 HP=%d",
  changed and tostring(changed) or "未变化", ehp(0)))
adv(20); shot("11_settled")
w(string.format("确认阶段总帧数 = %d；光标 (%d,%d)", emu.framecount() - fA, select(1, cur()), select(2, cur())))
f:close()
pcall(client.exit)
