-- 全 ctx 跨回合 diff：找出所有「变化且值 < 16」的字节，天气若存在应在此列
local B = "D:/prog/gba-ai/"
local CTX = 0x03000480
local LEN = 0x7B00
local f = io.open(B .. "logs/scan_weather2.txt", "w")
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
-- 转成 0 基索引的 table
local function snap()
  local t = {}
  local CH = 4096
  for off = 0, LEN - 1, CH do
    local n = math.min(CH, LEN - off)
    local r = memory.readbyterange(CTX + off, n)
    for i = 0, n - 1 do
      local v = r[i]
      if v == nil then v = r[i + 1] end
      t[off + i] = v or 0
    end
  end
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

local A = snap()
w("回合1 快照完成 ctx+0x20=" .. memory.read_u8(CTX + 0x20))

tap("Start", 60)
for _ = 1, 6 do tap("Up", 10) end
tap("A", 60); tap("A", 80)
adv(150)
local back = false
for i = 1, 20 do
  if mobile() then back = true; break end
  tap("A", 60); adv(50)
end
w("回到我方回合=" .. tostring(back) .. " ctx+0x20=" .. memory.read_u8(CTX + 0x20))

local C = snap()

-- 统计：变化且两值都 < 16 的（小整数候选）
local cand = {}
local total = 0
for i = 0, LEN - 1 do
  local a, b = A[i], C[i]
  if a ~= b then
    total = total + 1
    if a < 16 and b < 16 then cand[#cand + 1] = { i, a, b } end
  end
end
w(string.format("变化字节总数 = %d，其中小整数候选 = %d", total, #cand))

-- 排除已知的 UI 区（0x6000 以上是光标/菜单缓存）
w("=== 候选（ctx 偏移 / 旧 / 新）===")
for k = 1, math.min(#cand, 120) do
  local c = cand[k]
  w(string.format("  +0x%04X  %d -> %d", c[1], c[2], c[3]))
end
if #cand > 120 then w("  ...(截断)") end
f:close()
pcall(client.exit)
