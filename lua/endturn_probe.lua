-- 探明 Start 总菜单：怎么结束回合
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/endturn.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/et_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  joypad.set({ [k] = true }); emu.frameadvance(); joypad.set({}); adv(g or 20); say("tap "..k)
end
local function hold(k, f)
  for _ = 1, (f or 12) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(18); say("hold "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
tap("A", 90)      -- 确认部署
shot("00_map")
hold("Right", 12); shot("01_cursor")   -- 确认光标能动

tap("Start", 60); shot("02_start_menu")
hold("Down", 10);  shot("03_down1")
hold("Down", 10);  shot("04_down2")
hold("Up", 10);    shot("05_up")
tap("A", 60);      shot("06_a")
say("done")
pcall(client.exit)
