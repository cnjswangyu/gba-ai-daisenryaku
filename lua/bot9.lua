-- 邮箱发键：一回合给全部 10 个单位下令（编队东进 2 格，不乱冲）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/bot9.txt"
local MAIL = 0x03007F00
local LITS = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML = 0x080015F4
local A, B, START = 0x1, 0x2, 0x8
local RIGHT, LEFT, UP, DOWN = 0x10, 0x20, 0x40, 0x80

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/b9_"..n..".png") end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function unit(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2)
end
local function patch()
  memory.write_u16_le(MAIL, 0x3FF)
  for _, a in ipairs(LITS) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
end
local function down(bits) memory.write_u16_le(MAIL, 0x3FF - bits) end
local function up() memory.write_u16_le(MAIL, 0x3FF) end
local function key(bits, frames)
  down(bits); for _ = 1, (frames or 1) do emu.frameadvance() end; up(); adv(3)
end
local function tap(bits, wait) key(bits, 1); adv(wait or 8) end
local function holdUntil(bits, cond, maxf)
  down(bits)
  for _ = 1, (maxf or 60) do
    emu.frameadvance()
    if cond() then up(); adv(3); return true end
  end
  up(); adv(3); return false
end
local function mobile()
  local x0 = select(1, cur())
  key(RIGHT, 5)
  local x1 = select(1, cur())
  if x0 ~= x1 then key(LEFT, 5); return true end
  return false
end

say("== start ==")
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
  if mobilePad() then say("ready after " .. i); break end
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(45)
end
patch()

local t0 = os.clock()
local moved, failed = 0, 0
for i = 0, 9 do
  local x, y, hp = unit(i)
  if hp > 0 then
    -- 导航到单位
    holdUntil(RIGHT, function() return select(1, cur()) >= x end, 60)
    holdUntil(LEFT,  function() return select(1, cur()) <= x end, 60)
    holdUntil(DOWN,  function() return select(2, cur()) >= y end, 60)
    holdUntil(UP,    function() return select(2, cur()) <= y end, 60)
    local cx, cy = cur()
    if cx == x and cy == y then
      tap(A, 8); tap(A, 8)          -- 菜单 → 移動
      key(RIGHT, 5); key(RIGHT, 5)  -- 东进 2 格
      tap(A, 16); adv(30)           -- 确认落点
      tap(A, 16); adv(16)           -- 待机
      local nx, ny = unit(i)
      if nx ~= x or ny ~= y then moved = moved + 1 else failed = failed + 1 end
      say(string.format("u%d (%d,%d)->(%d,%d) %s", i, x, y, nx, ny, (nx ~= x or ny ~= y) and "OK" or "fail"))
    else
      failed = failed + 1
      say(string.format("u%d (%d,%d) 导航失败 (%d,%d)", i, x, y, cx, cy))
      tap(B, 8)
    end
    -- 确保回到可操作
    for _ = 1, 3 do if mobile() then break end; tap(A, 10) end
  end
end
say(string.format("移动 %d / 失败 %d  总用时 %.1fs", moved, failed, os.clock() - t0))
shot("01_after")
say("== done ==")
pcall(client.exit)
