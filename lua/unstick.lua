-- 先取消选中（B），看光标能否脱离被围住的单位；再试方向键
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/unstick.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/n_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 45); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00_in")

press("B", 8, 60);  shot("01_b")
press("Right", 8, 60); shot("02_right")
press("Right", 8, 60); shot("03_right2")
press("Up", 8, 60);    shot("04_up")
press("Left", 8, 60);  shot("05_left")
press("Select", 8, 60); shot("06_select")
say("done")
pcall(client.exit)
