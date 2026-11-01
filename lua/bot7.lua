-- 用 gkin 邮箱发键跑一个完整单位指令，并标定速度
local BASE = "D:/prog/gba-ai/"
dofile(BASE .. "lua/gkin.lua")
local SRC = BASE .. "states/battle.State"
local OUT = BASE .. "logs/bot7.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/b7_"..n..".png") end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function u0() return memory.read_u8(0x03002BE2), memory.read_u8(0x03002BE3) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv = nil
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

-- 用 joypad 清横幅（打补丁前）
local function mobile()
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
  if mobile() then say("ready after " .. i); break end
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}); adv(45)
end

GK.patch()
say("patched, mailbox active")

-- 标定：不同帧数走几格
for _, f in ipairs({ 1, 2, 3, 5, 8, 12 }) do
  local x0 = cur()
  GK.key(GK.RIGHT, f)
  local x1 = cur()
  say(string.format("  %2d 帧 → 走 %d 格", f, x1 - x0))
  GK.key(GK.LEFT, f)
  local x2 = cur()
  if x2 ~= x0 then
    -- 修正回原点
    for _ = 1, 10 do
      local xa = cur(); if xa == x0 then break end
      GK.key(GK.LEFT, 1)
    end
  end
end

-- 完整指令：选中 unit0 → 移動 → 走 3 格 → 确认 → 待机
local ux, uy = u0()
local t0 = os.clock()
say(string.format("unit0=(%d,%d) cursor=(%d,%d)", ux, uy, cur()))

GK.until(GK.RIGHT, function() return cur() >= ux end, 40)
GK.until(GK.LEFT, function() return select(1, cur()) <= ux end, 40)
GK.until(GK.DOWN, function() return select(2, cur()) >= uy end, 40)
GK.until(GK.UP, function() return select(2, cur()) <= uy end, 40)
local cx, cy = cur()
say(string.format("导航到单位: (%d,%d) %s", cx, cy, tostring(cx == ux and cy == uy)))

GK.tap(GK.A, 10)     -- 单位菜单
shot("01_menu")
GK.tap(GK.A, 10)     -- 移動
GK.key(GK.RIGHT, 6)  -- 走几格
GK.tap(GK.A, 20)     -- 确认落点
adv(40)
GK.tap(GK.A, 20)     -- 待机
adv(20)
local nx, ny = u0()
say(string.format("unit0 (%d,%d) -> (%d,%d)  用时 %.2fs", ux, uy, nx, ny, os.clock() - t0))
shot("02_after")
say("done")
pcall(client.exit)
