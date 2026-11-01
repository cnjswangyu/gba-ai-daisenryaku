-- 探针 3：正确序列（先清 2 段开场提示，再 选中 → 菜单① → 移動 → 寻路 → 确认 → 菜单② → 待機）
-- 目标：① 寻路态光标怎么动 ② 移动确认后单位坐标变化 ③ "已行动"标志在哪个字节 ④ 各阶段 ctx+8
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_live.State"
local OUT  = BASE .. "logs/probe_move.txt"
local CTX  = 0x03000480
local U    = 0x03002BE2

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/pv_" .. n .. ".png") end
local function tap(k, gap)
  for _ = 1, 4 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 30)
end
local function hold(k, f, gap)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 20)
end
local function rec(tag, n)
  local x, y = cur()
  local t = {}
  for i = 0, 23 do t[#t + 1] = string.format("%02X", memory.read_u8(U - 2 + i)) end
  w(string.format("%-16s ctx8=0x%02X cur=(%2d,%2d) u0=[%s]",
    tag, memory.read_u8(CTX + 8), x, y, table.concat(t, " ")))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(80)
  rec("0-地图"); shot("00_map")

  tap("A", 45); rec("1-A(清ターン)"); shot("01")
  tap("A", 45); rec("2-A(清行动开始)"); shot("02")
  tap("A", 45); rec("3-A(选中)"); shot("03")
  tap("A", 45); rec("4-A(菜单①)"); shot("04_menu1")

  tap("A", 45); rec("5-A(移動→寻路)"); shot("05_range")
  hold("Right", 14); rec("6-Right"); shot("06_r")
  hold("Right", 14); rec("7-Right"); shot("07_rr")
  hold("Down", 14);  rec("8-Down"); shot("08_d")

  tap("A", 45); rec("9-A(确认移动)"); shot("09_confirm")
  tap("A", 45); rec("10-A(菜单②)"); shot("10_menu2")
  tap("A", 45); rec("11-A(待機)"); shot("11_wait")
  adv(60);      rec("12-稳定"); shot("12")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
