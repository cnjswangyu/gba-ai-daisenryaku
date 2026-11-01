-- bot v3：精确导航（单步 + 精确匹配）+ 只在落点正确时下令 + 编队推进
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/bot3.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/b3_"..n..".png") end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 18)
end
local function step1(dir)             -- 走一格
  for _ = 1, 14 do joypad.set({ [dir] = true }); emu.frameadvance() end
  joypad.set({}); adv(6)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function uget(i)
  local o = 0x03002BE2 + i * 24
  return memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2)
end

-- 精确导航：单步逼近，卡住就换垂直方向绕
local function goto_exact(tx, ty, maxn)
  for _ = 1, (maxn or 30) do
    local cx, cy = cur()
    if cx == tx and cy == ty then return true end
    local tries = {}
    if cx < tx then tries[#tries + 1] = "Right" elseif cx > tx then tries[#tries + 1] = "Left" end
    if cy < ty then tries[#tries + 1] = "Down" elseif cy > ty then tries[#tries + 1] = "Up" end
    if #tries == 0 then tries = { "Right", "Down" } end
    local moved = false
    for _, d in ipairs(tries) do
      local bx, by = cur()
      step1(d)
      local ax, ay = cur()
      if ax ~= bx or ay ~= by then moved = true; break end
    end
    if not moved then
      -- 绕行：试另外两个方向
      for _, d in ipairs({ "Down", "Up", "Right", "Left" }) do
        local bx, by = cur()
        step1(d)
        local ax, ay = cur()
        if ax ~= bx or ay ~= by then moved = true; break end
      end
      if not moved then return false end
    end
  end
  return false
end

-- 解卡：下令后单位仍是"选中/菜单"态，方向键会被吞；用 B/A 交替直到光标能动
local function mobile()
  local x0, y0 = cur()
  step1("Right")
  local x1, y1 = cur()
  if x1 ~= x0 or y1 ~= y0 then step1("Left"); return true end
  return false
end
local function unstick()
  for _ = 1, 4 do
    if mobile() then return true end
    tap("B", 20)
    if mobile() then return true end
    tap("A", 20)
  end
  return mobile()
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
for _ = 1, 4 do
  local x0 = cur(); step1("Right"); local x1 = cur(); step1("Left")
  if x0 ~= x1 then break end
  tap("A", 60)
end
shot("00_ready")

local t0 = os.clock()
local ok_sel, ok_move = 0, 0
for i = 0, 9 do
  local x, y, hp = uget(i)
  if hp > 0 then
    local arrived = goto_exact(x, y, 30)
    local cx, cy = cur()
    if arrived then
      ok_sel = ok_sel + 1
      tap("A", 20)                -- 单位菜单
      tap("A", 20)                -- 移動
      -- 编队推进：每单位向东 2 格，纵向错开
      local tx, ty = x + 2, y + ((i % 3) - 1) * 2
      local reach = goto_exact(tx, ty, 8)
      tap("A", 40); adv(30)
      local nx, ny = uget(i)
      if nx ~= x or ny ~= y then ok_move = ok_move + 1 end
      if not unstick() then say("  WARN: 解卡失败") end
      say(string.format("u%d (%d,%d) 到(%d,%d) 选中%s 目标(%d,%d) %s -> (%d,%d)",
        i, x, y, cx, cy, tostring(arrived), tx, ty, reach and "可走" or "受限", nx, ny))
    else
      say(string.format("u%d (%d,%d) 导航失败 (停在 %d,%d)", i, x, y, cx, cy))
    end
  end
end
say(string.format("选中 %d/10, 移动 %d, 用时 %.1fs", ok_sel, ok_move, os.clock() - t0))
shot("01_after")
say("done")
pcall(client.exit)
