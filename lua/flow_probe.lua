-- 精确流程探测：单位菜单 → 選択移動 → 走格 → 确认 → 后续菜单；再探结束回合菜单
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/flow.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/fl_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40); say("tap "..k)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(18); say("hold "..k)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function unit(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2), memory.read_u8(o + 6)
end
local function move_to(tx, ty, maxn)
  for _ = 1, (maxn or 30) do
    local cx, cy = cur()
    if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then return true end
    if cx < tx then hold("Right", 14) elseif cx > tx then hold("Left", 14)
    elseif cy < ty then hold("Down", 14) else hold("Up", 14) end
  end
  return false
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

for i = 1, 6 do
  local x0, y0 = cur(); hold("Right", 12); local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then hold("Left", 12); say("ready after "..i); break end
  tap("A", 100)
end
shot("00_ready")

local ux, uy, uhp = unit(0)
say(string.format("unit0=(%d,%d) hp=%d", ux, uy, uhp))
move_to(ux, uy)
shot("01_on_unit")

tap("A", 50);  shot("02_menu")        -- 单位菜单
tap("A", 50);  shot("03_move_mode")   -- 选「移動」
hold("Right", 14); shot("04_step1")
hold("Right", 14); shot("05_step2")
say(string.format("cursor now (%d,%d)", cur()))
tap("A", 80);  shot("06_confirm")     -- 确认落点
adv(90);       shot("07_after_move")
tap("A", 50);  shot("08_menu2")       -- 移动后菜单
tap("A", 50);  shot("09_after2")
adv(60);       shot("10_final")
say(string.format("unit0 now (%d,%d)", unit(0)))
say("done")
pcall(client.exit)
