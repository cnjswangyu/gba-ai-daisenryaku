-- 关掉单位菜单后，逐方向测试光标是否真的会移动
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"   -- 用干净的满编状态
local OUT   = BASE .. "logs/cursor_move.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/cm_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 40); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

-- 进战斗：START → A → A（关横幅）
press("Start", 6, 60)
press("A", 6, 100)
adv(60)
press("A", 6, 100)   -- 青国行动开始
press("A", 6, 100)
shot("00_free")

press("Right", 6, 50); shot("01_r1")
press("Right", 6, 50); shot("02_r2")
press("Right", 6, 50); shot("03_r3")
press("Down", 6, 50);  shot("04_d1")
press("Left", 6, 50);  shot("05_l1")
say("done")
pcall(client.exit)
