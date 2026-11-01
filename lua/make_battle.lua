-- 从 battle_start：确认部署 → START 菜单选「开始战斗」→ 清横幅 → 验证光标 → 存档
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local DST   = BASE .. "states/turn1.State"
local OUT   = BASE .. "logs/mk_battle.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/mb_"..n..".png") end
local function tap(k, g)
  joypad.set({ [k] = true }); emu.frameadvance(); joypad.set({}); adv(g or 30); say("tap "..k)
end
local function hold(k, f)
  for _ = 1, (f or 12) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(18); say("hold "..k)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

tap("A", 90)          -- 确认自动部署（进入配置阶段）
shot("01_config")
tap("Start", 70)      -- 总菜单
shot("02_menu")
tap("A", 120)         -- 第一项 = 开始战斗
shot("03_battle")
adv(120)
shot("04_wait")

-- 清掉可能残留的横幅：A 若干次，直到光标能动
for i = 1, 5 do
  local x0, y0 = cur()
  hold("Right", 12)
  local x1, y1 = cur()
  say(string.format("try%d: (%d,%d)->(%d,%d)", i, x0, y0, x1, y1))
  if x0 ~= x1 or y0 ~= y1 then
    hold("Left", 12)
    break
  end
  tap("A", 100)
  shot("05_clear" .. i)
end

say("final=" .. string.format("(%d,%d)", cur()))
shot("06_ready")
say("save=" .. tostring(pcall(savestate.save, DST)))
say("done")
pcall(client.exit)
