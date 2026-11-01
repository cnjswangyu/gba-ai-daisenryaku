-- 探战斗中 START 菜单（结束回合在哪一项）
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/endturn3.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/te_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40); say("tap "..k)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

-- 清横幅
for i = 1, 6 do
  joypad.set({ Right = true }); emu.frameadvance(); joypad.set({})
  local x, y = cur()
  if x ~= 21 then break end
  tap("A", 100)
end
tap("B", 40)
tap("Start", 80)
shot("01_menu")
tap("Down", 40); shot("02_down")
tap("Down", 40); shot("03_down2")
say("done")
pcall(client.exit)
