-- 情报画面的「部隊」页：能不能直接从列表选中某个单位（用来绕开被围住的单位）
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/intel.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/i_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 45); say("press "..k)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

press("B", 8, 50)        -- 先取消
press("Select", 8, 70); shot("00_intel")
press("R", 8, 60);      shot("01_tab2")
press("R", 8, 60);      shot("02_tab3")
press("Down", 8, 50);   shot("03_down")
press("A", 8, 70);      shot("04_a")
say("done")
pcall(client.exit)
