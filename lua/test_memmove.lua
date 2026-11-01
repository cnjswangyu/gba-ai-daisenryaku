-- 实验：能不能绕过按键，直接写单位表把单位"传送"过去？
-- 验证 4 件事：① 读回是否为新坐标 ② 画面是否跟着变 ③ 会不会被游戏下一帧刷回去 ④ 燃料是否自动扣
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_memmove.txt"
local U    = 0x03002BE2
local K    = 17          -- M-3A2 侦察车，原始 (19,29)

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/mm_" .. n .. ".png") end
local function rec(tag)
  local o = U + K * 24
  w(string.format("%-14s id=%d x=%d y=%d fuel=%d hp=%d st=%d cursor=(%d,%d)",
    tag, memory.read_u16_le(o - 2), memory.read_u8(o), memory.read_u8(o + 1),
    memory.read_u8(o + 2), memory.read_u8(o + 4), memory.read_u8(o + 7),
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
end
local function setpos(x, y)
  local o = U + K * 24
  memory.write_u8(o, x)
  memory.write_u8(o + 1, y)
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(80)
  rec("0-原始"); shot("0_orig")

  w(">>> 写 (18,31)")
  setpos(18, 31)
  rec("1-写完当帧")
  adv(5);   rec("2-5帧后")
  adv(30);  rec("3-35帧后"); shot("1_after35")
  adv(200); rec("4-235帧后"); shot("2_after235")

  w(">>> 写 (30,10) 远处")
  setpos(30, 10)
  adv(60);  rec("5-远处60帧"); shot("3_far")

  w(">>> 写 200,200 非法值")
  setpos(200, 200)
  adv(30);  rec("6-非法值")
  setpos(18, 31)
  adv(30);  rec("7-恢复")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
