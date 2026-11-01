-- 长按测试：方向键按住 30 帧，看地图是否滚动/光标是否移动
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/moved.State"
local OUT   = BASE .. "logs/long_press.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/lp_"..n..".png"); say("shot "..n) end
local function hold(k, frames)
  joypad.set({ [k] = true }); adv(frames or 30); joypad.set({}); adv(30); say("hold "..k.." "..tostring(frames))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00")
hold("Right", 30); shot("01_right30")
hold("Up", 30);    shot("02_up30")
hold("Left", 30);  shot("03_left30")
hold("Down", 30);  shot("04_down30")
hold("Select", 10); shot("05_select")
hold("L", 10);     shot("06_l")
say("done")
pcall(client.exit)
