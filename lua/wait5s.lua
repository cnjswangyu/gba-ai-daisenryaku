-- 长等待：不管横幅，先空转 5 秒再试方向键
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/wait5s.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/q_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 10); joypad.set({}); adv(gap or 50); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00_load")

adv(300)          -- 空转 5 秒，让横幅自己走完
shot("01_after5s")
press("Right", 10, 60); shot("02_r1")
press("Right", 10, 60); shot("03_r2")
press("Down", 10, 60);  shot("04_d1")
press("A", 10, 80);     shot("05_a")
say("done")
pcall(client.exit)
