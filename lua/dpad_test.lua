-- 对照：不载存档，冷启动到主菜单，测 UP/DOWN 是否移动高亮
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/dpad.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/dp_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 40); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(90)
press("A", 5, 150)     -- 过开机图
adv(200)
press("Start", 6, 90)  -- 标题
adv(120)
shot("00_menu")
press("Down", 6, 50);  shot("01_down")
press("Down", 6, 50);  shot("02_down2")
press("Up", 6, 50);    shot("03_up")
say("done")
pcall(client.exit)
