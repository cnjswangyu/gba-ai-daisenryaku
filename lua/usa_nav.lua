-- USA 导航探针: mode0列表 → B/A 回 state4 → 重进 state6 → 入口对话框 → A → 自动部署界面 → START → A → 战场?
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/usa_nav.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/nv_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 40)
end

local CTX = 0x03000480
local function dump(tag)
  local st = memory.read_u8(CTX)
  local sub = memory.read_u8(CTX+1)
  local p990 = memory.read_u8(CTX+0x990)
  local p991 = memory.read_u8(CTX+0x991)
  local money = memory.read_u32_le(CTX+0x68)
  local cnt = memory.read_u32_le(0x020095B4)
  local n = 0
  for i = 0, 63 do
    if memory.read_u16_le(CTX+0x2760+i*24) ~= 0 then n = n + 1 end
  end
  -- 池原始字节: 前 12 条 × 4B
  local raw = {}
  for i = 0, 11 do
    local b0 = memory.read_u8(CTX+0x188+i*4)
    local b1 = memory.read_u8(CTX+0x188+i*4+1)
    local b2 = memory.read_u8(CTX+0x188+i*4+2)
    local b3 = memory.read_u8(CTX+0x188+i*4+3)
    raw[#raw+1] = string.format("%02X%02X%02X%02X", b0, b1, b2, b3)
  end
  w(string.format("%-12s f=%-5d state=%d sub=%d p990=%d p991=%d money=%d cnt=%d battle=%d",
    tag, emu.framecount(), st, sub, p990, p991, money, cnt, n))
  w("             pool=" .. table.concat(raw, " "))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/pre_battle_usa.State")
  adv(60)
  dump("loaded"); shot("00_list")

  press("B", 6, 60)            -- B 中止 → 期望弹"停止进行军队的部署"
  dump("afterB"); shot("01_B_dialog")

  press("A", 6, 90)            -- 确认 → 期望 state=4
  dump("afterBA"); shot("02_state4")

  press("A", 6, 120)           -- state4 项0(出击编成) → 期望 state=6 + 入口对话框
  dump("afterA2"); shot("03_state6_dialog")

  press("A", 6, 120)           -- 确认电脑自动部署 → 期望自动部署界面
  dump("afterA3"); shot("04_autodeploy")

  adv(120); dump("adv120"); shot("05_autodeploy2")

  press("Start", 8, 120)       -- 自动部署界面 START → 期望"自动部署这些被选定的单位"确认框
  dump("afterStart"); shot("06_ad_dialog")

  press("A", 8, 150)           -- 确认 → 期望战场
  dump("afterA4"); shot("07_battle")

  adv(180); dump("adv180"); shot("08_battle2")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
