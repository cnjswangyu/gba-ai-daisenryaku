-- 复现 AI 的指令序列，定位单元消失/格表错乱发生在哪一步
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local f = io.open(B .. "logs/repro_bug.txt", "w")
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
local function dir(k) hold(k, 5, 6) end
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
local function shot(n) pcall(client.screenshot, B .. "shots/rb_" .. n .. ".png") end
local function ga(x, y) return CTX + 0x3F60 + x * 4 + y * 0xC0 end

-- 统计：单位表非空数 + 格表里阵营1/2的项数 + 不一致明细
local function audit(tag)
  local my, en = 0, 0
  local gmy, gen = 0, 0
  local bad = {}
  for k = 0, 63 do
    local id = memory.read_u16_le(U + k * STRIDE - 2)
    if id ~= 0 then
      my = my + 1
      local x = memory.read_u8(U + k * STRIDE)
      local y = memory.read_u8(U + k * STRIDE + 1)
      local g = ga(x, y)
      local gc, gs = memory.read_u8(g), memory.read_u8(g + 1)
      if not (gc == 1 and gs == k + 1) then
        bad[#bad + 1] = string.format("U%d(%d,%d)格表[%d,%d]", k, x, y, gc, gs)
      end
    end
    local eid = memory.read_u16_le(0x030031E2 + k * STRIDE - 2)
    if eid ~= 0 then en = en + 1 end
  end
  for gy = 0, 47 do
    for gx = 0, 47 do
      local c = memory.read_u8(ga(gx, gy))
      if c == 1 then gmy = gmy + 1 elseif c == 2 then gen = gen + 1 end
    end
  end
  w(string.format("[%s] 单位表 我=%d 敌=%d | 格表 我=%d 敌=%d %s",
    tag, my, en, gmy, gen, (#bad > 0) and ("不一致 " .. #bad .. " 处") or "全部一致"))
  for i = 1, math.min(#bad, 8) do w("    " .. bad[i]) end
end

pcall(client.speedmode, 0)
adv(20)
pcall(savestate.load, B .. "states/battle_usa_ready.State")
adv(60)
for i = 1, 10 do
  local x0, y0 = cur(); dir("Right"); adv(6)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then dir("Left"); adv(6); break end
  tap("A", 40)
end
patch_mail()
audit("载入后")
shot("00_start")

-- 打印 E10 位置，便于复现
local e10 = 0x030031E2 + 10 * STRIDE
w(string.format("E10 id=%d (%d,%d) hp=%d", memory.read_u16_le(e10 - 2),
  memory.read_u8(e10), memory.read_u8(e10 + 1), memory.read_u8(e10 + 4)))
local e9 = 0x030031E2 + 9 * STRIDE
w(string.format("E9  id=%d (%d,%d) hp=%d", memory.read_u16_le(e9 - 2),
  memory.read_u8(e9), memory.read_u8(e9 + 1), memory.read_u8(e9 + 4)))
local u9 = U + 9 * STRIDE
w(string.format("U9  id=%d (%d,%d) hp=%d", memory.read_u16_le(u9 - 2),
  memory.read_u8(u9), memory.read_u8(u9 + 1), memory.read_u8(u9 + 4)))

-- ===== 复现 ATTACK 9 10（用主线同样的实现）=====
local function NEIGH_ok(px, py)
  return px > 0 and px < 48 and py > 0 and py < 48 and memory.read_u8(ga(px, py)) == 0
end
local function do_attack(idx, eidx)
  local NEIGH = { {1,0},{-1,0},{0,2},{0,-2},{1,2},{1,-2},{-1,2},{-1,-2},{2,0},{-2,0} }
  local ex, ey = memory.read_u8(0x030031E2 + eidx * STRIDE), memory.read_u8(0x030031E2 + eidx * STRIDE + 1)
  local ax, ay
  for _, d in ipairs(NEIGH) do
    local px, py = ex + d[1], ey + d[2]
    if NEIGH_ok(px, py) then ax, ay = px, py; break end
  end
  if not ax then w("  找不到空邻格"); return false end
  w(string.format("  瞬移 U%d -> (%d,%d)（E%d 在 %d,%d）", idx, ax, ay, eidx, ex, ey))
  local ux, uy = memory.read_u8(U + idx * STRIDE), memory.read_u8(U + idx * STRIDE + 1)
  local g1 = ga(ux, uy); memory.write_u8(g1, 0); memory.write_u8(g1 + 1, 0)
  local g2 = ga(ax, ay); memory.write_u8(g2, 1); memory.write_u8(g2 + 1, idx + 1)
  memory.write_u8(U + idx * STRIDE, ax); memory.write_u8(U + idx * STRIDE + 1, ay)
  memory.write_u8(CTX + 0x637E, ax); memory.write_u8(CTX + 0x637F, ay)
  memory.write_u8(CTX + 0x990, idx)
  adv(8)
  audit("瞬移后")
  shot("01_after_tp")
  local hp0 = memory.read_u8(0x030031E2 + eidx * STRIDE + 4)
  tap("A", 30); tap("Down", 22); tap("A", 30)
  local dx, dy = ex - ax, ey - ay
  local key = (math.abs(dx) >= math.abs(dy)) and ((dx > 0) and "Right" or "Left")
                                              or ((dy > 0) and "Down" or "Up")
  hold(key, 5, 16)
  shot("02_aim")
  tap("A", 34); tap("A", 26)
  for i = 1, 24 do adv(4); if memory.read_u8(0x030031E2 + eidx * STRIDE + 4) ~= hp0 then break end end
  adv(30)
  audit("攻击后")
  shot("03_after_atk")
  local hp1 = memory.read_u8(0x030031E2 + eidx * STRIDE + 4)
  w(string.format("  E%d HP %d -> %d", eidx, hp0, hp1))
  return true
end

w("=== 复现：秒杀一个敌人 ATTACK 0 5 ===")
do_attack(0, 5)
adv(40)
audit("秒杀后")

w("=== 结束回合 x1 ===")
tap("Start", 60)
for _ = 1, 6 do tap("Up", 10) end
tap("A", 60); tap("A", 80)
adv(150)
for i = 1, 20 do
  local x0, y0 = cur(); dir("Right"); adv(6)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then dir("Left"); adv(6); break end
  tap("A", 60); adv(50)
end
audit("回合2")
shot("04_after_endturn")
f:close()
pcall(client.exit)
