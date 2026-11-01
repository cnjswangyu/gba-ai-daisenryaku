-- 战局起始状态排查：先按 A 看是否有提示框，再试方向键
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/cursor_test2.txt"
local function say(s)
  local f = io.open(OUT, "a"); if f then f:write(s, "\n"); f:close() end
  pcall(console.log, s)
end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/y_" .. n .. ".png") say("shot " .. n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 6)
  joypad.set({})
  adv(gap or 40)
  say("press " .. k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, STATE)))
adv(60)
shot("00")
press("A", 6, 50);  shot("01_afterA")
press("A", 6, 50);  shot("02_afterA2")
press("Right", 6, 40); shot("03_right")
press("Right", 6, 40); shot("04_right2")
press("A", 6, 50);  shot("05_select")
press("Right", 6, 40); shot("06_move")
say("done")
pcall(client.exit)
