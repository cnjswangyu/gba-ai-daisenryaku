-- USA: 手动部署第 1 个单位，看菜单/计数变化
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/usa_deploy1.txt"
local lines = {}
local function w(s) lines[#lines+1] = s end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/d1_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 5)
  joypad.set({}); adv(gap or 30)
end

local CTX = 0x03000480
local function info(tag)
  local st = memory.read_u8(CTX)
  local sub = memory.read_u8(CTX+1)
  local cnt = memory.read_u32_le(0x020095B4)
  local n = 0
  for i = 0, 63 do
    if memory.read_u16_le(CTX+0x2760+i*24) ~= 0 then n = n + 1 end
  end
  -- 池前 24 槽: id + flag(+3)
  local pool = {}
  for i = 0, 23 do
    local id = memory.read_u16_le(CTX+0x188+i*4)
    local fl = memory.read_u8(CTX+0x188+i*4+3)
    if id ~= 0 then pool[#pool+1] = string.format("%d:%02X", id, fl) end
  end
  w(string.format("%-10s f=%-5d state=%d sub=%d cnt=%d battle=%d pool=[%s]",
    tag, emu.framecount(), st, sub, cnt, n, table.concat(pool, " ")))
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(30)
pcall(savestate.load, BASE .. "states/pre_battle_usa.State")
adv(60)
info("loaded"); shot("00_list")

press("A", 6, 60)           -- 选择单位1 → 放置模式
info("afterA1"); shot("01_placemode")

press("A", 6, 60)           -- 在当前光标位放置
info("afterA2"); shot("02_placed")

press("B", 6, 60)           -- 退出放置模式
info("afterB"); shot("03_back")

press("A", 6, 60)           -- 选单位2
info("afterA3"); shot("04_unit2")
press("A", 6, 60)           -- 放置
info("afterA4"); shot("05_placed2")
press("B", 6, 60)
info("afterB2"); shot("06_back2")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
