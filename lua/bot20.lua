-- 战斗 bot：读内存驱动，逐单位「移動」→ 校验坐标 → 结束回合，最多 N 回合
local BASE   = "D:/prog/gba-ai/"
local SRC    = BASE .. "states/battle.State"
local OUT    = BASE .. "logs/bot20.txt"
local TURNS  = 20
local MAXU   = 10

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/b20_"..n..".png") end
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

local function move_to(tx, ty, maxn)
  for _ = 1, (maxn or 24) do
    local cx, cy = cur()
    if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then return true end
    if cx < tx then hold("Right", 14)
    elseif cx > tx then hold("Left", 14)
    elseif cy < ty then hold("Down", 14)
    else hold("Up", 14) end
  end
  return false
end

-- 等横幅结束：光标能自由移动
local function wait_ready()
  for _ = 1, 8 do
    local x0, y0 = cur()
    hold("Right", 12)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 12); return true end
    tap("A", 90)
  end
  return false
end

local function end_turn()
  tap("B", 40)        -- 取消选中（否则 START 不响应）
  tap("Start", 70)
  tap("A", 90)        -- 第一项「结束回合」
  adv(60)
  tap("A", 90)        -- 可能的确认
  adv(150)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
if not wait_ready() then say("WARN: 横幅没清掉") end
shot("00_ready")

for turn = 1, TURNS do
  say(string.format("=== 回合 %d ===", turn))
  for i = 0, MAXU - 1 do
    local x, y, hp, tid = unit(i)
    if hp > 0 then
      -- 散开的目标阵位：东侧 3 列 x 4 行
      local tx = 26 + (i % 3) * 2
      local ty = 27 + math.floor(i / 3) * 2 + (turn - 1) * 0
      move_to(x, y)
      tap("A", 40)          -- 菜单：移動/解散
      tap("A", 40)          -- 移動
      -- 朝目标走最多 3 格（受移动力限制会自动停）
      for _ = 1, 3 do
        local cx, cy = cur()
        if cx < tx then hold("Right", 14)
        elseif cy < ty then hold("Down", 14)
        elseif cy > ty then hold("Up", 14)
        elseif cx > tx then hold("Left", 14) end
      end
      local before = { unit(i) }
      tap("A", 70)          -- 确认落点
      adv(60)
      local bx, by, bhp = unit(i)
      say(string.format("  u%d (%d,%d)->(%d,%d) hp=%d", i, x, y, bx, by, bhp))
    end
  end
  shot(string.format("turn%02d", turn))
  end_turn()
  if not wait_ready() then say("WARN: 回合开始横幅没清掉") end
  pcall(savestate.save, BASE .. "states/auto_turn.State")
  shot(string.format("turn%02d_end", turn))
end
say("done")
pcall(client.exit)
