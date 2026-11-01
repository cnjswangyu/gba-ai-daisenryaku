-- 光标移动性测试： RIGHT 一次一图，看右下角坐标与画面变化
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/cursor_test.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/x_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 6)
  joypad.set({})
  adv(gap or 40)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
w("load=" .. tostring(pcall(savestate.load, STATE)))
adv(60)
shot("00")

press("Right", 6, 40); shot("01")
press("Right", 6, 40); shot("02")
press("Down", 6, 40);  shot("03")
press("A", 6, 50);     shot("04_select")
press("Right", 6, 40); shot("05_move1")
press("Right", 6, 40); shot("06_move2")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
