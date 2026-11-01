-- 从编成表 → START → A(确认自动部署) → 战场，并存一个"开战"存档点
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/pre_battle.State"
local BATTLE = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/enter_battle.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/e_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function reg(n) local ok, v = pcall(emu.getregister, n); if ok and v then return v end return 0 end
local function info(tag)
  local n = 0
  for i = 0, 127 do
    local a0 = memory.read_u16_le(0x07000000 + i * 8)
    local a1 = memory.read_u16_le(0x07000000 + i * 8 + 2)
    local a2 = memory.read_u16_le(0x07000000 + i * 8 + 4)
    local dis = math.floor(a0 / 512) % 2 == 1
    local x, y = a1 % 512, a0 % 256
    if not dis and not (a0 == 0 and a1 == 0 and a2 == 0) and x < 260 and y < 200 then n = n + 1 end
  end
  w(string.format("%-12s f=%-5d DISPCNT=0x%04X OAM=%d R15=0x%08X", tag, emu.framecount(), memory.read_u16_le(0x04000000), n, reg("R15")))
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(30)
pcall(savestate.load, STATE)
adv(30)

press("Start", 6, 90)        -- 出击
shot("01_dialog"); info("dialog")
press("A", 6, 120)           -- 确认自动部署
shot("02_deployed"); info("deployed")
adv(150); shot("03_map"); info("map")
adv(150); shot("04_map2")
adv(180); shot("05_map3"); info("map3")

local ok = pcall(savestate.save, BATTLE)
w("save battle_start ok=" .. tostring(ok))

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
