-- 进入真正的战斗（第1回合）并存档：battle_start → START → A → 演習标题 → 第1回合
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local DST   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/make_turn1.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/t1_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 40); say("press "..k)
end
local function ki() return memory.read_u16_le(0x04000130) % 1024 end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

press("Start", 6, 60); shot("01")
press("A", 6, 90);     shot("02_intro")      -- 演習标题
adv(90);               shot("03")
press("A", 6, 120);    shot("04_turn1")      -- 第1回合
adv(120);              shot("05_turn1b")

-- 存档前先确认方向键能动
press("Right", 6, 40); shot("06_right")
press("Right", 6, 40); shot("07_right2")
press("Down", 6, 40);  shot("08_down")

say("save=" .. tostring(pcall(savestate.save, DST)))
say(string.format("KEYINPUT=%03X", ki()))
say("done")
pcall(client.exit)
