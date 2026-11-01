-- 贪心突围：用光标当探针，朝远离质心方向走，走不动换方向；每步内存校验
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/breakout3.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/bg_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(14)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function uget(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2)
end
local function goto_xy(tx, ty, maxn)
  for _ = 1, (maxn or 14) do
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
for _ = 1, 6 do
  local x0 = cur(); hold("Right", 12); local x1 = cur(); hold("Left", 12)
  if x0 ~= x1 then break end
  tap("A", 100)
end
shot("00_ready")

local sx, sy, n = 0, 0, 0
for i = 0, 9 do
  local x, y, hp = uget(i)
  if hp > 0 then sx = sx + x; sy = sy + y; n = n + 1 end
end
local ccx, ccy = sx / n, sy / n
say(string.format("质心(%.1f,%.1f) 单位 %d", ccx, ccy, n))

local order = {}
for i = 0, 9 do
  local x, y, hp = uget(i)
  if hp > 0 then order[#order + 1] = { i = i, d = math.abs(x - ccx) + math.abs(y - ccy) } end
end
table.sort(order, function(a, b) return a.d > b.d end)

for _, o in ipairs(order) do
  local i = o.i
  local x, y, hp = uget(i)
  if hp > 0 then
    goto_xy(x, y)
    tap("A", 40); tap("A", 40)   -- 菜单 → 移動
    local steps = 0
    for _ = 1, 6 do
      local cx, cy = cur()
      local dirs = {}
      if cx > ccx + 0.5 then dirs[#dirs + 1] = "Right" elseif cx < ccx - 0.5 then dirs[#dirs + 1] = "Left" end
      if cy > ccy + 0.5 then dirs[#dirs + 1] = "Down" elseif cy < ccy - 0.5 then dirs[#dirs + 1] = "Up" end
      if #dirs == 0 then dirs = { "Right", "Up" } end
      local moved = false
      for _, d in ipairs(dirs) do
        local bx, by = cur()
        hold(d, 14)
        local ax, ay = cur()
        if ax ~= bx or ay ~= by then moved = true; steps = steps + 1; break end
      end
      if not moved then break end
    end
    local cx, cy = cur()
    tap("A", 80); adv(50)
    local nx, ny = uget(i)
    say(string.format("u%d (%d,%d) 光标(%d,%d) 走%d步 -> (%d,%d) %s",
      i, x, y, cx, cy, steps, nx, ny, (nx ~= x or ny ~= y) and "MOVED" or "未动"))
  end
end
shot("01_after")
say("done")
pcall(client.exit)
