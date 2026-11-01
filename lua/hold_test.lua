-- 正确长按：每帧都要 joypad.set，才是真正的"按住"
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/hold.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/hd_"..n..".png") end
local function tap(k)                     -- 单帧点击（菜单够用）
  joypad.set({ [k] = true }); emu.frameadvance(); joypad.set({}); adv(6)
end
local function hold(k, frames)            -- 真·按住
  for _ = 1, (frames or 20) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(20)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

tap("Start"); adv(40)
tap("A"); adv(80)
tap("A"); adv(80)
shot("00_base")

hold("Right", 30); shot("01_right30")
hold("Right", 30); shot("02_right60")
hold("Down", 30);  shot("03_down30")
hold("Left", 30);  shot("04_left30")
say("done")
pcall(client.exit)
