-- 用范围掩码驱动全部单位"向外突围"一回合
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/breakout2.txt"
local MASK, STRIDE, ROWS, COLS = 0x030010DD, 48, 144, 48

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/bk_"..n..".png"); say("shot "..n) end
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
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2), memory.read_u8(o + 6)
end
local function mark(c, r)
  if c < 0 or c >= COLS or r < 0 or r >= ROWS then return false end
  return memory.read_u8(MASK + r * STRIDE + c) ~= 0xF1
end
local function goto_xy(tx, ty, maxn)
  for _ = 1, (maxn or 16) do
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

-- 质心
local sx, sy, n = 0, 0, 0
for i = 0, 9 do
  local x, y, hp = uget(i)
  if hp > 0 then sx = sx + x; sy = sy + y; n = n + 1 end
end
local ccx, ccy = sx / n, sy / n
say(string.format("质心(%.1f,%.1f)", ccx, ccy))

-- 外圈优先
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
    tap("A", 40); tap("A", 40)     -- 菜单 → 移動
    adv(30)
    -- 掩码 bbox → 偏移
    local minc, maxc, minr, maxr = 999, -1, 999, -1
    for r = 0, ROWS - 1 do
      for c = 0, COLS - 1 do
        if mark(c, r) then
          if c < minc then minc = c end; if c > maxc then maxc = c end
          if r < minr then minr = r end; if r > maxr then maxr = r end
        end
      end
    end
    if maxc >= 0 then
      local offc = x - (minc + maxc) / 2
      local offr = y - (minr + maxr) / 2
      -- 选离质心最远、且离自己至少 2 格的掩码格
      local bc, br, bd = nil, nil, -1
      for r = minr, maxr do
        for c = minc, maxc do
          if mark(c, r) then
            local hx, hy = c + offc, r + offr
            local d = math.abs(hx - ccx) + math.abs(hy - ccy)
            local selfd = math.abs(hx - x) + math.abs(hy - y)
            if selfd >= 2 and d > bd then bd, bc, br, btx, bty = d, c, r, hx, hy end
          end
        end
      end
      if bc then
        local tx, ty = math.floor(btx + 0.5), math.floor(bty + 0.5)
        local ok = goto_xy(tx, ty, 10)
        local cx2, cy2 = cur()
        tap("A", 80); adv(60)
        local nx, ny = uget(i)
        say(string.format("u%d (%d,%d) 目标(%d,%d) 光标(%d,%d) 导航%s -> (%d,%d) %s",
          i, x, y, tx, ty, cx2, cy2, ok and "ok" or "限界", nx, ny,
          (nx ~= x or ny ~= y) and "MOVED" or "未动"))
      else
        say(string.format("u%d (%d,%d) 无可用掩码", i, x, y))
        tap("B", 40); tap("B", 40)
      end
    else
      say(string.format("u%d (%d,%d) 掩码全空", i, x, y))
      tap("B", 40); tap("B", 40)
    end
  end
end
shot("01_after")
say("done")
pcall(client.exit)
