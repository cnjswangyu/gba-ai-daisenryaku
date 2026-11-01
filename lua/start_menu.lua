-- 地图上按 START 打开总菜单，测方向键是否可导航
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/startmenu.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/sm_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 50); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

press("A", 8, 120)    -- 确认部署
adv(120)
press("A", 8, 120)
adv(120)
shot("00_base")

press("Start", 8, 80);  shot("01_start")
press("Down", 8, 60);   shot("02_down")
press("Down", 8, 60);   shot("03_down2")
press("Up", 8, 60);     shot("04_up")
press("A", 8, 90);      shot("05_a")
say("done")
pcall(client.exit)
