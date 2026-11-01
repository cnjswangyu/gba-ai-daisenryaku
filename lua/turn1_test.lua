-- 回合横幅 → 试 A 关掉 → 再试方向键
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/turn1_test.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/w_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 40); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, STATE)))
adv(60)
shot("00")

for i = 1, 3 do
  press("A", 6, 80); shot(string.format("a%d", i))
end
press("Right", 6, 40); shot("r1")
press("Right", 6, 40); shot("r2")
press("Down", 6, 40);  shot("d1")
press("A", 6, 60);     shot("sel")
say("save=" .. tostring(pcall(savestate.save, BASE .. "states/turn1.State")))
say("done")
pcall(client.exit)
