-- 在干净的第1回合状态里探 Start 总菜单 / 结束回合
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/endturn2.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/eu_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  joypad.set({ [k] = true }); emu.frameadvance(); joypad.set({}); adv(g or 30); say("tap "..k)
end
local function hold(k, f)
  for _ = 1, (f or 10) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(18); say("hold "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00_map")

tap("Start", 70); shot("01_menu")
hold("Down", 10); shot("02_down")
hold("Down", 10); shot("03_down2")
hold("Down", 10); shot("04_down3")
tap("A", 90);     shot("05_a")
adv(90);          shot("06_after")
say("done")
pcall(client.exit)
