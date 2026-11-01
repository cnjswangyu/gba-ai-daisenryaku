-- 建一个"战前编成"存档点：跑到出击编成表后 savestate.save
local BASE = "D:/prog/gba-ai/"
local STATE = BASE .. "states/pre_battle.State"
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function key(n, times) for _ = 1, times do press(n, 4, 8) end end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90)
press("A", 5, 150)
adv(180)
press("Start", 6, 90)
adv(120)
press("A", 6, 150)
press("A", 6, 60)
press("Right", 4, 40)
press("A", 6, 50)
press("Right", 4, 20)
press("A", 6, 50)
key("Down", 5); key("Right", 8)
press("A", 6, 90)
adv(120)
press("A", 6, 120)
press("A", 6, 120)
for _ = 1, 14 do press("A", 6, 100); adv(30) end

local ok, err = pcall(savestate.save, STATE)
pcall(client.screenshot, BASE .. "shots/b_state_point.png")
local f = io.open(BASE .. "logs/boot_state.txt", "w")
if f then f:write("savestate.save ok=" .. tostring(ok) .. " err=" .. tostring(err) .. "\n"); f:close() end
pcall(client.exit)
