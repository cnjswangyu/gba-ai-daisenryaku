-- 验证天气：逐回合读 ctx+0x23 / ctx+0x20，并读 ROM 天气表
local B = "D:/prog/gba-ai/"
local CTX = 0x03000480
local f = io.open(B .. "logs/test_weather.txt", "w")
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
local function tbl()
  local t = {}
  for i = 0, 7 do t[#t + 1] = tostring(memory.read_u32_le(0x087A3944 + i * 4)) end
  return table.concat(t, " ")
end
local function state(tag)
  w(string.format("%-10s ctx+0x20=%d ctx+0x21=%d ctx+0x22=%d ctx+0x23=%d ctx+0x24=%d",
    tag, memory.read_u8(CTX + 0x20), memory.read_u8(CTX + 0x21),
    memory.read_u8(CTX + 0x22), memory.read_u8(CTX + 0x23), memory.read_u8(CTX + 0x24)))
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

w("ROM 天气表: " .. tbl())
state("回合1")

for turn = 2, 4 do
  -- 结束回合
  tap("Start", 60)
  for _ = 1, 6 do tap("Up", 10) end
  tap("A", 60); tap("A", 80)
  adv(150)
  local back = false
  for i = 1, 20 do
    if mobile() then back = true; break end
    tap("A", 60); adv(50)
  end
  if not back then w("!! 没回到我方回合"); break end
  state("回合" .. turn)
  adv(20)
end

-- 看 ctx+0x20..0x2F 全量
local line = {}
for i = 0x20, 0x2F do line[#line + 1] = tostring(memory.read_u8(CTX + i)) end
w("ctx+0x20..2F = " .. table.concat(line, " "))
f:close()
pcall(client.exit)
