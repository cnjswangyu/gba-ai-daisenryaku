-- 光标沿一条线走 10 格，每格存一份小窗口 RAM + 截图，用于定位地形ID/防御值
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local DIR  = BASE .. "states/terr/"
local LOG  = BASE .. "logs/terr.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80
local WIN, WLEN = 0x03006000, 0x0A00

local unpack = table.unpack or unpack
local function say(s) local f=io.open(LOG,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function patch()
  memory.write_u16_le(MAIL, 0x3FF)
  for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
end
local function down(bits) memory.write_u16_le(MAIL, 0x3FF - bits) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function key(bits, f) down(bits); for _ = 1, (f or 1) do emu.frameadvance() end; up(); adv(4) end
local function tap(bits, w) key(bits, 1); adv(w or 10) end

local function dump(tag)
  local parts = {}
  for off = 0, WLEN - 1, 512 do
    local n = math.min(512, WLEN - off)
    local ok, b = pcall(memory.readbyterange, WIN + off, n)
    if ok and b then
      local acc = {}
      for i = 0, n - 1, 128 do
        local chunk = {}
        for j = i, math.min(i + 127, n - 1) do chunk[#chunk + 1] = b[j] or 0 end
        acc[#acc + 1] = string.char(unpack(chunk))
      end
      parts[#parts + 1] = table.concat(acc)
    end
  end
  local f = io.open(DIR .. tag .. ".bin", "wb")
  if f then f:write(table.concat(parts)); f:close() end
  pcall(client.screenshot, BASE .. "shots/t_" .. tag .. ".png")
  local x, y = cur()
  say(string.format("%s  cursor=(%d,%d)", tag, x, y))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
-- joypad 清横幅
local function mobilePad()
  local x0 = cur()
  for _ = 1, 14 do joypad.set({ Right = true }); emu.frameadvance() end
  joypad.set({})
  local x1 = cur()
  if x0 ~= x1 then
    for _ = 1, 14 do joypad.set({ Left = true }); emu.frameadvance() end
    joypad.set({}); return true
  end
  return false
end
for i = 1, 10 do
  if mobilePad() then break end
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(45)
end
patch()

dump("00")
for i = 1, 12 do
  key(RIGHT, 5)          -- 一格
  dump(string.format("%02d", i))
end
say("done")
pcall(client.exit)
