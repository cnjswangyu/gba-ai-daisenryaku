-- 重建干净的战斗存档点：battle_start → A 确认部署 → 清掉横幅 → 存 turn1.State
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local DST   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/ready.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/rd_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 60); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00_load")

press("A", 8, 120); shot("01_confirm")   -- 确认自动部署
adv(120);           shot("02_wait")
press("A", 8, 120); shot("03_a2")        -- 回合横幅类
adv(120);           shot("04_wait2")

-- 先确认方向键能动：按 RIGHT 看是否切换
press("Right", 10, 60); shot("05_right")
press("Right", 10, 60); shot("06_right2")

say("save=" .. tostring(pcall(savestate.save, DST)))
say("done")
pcall(client.exit)
