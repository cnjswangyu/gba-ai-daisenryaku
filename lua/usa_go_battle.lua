-- battle_usa.State（配置阶段）→ START「开始战斗」→ 真战场，存 battle_usa_live.State
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa.State"
local DST  = BASE .. "states/battle_usa_live.State"
local OUT  = BASE .. "logs/usa_go_battle.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/gb_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40); say("tap "..k)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(18)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function units(base, side)
  local n = 0
  for k = 0, 63 do
    local o = base + k * 24
    local x, y, fuel = memory.read_u8(o), memory.read_u8(o+1), memory.read_u8(o+2)
    if x > 0 and x < 64 and y > 0 and y < 64 and fuel > 0 then
      n = n + 1
      if n <= 24 then
        say(string.format("  U%s%02d id=%d (%d,%d) fuel=%d hp=%d acted=%d kind=%d",
          side, k, memory.read_u16_le(o-2), x, y, fuel,
          memory.read_u8(o+4), memory.read_u8(o+5), memory.read_u8(o+6)))
      end
    end
  end
  say(string.format("  %s total=%d", side, n))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
shot("00_map")

-- 清横幅
local function mobilePad()
  local x0 = select(1, cur())
  hold("Right", 14)
  local x1 = select(1, cur())
  if x0 ~= x1 then hold("Left", 14); return true end
  return false
end
for i = 1, 10 do
  if mobilePad() then say("ready after " .. i); break end
  tap("A", 60)
end

say("== 配置阶段单位 ==")
units(0x03002BE2, "US")
units(0x030031E2, "EN")

tap("B", 40)          -- 取消选中
tap("Start", 70)      -- 总菜单
shot("01_start_menu")
tap("A", 120)         -- 第一项「开始战斗」
shot("02_afterA")
adv(150)
tap("A", 120)         -- 清横幅/确认
adv(150)
shot("03_turn1")
say("cursor=" .. string.format("(%d,%d)", cur()))
say("== 开战后单位 ==")
units(0x03002BE2, "US")
units(0x030031E2, "EN")
say("save=" .. tostring(pcall(savestate.save, DST)))
say("done")
pcall(client.exit)
