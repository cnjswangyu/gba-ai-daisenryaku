-- 找出"换选中单位/释放光标"的键：B、L、R、SELECT 各试一次
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/switch.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/sw_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 50); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

press("A", 8, 120)   -- 确认部署
adv(120)
press("A", 8, 120)   -- 后续提示
adv(120)
shot("00_base")

press("B", 8, 60);      shot("01_B")
press("Right", 10, 60); shot("02_B_right")
press("L", 10, 60);     shot("03_L")
press("R", 10, 60);     shot("04_R")
press("B", 8, 60);      shot("05_B2")
press("Right", 10, 60); shot("06_right")
press("Up", 10, 60);    shot("07_up")
say("done")
pcall(client.exit)
