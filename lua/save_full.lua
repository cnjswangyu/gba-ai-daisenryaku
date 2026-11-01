-- 满编开战并存档：pre_battle → 全选 10 个单位 → START → A → battle_start.State
local BASE  = "D:/prog/gba-ai/"
local OUT   = BASE .. "states/pre_battle.State"
local DST   = BASE .. "states/battle_start.State"
local LOG   = BASE .. "logs/save_full.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 4)
  joypad.set({})
  adv(gap or 24)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
w("load=" .. tostring(pcall(savestate.load, OUT)))
adv(40)

-- 全选（第 1 行已配，2..10 逐个点）
for i = 2, 10 do
  press("Down", 4, 20)
  press("A", 4, 24)
end
press("Start", 6, 60)
press("A", 6, 150)
adv(180)
w("save=" .. tostring(pcall(savestate.save, DST)))
pcall(client.screenshot, BASE .. "shots/full_deploy_map.png")

local f = io.open(LOG, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
