-- 部署确认框按 B（取消自动部署），看是否进入手动配置
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/manual_deploy.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/md_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 50); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

press("Start", 8, 80)     -- 出击
shot("01_after_start")
press("B", 8, 100)        -- 取消自动部署？
shot("02_after_b")
adv(60); shot("03_wait")
press("Right", 10, 60); shot("04_right")
press("Right", 10, 60); shot("05_right2")
press("Down", 10, 60);  shot("06_down")
press("A", 8, 90);      shot("07_a")
say("done")
pcall(client.exit)
