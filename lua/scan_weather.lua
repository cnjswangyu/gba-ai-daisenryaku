-- 跨回合 diff：找 ctx 区里在「我方回合 -> 敌方回合 -> 我方回合」之间变化的小整数（候选天气/日期）
local B = "D:/prog/gba-ai/"
local CTX = 0x03000480
local f = io.open(B .. "logs/scan_weather.txt", "w")
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

-- 抓 ctx 前 0x400 字节
local function snap_ctx()
  local t = {}
  for i = 0, 0x3FF do t[i] = memory.read_u8(CTX + i) end
  return t
end

pcall(client.speedmode, 0)
adv(20)
pcall(savestate.load, B .. "states/battle_usa_ready.State")
adv(60)
for i = 1, 12 do
  if mobile() then break end
  tap("A", 40)
end
patch_mail()

local A = snap_ctx()
local turnA = memory.read_u8(CTX + 0x20)   -- 猜测的回合字段
local ctx21a = memory.read_u8(CTX + 0x21)
local ctx22a = memory.read_u8(CTX + 0x22)
w(string.format("回合1: ctx+0x20=%d ctx+0x21=%d ctx+0x22=%d", turnA, ctx21a, ctx22a))

-- 结束回合（START -> UP x6 -> A -> A）
tap("Start", 60)
for _ = 1, 6 do tap("Up", 10) end
tap("A", 60)
tap("A", 80)
adv(150)
-- 等敌方回合结束
local back = false
for i = 1, 20 do
  if mobile() then back = true; w("已回到我方回合 (第" .. i .. "轮)") ; break end
  tap("A", 60)
  adv(50)
end
if not back then w("!! 没回到我方回合") end

local C = snap_ctx()
local turnC = memory.read_u8(CTX + 0x20)
w(string.format("回合2: ctx+0x20=%d ctx+0x21=%d ctx+0x22=%d", turnC,
  memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22)))

w("=== ctx+0x000..0x3FF 变化字节（只列 <=0x20 或 0x20..0x200 且值 < 16 的）===")
local n = 0
for i = 0, 0x3FF do
  local a, b = A[i], C[i]
  if a ~= b and (b < 16 or a < 16) then
    w(string.format("  ctx+0x%03X  %d -> %d", i, a, b))
    n = n + 1
    if n > 80 then w("  ...(截断)"); break end
  end
end
w("候选数 = " .. n)

-- 额外：把 0x20..0x60 全部打印，人工看
w("=== ctx+0x20..0x60 原始值（回合2）===")
local line = {}
for i = 0x20, 0x60 do
  line[#line + 1] = string.format("%d", C[i])
  if #line == 16 then w("  +0x" .. string.format("%02X", i - 15) .. ": " .. table.concat(line, " ")); line = {} end
end
if #line > 0 then w("  tail: " .. table.concat(line, " ")) end
f:close()
pcall(client.exit)
