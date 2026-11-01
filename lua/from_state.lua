-- 从"战前编成"存档点继续（SL 大法：不用每次从头跑）
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/from_state.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/c_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(30)

local ok, err = pcall(savestate.load, STATE)
w("load ok=" .. tostring(ok) .. " err=" .. tostring(err))
adv(30)
shot("00_loaded")

press("A", 6, 120)          -- 自动部署 确认
shot("01_after_confirm")
adv(150); shot("02_a")
adv(150); shot("03_b")
press("A", 6, 120)
shot("04_c")
adv(150); shot("05_d")
press("Start", 6, 120)
shot("06_e")
adv(180); shot("07_f")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
