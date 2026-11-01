-- 枚举编成表的 10 个候选单位：逐行截图
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/enum_units.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/u_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 4)
  joypad.set({})
  adv(gap or 24)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
w("load=" .. tostring(pcall(savestate.load, STATE)))
adv(40)

shot("00")
for i = 1, 9 do
  press("Down", 4, 24)
  shot(string.format("%02d", i))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
