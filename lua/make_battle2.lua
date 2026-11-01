-- 开战并保存 battle.State；然后 B+START 看战斗中总菜单
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/turn1.State"
local DST   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/mk_battle2.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/b2_"..n..".png"); say("shot "..n) end
local function tap(k, g)   -- 5 帧，避免被 vblank 吞
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40); say("tap "..k)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

tap("B", 40)           -- 取消选中
tap("Start", 70)       -- 总菜单
shot("01_menu")
tap("A", 120)          -- 开始战斗
shot("02_a")
adv(150)
tap("A", 120)          -- 确认/清横幅
adv(150)
shot("03_turn1")
say("cursor=" .. string.format("(%d,%d)", cur()))

say("save=" .. tostring(pcall(savestate.save, DST)))
tap("B", 40)
tap("Start", 70)
shot("04_battle_menu")
say("done")
pcall(client.exit)
