-- 从第1回合干净状态出发，逐键单独试，每步截图（用于判断哪个键有效）
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/key_sweep.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/k_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 45); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

-- 进入第1回合，把横幅全部清掉
press("Start", 6, 60)
press("A", 8, 120)
adv(60)
press("A", 8, 120)
press("A", 8, 120)
shot("00_clean")

-- A 打开单位菜单
press("A", 8, 90); shot("01_A_menu")
press("Down", 8, 60); shot("02_down")
press("Down", 8, 60); shot("03_down2")
press("A", 8, 90); shot("04_A_choose")
press("Right", 8, 60); shot("05_right")
press("Up", 8, 60); shot("06_up")
say("done")
pcall(client.exit)
