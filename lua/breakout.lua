-- 一回合突破：从"最外圈"的单位开始往外走，逐个验证坐标
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/breakout.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/bo_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(16)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function unit(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2), memory.read_u8(o + 6)
end
local function occupied(x, y)
  for i = 0, 9 do
    local ux, uy, hp = unit(i)
    if hp > 0 and math.abs(ux - x) <= 1 and math.abs(uy - y) <= 1 then return true end
  end
  return false
end
local function move_to(tx, ty, maxn)
  for _ = 1, (maxn or 24) do
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

-- 清横幅
for _ = 1, 6 do
  local x0 = cur(); hold("Right", 12); local x1 = cur(); hold("Left", 12)
  if x0 ~= x1 then break end
  tap("A", 100)
end
shot("00_ready")

-- 质心
local sx, sy, n = 0, 0, 0
for i = 0, 9 do
  local x, y, hp = unit(i)
  if hp > 0 then sx = sx + x; sy = sy + y; n = n + 1 end
end
local cx, cy = sx / n, sy / n
say(string.format("质心 (%.1f,%.1f) 单位数 %d", cx, cy, n))

-- 按"离质心由远到近"排序
local order = {}
for i = 0, 9 do
  local x, y, hp = unit(i)
  if hp > 0 then
    order[#order + 1] = { i = i, d = math.abs(x - cx) + math.abs(y - cy) }
  end
end
table.sort(order, function(a, b) return a.d > b.d end)

for _, o in ipairs(order) do
  local i = o.i
  local x, y, hp, tid = unit(i)
  -- 朝远离质心方向找空位
  local dx = (x > cx) and 2 or ((x < cx) and -2 or 0)
  local dy = (y > cy) and 2 or ((y < cy) and -2 or 0)
  local tx, ty = x + dx, y + dy
  if dx == 0 and dy == 0 then tx, ty = x + 2, y end
  say(string.format("u%d (%d,%d) -> (%d,%d) 占用=%s", i, x, y, tx, ty, tostring(occupied(tx, ty))))
  move_to(x, y)
  tap("A", 40)
  tap("A", 40)
  -- 走到目标
  for _ = 1, 3 do
    local px, py = cur()
    if math.abs(px - tx) <= 1 and math.abs(py - ty) <= 1 then break end
    if px < tx then hold("Right", 14) elseif px > tx then hold("Left", 14)
    elseif py < ty then hold("Down", 14) else hold("Up", 14) end
  end
  tap("A", 70)
  adv(60)
  local nx, ny = unit(i)
  say(string.format("   result (%d,%d) %s", nx, ny, (nx ~= x or ny ~= y) and "MOVED" or "blocked"))
end
shot("01_after")
say("done")
pcall(client.exit)
