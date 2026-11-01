-- 配置阶段 → START → A(开始战斗) → 逐步截图，确认到底走到哪一步
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/start_battle.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/sb_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 30); say("tap5 "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00_map")
tap("B", 40); shot("00b")
tap("Start", 60); shot("01_menu")
tap("A", 80);     shot("02_afterA")
tap("A", 100);    shot("03_afterA2")
adv(120);         shot("04_wait")
tap("A", 100);    shot("05_afterA3")
adv(120);         shot("06_wait2")
say("done")
pcall(client.exit)
