-- 布阵阶段按键全扫：每个键单独试，标出真正有反应的键
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/sweep2.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/s2_"..n..".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 12); joypad.set({}); adv(gap or 45)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

press("Start", 8, 80)    -- 出击
press("A", 8, 150)       -- 确认自动部署 → 进入布阵
adv(120)
shot("00_base")

local keys = { "Right", "Down", "Left", "Up", "A", "B", "L", "R", "Start", "Select" }
for i, k in ipairs(keys) do
  press(k, 12, 55)
  shot(string.format("%02d_%s", i, k))
  say("pressed " .. k)
end
say("done")
pcall(client.exit)
