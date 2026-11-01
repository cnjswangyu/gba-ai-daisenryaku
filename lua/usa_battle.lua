-- USA: pre_battle_usa.State → START(出击) → A(确认自动部署) → 战场
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/usa_battle.txt"
local lines = {}
local function w(s) lines[#lines+1] = s end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/u_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 5)
  joypad.set({}); adv(gap or 30)
end

local CTX = 0x03000480
local function info(tag)
  local st = memory.read_u8(CTX)
  local sub = memory.read_u8(CTX+1)
  local cnt = memory.read_u32_le(0x020095B4)  -- 已选计数
  local money = memory.read_u32_le(CTX+0x68)
  -- 战场表单位数 (ctx+0x2760, 24B/条, id!=0)
  local n = 0
  for i = 0, 63 do
    local id = memory.read_u16_le(CTX+0x2760+i*24)
    if id ~= 0 then n = n + 1 end
  end
  w(string.format("%-10s f=%-5d state=%d sub=%d count=%d money=%d battleUnits=%d",
    tag, emu.framecount(), st, sub, cnt, money, n))
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(30)
pcall(savestate.load, BASE .. "states/pre_battle_usa.State")
adv(60)
info("loaded"); shot("00_list")

press("Start", 6, 90)        -- 出击
info("afterStart"); shot("01_dialog")

press("A", 6, 120)           -- 确认自动部署
info("afterA"); shot("02_deployed")

adv(150); info("map"); shot("03_map")
adv(150); info("map2"); shot("04_map2")
adv(180); info("map3"); shot("05_map3")

local ok = pcall(savestate.save, BASE .. "states/battle_usa.State")
w("save battle_usa ok=" .. tostring(ok))

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
