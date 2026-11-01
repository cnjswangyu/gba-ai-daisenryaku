-- 打开 START 菜单里的「兵器资料」，看是不是完整兵种表
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/zukan.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/zk_"..n..".png"); say("shot "..n) end
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
  if mobilePad() then say("ready " .. i); break end
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(45)
end
patch()

tap(B, 20)        -- 取消选中
tap(START, 40)    -- 总菜单
shot("01_menu")
for i = 1, 4 do tap(DOWN, 12) end   -- 到第 5 行「兵器资料」
shot("02_sel")
tap(A, 60)
shot("03_zukan")
adv(60)
shot("04_zukan2")
say("done")
pcall(client.exit)
