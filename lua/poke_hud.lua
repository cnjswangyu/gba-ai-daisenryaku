-- 暴力字段验证：逐个改地形区字节，截图，看 HUD 的「防+」是否变化
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local DIR  = BASE .. "states/poke/"
local LOG  = BASE .. "logs/poke_hud.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT = 0x10, 0x20
local SCAN_FROM, SCAN_TO = 0x087616B8, 0x08761708

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

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
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
say(string.format("cursor=(%d,%d)", cur()))

pcall(client.screenshot, DIR .. "base.png")
for a = SCAN_FROM, SCAN_TO do
  local off = a - 0x08000000
  local old = memory.read_u8(a)
  memory.write_u8(a, 250)
  adv(6)
  pcall(client.screenshot, string.format("%s%04X.png", DIR, a % 0x10000))
  memory.write_u8(a, old)
end
say("done")
pcall(client.exit)
