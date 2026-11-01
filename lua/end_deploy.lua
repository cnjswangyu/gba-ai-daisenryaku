-- 布阵阶段 → 试各种结束方式（START / B / A）
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/end_deploy.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/z_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 40); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, STATE)))
adv(60)
shot("00")

press("Start", 6, 60); shot("01_start")
press("A", 6, 80);     shot("02_a")
adv(60);               shot("03_wait")
press("B", 6, 60);     shot("04_b")
press("Start", 6, 60); press("A", 6, 100); shot("05_start_a")
adv(120); shot("06_wait2")
say("done")
pcall(client.exit)
