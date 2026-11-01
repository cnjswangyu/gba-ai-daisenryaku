-- 选中单位 → 选「移動」→ 再试方向键，看坐标/画面是否变化
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local OUT   = BASE .. "logs/cursor_move2.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/mv_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 40); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

press("Start", 6, 60)
press("A", 6, 100)
adv(60)
press("A", 6, 100)   -- 青国行动开始
press("A", 6, 100)   -- 回合横幅
shot("00")
press("A", 6, 80); shot("01_select")     -- 选中单位 → 菜单
press("A", 6, 80); shot("02_move_mode")  -- 选「移動」
press("Right", 6, 50); shot("03_r1")
press("Right", 6, 50); shot("04_r2")
press("Down", 6, 50);  shot("05_d1")
press("A", 6, 80);     shot("06_confirm") -- 确认移动
adv(90); shot("07_after")
say("save=" .. tostring(pcall(savestate.save, BASE .. "states/moved.State")))
say("done")
pcall(client.exit)
