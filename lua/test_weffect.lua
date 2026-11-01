-- 对照实验：天气表[0]=3 攻击一次，改成 1 再攻击一次，比较伤害
local B = "D:/prog/gba-ai/"
local CTX, U, STRIDE = 0x03000480, 0x03002BE2, 24
local WT = 0x087A3944
local f = io.open(B .. "logs/test_weffect.txt", "w")
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
local function mobile()
  local x0, y0 = cur(); dir("Right"); adv(6)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then dir("Left"); adv(6); return true end
  return false
end
local function ga(x, y) return CTX + 0x3F60 + x * 4 + y * 0xC0 end
local function uxy(k) return memory.read_u8(U + k * STRIDE), memory.read_u8(U + k * STRIDE + 1) end
local function ehp(k) return memory.read_u8(0x03002BE0 + 0x600 + k * 24 + 6) end
local function uhpx(k) return memory.read_u8(0x03002BE0 + k * 24 + 6) end
local function tp(k, tx, ty)
  local ox, oy = uxy(k)
  local g1 = ga(ox, oy); memory.write_u8(g1, 0); memory.write_u8(g1 + 1, 0)
  local g2 = ga(tx, ty); memory.write_u8(g2, 1); memory.write_u8(g2 + 1, k + 1)
  memory.write_u8(U + k * STRIDE, tx); memory.write_u8(U + k * STRIDE + 1, ty)
  memory.write_u8(CTX + 0x637E, tx); memory.write_u8(CTX + 0x637F, ty)
  memory.write_u8(CTX + 0x990, k)
  adv(4)
end
local function wt(i) return memory.read_u32_le(WT + i * 4) end
local function setwt(i, v) memory.write_u32_le(WT + i * 4, v) end

-- 一次完整攻击，返回 造成的伤害 / 自身掉血
local function attack_once(idx, eidx)
  local e0, u0 = ehp(eidx), uhpx(idx)
  local e = 0x03002BE0 + 0x600 + eidx * 24
  local ex, ey = memory.read_u8(e + 2), memory.read_u8(e + 3)
  -- 找空邻格
  local NEIGH = { {1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1},{2,0},{-2,0} }
  local ax, ay
  for _, d in ipairs(NEIGH) do
    local px, py = ex + d[1], ey + d[2]
    if px > 0 and px < 48 and py > 0 and py < 48 then
      if memory.read_u8(ga(px, py)) == 0 then ax, ay = px, py; break end
    end
  end
  if not ax then return nil end
  tp(idx, ax, ay)
  adv(8)
  tap("A", 34)
  tap("Down", 24)
  tap("A", 34)
  local dx, dy = ex - ax, ey - ay
  local key = (math.abs(dx) >= math.abs(dy)) and ((dx > 0) and "Right" or "Left")
                                              or ((dy > 0) and "Down" or "Up")
  hold(key, 5, 18)
  tap("A", 38)
  tap("A", 34)
  -- 等结算
  for i = 1, 40 do
    adv(5)
    if ehp(eidx) ~= e0 then break end
  end
  adv(30)
  return e0 - ehp(eidx), u0 - uhpx(idx)
end

pcall(client.speedmode, 0)
adv(20)

-- ===== 第一次：原始天气表 =====
pcall(savestate.load, B .. "states/battle_usa_ready.State")
adv(60)
for i = 1, 12 do if mobile() then break end; tap("A", 40) end
patch_mail()
w(string.format("原始表: %d %d %d %d %d %d %d %d", wt(0), wt(1), wt(2), wt(3), wt(4), wt(5), wt(6), wt(7)))
w(string.format("第1回合天气 = %d；E0 HP=%d U0 HP=%d", wt(0), ehp(0), uhpx(0)))
local d1, s1 = attack_once(0, 0)
w(string.format(">>> 天气%d：对 E0 造成 %s 伤害，自身掉 %s；E0 HP=%d",
  wt(0), tostring(d1), tostring(s1), ehp(0)))

-- ===== 第二次：把第1回合天气改成 1（无修正）=====
pcall(savestate.load, B .. "states/battle_usa_ready.State")
adv(60)
for i = 1, 12 do if mobile() then break end; tap("A", 40) end
patch_mail()
setwt(0, 1)
w(string.format("改表后: %d %d %d ...", wt(0), wt(1), wt(2)))
adv(5)
w(string.format("第1回合天气 = %d；E0 HP=%d U0 HP=%d", wt(0), ehp(0), uhpx(0)))
local d2, s2 = attack_once(0, 0)
w(string.format(">>> 天气%d：对 E0 造成 %s 伤害，自身掉 %s；E0 HP=%d",
  wt(0), tostring(d2), tostring(s2), ehp(0)))

f:close()
pcall(client.exit)
