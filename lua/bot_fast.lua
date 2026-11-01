-- 快速 bot v2：标定长按（10 + 2.5*格）+ 编队推进 + 不孤军深入
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/botfast.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/bf_"..n..".png") end
local function tap(k, g)              -- 5 帧短按
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 18)
end
local function holdFrames(k, f)       -- 精确帧数长按
  for _ = 1, f do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(6)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function uget(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2)
end

-- 一次长按走 n 格（10 帧延迟 + 2.5 帧/格，保守取 n-0.5）
local function stepN(dir, n)
  n = math.max(1, n)
  holdFrames(dir, math.floor(10 + 2.5 * (n - 0.5)))
end

-- 快速导航：一次长按 + 少量 1 格修正
local function goto_fast(tx, ty, tries)
  for k = 1, (tries or 6) do
    local cx, cy = cur()
    if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then return true end
    local d, n
    if cx < tx then d, n = "Right", (tx - cx) / 2
    elseif cx > tx then d, n = "Left", (cx - tx) / 2
    elseif cy < ty then d, n = "Down", (ty - cy) / 2
    else d, n = "Up", (cy - ty) / 2 end
    stepN(d, (k == 1) and math.max(1, n - 1) or 1)
  end
  return false
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
for _ = 1, 4 do
  local x0 = cur(); holdFrames("Right", 10); local x1 = cur(); holdFrames("Left", 10)
  if x0 ~= x1 then break end
  tap("A", 60)
end
shot("00_ready")

local t0 = os.clock()
for turn = 1, 2 do
  say(string.format("=== 回合 %d (elapsed %.1fs) ===", turn, os.clock() - t0))
  -- 集结点：东侧道路（编队推进，不孤军）
  local RALLY_X, RALLY_Y = 26 + (turn - 1) * 2, 30
  local moved, blocked = 0, 0
  for i = 0, 9 do
    local x, y, hp = uget(i)
    if hp > 0 then
      goto_fast(x, y, 4)
      tap("A", 18); tap("A", 18)      -- 菜单 → 移動
      -- 编队：目标按 i 错开，避免叠在一格
      local tx = RALLY_X + (i % 3) * 2
      local ty = RALLY_Y + (math.floor(i / 3) - 1) * 2
      goto_fast(tx, ty, 4)
      tap("A", 40); adv(30)
      local nx, ny = uget(i)
      if nx ~= x or ny ~= y then moved = moved + 1 else blocked = blocked + 1 end
    end
  end
  say(string.format("  移动 %d, 未动 %d, 用时 %.1fs", moved, blocked, os.clock() - t0))
  shot(string.format("turn%d", turn))
  -- 结束回合
  tap("B", 18); tap("Start", 30); tap("A", 40); adv(40); tap("A", 40); adv(60)
  for _ = 1, 4 do
    local x0 = cur(); holdFrames("Right", 10); local x1 = cur(); holdFrames("Left", 10)
    if x0 ~= x1 then break end
    tap("A", 60)
  end
end
say(string.format("总用时 %.1fs", os.clock() - t0))
shot("99_end")
say("done")
pcall(client.exit)
