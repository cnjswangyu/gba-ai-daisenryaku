local recordName,recordTick,recordFrame=nil,0,0
local function controlled_frame()
 emu.frameadvance()
 if recordName then
  recordTick=recordTick+1
  if recordTick%6==0 then
   recordFrame=recordFrame+1
   client.screenshot(string.format("D:/prog/gba-ai/shots/native_attack/frames/%s_%05d.png",recordName,recordFrame))
  end
 end
end
--[[
  usa_ai_state.lua —— 《大战略》USA 局 AI 代理（游戏数据态版）

  与 state_agent.lua 的区别：
    - 不输出硬件态（GRID/OAM/内存块），而输出**游戏数据态**：双方单位、资金、光标地形
    - 接收**语义指令**（MOVE/ENDTURN），由 Lua 侧展开成确定性按键序列
      （模型不会数帧，绝不让它直接发按键）
    - 每条指令执行后有校验，结果写 shots/result.txt 供大脑回读

  协议：
    Lua  -> shots/state.txt   （step=N + 态势文本）
    Python -> shots/action.txt （step=N + 语义指令行）
    Lua  -> shots/result.txt  （step=N + 每条指令的成功/失败）

  用法：
    终端1: C:\ProgramData\Anaconda3\python.exe -u tools/ai_loop.py
    终端2: tools\EmuHawk.exe "roms\0219 - Daisenryaku.gba" --lua="D:/prog/gba-ai/lua/usa_ai_state.lua"

  实测要点（2026-10-18 探针验证，勿改）：
    - 单位记录：id(u16) 在 base-2；+0 x, +1 y, +2 燃料, +4 HP, +6 类别码, +7 状态码
      敌方表 = 我方表 + 0x600
    - 战场存档点载入后有 3 段开场演出（第1ターン/青国行动开始/…），需按 A 逐段点掉
      states/battle_usa_ready.State 已跳过演出，直接用
    - 地图态按 A：选中单位(信息面板) -> 再 A 出「移動/解散」-> 再 A 选「移動」进寻路
    - 寻路态方向键每按住约 13 帧走 1 格（x 增量 +1 或 +2，取决于奇偶）
    - 移动确认后按一次 A 即待机（该单位行动结束）
    - START 总菜单两列 10 项：左上「结束回合」，然后 A -> 确认框 -> A
    - joypad.set 不能传第二个参数，且必须每帧 set 才是真按住
]]

local BASE   = "D:/prog/gba-ai/"
local STATE  = BASE .. "shots/state.txt"
local ACTION = BASE .. "shots/action.txt"
local RESULT = BASE .. "shots/result.txt"
local SHOT   = BASE .. "shots/cur.png"
local LOGF   = BASE .. "logs/current_battle2.txt"
local DBF    = BASE .. "lua/unitdb.tsv"
local LOAD_STATE = BASE .. "states/v2_fixture.State"

local CTX      = 0x03000480
local U        = 0x03002BE2   -- 我方单位表（记录起点 base-2）
local PB       = 0x600        -- 敌方表偏移
local STRIDE   = 24
local SLOTS    = 64

local MAXSTEP  = 400
local WAIT_TRIES = 2400       -- 50ms * 2400 = 120s
local step = 0                -- 当前步（build_state 里要用，必须在它之前声明）

-- ============ 输入通道：邮箱注入（优先）/ joypad 回退 ============
-- 游戏把读 KEYINPUT 的代码复制到 IWRAM，运行期有 5 处 0x04000130 字面量 + ROM 1 处。
-- 全改成邮箱地址后，写 0x3FF-bits 即按下、0x3FF 即松开，绕过 BIOS 输入驱动的时序问题。
-- 实测：邮箱发键 5 帧 = 走 1 格（joypad.set 要 13 帧）。
local MAIL   = 0x03007F00
local LITS   = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
local ROML   = 0x080015F4
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80,
                 R = 0x100, L = 0x200 }
local mailOK = false

local HOLD_DIR_MAIL = 5       -- 邮箱：1 格
local HOLD_DIR_PAD  = 13      -- joypad 回退：1 格
local HOLD_BTN = 4            -- A/B/START：首帧会被 vblank 吞，至少 3 帧

-- ============ 工具 ============
local logf = io.open(LOGF, "w")
local function log(s)
  local line = string.format("[%d] %s", emu.framecount(), tostring(s))
  if logf then logf:write(line .. "\n"); logf:flush() end
end
local function r8(a) return memory.read_u8(a) end
local function adv(n) for _ = 1, (n or 1) do controlled_frame() end end
local function cur() return r8(0x030067FE), r8(0x030067FF) end

-- 每帧都 set 才是真按住；不要传 player 索引
local function hold(k, frames)
  if mailOK then
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    for _ = 1, (frames or HOLD_BTN) do controlled_frame() end
    memory.write_u16_le(MAIL, 0x3FF)       -- 必须松开，否则游戏一直读到按住
  else
    for _ = 1, (frames or HOLD_BTN) do
      joypad.set({ [k] = true })
      controlled_frame()
    end
    joypad.set({})
  end
end
local function tap(k, gap) hold(k, HOLD_BTN); adv(gap or 30) end
local function dir(k)
  if mailOK then hold(k, HOLD_DIR_MAIL); adv(5)
  else hold(k, HOLD_DIR_PAD); adv(8) end
end

-- 打补丁：把游戏读 KEYINPUT 的字面量全指向邮箱。
-- 铁律：**全改或全不改**。只改一半会让部分代码读邮箱、部分读硬件，按键直接全失效（踩过）。
-- IWRAM 里的地址每次载入存档都可能不同，所以动态扫描，不硬编码。
local function patch_mail()
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  local rv = memory.read_u32_le(ROML)
  local romok = (rv == 0x04000130)
  local romdone = (rv == MAIL)
  -- 战场态实测只有 2 处 IWRAM 副本（0x030075B8 / 0x030075DC），不是文档里的 5 处
  if #hits == 0 and not romok and not romdone then
    log("邮箱补丁：找不到读键字面量，放弃，改用 joypad")
    mailOK = false
    return false
  end
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  if romok then memory.write_u32_le(ROML, MAIL) end
  memory.write_u16_le(MAIL, 0x3FF)
  mailOK = true
  log(string.format("邮箱补丁：IWRAM %d 处 + ROM %s -> 邮箱通道", #hits,
    romok and "已改" or "此前已改"))
  for _, a in ipairs(hits) do log(string.format("   patched 0x%08X", a)) end
  return true
end

local function shot(n) pcall(client.screenshot, BASE .. "shots/" .. n .. ".png") end

-- ============ 单位库 ============
local DB = {}
local DB_N = 0
do
  local f = io.open(DBF, "r")
  if f then
    for line in f:lines() do
      if line:sub(1, 1) ~= "#" and #line > 0 then
        local c = {}
        for w in line:gmatch("[^\t]+") do c[#c + 1] = w end
        local id = tonumber(c[1])
        if id then
          DB_N = DB_N + 1
          DB[id] = {
            name = c[2] or "?",
            class = tonumber(c[3]) or 1,
            move = tonumber(c[4]) or 0,
            speed = tonumber(c[6]) or 0,
            dur = tonumber(c[7]) or 1,      -- HP 上限 = dur * 4
            atk = c[8] or "0,0,0,0,0",
            fuel = tonumber(c[9]) or 0,
            price = tonumber(c[10]) or 0,
            wtype = tonumber(c[11]) or 0,
          }
        end
      end
    end
    f:close()
    log("单位库载入 " .. DB_N .. " 条")
  else
    log("!! 单位库打不开 " .. DBF)
  end
end

local function db(id) return DB[id] end

-- ============ 地形 ============
local TNAME = {
  [0x00] = "海", [0x01] = "平地", [0x02] = "草地", [0x0C] = "海",
  [0x10] = "首都", [0x11] = "市街", [0x12] = "市街", [0x13] = "市街",
  [0x14] = "村落", [0x83] = "道路", [0x84] = "道路", [0x8B] = "森林",
}
local function tname(c) return TNAME[c] or string.format("地形%02X", c) end
-- 防御加成（HANDOFF §0.8.3 实测规则）
local function tdef(c)
  if c == 0x10 then return 30 end
  if c >= 0x11 and c <= 0x13 then return 20 end
  if c == 0x14 then return 10 end
  if c == 0x8B then return 10 end
  return 0
end
local function terrain_at(x, y)
  local base = memory.read_u32_le(CTX + 0x18)
  if base == 0 then return 0xFF end
  return r8(base + x * 4 + y * 0xC0)
end

-- ============ 读单位 ============
local function unit_side(side, k)
  local base = U + side * PB + k * STRIDE
  local id = memory.read_u16_le(base - 2)
  if id == 0 then return nil end
  local x, y = r8(base), r8(base + 1)
  if not (x > 0 and x < 64 and y > 0 and y < 64) then return nil end
  local d = db(id)
  return {
    side = side, idx = k, key = side * SLOTS + k, id = id,
    name = d and d.name or ("ID" .. id),
    x = x, y = y,
    fuel = r8(base + 2),
    exp = r8(base + 3), -- Unit record +5, independent of acted/state at record +7.
    hp = r8(base + 4),
    maxhp = d and (d.dur * 4) or 0,
    ammo = r8(base + 6),
    st = r8(base + 5),
    -- 记录从 ID(base-2) 开始；记录+7 的 bit0 位于 base+5。
    acted = (r8(base + 5) % 2 == 1),
  }
end

local MAX_SIDES = 4
-- ============ 多阵营（v2）============
-- 势力上限 4：FUN_08018ca0 里 `uVar5 < 4`。
-- 单位表 ctx+0x2760+side*0x600；阵营记录 ctx+0x24+side*0xC +4 = 状态(1..3 参战, FUN_080023c4)；
-- 玩家阵营 ctx+0x990；格表 +0 = 阵营+1。
local function side_alive(s)
  local v = memory.read_u8(CTX + 0x24 + s * 0xC + 4)
  return v >= 1 and v <= 3
end
local function player_side() return memory.read_u8(CTX + 0x990) end
local function foe_sides()
  local p, t = player_side(), {}
  for s = 0, MAX_SIDES - 1 do
    if s ~= p and side_alive(s) then t[#t + 1] = s end
  end
  return t
end
local function unit_side(side, k)
  local base = U + side * PB + k * STRIDE
  local id = memory.read_u16_le(base - 2)
  if id == 0 then return nil end
  local x, y = r8(base), r8(base + 1)
  if not (x > 0 and x < 64 and y > 0 and y < 64) then return nil end
  local d = db(id)
  return {
    side = side, idx = k, key = side * SLOTS + k, id = id,
    name = d and d.name or ("ID" .. id),
    x = x, y = y,
    fuel = r8(base + 2),
    exp = r8(base + 3),
    hp = r8(base + 4),
    maxhp = d and (d.dur * 4) or 0,
    ammo = r8(base + 6),
    st = r8(base + 5),
    acted = (r8(base + 5) % 2 == 1),
  }
end
local function all_units_side(side)
  local t = {}
  for k = 0, SLOTS - 1 do
    local u = unit_side(side, k)
    if u then t[#t + 1] = u end
  end
  return t
end
-- 旧接口：unit("MY",k)/all_units("MY") = 玩家阵营；"EN" = 全部敌对阵营（并集）
local function unit(side, k)
  if side == "MY" then return unit_side(player_side(), k) end
  if side == "EN" then
    local f = foe_sides()
    if not f[1] then return nil end
    return unit_side(f[1], k)
  end
  return unit_side(side, k)
end
local function all_units(side)
  if side == "EN" then
    local t = {}
    for _, s in ipairs(foe_sides()) do
      for k = 0, SLOTS - 1 do
        local u = unit_side(s, k)
        if u then t[#t + 1] = u end
      end
    end
    return t
  end
  local s = (side == "MY") and player_side() or side
  return all_units_side(s)
end

-- ============ 状态导出 ============
local myTurn = 1
local function build_state()
  local cx, cy = cur()
  local cell = terrain_at(cx, cy)
  local L = {}
  L[#L + 1] = string.format("step=%d turn=%d money=%d", step, r8(CTX + 0x20), memory.read_u32_le(CTX + 0x24))
  -- 天气：FUN_08030858 -> 表[(回合-1) % 8]，实现在 ROM 0x087A3944（8 项 u32）
  -- 伤害修正（FUN_08030644 地面部队分支）：1=100%，0/2=85%，3=70%
  local turnNow = memory.read_u8(CTX + 0x20)
  if turnNow < 1 then turnNow = 1 end
  local wt = memory.read_u32_le(0x087A3944 + ((turnNow - 1) % 8) * 4)
  L[#L + 1] = string.format("WEATHER %d", wt)
  L[#L + 1] = string.format("CURSOR %d,%d %s def+%d", cx, cy, tname(cell), tdef(cell))

  local my = all_units("MY")
  local en = all_units("EN")
  L[#L + 1] = string.format("MY %d", #my)
  for _, u in ipairs(my) do
    L[#L + 1] = string.format("U%d id%d %s x%d y%d hp%d/%d f%d st%d act%d ammo%d",
      u.idx, u.id, u.name, u.x, u.y, u.hp, u.maxhp, u.fuel, u.st, u.acted and 1 or 0, u.ammo)
  end
  L[#L + 1] = string.format("EN %d", #en)
  for _, u in ipairs(en) do
    L[#L + 1] = string.format("E%d id%d %s x%d y%d hp%d/%d f%d st%d act%d ammo%d side%d",
      u.idx, u.id, u.name, u.x, u.y, u.hp, u.maxhp, u.fuel, u.st, u.acted and 1 or 0, u.ammo, u.side or 1)
  end
  L[#L + 1] = "END"
  return table.concat(L, "\n") .. "\n"
end

-- ============ 界面操作 ============
-- 光标能动 = 已到可操作地图态（演出期间方向键无效）
local function mobile()
  local x0, y0 = cur()
  dir("Right"); adv(6)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then
    dir("Left"); adv(6)
    return true
  end
  return false
end

-- 清开场演出：A 推进直到光标可动
local function ensure_map()
  for i = 1, 12 do
    if mobile() then
      log("已在可操作地图态 (第" .. i .. "轮)")
      return true
    end
    log("演出中，按 A 推进 #" .. i)
    tap("A", 40)
  end
  log("!! 12 轮后光标仍不可动")
  return false
end

-- 退到地图（菜单/面板都用 B 退；B 在地图态无副作用）
local function to_map()
  for _ = 1, 4 do tap("B", 18) end
  adv(10)
end

-- 走到目标格：读光标闭环纠正（六角坐标增量不固定，必须闭环）
local function goto_cell(tx, ty, maxit)
  maxit = maxit or 90
  local lastx, lasty, still = -99, -99, 0
  for i = 1, maxit do
    local x, y = cur()
    if x == tx and y == ty then return true, i end
    if x == lastx and y == lasty then
      still = still + 1
      if still >= 3 then
        -- 脱困：四个方向各试一次，只要有一个能动就继续
        local moved = false
        for _, k in ipairs({ "Up", "Down", "Left", "Right" }) do
          local bx, by = cur()
          dir(k)
          local nx, ny = cur()
          if nx ~= bx or ny ~= by then moved = true; break end
        end
        still = 0
        if not moved then return false, i end
      end
    else
      still = 0
    end
    lastx, lasty = x, y

    local dx, dy = tx - x, ty - y
    local key
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then
      key = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then
      key = (dx > 0) and "Right" or "Left"
    else
      key = (dy > 0) and "Down" or "Up"
    end
    dir(key)

    -- 该轴卡住就换另一轴
    local nx, ny = cur()
    if nx == x and ny == y then
      local alt
      if dx ~= 0 then alt = (dx > 0) and "Right" or "Left"
      else alt = (dy > 0) and "Down" or "Up" end
      if alt and alt ~= key then dir(alt) end
    end
  end
  return false, maxit
end

-- ============ 指令执行 ============
local results = {}

-- 内存瞬移：同帧更新新旧占用格、单位坐标和光标。
-- 原脚本还写 ctx+0x990；该字段实际是玩家阵营，写单位槽会污染游戏。
-- 把光标拉回我方重心附近：选「离所有我方单位重心最近的那个单位」，
-- 点选单位时游戏从光标所在格的占用表读取槽号。
local function recenter()
  local sx, sy, n = 0, 0, 0
  for k = 0, 63 do
    if memory.read_u16_le(U + k * STRIDE - 2) ~= 0 then
      sx = sx + memory.read_u8(U + k * STRIDE)
      sy = sy + memory.read_u8(U + k * STRIDE + 1)
      n = n + 1
    end
  end
  if n == 0 then return end
  local mx, my = sx / n, sy / n
  local bk, bx, by, bd = -1, nil, nil, 1e9
  for k = 0, 63 do
    if memory.read_u16_le(U + k * STRIDE - 2) ~= 0 then
      local x = memory.read_u8(U + k * STRIDE)
      local y = memory.read_u8(U + k * STRIDE + 1)
      local d = math.abs(x - mx) + math.abs(y - my)
      if d < bd then bd, bk, bx, by = d, k, x, y end
    end
  end
  if bk < 0 then return end
  memory.write_u8(CTX + 0x637E, bx)
  memory.write_u8(CTX + 0x637F, by)
  -- ctx+0x990 是玩家势力索引，不是选中单位槽号，不能在此写 bk。
  adv(4)
end

local function teleport_mem(idx, tx, ty)
  local u = unit("MY", idx)
  if not u then return false, "单位槽 " .. idx .. " 为空" end
  local gx, gy = tx, ty
  if not (gx > 0 and gx < 48 and gy > 0 and gy < 48) then
    return false, string.format("目标 (%d,%d) 超出地图", tx, ty)
  end
  -- 目标格必须空（否则会覆盖别的单位）
  local occupied = memory.read_u8(CTX + 0x3F60 + tx * 4 + ty * 0xC0)
  if occupied ~= 0 and not (tx == u.x and ty == u.y) then
    return false, string.format("目标格 (%d,%d) 已被占", tx, ty)
  end

  -- 1) 清旧格
  local g1 = CTX + 0x3F60 + u.x * 4 + u.y * 0xC0
  memory.write_u8(g1, 0)
  memory.write_u8(g1 + 1, 0)
  -- 2) 写新格：阵营 1(蓝) + 槽号(idx+1, 1-based)
  local g2 = CTX + 0x3F60 + tx * 4 + ty * 0xC0
  memory.write_u8(g2, 1)
  memory.write_u8(g2 + 1, idx + 1)
  -- 3) 单位表坐标（U = 记录+2，所以 U+idx*24 就是 x）
  memory.write_u8(U + idx * STRIDE, tx)
  memory.write_u8(U + idx * STRIDE + 1, ty)
  -- 4) 同步光标；所属阵营和单位槽由游戏从占用格读取。
  memory.write_u8(CTX + 0x637E, tx)
  memory.write_u8(CTX + 0x637F, ty)
  -- ctx+0x990 是玩家势力索引，保持不变。

  adv(4)
  local u2 = unit("MY", idx)
  if u2 and u2.x == tx and u2.y == ty then
    return true, string.format("瞬移 U%d (%d,%d)->(%d,%d)", idx, u.x, u.y, tx, ty)
  end
  local p = u2 and string.format("(%d,%d)", u2.x, u2.y) or "消失"
  return false, string.format("瞬移校验失败，单位在 %s", p)
end

-- 按键版移动（保留作回退）：走菜单 + 寻路
local function move_by_keys(idx, tx, ty)
  local u = unit("MY", idx)
  if not u then return false, "单位槽 " .. idx .. " 为空" end
  to_map()
  local ok = goto_cell(u.x, u.y)
  if not ok then
    to_map()
    ok = goto_cell(u.x, u.y)
  end
  if not ok then
    local cx, cy = cur()
    return false, string.format("走不到单位格 (%d,%d)，光标卡在 (%d,%d)", u.x, u.y, cx, cy)
  end
  tap("A", 32); tap("A", 32); tap("A", 32)
  local ok2, it = goto_cell(tx, ty)
  if not ok2 then
    local cx, cy = cur()
    to_map()
    return false, string.format("寻路走不到 (%d,%d)，光标停在 (%d,%d)，走了 %d 步", tx, ty, cx, cy, it)
  end
  tap("A", 40); tap("A", 35)
  local u2 = unit("MY", idx)
  if u2 and u2.x == tx and u2.y == ty then
    return true, string.format("按键移动 U%d -> (%d,%d)", idx, tx, ty)
  end
  local p = u2 and string.format("(%d,%d)", u2.x, u2.y) or "消失"
  return false, string.format("移动校验失败，单位现在 %s", p)
end

local function exec_move(idx, tx, ty)
  local before = unit("MY", idx)
  if not before or before.hp == 0 then return false, "单位不存在或已被击毁" end
  if before.acted then return false, "该单位本回合已经行动" end
  -- 优先内存瞬移（快、不受地形/移动力限制）；失败再走按键
  local ok, msg = teleport_mem(idx, tx, ty)
  if ok then
    -- 补上游戏本会做的副作用：扣燃料 + 置已行动
    local u = unit("MY", idx)
    if u then
      local dq = (tx - math.floor(ty / 2)) - (before.x - math.floor(before.y / 2))
      local dr = ty - before.y
      local cost = math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr))
      local f = u.fuel - cost
      if f < 0 then f = 0 end
      memory.write_u8(U + idx * STRIDE + 2, f)      -- +2(相对U) = 记录+4 = 燃料
      memory.write_u8(U + idx * STRIDE + 5, (u.st or 0) | 1)  -- +5(相对U) = 记录+7 = 状态
    end
    return true, msg
  end
  log("瞬移失败(" .. msg .. ")，回退按键")
  local ok2, msg2 = move_by_keys(idx, tx, ty)
  return ok2, msg2
end

-- FUN_08002DC4 的真实六邻格：奇数行向右偏移，y 每格增减 1。
local function neighbors(x, y)
  local d = (y % 2 == 0) and -1 or 0
  return { {x+1,y}, {x-1,y}, {x+d,y-1}, {x+d+1,y-1},
           {x+d+1,y+1}, {x+d,y+1} }
end

-- 菜单文字由 ROM 图块直接复制到 OBJ VRAM；OAM 验证当前行确实可见，
-- 避免把关闭菜单后残留在 VRAM 的旧「攻击」误认作当前选项。
local menu_signatures = nil
local function tile_signature(addr)
  local bytes = {}
  for i = 0, 127 do bytes[#bytes + 1] = string.char(r8(addr + i)) end
  return table.concat(bytes)
end
local function read_unit_menu()
  if not menu_signatures then
    menu_signatures = {}
    for bank = 0, 1 do
      local base = (bank == 0) and 0x0806A830 or 0x0806B930
      for action = 0, 16 do
        menu_signatures[tile_signature(base + action * 0x100)] = {
          action = action, enabled = bank == 0,
        }
      end
    end
  end
  local rows = {}
  for row = 0, 16 do
    local o = 0x07000000 + (row + 2) * 8
    local a0 = memory.read_u16_le(o)
    local a1 = memory.read_u16_le(o + 2)
    local a2 = memory.read_u16_le(o + 4)
    if (a0 & 0xC000) ~= 0x4000 or (a1 & 0xC000) ~= 0x8000
        or (a2 & 0x3FF) ~= 0x228 + row * 8 then break end
    local entry = menu_signatures[tile_signature(0x06014500 + row * 0x100)]
    if not entry then return nil, "菜单图块无法识别，已取消操作" end
    rows[#rows + 1] = { row = row, action = entry.action, enabled = entry.enabled }
  end
  return rows
end

local function battle_result()
  if r8(CTX) ~= 8 and not (r8(CTX) == 7 and r8(CTX + 1) == 2) then return nil end
  local player = r8(CTX + 0x990)
  if player >= 4 then return nil end
  return r8(CTX + player * 12 + 0x2C)
end

-- 攻击：瞬移到目标邻格 → A 开菜单 → DOWN「攻撃」→ A 进入瞄准 → 方向瞄准 → A → A
-- 实测（logs/test_attack.txt）：M1A2 打 T-72B，敌 HP 12->8，我方 16->13（被反击）
local function exec_attack(idx, eidx)
  local u = unit("MY", idx)
  local e = unit("EN", eidx)
  if not u then return false, "我方槽 " .. idx .. " 为空" end
  if not e then return false, "敌方槽 " .. eidx .. " 为空" end
  if u.hp == 0 or u.acted then return false, "攻击单位已被击毁或本回合已行动" end
  if u.ammo == 0 then return false, "攻击单位弹药耗尽，需要补给" end
  if e.hp == 0 then return false, "目标已被击毁，等待游戏清理" end

  -- 1) 找一个空邻格
  local ax, ay
  for _, p in ipairs(neighbors(e.x, e.y)) do
    local px, py = p[1], p[2]
    if px > 0 and px < 48 and py > 0 and py < 48 then
      if memory.read_u8(CTX + 0x3F60 + px * 4 + py * 0xC0) == 0
          or (px == u.x and py == u.y) then
        ax, ay = px, py
        break
      end
    end
  end
  if not ax then return false, string.format("E%d 周围没有空位可站", eidx) end

  -- 2) 瞬移到位（会把光标和选中槽号一起设好）
  local okm, msgm = teleport_mem(idx, ax, ay)
  if not okm then return false, "无法到位：" .. msgm end
  adv(10)

  -- 3) 菜单：A → DOWN(攻撃) → A → 瞄准 → A → A
  tap("A", 38)
  local menu, menu_error = read_unit_menu()
  local attack_row = nil
  for _, entry in ipairs(menu or {}) do
    if entry.action == 1 and entry.enabled then attack_row = entry.row; break end
  end
  if attack_row == nil then
    to_map()
    return false, menu_error or "当前位置没有可用的直射攻击选项，需要检查射程或使用间接攻击"
  end
  for _ = 1, attack_row do tap("Down", 28) end
  tap("A", 38)      -- 进入瞄准态（光标变十字准星）
  -- 直接定位瞄准光标，确认前仍交给游戏自身验证射程和目标。
  memory.write_u8(CTX + 0x637E, e.x)
  memory.write_u8(CTX + 0x637F, e.y)
  adv(8)
  local aimx, aimy = cur()
  if aimx ~= e.x or aimy ~= e.y then
    to_map()
    return false, "瞄准光标未停在目标上，已取消攻击"
  end
  tap("A", 34)      -- 选定目标
  tap("A", 24)      -- 确认（演出已关，确认后约 20 帧结算）
  -- 自适应等待：敌方 HP 变化（或消失）就认为结算完
  local settled = false
  for _ = 1, 24 do
    adv(4)
    local now = unit("EN", eidx)
    if (not now) or now.hp ~= e.hp then settled = true; break end
  end
  adv(15)           -- 结算提示框稳定
  tap("A", 20)      -- 跳过余下提示
  adv(10)
  -- 击毁后还需关闭报告；最后一个敌人被删除时，A 接受投降，B 会拒绝。
  -- 只在游戏自身已把敌军槽清空后确认投降，不改动 HP 或胜负标志。
  for _ = 1, 30 do
    if battle_result() ~= nil then break end
    local now = unit("EN", eidx)
    if #all_units("EN") == 0 or (now and now.hp == 0) then
      tap("A", 30)
    else
      to_map()
      adv(35)
      break
    end
  end
  if not settled then
    log(string.format("警告：E%d HP 在 96 帧内未变化，可能未命中", eidx))
  end

  -- 4) 校验：目标 HP 是否下降
  local e2 = unit("EN", eidx)
  local me = unit("MY", idx)
  if not e2 then
    return true, string.format("击毁 E%d（由 U%d 攻击）", eidx, idx)
  end
  if e2.hp < e.hp then
    return true, string.format("攻击 E%d：HP %d->%d；U%d HP=%s",
      eidx, e.hp, e2.hp, idx, me and tostring(me.hp) or "?")
  end
  return false, string.format("攻击无效：E%d HP 仍 %d", eidx, e2.hp)
end

local function exec_endturn()
  to_map()
  tap("Start", 70)
  for _ = 1, 6 do tap("Up", 12) end   -- 回第一项「结束回合」
  tap("A", 70)                        -- 打开确认框
  tap("A", 90)                        -- 确认结束
  adv(200)

  -- 敌方回合：等回我方（光标可动）
  local back = false
  for i = 1, 14 do
    if mobile() then back = true; log("敌方回合结束 (第" .. i .. "轮)"); break end
    tap("A", 70)
    adv(60)
  end
  if back then
    myTurn = r8(CTX + 0x20)
    return true, "回合结束，进入第 " .. myTurn .. " 回合"
  end
  return false, "结束回合后未回到可操作态"
end

local function run_directive(line)
  local cmd, rest = line:match("^([A-Z_]+)%s*(.*)$")
  if not cmd then return end
  if cmd == "MOVE" then
    local idx, x, y = rest:match("(%d+)%s+(%d+)%s+(%d+)")
    if not idx then
      results[#results + 1] = "ERR MOVE 参数格式应为 MOVE <单位序号> <x> <y>"
      return
    end
    local ok, msg = exec_move(tonumber(idx), tonumber(x), tonumber(y))
    results[#results + 1] = (ok and "OK  " or "FAIL ") .. "MOVE " .. rest .. " | " .. msg
  elseif cmd == "ENDTURN" then
    local ok, msg = exec_endturn()
    results[#results + 1] = (ok and "OK  " or "FAIL ") .. "ENDTURN | " .. msg
  elseif cmd == "ATTACK" then
    local idx, eidx = rest:match("(%d+)%s+(%d+)")
    if not idx then
      results[#results + 1] = "ERR ATTACK 参数格式应为 ATTACK <我方槽> <敌方槽>"
    else
      local ok, msg = exec_attack(tonumber(idx), tonumber(eidx))
      results[#results + 1] = (ok and "OK  " or "FAIL ") .. "ATTACK " .. rest .. " | " .. msg
    end
  elseif cmd == "WAIT" or cmd == "NOOP" then
    results[#results + 1] = "OK  " .. cmd .. " | 原地不动"
  else
    results[#results + 1] = "ERR 未知指令 " .. cmd
  end
end


local RUN=BASE .. "shots/native_attack/"
local CAMPAIGN=1
local SAVE_PREFIX="stage1_v2"
local HOOK,CAVE,MAILBOX=0x08018AF4,0x0203FC00,0x0203FE00
local original={0x30,0xB5,0xE9,0xF7,0x79,0xFC,0x00,0x06}
local installed=false
local native_frames={}
local backup=nil
local stub=nil
local function writefile(path,text)
 local f=assert(io.open(path,"w")); f:write(text); f:close()
end
local function restore_keyboard()
 local n=0
 for addr=0x03000000,0x03007FFC,4 do
  if memory.read_u32_le(addr)==0x03007F00 then memory.write_u32_le(addr,0x04000130); n=n+1 end
 end
 if memory.read_u32_le(0x080015F4)==0x03007F00 then memory.write_u32_le(0x080015F4,0x04000130) end
 mailOK=false
 log("恢复原生键盘输入，IWRAM " .. n .. " 处")
end
local function uninstall()
 if not installed then return end
 assert(memory.read_u32_le(MAILBOX)~=2,"native call is still running")
 for i=1,8 do memory.write_u8(HOOK+i-1,original[i]) end
 for i=1,#backup do memory.write_u8(CAVE+i-1,backup[i]) end
 installed=false
 log("原生调用补丁已移除")
end
local function install()
 if installed then return end
 assert(r8(CTX)==7 and r8(CTX+1)==1 and r8(CTX+0x21)==3 and r8(CTX+0x22)==0,"not player map phase")
 for i=1,8 do assert(r8(HOOK+i-1)==original[i],"ROM entry differs from audited bytes") end
 local f=assert(io.open(BASE .. "lua/native_attack_stub.bin","rb")); stub=f:read("*a"); f:close()
 backup={}
 for i=0,0x23F do
  local b=r8(CAVE+i); assert(b==0,"EWRAM code/mailbox region is occupied"); backup[#backup+1]=b
 end
 for i=1,#stub do memory.write_u8(CAVE+i-1,stub:byte(i)) end
 for i=0,63 do memory.write_u8(MAILBOX+i,0) end
 memory.write_u16_le(HOOK,0x4B00); memory.write_u16_le(HOOK+2,0x4718)
 memory.write_u32_le(HOOK+4,CAVE+1)
 installed=true
 adv(8)
 log("已安装自然地图调用点 Thumb mailbox，" .. #stub .. " bytes")
end
local whitelist={ [0x08002E74]=true,[0x08023940]=true,[0x08023188]=true,[0x0801F078]=true,[0x0801F130]=true,[0x08016BE0]=true,[0x080169D4]=true,[0x08020B20]=true,[0x08020F14]=true }
local function native_call(addr,args,maxframes)
 assert(whitelist[addr],"function is not on audited whitelist")
 install()
 for i=1,#stub do assert(r8(CAVE+i-1)==stub:byte(i),"code cave changed") end
 assert(memory.read_u32_le(MAILBOX)~=2,"mailbox busy")
 memory.write_u32_le(MAILBOX+4,addr+1)
 for i=1,6 do memory.write_u32_le(MAILBOX+4+i*4,(args[i] or 0)&0xFFFFFFFF) end
 memory.write_u32_le(MAILBOX+32,0xDEADBEEF)
 memory.write_u32_le(MAILBOX,1)
 local start_frame=emu.framecount()
 local done=false
 for i=1,(maxframes or 1200) do
  adv(1)
  -- Last kill can open the native surrender confirmation before this call returns.
  -- Accept only during a battle with no surviving enemies, never during ordinary attacks.
  if addr==0x08023188 and i>120 and i%60==0 and #all_units("EN")==0 then
   log("SURRENDER confirming native last-enemy dialog")
   tap("A",20)
  end
  if memory.read_u32_le(MAILBOX)==3 then done=true; break end
 end
 assert(done,string.format("native call 0x%08X did not return; status=%d PC=0x%08X",addr,memory.read_u32_le(MAILBOX),emu.getregister("R15")))
 local before=memory.read_u32_le(MAILBOX+40)
 local after=memory.read_u32_le(MAILBOX+44)
 assert(before==after,"native call stack imbalance")
 assert(r8(CTX+0x990)==0,"player side changed")
 local value=memory.read_u32_le(MAILBOX+32)
 native_frames[addr]=emu.framecount()-start_frame
 log(string.format("CALL 0x%08X -> 0x%08X SP=0x%08X/0x%08X frames=%d",addr,value,before,after,native_frames[addr]))
 if value>=0x80000000 then value=value-0x100000000 end
 return value
end
local function distance(a,b)
 local dq=(a.x-math.floor(a.y/2))-(b.x-math.floor(b.y/2))
 local dr=a.y-b.y
 return math.max(math.abs(dq),math.abs(dr),math.abs(dq+dr))
end
 local function attack(idx,foe)
 -- foe: 目标单位表（带 side/idx）；也接受槽号（旧调用，默认第一个敌对阵营）
 if type(foe)~="table" then foe=unit("EN",foe) end
 assert(foe,"invalid target")
 local eidx,eside=foe.idx,foe.side
 assert(idx and idx>=0 and idx<64 and eidx>=0 and eidx<64,"slot out of bounds")
 local u,e=unit("MY",idx),unit(eside,eidx)
 assert(u and e and u.hp>0 and e.hp>0,"invalid unit/target")
 assert(not u.acted,"unit has already acted")
 memory.write_u8(CTX+0x637E,u.x); memory.write_u8(CTX+0x637F,u.y)
 native_call(0x080169D4,{u.x,u.y})
 native_call(0x08016BE0,{})
 local d=distance(u,e)
 local ur,er=U+idx*STRIDE-2,U+(eside or 1)*PB+eidx*STRIDE-2
 local classA=r8(0x08798A98+u.id*0x5C+4)
 local classB=r8(0x08798A98+e.id*0x5C+4)
 local wa=native_call(0x08023940,{ur,classB,d})
 local wb=native_call(0x08023940,{er,classA,d})
 assert(wa>=0 and wa<=3 and r8(ur+8+wa)>0,"no usable weapon in range")
 assert(r8(0x08798A98+u.id*0x5C+0x27+wa*16)~=4 or d>=2,"weapon minimum range is 2")
 if wb>=0 then assert(wb<=3 and r8(er+8+wb)>0,"invalid counter weapon") end
 if wb>=0 then assert(r8(0x08798A98+e.id*0x5C+0x27+wb*16)~=4 or d>=2,"counter weapon minimum range requires another weapon") end
 local ammoA,ammoB=r8(ur+8+wa),(wb>=0) and r8(er+8+wb) or -1
 log(string.format("DIRECT U%d -> E%d(side%d) distance=%d weapons=%d/%d HP=%d/%d",idx,eidx,eside,d,wa,wb,u.hp,e.hp))
 -- 灭国会放很长的演出（多阵营地图上常见）：预算放到 6000 帧再判超时
 native_call(0x08023188,{player_side(),idx,wa,eside,eidx,wb},6000)
 local now=unit("MY",idx)
 if now and now.hp>0 and r8(CTX)==7 and r8(CTX+1)==1 then
  native_call(0x0801F078,{0,idx,0})
  now=unit("MY",idx)
  if now and now.hp>0 then native_call(0x0801F130,{ur}) end
 end
 if r8(CTX)==7 and r8(CTX+1)==1 then native_call(0x08016BE0,{}) end
 adv(30)
 local a,b=unit("MY",idx),unit(eside,eidx)
 return string.format("DIRECT U%d E%d(side%d) | my HP %d->%d enemy HP %d->%d ammo %d->%d counter %d->%d acted=%s",
  idx,eidx,eside,u.hp,a and a.hp or 0,e.hp,b and b.hp or 0,ammoA,r8(ur+8+wa),ammoB,
  wb>=0 and r8(er+8+wb) or -1,tostring(a and a.acted))
end
local function animation(mode)
 local addr=CTX+0xC55
 local old=r8(addr)
 if mode=="ON" then memory.write_u8(addr,1)
 elseif mode=="OFF" then memory.write_u8(addr,0)
 elseif mode=="TOGGLE" then memory.write_u8(addr,(old==1) and 0 or 1)
 elseif mode~="STATUS" and mode~="" then error("ANIMATION ON|OFF|TOGGLE|STATUS") end
 local now=r8(addr)
 return string.format("ANIMATION %s address=0x%08X value=%d previous=%d",(now==1) and "ON" or "OFF",addr,now,old)
end
local function endturn()
 local oldturn=r8(CTX+0x20)
 uninstall()
 to_map()
 tap("Start", 70)
 for _=1,6 do tap("Up", 12) end
 tap("A", 70)
 tap("A", 90)
 adv(200)
 local back=false
 for i=1,80 do
  if r8(CTX)==8 then
   return r8(CTX+0x2C)==2,"ENDTURN result="..r8(CTX+0x2C)
  end
  if r8(CTX)==7 and r8(CTX+1)==1 and r8(CTX+0x21)==3
      and r8(CTX+0x20)>oldturn and r8(CTX+0x22)==0 and mobile() then back=true; break end
  tap("A", 70); adv(60)
 end
 if not back then return false,"结束回合后未回到新回合可操作态" end
 to_map(); adv(60)
 local msg=string.format("ENDTURN ok turn=%d enemies=%d", r8(CTX+0x20), #all_units("EN"))
 log(msg)
 return true,msg
end
local function hexd(ax,ay,bx,by)
 local dq=(ax-math.floor(ay/2))-(bx-math.floor(by/2))
 local dr=ay-by
 return math.max(math.abs(dq),math.abs(dr),math.abs(dq+dr))
end
local function free_cell_near(tx,ty,want)
 for yy=1,34 do
  for xx=1,46 do
   if hexd(xx,yy,tx,ty)==want and r8(CTX+0x3F60+xx*4+yy*0xC0)==0 then return xx,yy end
  end
 end
 return nil
end
-- ===== 移动共享件（vm 与 autoclear 共用，全逆向：FUN_08002964 + FUN_0801e33e@0x12）=====
local VMLAND_REFRESH=false   -- 落格后是否主动整屏刷新（false = 交给游戏自身渲染，避免画面跳动）
local function vm_ctx(k)
 local u=unit("MY",k)
 assert(u,"槽 "..k.." 无单位")
 assert(not u.acted,"已行动")
 local cat=r8(0x08798A98+u.id*0x5C+5)
 -- TSV 'move' is a movement CATEGORY, not the per-turn budget. ROM +0x0D is speed.
 local mv=r8(0x08798A98+u.id*0x5C+0x0D)
 return u,cat,math.min(mv,u.fuel)
end
local function vm_cost(terr,cat)
 if terr>=0x10 and terr<0x29 then return r8(0x08046FC6+(terr-0x10)+cat*5) end
 local c=r8(memory.read_u32_le(0x080026d4)+terr)
 if c==0 then return 0 end
 return r8(0x08046F26+c+cat*0x10)
end
local function vm_nbrs(x,y)
 local d=(y%2==0) and -1 or 0
 return {{x+1,y},{x-1,y},{x+d,y-1},{x+d+1,y-1},{x+d+1,y+1},{x+d,y+1}}
end
-- Dijkstra：友军可穿行不可落（用户确认），敌军阻挡，移耗 0=不可通行；dist["x,y"]=移耗
local function vm_reach(u,cat,budget)
 local dist,queue={},{ {u.x,u.y,0} }
 dist[u.x..","..u.y]=0
 while #queue>0 do
  table.sort(queue,function(a,b) return a[3]<b[3] end)
  local c=table.remove(queue,1)
  if c[3]==dist[c[1]..","..c[2]] then
   for _,n in ipairs(vm_nbrs(c[1],c[2])) do
    local nx,ny=n[1],n[2]
    if nx>=1 and nx<=46 and ny>=1 and ny<=34 then
     local occ=r8(CTX+0x3F60+nx*4+ny*0xC0)
     if occ==0 or occ==1 then
      local tc=vm_cost(terrain_at(nx,ny),cat)
      if tc==0 then tc=99 end
      local nc=c[3]+tc
      if nc<=budget and (dist[nx..","..ny]==nil or nc<dist[nx..","..ny]) then
       dist[nx..","..ny]=nc; queue[#queue+1]={nx,ny,nc}
      end
     end
    end
   end
  end
 end
 return dist
end
-- 落格字段写（复刻 0x12 分支：格表+记录+燃料+乘客联动+镜头重绘，不含置 acted）
local function vm_land(k,u,x,y,costc)
 local ur=U+k*STRIDE-2
 local g1=CTX+0x3F60+u.x*4+u.y*0xC0
 memory.write_u8(g1,0); memory.write_u8(g1+1,0)
 local g2=CTX+0x3F60+x*4+y*0xC0
 memory.write_u8(g2,1); memory.write_u8(g2+1,k+1)
 memory.write_u8(ur+2,x); memory.write_u8(ur+3,y)
 memory.write_u8(ur+4,u.fuel-costc)
 memory.write_u8(CTX+0x637E,x); memory.write_u8(CTX+0x637F,y)
 if bit.band(r8(ur+7),4)~=0 then
  for i=0,5 do
   local pid=r8(ur+12+i)
   if pid~=0 then
    local pr=CTX+pid*0x18-0x18+2
    memory.write_u8(pr,x); memory.write_u8(pr+1,y)
   end
  end
 end
 -- 注意：FUN_080169D4 / FUN_08016BE0 是整屏刷新包装（内含滚屏/淡入重置），
 -- 每移动一个单位调一次会让画面到处跳 → 默认不调，交给游戏自己的每帧渲染。
 if VMLAND_REFRESH then
  native_call(0x080169D4,{x,y})
  native_call(0x08016BE0,{})
 end
end
local function vm(k,x,y)
 local u,cat,budget=vm_ctx(k)
 assert(x>=1 and x<=46 and y>=1 and y<=34,"越界")
 local dist=vm_reach(u,cat,budget)
 local c=dist[x..","..y]
 assert(c, string.format("(%d,%d) 不在移动范围内（预算 %d）",x,y,budget))
 assert(r8(CTX+0x3F60+x*4+y*0xC0)==0,"目标格被占用（可穿不可停）")
 vm_land(k,u,x,y,c)
 native_call(0x0801F130,{U+k*STRIDE-2})
 local u2=unit("MY",k)
 assert(u2 and u2.x==x and u2.y==y,"落点读回失败")
 return string.format("VM 槽%d(id%d) 落点(%d,%d) 移耗%d 燃料%d->%d acted=1",
  k,u.id,x,y,c,u.fuel,u2.fuel)
end
-- ===== 占领（行动分派 0x22 分支 → FUN_08020b20(side, slot)）=====
-- 可占领地形判定 = FUN_080026d8: (terr-0x10) < 0x19 → 0x10..0x28 全部建筑类
local function terr_base() return memory.read_u32_le(CTX + 0x18) end
local function capturable(x,y)
 local t=r8(terr_base()+x*4+y*0xC0)
 return t>=0x10 and t<=0x28
end
local function cap(k)
 local u=unit("MY",k); assert(u,"槽 "..k.." 无单位")
 assert(not u.acted,"已行动")
 assert(u.id==305 or u.id==324,"当前接口仅验证步兵/空降兵占领")
 assert(capturable(u.x,u.y), string.format("(%d,%d) 地形不可占领",u.x,u.y))
 local cb=terr_base()+u.x*4+u.y*0xC0
 local ob,mb=r8(cb+2),memory.read_u32_le(CTX+0x24)
 assert(ob~=player_side()+1,"已经是我方建筑")
 native_call(0x08020B20,{player_side(),k})  -- 占領：归属翻转 + 收入 + 首都胜利判定
 adv(3)
 local oa,ma=r8(cb+2),memory.read_u32_le(CTX+0x24)
 if r8(CTX)==7 and r8(CTX+1)==1 then native_call(0x0801F130,{U+k*STRIDE-2}) end
 local msg=string.format("CAP 槽%d 占領(%d,%d) 归属%d->%d 资金%d->%d state=%d/%d",
  k,u.x,u.y,ob,oa,mb,ma,r8(CTX),r8(CTX+1))
 log(msg)
 return msg
end
local function commander()
 return string.format("rank=%d points=%d money=%d state=%d",r8(CTX+0x65),memory.read_u32_le(CTX+0x6C),memory.read_u32_le(CTX+0x68),r8(CTX))
end
local function settle_result(previous_points,previous_rank)
 assert(r8(CTX)==8 and r8(CTX+0x2C)==2,"not a victory result")
 local credited_at=nil
 for i=1,12000 do
  adv(1)
  if r8(CTX+0x65)>previous_rank then
   adv(90)
   client.screenshot(BASE.."shots/farm_rank_promotion.png")
   savestate.save(BASE.."states/farm_rank_promotion.State")
   log("PROMOTED "..commander())
   return true
  end
  if memory.read_u32_le(CTX+0x6C)>previous_points then
   credited_at=credited_at or i
   if i-credited_at>=400 then log("CREDITED "..commander()); return false end
  end
 end
 error("native result points have not been credited; "..commander())
end
local function replay_first(speed)
 uninstall(); client.speedmode(tonumber(speed) or 400)
 assert(r8(CTX)==8 and r8(CTX+0x2C)==2,"REPLAYFIRST needs the previous victory")
 local points,rank=memory.read_u32_le(CTX+0x6C),r8(CTX+0x65)
 savestate.save(BASE.."states/farm_before_reentry.State")
 for i=1,16 do
  if r8(CTX)==3 then break end
  tap("A",50); if r8(CTX)==3 then break end
  tap("B",50); if r8(CTX)==3 then break end
  tap("A",100)
 end
 assert(r8(CTX)==3,"could not leave the result page; "..commander())
 local selected=false
 for i=1,48 do
  tap("A",100)
  if r8(CTX)==4 then
   local p=memory.read_u32_le(CTX+0x14); local same=true
   for j=0,15 do if r8(p+j)~=r8(0x08762B10+j) then same=false end end
   if same then selected=true; break end
   tap("B",50); tap("Up",25)
  elseif r8(CTX)==3 then log("FARM SELECT dismissed scenario-list instructions")
  else error("unexpected scenario selection state "..r8(CTX)) end
 end
 assert(selected,"could not select Military Exercise 1")
 tap("A",100); assert(r8(CTX)==6,"not in deployment dialog")
 local wanted={[187]=9,[241]=4,[305]=4,[324]=2,[339]=1}
 local old,counts,empty={},{},{}
 for k=0,98 do
  local a=CTX+0x188+k*4; local id=memory.read_u16_le(a)
  if id==0 then empty[#empty+1]=k
  else
   assert(wanted[id],"unexpected inherited type "..id)
   counts[id]=(counts[id] or 0)+1
   old[#old+1]={slot=k,id=id,exp=r8(a+2)}
  end
 end
 local additions={}; local cost=0
 for _,id in ipairs({187,241,305,324,339}) do
  assert((counts[id] or 0)<=wanted[id],"inherited army exceeds plan")
  for _=1,wanted[id]-(counts[id] or 0) do
   additions[#additions+1]=id
   cost=cost+memory.read_u16_le(0x08798A98+id*0x5C+0x1A)
  end
 end
 local money=memory.read_u32_le(CTX+0x68)
 assert(#old+#additions==20 and #empty>=#additions and money>=cost,"cannot replenish inherited army")
 for i,id in ipairs(additions) do
  local a=CTX+0x188+empty[i]*4
  memory.write_u16_le(a,id); memory.write_u8(a+2,0); memory.write_u8(a+3,0)
 end
 memory.write_u32_le(CTX+0x68,money-cost)
 log(string.format("FARM REPLENISH veterans=%d added=%d cost=%d points=%d rank=%d",#old,#additions,cost,points,rank))
 savestate.save(BASE.."states/farm_stage1_army_ready.State")
 local deployed=false
 for trial=1,2 do
  savestate.load(BASE.."states/farm_stage1_army_ready.State"); adv(15); restore_keyboard()
  tap("A",180)
  if trial==1 then tap("A",40) end
  for i=1,20 do tap("A",35); if i<20 then tap("Down",35) end end
  tap("Start",90); tap("A",120); adv(500)
  if #all_units("MY")==20 then deployed=true; break end
 end
 assert(deployed,"could not deploy all inherited/replenished units")
 for _,v in ipairs(old) do
  local a=CTX+0x188+v.slot*4; local k=r8(a+3)%100-1
  assert(k>=0 and k<64,"missing deployment association")
  local record=U-2+k*STRIDE
  assert(memory.read_u16_le(record)==v.id and r8(record+5)==v.exp,"veteran experience was not preserved")
 end
 tap("Start",90); tap("A",120)
 local ready=false
 for i=1,30 do
  adv(60)
  if r8(CTX)==7 and r8(CTX+1)==1 and r8(CTX+0x21)==3 and r8(CTX+0x22)==0 then ready=true; break end
  tap("A",40)
 end
 assert(ready,"replay did not enter player phase")
 tap("B",40)
 assert(memory.read_u32_le(CTX+0x6C)==points and r8(CTX+0x65)==rank,"commander progress changed during replay setup")
 savestate.save(BASE.."states/farm_stage1_deployed.State")
 log("FARM REPLAY READY "..commander())
 return "OK REPLAYFIRST "..commander()
end
local function autoclear(speed)
 -- ===== 武器表（ROM 实测：DB=0x08798AF4，槽 i = base+(id-1)*0x5C+0x18+i*0x10）=====
 -- 槽+0xD=最大射程, 槽+8+目标类别=攻击力(类别=敌 entry+4)，弹药=单位记录+8+i
 local DB=0x08798AF4
 local function wslot(id,wa) return DB+(id-1)*0x5C+0x18+wa*0x10 end
 local function tcls(id) return r8(DB+(id-1)*0x5C+4) end
 local function uammo(k,wa) return r8(U+k*STRIDE-2+8+wa) end
 -- ===== 战术 =====
 client.speedmode(tonumber(speed) or 800)
 local initial_points,initial_rank=memory.read_u32_le(CTX+0x6C),r8(CTX+0x65)
 local report={}
 local function progress()
  writefile(RUN.."state.txt",build_state()..string.format("CTX state=%d sub=%d result=%d animation=%d\n",r8(CTX),r8(CTX+1),r8(CTX+0x2C),r8(CTX+0xC55)))
  client.screenshot(RUN.."current.png")
 end
 local function finish(reason)
  uninstall()
  for i=1,160 do
   if r8(CTX)==8 then break end
   adv(20)
   if i%5==0 then tap("A",20) end
  end
  adv(600) -- Let the flag intro reach the visible victory title before freezing the bridge.
  if r8(CTX)==8 and r8(CTX+0x2C)==2 then settle_result(initial_points,initial_rank) end
  progress()
  client.speedmode(100)
  if r8(CTX)~=8 or r8(CTX+0x2C)~=2 then
   return string.format("FAIL 结算未确认胜利 state=%d/%d result=%d",r8(CTX),r8(CTX+1),r8(CTX+0x2C))
  end
  savestate.save(BASE.."states/"..SAVE_PREFIX.."_victory.State")
  client.screenshot(BASE.."shots/"..SAVE_PREFIX.."_victory.png")
  local report_prefix=(SAVE_PREFIX:match("^farm_") or SAVE_PREFIX:match("^current_")) and SAVE_PREFIX or (CAMPAIGN==2 and "stage2" or "stage1")
  writefile(BASE.."logs/"..report_prefix.."_battle_report.txt",table.concat(report,"\n"))
  local msg=string.format("VICTORY %s turn=%d friendly=%d enemies=%d result=2",reason,r8(CTX+0x20),#all_units("MY"),#all_units("EN"))
  msg=msg.." "..commander(); log(msg)
  return msg
 end
 local function markacted(k)
  local u=unit("MY",k)
  if u and not u.acted then native_call(0x0801F130,{U+k*STRIDE-2}) end
 end
 local function best_reach_cell(reach,e,want)
  -- 从可达集中选 dist==want、空置、防御最高的落点
  local bx,by,bs=nil,nil,-1e9
  for key in pairs(reach) do
   local xx,yy=key:match("(-?%d+),(-?%d+)")
   xx,yy=tonumber(xx),tonumber(yy)
   if hexd(xx,yy,e.x,e.y)==want and r8(CTX+0x3F60+xx*4+yy*0xC0)==0 then
     local t=tdef(terrain_at(xx,yy))*100-reach[key]*2-yy*0.01-xx*0.0001
    if t>bs then bs,bx,by=t,xx,yy end
   end
  end
  return bx,by
 end
 local function route_field(e,pref,cat)
  local costs,queue={},{}
  for y=1,34 do for x=1,46 do
   if hexd(x,y,e.x,e.y)==pref and vm_cost(terrain_at(x,y),cat)>0
       and r8(CTX+0x3F60+x*4+y*0xC0)<=1 then
    costs[x..","..y]=0; queue[#queue+1]={x,y,0}
   end
  end end
  local head=1
  while head<=#queue do
   local node=queue[head]; head=head+1
   local key=node[1]..","..node[2]
   if costs[key]==node[3] then
    local step_cost=vm_cost(terrain_at(node[1],node[2]),cat)
    for _,n in ipairs(vm_nbrs(node[1],node[2])) do
     local x,y=n[1],n[2]
     if x>=1 and x<=46 and y>=1 and y<=34 and vm_cost(terrain_at(x,y),cat)>0
         and r8(CTX+0x3F60+x*4+y*0xC0)<=1 then
      local nk=x..","..y; local candidate=node[3]+step_cost
      if not costs[nk] or candidate<costs[nk] then
       costs[nk]=candidate; queue[#queue+1]={x,y,candidate}
      end
     end
    end
   end
  end
  return costs
 end
 local function best_advance_cell(reach,e,pref,cat)
  -- 无攻击方案时：可达集中逼近本兵种最优交战距离、防御最高的推进点
  local bx,by,bs,bd=nil,nil,-1e9,nil
  local routes=(CAMPAIGN~=1) and route_field(e,pref,cat) or nil
  for key in pairs(reach) do
   local xx,yy=key:match("(-?%d+),(-?%d+)")
   xx,yy=tonumber(xx),tonumber(yy)
   if r8(CTX+0x3F60+xx*4+yy*0xC0)==0 then
    local dd=hexd(xx,yy,e.x,e.y)
    local remaining=math.abs(dd-pref)
    if routes then remaining=routes[key] end
    local sc=remaining and (-remaining*100+tdef(terrain_at(xx,yy))) or -1e10
    if CAMPAIGN~=1 then sc=sc-reach[key]*0.1-yy*0.001-xx*0.00001 end
    if sc>bs then bs,bx,by,bd=sc,xx,yy,dd end
   end
  end
  return bx,by,bd
 end
 local function my_best(u,dist,eid)
  -- 我方对 eid 的最佳可用攻击力（考虑弹药/射程）
  local cls=tcls(eid)
  local best=-1
  for wa=0,3 do
   if uammo(u.idx,wa)>0 then
    local a=r8(wslot(u.id,wa)+8+cls)
    local mr=r8(wslot(u.id,wa)+13)
    if a>0 and dist<=mr and a>best then best=a end
   end
  end
  return best
 end
 local function enemy_counter(e,myid,dist)
  local cls=tcls(myid)
  local best=0
  for wa=0,3 do
   local ammo=r8(U+(e.side or 1)*PB+e.idx*STRIDE-2+8+wa)
   if ammo>0 then
    local a=r8(wslot(e.id,wa)+8+cls)
    local mr=r8(wslot(e.id,wa)+13)
    if a>best and dist<=mr then best=a end
   end
  end
  return best
 end
 -- Approximate native attack/defence ratio (FUN_08020010/2008C/20220).
 -- Actual HP, ammo and kills are always read back after the real battle.
 local function estimate(att,def,power,x,y)
  if power<=0 then return 0 end
  local ab=DB+(att.id-1)*0x5C
  local bb=DB+(def.id-1)*0x5C
  local ac=math.ceil(att.hp/math.max(1,r8(ab+0x0E)))
  local dc=math.ceil(def.hp/math.max(1,r8(bb+0x0E)))
  local armour=r8(bb+0x14+tcls(att.id))+tdef(terrain_at(x or def.x,y or def.y))
  local weather=(r8(CTX+0x23)==3) and 0.7 or ((r8(CTX+0x23)==1) and 1 or 0.85)
  return math.max(0,math.floor(4*power*ac*weather/math.max(1,armour*dc)))
 end
 local function tb() return memory.read_u32_le(CTX+0x18) end
 local function on_building(x,y)
  local t=r8(tb()+x*4+y*0xC0)
  return t>=0x10 and t<=0x28
 end
 local function enemy_capitals()
  -- 敌方各阵营的首都（归属 != 我方），多阵营下一个都不漏
  local b,out=tb(),{}
  for y=1,46 do
   for x=1,46 do
    local c=b+x*4+y*0xC0
    if r8(c)==0x10 then
     local o=r8(c+2)
     if o>=1 and o~=player_side()+1 then out[#out+1]={x=x,y=y,owner=o} end
    end
   end
  end
  return out
 end
 local function enemy_capital()
  local caps=enemy_capitals()
  if caps[1] then return caps[1].x,caps[1].y end
 end
 local function is_capturer(id) return id==305 or id==324 end
-- current_tactics2.lua —— 接管当前战局的 v2 战术（多阵营 + 城市补给）
--
-- 逆向依据（2026-10-18 实测/反编译）：
--  * 势力数上限 4。单位为 ctx+0x2760+side*0x600，stride 0x18。
--  * 阵营记录 ctx+0x24+side*0xC：+0 资金(u32)，+4 状态（1..3=参战，FUN_080023c4）。
--  * 玩家阵营 = ctx+0x990；格表 +0 = 阵营+1。
--  * 战斗结算 FUN_08023188(我方阵营, 槽, 武器, 敌方阵营, 敌槽, 反击武器) —— 目标阵营是明文参数，
--    旧桥把它写死成 1，所以只认一个敌人。
--  * **城市补给**：势力回合开始时，站在「地形 ∈ {0x10 首都, 0x11 市街, 0x14 村落} 且归属=自己」
--    的单位 HP/燃料/弹药 全部补满（25 种建筑矩阵实测）。
local cs_player = player_side()
local cs_owner = cs_player + 1
local CS_SUPPLY = { [0x10] = true, [0x11] = true, [0x14] = true }

local function cs_side_of_unit(u) return u.side or cs_player end
local function cs_is_foe_side(s) return s ~= cs_player and side_alive(s) end
local function cs_supply_cell(x, y)
 return CS_SUPPLY[terrain_at(x, y)] and r8(tb() + x * 4 + y * 0xC0 + 2) == cs_owner
end
local function cs_ammo_total(k)
 local n = 0
 for wa = 0, 3 do n = n + r8(U + k * STRIDE - 2 + 8 + wa) end
 return n
end
local function cs_armed(u)
 -- 还有弹药（任一武器槽 > 0）就能开火
 for wa = 0, 3 do
  if r8(U + u.idx * STRIDE - 2 + 8 + wa) > 0 then return true end
 end
 return false
end
local function cs_needs_supply(u)
 if u.maxhp > 0 and u.hp <= u.maxhp * 0.7 then return true end
 if u.fuel <= 12 then return true end
 if not cs_armed(u) then return true end
 return false
end

local current_orders, current_previous_en, current_capture_jobs = {}, {}, {}
local current_routes, current_my_cities, current_my_capital = {}, {}, nil
local current_foes = {}

local function cs_friendly_city(x, y)
 return cs_supply_cell(x, y)
end
local function cs_danger(u, x, y, en)
 local risk = 0
 for _, e in ipairs(en) do
  local d = hexd(x, y, e.x, e.y)
  -- 保守估计：敌方整条移动力预算 + 武器射程
  local mv = r8(0x08798A98 + e.id * 0x5C + 0x0D)
  local power = enemy_counter(e, u.id, math.max(1, d - math.min(mv, e.fuel or 0)))
  if power > 0 then
   local hit = estimate(e, u, power, x, y)
   risk = risk + hit * (enemy_counter(e, u.id, d) > 0 and 1 or 0.4)
  end
 end
 return risk
end
-- 我方最靠近的家（首都优先）：取代旧代码里写死的 (21,30)
local function cs_home_distance(x, y)
 if current_my_capital then return hexd(x, y, current_my_capital.x, current_my_capital.y) end
 local best = 99
 for _, c in ipairs(current_my_cities) do best = math.min(best, hexd(x, y, c.x, c.y)) end
 return best
end
local function cs_guard(u, en)
 return terrain_at(u.x, u.y) == 0x10 and r8(tb() + u.x * 4 + u.y * 0xC0 + 2) == cs_owner
end
local function cs_near_supply(k, u, reach)
 -- 本回合结束时能否站在自家补给点上（含原地）
 if cs_supply_cell(u.x, u.y) then return true end
 for key in pairs(reach) do
  local x, y = key:match("(%-?%d+),(%-?%d+)")
  x, y = tonumber(x), tonumber(y)
  if x and cs_supply_cell(x, y) then return true end
 end
 return false
end
local function cs_hold(u, en)
 -- 首都守卫永不擅自离岗
 if cs_guard(u, en) then return true, "capital_garrison" end
 if current_orders[u.idx] and current_orders[u.idx].kind == "intercept" then return false end
 local on_supply = cs_supply_cell(u.x, u.y)
 if on_supply then
  local risk = cs_danger(u, u.x, u.y, en)
  if risk >= u.hp * 0.9 then return false end
  -- 站在自家补给点上且需要补给 → 原地待机，下回合补满
  if cs_needs_supply(u) then return true, "resupply_in_city" end
 end
 if not on_supply then return false end
 for _, e in ipairs(en) do
  local d = hexd(u.x, u.y, e.x, e.y)
  if d <= 6 and (enemy_counter(e, u.id, 1) > 0 or my_best(u, d, e.id) > 0) then
   return true, "hold_frontline_city"
  end
 end
 return false
end
local function cs_hold_action(k, u, en, reason)
 local target, score = nil, -1e9
 for _, e in ipairs(en) do
  local d = hexd(u.x, u.y, e.x, e.y)
  local hit = estimate(u, e, my_best(u, d, e.id))
  local loss = estimate(e, u, enemy_counter(e, u.id, d), u.x, u.y)
  if hit > 0 and loss < u.hp * 0.6 then
   local value = math.min(hit, e.hp) * 16 - loss * 20 + (hit >= e.hp and 180 or 0)
   if value > score then target, score = e, value end
  end
 end
 if target then
  local ok, msg = pcall(attack, k, target)
  log(string.format("HOLD U%d %s attack=E%d(side%d) %s %s", k, reason, target.idx, target.side,
   tostring(ok), tostring(msg)))
  if r8(CTX) == 8 or #all_units("EN") == 0 then return end
 end
 markacted(k)
 log(string.format("HOLD U%d %s hp=%d/%d fuel=%d at=%d,%d", k, reason, u.hp, u.maxhp, u.fuel, u.x, u.y))
end

local function current_begin_round()
 current_routes, current_my_cities = {}, {}
 current_my_capital = nil
 for y = 1, 46 do
  for x = 1, 46 do
   if cs_supply_cell(x, y) then
    current_my_cities[#current_my_cities + 1] = { x = x, y = y, capital = terrain_at(x, y) == 0x10 }
    if terrain_at(x, y) == 0x10 and not current_my_capital then
     current_my_capital = { x = x, y = y }
    end
   end
  end
 end
 current_foes = {}
 for s = 0, 3 do
  if cs_is_foe_side(s) then current_foes[#current_foes + 1] = s end
 end
 log(string.format("SIDES player=%d foes=[%s] my_supply_cities=%d", cs_player,
  table.concat(current_foes, ","), #current_my_cities))
end
local function current_route(goal, pref, cat)
 local key = goal.x .. "," .. goal.y .. "," .. pref .. "," .. cat
 if not current_routes[key] then current_routes[key] = route_field(goal, pref, cat) end
 return current_routes[key]
end

-- 守住自家补给城市（首都优先）；被威胁的城市再加一个预备队
local function current_defend_capitals()
 local en = all_units("EN")
 local assigned = {}
 local queue = {}
 for _, c in ipairs(current_my_cities) do
  if c.capital then queue[#queue + 1] = c end
 end
 for _, c in ipairs(current_my_cities) do
  if not c.capital then queue[#queue + 1] = c end
 end
 for _, capital in ipairs(queue) do
  local threatened = false
  for _, e in ipairs(en) do
   local speed = math.min(r8(0x08798A98 + e.id * 0x5C + 0x0D), e.fuel or 0)
   local reach = capital.capital and math.max(10, speed + 3) or math.max(4, speed)
   if hexd(e.x, e.y, capital.x, capital.y) <= reach then threatened = true; break end
  end
  local occupied = r8(CTX + 0x3F60 + capital.x * 4 + capital.y * 0xC0) == cs_owner
  local roles = occupied and (threatened and { 1, 2, 3 } or { 1, 2 }) or (threatened and { 0, 1, 2, 3 } or { 0, 1, 2 })
  for _, pref in ipairs(roles) do
   local chosen, best = nil, 1e30
   for _, u in ipairs(all_units("MY")) do
    local grid = CTX + 0x3F60 + u.x * 4 + u.y * 0xC0
    if not u.acted and u.hp > 0 and not assigned[u.idx] and not cs_guard(u, en)
        and not (u.id >= 339 and u.id <= 345) and r8(grid) == cs_owner and r8(grid + 1) == u.idx + 1 then
     local _, cat, budget = vm_ctx(u.idx)
     local routes = current_route(capital, pref, cat)
     local distance = routes[u.x .. "," .. u.y]
     if distance and (distance == 0 or budget > 0) then
      local ratio = u.hp / math.max(1, u.maxhp)
      local armed = cs_armed(u)
      local score = distance * 10 + (1 - ratio) * 30 + (armed and 0 or 100) + (is_capturer(u.id) and 150 or 0)
      if score < best then chosen, best = u, score end
     end
    end
   end
   if chosen then
    assigned[chosen.idx] = true
    local _, cat, budget = vm_ctx(chosen.idx)
    local reach = vm_reach(chosen, cat, budget)
    local routes = current_route(capital, pref, cat)
    local bx, by, bs = chosen.x, chosen.y, -1e30
    for key, cost in pairs(reach) do
     local x, y = key:match("(%d+),(%d+)"); x, y = tonumber(x), tonumber(y)
     if routes[key] and ((x == chosen.x and y == chosen.y) or r8(CTX + 0x3F60 + x * 4 + y * 0xC0) == 0) then
      local score = -routes[key] * 100 - cs_danger(chosen, x, y, en) * 4 - cost
      if routes[key] == 0 then score = score + 1000 end
      if cs_supply_cell(x, y) then score = score + 120 end
      if score > bs then bx, by, bs = x, y, score end
     end
    end
    local ok, msg = true, "hold"
    local moved = bx ~= chosen.x or by ~= chosen.y
    if moved then ok, msg = pcall(vm_land, chosen.idx, chosen, bx, by, reach[bx .. "," .. by]) end
    if ok then
     if not moved then cs_hold_action(chosen.idx, chosen, en, "capital_reserve")
     else markacted(chosen.idx) end
    end
    log(string.format("DEFEND city=%d,%d U%d role=%s destination=%d,%d ok=%s %s",
     capital.x, capital.y, chosen.idx, pref == 0 and "garrison" or "reserve", bx, by, tostring(ok), tostring(msg)))
    if r8(CTX) == 8 or #all_units("EN") == 0 then return end
   else
    log(string.format("DEFEND WARNING city=%d,%d no available %s", capital.x, capital.y,
     pref == 0 and "garrison" or "reserve"))
   end
  end
 end
end

local function current_advance(k, u, reach, cat, en)
 local risks = {}
 local function risk_at(x, y)
  local key = x .. "," .. y
  if risks[key] == nil then risks[key] = cs_danger(u, x, y, en) end
  return risks[key]
 end
 local capturer = is_capturer(u.id)
 local needy = cs_needs_supply(u)
 local start_risk = risk_at(u.x, u.y)
 local retreat = start_risk >= u.hp * 0.9
 local goals = {}
 -- 目标一：自家补给城市（缺编/LV低时优先回去补）
 for _, c in ipairs(current_my_cities) do
  local occ = r8(CTX + 0x3F60 + c.x * 4 + c.y * 0xC0)
  if occ == 0 or (c.x == u.x and c.y == u.y) then
   local risk = risk_at(c.x, c.y)
   if risk < u.hp * 0.8 or (c.x == u.x and c.y == u.y) then
    local value = hexd(u.x, u.y, c.x, c.y) + (risk / math.max(1, u.hp)) * 8
    if c.capital then value = value - 4 end
    goals[#goals + 1] = { x = c.x, y = c.y, pref = 0, value = value,
     kind = needy and "resupply" or "defend_city" }
   end
  end
 end
 -- 目标二：可占领的敌/中立建筑（能占领到的补给地形价值最高：占下来就是补给站）
 for y = 1, 46 do
  for x = 1, 46 do
   if on_building(x, y) then
    local owner = r8(tb() + x * 4 + y * 0xC0 + 2)
    local occ = r8(CTX + 0x3F60 + x * 4 + y * 0xC0)
    if capturer and (occ == 0 or (x == u.x and y == u.y)) and owner ~= cs_owner and not needy then
     local risk = risk_at(x, y)
     if risk < u.hp * 0.7 then
      local value = hexd(u.x, u.y, x, y) + (risk / math.max(1, u.hp)) * 8
      local terr = terrain_at(x, y)
      if CS_SUPPLY[terr] then value = value - 14 end     -- 补给建筑优先占
      if terr == 0x10 then value = value - 2 end          -- 敌首都（胜利条件）
      goals[#goals + 1] = { x = x, y = y, pref = 0, value = value, kind = "capture" }
     end
    end
   end
  end
 end
 if needy or retreat then
  local supply = {}
  for _, goal in ipairs(goals) do
   if goal.kind == "resupply" then supply[#supply + 1] = goal end
  end
  if #supply > 0 then goals = supply end
 end
 -- 目标三：向我方能打的敌人靠拢（多阵营一起考虑）
 if not needy and not retreat then
  for _, e in ipairs(en) do
   local pref, armed = 1, false
   for d = 3, 1, -1 do if my_best(u, d, e.id) > 0 then pref, armed = d, true; break end end
   if armed or not capturer then
    goals[#goals + 1] = { x = e.x, y = e.y, pref = armed and pref or 4,
     value = hexd(u.x, u.y, e.x, e.y) + (armed and 8 or 18), kind = armed and "engage" or "support" }
   end
  end
 end
 local order = current_orders[k]
 if order and (not needy and not retreat or order.kind == "intercept") then goals = { order } end
 table.sort(goals, function(a, b) return a.value < b.value end)
 local bx, by, best, bwhy = nil, nil, -1e30, "no_route"
 local cells = {}
 for key, cost in pairs(reach) do cells[key] = cost end
 cells[u.x .. "," .. u.y] = 0
 local reachable_goals = 0
 for i = 1, #goals do
  local goal = goals[i]; local routes = current_route(goal, goal.pref, cat)
  local initial = routes[u.x .. "," .. u.y]
  if initial then
   reachable_goals = reachable_goals + 1
   for key, cost in pairs(cells) do
    local x, y = key:match("(%d+),(%d+)"); x, y = tonumber(x), tonumber(y)
    local remaining = routes[key]
    local same = x == u.x and y == u.y
    if remaining and (same or r8(CTX + 0x3F60 + x * 4 + y * 0xC0) == 0) then
     local risk = risk_at(x, y)
     if risk < u.hp * 0.9 or risk < start_risk * 0.7 then
      local score = (initial - remaining) * 35 - goal.value * 8 - risk * 18 + tdef(terrain_at(x, y)) - cost * 0.2
      if cs_supply_cell(x, y) then
       -- 结束在自家补给点上：下一回合 HP/燃料/弹药全补满
       score = score + (needy and 260 or 45)
      end
      if not same and cs_supply_cell(u.x, u.y) and not needy then score = score - 25 end
      if remaining == 0 and goal.kind == "capture" then score = score + 160 end
      if remaining == 0 and goal.kind == "resupply" then score = score + 200 end
      if remaining == 0 and goal.kind == "defend_city" then score = score + 120 end
      if score > best then bx, by, best, bwhy = x, y, score, goal.kind end
     end
    end
   end
  end
  if reachable_goals >= 8 then break end
 end
 if not bx then
  for key, cost in pairs(cells) do
   local x, y = key:match("(%d+),(%d+)"); x, y = tonumber(x), tonumber(y)
   if (x == u.x and y == u.y) or r8(CTX + 0x3F60 + x * 4 + y * 0xC0) == 0 then
    local score = -risk_at(x, y) * 18 + tdef(terrain_at(x, y)) - cost
    if cs_supply_cell(x, y) then score = score + 80 end
    if score > best then bx, by, best, bwhy = x, y, score, "cover" end
   end
  end
 end
 local moved = bx and (bx ~= u.x or by ~= u.y)
 if moved then
  local ok, msg = pcall(vm_land, k, u, bx, by, cells[bx .. "," .. by])
  log(string.format("ADVANCE U%d %s %d,%d->%d,%d ok=%s %s", k, bwhy, u.x, u.y, bx, by, tostring(ok), tostring(msg)))
  if not ok then return end
 end
 local now = unit("MY", k)
 if now and capturer and on_building(now.x, now.y) and r8(tb() + now.x * 4 + now.y * 0xC0 + 2) ~= cs_owner then
  local ok, msg = pcall(cap, k)
  log(string.format("CAPTURE U%d ok=%s %s", k, tostring(ok), tostring(msg)))
 elseif not moved then
  local count = 0; for _ in pairs(reach) do count = count + 1 end
  local why = u.fuel == 0 and "no_fuel" or (count <= 1 and "no_reachable_cell" or bwhy)
  log(string.format("WAIT U%d %s hp=%d/%d fuel=%d reachable_cells=%d", k, why, u.hp, u.maxhp, u.fuel, count))
 end
end

-- 灭国判定：多阵营地图上「灭掉某一方」会让游戏进灭国演出，原生战斗调用再也回不来
-- （实测 1800/6000 帧都不返回，PC 停在 0x080006C2，游戏被卡死）。
-- 所以：只要还有别的敌对阵营活着，就不打「某方的最后一个单位」—— 改为先削其他阵营、
-- 并去占它的首都（场景胜利条件）。单一阵营（other==0）时最后一击 = 正常胜利路径。
local function cs_eliminates_faction(e, en)
 local same, other = 0, 0
 for _, o in ipairs(en) do
  if o.hp > 0 then
   if o.side == e.side then same = same + 1 else other = other + 1 end
  end
 end
 return same <= 1 and other >= 1
end

-- 追击/护卫任务时过滤攻击目标；多阵营下按 (side,slot) 唯一键
local function current_attack_targets(u, en)
 local function usable(list)
  local out = {}
  for _, e in ipairs(list) do
   if e.hp > 0 and not cs_eliminates_faction(e, en) then out[#out + 1] = e end
  end
  return out
 end
 local order = current_orders[u.idx]
 if order and order.kind == "intercept" then
  local targets = usable(en)
  local picked = {}
  for _, e in ipairs(targets) do
   if e.side == order.foe_side and e.idx == order.foe_slot then picked[#picked + 1] = e end
  end
  if #picked == 0 then
   if #targets == 0 then return {} end
   current_orders[u.idx] = nil
   log("ORDER U" .. u.idx .. " intercept target unusable/destroyed; released")
   return targets
  end
  return picked
 end
 if order and order.kind == "escort" then
  local foot = unit("MY", order.subject)
  local picked = {}
  for _, e in ipairs(usable(en)) do
   if hexd(e.x, e.y, order.x, order.y) <= 6 or (foot and hexd(e.x, e.y, foot.x, foot.y) <= 6) then
    picked[#picked + 1] = e
   end
  end
  return picked
 end
 return usable(en)
end

local function current_plan_round()
 current_orders = {}
 local en, my = all_units("EN"), all_units("MY")
 local threats = {}
 for _, e in ipairs(en) do
  local closest = 1e9
  if current_my_capital then closest = hexd(e.x, e.y, current_my_capital.x, current_my_capital.y) end
  for _, c in ipairs(current_my_cities) do closest = math.min(closest, hexd(e.x, e.y, c.x, c.y)) end
  local old = current_previous_en[e.side * 64 + e.idx]
  local closing = old and closest < old.distance
  if closest <= 18 or (closing and closest <= 24) then
   threats[#threats + 1] = { unit = e, priority = closest - (is_capturer(e.id) and 6 or 0) - (closing and 3 or 0) }
  end
 end
 table.sort(threats, function(a, b) return a.priority < b.priority end)
 local allocated, limit = 0, math.max(3, math.floor(#my * (0.25 + 0.1 * #current_foes)))
 for _, threat in ipairs(threats) do
  local e = threat.unit
  for role = 1, 2 do
   if allocated >= limit then break end
   local selected, score = nil, 1e30
   for _, u in ipairs(my) do
    if not u.acted and u.hp > 0 and not current_orders[u.idx] and not cs_guard(u, en)
        and not is_capturer(u.id) and not (u.id >= 339 and u.id <= 345) then
     local pref = nil
     for d = 3, 1, -1 do if my_best(u, d, e.id) > 0 then pref = d; break end end
     if pref then
      local _, cat, budget = vm_ctx(u.idx)
      local distance = current_route(e, pref, cat)[u.x .. "," .. u.y]
      if distance and (distance == 0 or budget > 0) then
       local value = distance + (1 - u.hp / math.max(1, u.maxhp)) * 15
       if cs_needs_supply(u) then value = value + 20 end   -- 缺编的先去补给，不接活
       if value < score then selected, score = { u = u, pref = pref }, value end
      end
     end
    end
   end
   if selected then
    local u = selected.u
    current_orders[u.idx] = { x = e.x, y = e.y, pref = selected.pref, value = -100,
     kind = "intercept", foe_side = e.side, foe_slot = e.idx }
    allocated = allocated + 1
    log(string.format("ORDER U%d intercept E%d(side%d) at=%d,%d", u.idx, e.idx, e.side, e.x, e.y))
   end
  end
 end
 -- 步兵专职任务：优先抢补给建筑（占下来就是自家补给站）
 local claimed = {}
 for _, u in ipairs(my) do
  if not u.acted and u.hp > 0 and is_capturer(u.id) and not cs_guard(u, en) then
   local _, cat = vm_ctx(u.idx)
   local chosen, score = nil, 1e30
   for y = 1, 46 do
    for x = 1, 46 do
     if on_building(x, y) and r8(tb() + x * 4 + y * 0xC0 + 2) ~= cs_owner and not claimed[x .. "," .. y] then
      local pref = r8(CTX + 0x3F60 + x * 4 + y * 0xC0) > 1 and 1 or 0
      local distance = current_route({ x = x, y = y }, pref, cat)[u.x .. "," .. u.y]
      if distance then
       local risk = cs_danger(u, x, y, en)
       local terr = terrain_at(x, y)
       local value = distance + risk * 2
       if CS_SUPPLY[terr] then value = value - 22 end     -- 补给地形价值极高
       if terr == 0x10 then value = value - 10 end
       local old = current_capture_jobs[u.idx]
       if old and old.x == x and old.y == y then value = value - 12 end
       if value < score then chosen, score = { x = x, y = y, pref = pref, value = -30, kind = "capture" }, value end
      end
     end
    end
   end
   if chosen then
    current_orders[u.idx] = chosen; current_capture_jobs[u.idx] = chosen; claimed[chosen.x .. "," .. chosen.y] = true
    log(string.format("ORDER U%d capture target=%d,%d staging=%d terr=0x%02X",
     u.idx, chosen.x, chosen.y, chosen.pref, terrain_at(chosen.x, chosen.y)))
    local escort, best = nil, 1e30
    for _, candidate in ipairs(my) do
     if not candidate.acted and candidate.hp > 0 and not current_orders[candidate.idx]
         and not cs_guard(candidate, en) and not is_capturer(candidate.id)
         and not (candidate.id >= 339 and candidate.id <= 345) then
      local armed = false
      for _, e in ipairs(en) do if my_best(candidate, 1, e.id) > 0 then armed = true; break end end
      if armed then
       local value = hexd(u.x, u.y, candidate.x, candidate.y) + (1 - candidate.hp / math.max(1, candidate.maxhp)) * 10
       if value < best then escort, best = candidate, value end
      end
     end
    end
    if escort then
     current_orders[escort.idx] = { x = chosen.x, y = chosen.y, pref = 1, value = -25, kind = "escort", subject = u.idx }
     log(string.format("ORDER U%d escort U%d target=%d,%d", escort.idx, u.idx, chosen.x, chosen.y))
    end
   else
    log("ORDER U" .. u.idx .. " capture no reachable city")
   end
  end
 end
 current_previous_en = {}
 for _, e in ipairs(en) do
  local distance = 1e9
  if current_my_capital then distance = hexd(e.x, e.y, current_my_capital.x, current_my_capital.y) end
  for _, c in ipairs(current_my_cities) do distance = math.min(distance, hexd(e.x, e.y, c.x, c.y)) end
  current_previous_en[e.side * 64 + e.idx] = { x = e.x, y = e.y, distance = distance }
 end
end

local function current_capture_action(k, u, en)
 local order = current_orders[k]
 if not order or order.kind ~= "capture" then return false end
 local _, cat, budget = vm_ctx(k)
 current_advance(k, u, vm_reach(u, cat, budget), cat, en)
 if r8(CTX) ~= 8 and #all_units("EN") > 0 then markacted(k) end
 return true
end

local function current_trace_round(phase)
 local rows = {}
 for _, side in ipairs({ "MY", "EN" }) do
  for _, u in ipairs(all_units(side)) do
   local order = (side == "MY") and current_orders[u.idx] or nil
   rows[#rows + 1] = string.format('{"side":"%s","slot":%d,"id":%d,"x":%d,"y":%d,"hp":%d,"fuel":%d,"order":"%s","goal_x":%d,"goal_y":%d}',
    side, u.idx, u.id, u.x, u.y, u.hp, u.fuel, order and order.kind or "", order and order.x or -1, order and order.y or -1)
  end
 end
 local f = assert(io.open(BASE .. "logs/" .. SAVE_PREFIX .. "_trajectory.jsonl", "a"))
 f:write(string.format('{"turn":%d,"phase":"%s","units":[%s]}\n', r8(CTX + 0x20), phase, table.concat(rows, ",")))
 f:close()
end

-- 原生战斗调用卡住时的自救：多阵营地图上「灭掉其中一个敌对阵营」会让游戏进入
-- 灭国演出/弹窗（等输入），此时 FUN_08023188 不会返回，mailbox 停在 busy。
-- 做法：卸掉 hook → 用 A 推过演出/对话 → 状态还是我方地图态就装回 hook 继续。
local cs_stuck_aborted = false
local function cs_recover_stuck(k)
 log(string.format("STUCK U%d 战斗调用未返回（灭国演出/对话），开始恢复", k))
 -- 1) 清 mailbox：stub 中断时状态卡在 2=busy，uninstall 会因此拒绝
 pcall(function() for i = 0, 63 do memory.write_u8(MAILBOX + i, 0) end end)
 -- 2) 直接写回原始 8 字节（不依赖 uninstall 的断言），再把 EWRAM 桥区 + mailbox 清零
 pcall(function() for i = 1, 8 do memory.write_u8(HOOK + i - 1, original[i]) end end)
 pcall(function()
  for i = 0, 0x23F do memory.write_u8(CAVE + i, 0) end
  for i = 0, 63 do memory.write_u8(MAILBOX + i, 0) end
 end)
 installed = false
 -- 3) 推 A 过掉灭国演出/对话框
 for i = 1, 30 do
  adv(20); tap("A", 25)
 end
 -- 4) 还是我方地图态就装回 hook；已经进结算（state 8）就交给上层胜利判定
 if r8(CTX) == 8 then
  log(string.format("STUCK 已进入结算 state=%d/%d result=%d", r8(CTX), r8(CTX + 1), r8(CTX + 0x2C)))
  return
 end
 local ok, err = pcall(install)
 if ok then
  log(string.format("STUCK 恢复完成 state=%d/%d", r8(CTX), r8(CTX + 1)))
 else
  cs_stuck_aborted = true
  log(string.format("STUCK hook 装回失败（%s），停手；战场已保留，重跑 Play-Current2 可继续", tostring(err)))
 end
end

-- 敌人列表里每个单位带 side/key：给旧打分代码用的威胁距离
local function current_home_threat(e)
 return cs_home_distance(e.x, e.y)
end

 local function try_capture_capital(tn)
  local cx,cy=enemy_capital()
  if not cx then return false end
  if r8(CTX+0x3F60+cx*4+cy*0xC0)~=0 then return false end   -- 首都上有守军，先清场
  for k=0,63 do
   local u=unit("MY",k)
   if u and u.hp>0 and not u.acted and is_capturer(u.id) then
    local _,cat,budget=vm_ctx(k)
    local reach=vm_reach(u,cat,budget)
    local c=reach[cx..","..cy]
    if c then
     local okm=pcall(vm_land,k,u,cx,cy,c)
     if okm then
      local okc,msgc=pcall(cap,k)
      report[#report+1]=string.format("T%d 首都占領 %s",tn,tostring(msgc))
      return okc
     end
    end
   end
  end
  return false
 end
 for iteration=1,80 do
  current_begin_round()
  current_trace_round("before_defense")
  current_defend_capitals()
  if r8(CTX)==8 or #all_units("EN")==0 then return finish("城市防守结算") end
  current_plan_round()
  current_trace_round("planned")
  local turn=r8(CTX+0x20)
  log(string.format("TURN %d game_turn=%d friendly=%d enemies=%d",turn,r8(CTX+0x20),#all_units("MY"),#all_units("EN")))
  -- 首都攻略（优先）：能占就占 —— 占领首都即胜利条件
  if try_capture_capital(turn) then
   uninstall(); savestate.save(BASE.."states/"..SAVE_PREFIX.."_capital.State")
   return finish("占領敌方首都")
  end
  for k=0,63 do
   local u=unit("MY",k)
   if u and u.hp>0 and not u.acted then
    local en=all_units("EN")
    if #en==0 then break end
    local hold,reason=cs_hold(u,en)
    if hold then
     cs_hold_action(k,u,en,reason)
     if r8(CTX)==8 or #all_units("EN")==0 then return finish("城市驻守结算") end
    elseif current_capture_action(k,u,en) then
     if r8(CTX)==8 or #all_units("EN")==0 then return finish("步兵占领结算") end
    elseif u.id>=339 and u.id<=345 then
     local _,support_cat,support_budget=vm_ctx(k)
     current_advance(k,u,vm_reach(u,support_cat,support_budget),support_cat,en)
     markacted(k)
    else
     local _,cat0,budget0=vm_ctx(k)
     local reach=vm_reach(u,cat0,budget0)
     local bestScore,bestPlan=-1,nil
     for _,e in ipairs(current_attack_targets(u,en)) do
      local plans={}
      local d0=hexd(u.x,u.y,e.x,e.y)
      local h0=my_best(u,d0,e.id)
      if h0>0 then plans[#plans+1]={d=d0,atk=h0} end
      for want=1,3 do
       if want~=d0 and not cs_guard(u,en) then -- U0 guards our capital, blocking a cheap enemy capture.
        local hit=my_best(u,want,e.id)
        if hit>0 then
         local cx,cy=best_reach_cell(reach,e,want)
         if cx then plans[#plans+1]={d=want,atk=hit,cx=cx,cy=cy} end
        end
       end
      end
      for _,p in ipairs(plans) do
       local counter=enemy_counter(e,u.id,p.d)
       local hp=u.hp
       local eff=estimate(u,e,p.atk)
       local loss=estimate(e,u,counter,p.cx or u.x,p.cy or u.y)
       local kill=eff>=e.hp
       -- 比较估计 HP 损失；建筑守军可被同回合集火，不再禁止所有非致命攻击。
       local exposure=cs_danger(u,p.cx or u.x,p.cy or u.y,en)
       if eff<1 or (loss>=hp and not kill) or (p.cx and exposure>=hp*0.9) then
        -- skip
       else
        local threat=current_home_threat(e)
        local score=math.min(eff,e.hp)*16-loss*20+(kill and 180 or 0)
             +((threat<=6) and (7-threat)*20 or 0)
             +((e.id==224 or e.id==235) and 50 or 0)
             +((CAMPAIGN==2 and e.id==243) and 70 or 0)
             +((CAMPAIGN==2 and e.id==211) and 40 or 0)
             +((e.hp<(db(e.id).dur*4)) and 20 or 0)
             -((p.cx and reach[p.cx..","..p.cy]) or 0)-exposure*8
             +((p.cx and cs_supply_cell(p.cx,p.cy)) and 70 or 0)
             +((not p.cx and cs_supply_cell(u.x,u.y)) and (cs_needs_supply(u) and 180 or 40) or 0)
        if score>bestScore then
         bestScore,bestPlan=score,{e=e,p=p}
        end
       end
      end
     end
     if bestPlan then
      local e,p=bestPlan.e,bestPlan.p
      local ok,amsg=true,""
      if p.cx then
       local okm,amsgm=pcall(vm_land,k,u,p.cx,p.cy,reach[p.cx..","..p.cy] or 1)
       if okm then
        adv(10)
       else
        ok,amsg=false,"落格失败:"..tostring(amsgm)
       end
      end
      if ok then
       local ok2,amsg2=pcall(attack,k,e)
       ok,amsg=ok2,tostring(amsg2)
      end
      report[#report+1]=string.format("T%d U%d(id%d)->E%d(side%d,id%d) %s %s",turn,k,u.id,e.idx,e.side,e.id,ok and "OK" or "FAIL",amsg)
      log(report[#report]); progress()
      if r8(CTX)==8 or #all_units("EN")==0 then return finish("全歼/战斗结算") end
      if not ok then
       local why=tostring(amsg)
       if why:find("did not return") or why:find("mailbox busy") then
        cs_recover_stuck(k)
        if cs_stuck_aborted then return "FAIL STUCK 灭国演出打断，战场已保留；重新运行 Play-Current2 可继续" end
        if r8(CTX)==8 or #all_units("EN")==0 then return finish("战斗结算/敌军全灭") end
       end
       markacted(k)
      end
     else
      current_advance(k,u,reach,cat0,en)
      if r8(CTX)==8 or #all_units("EN")==0 then return finish("推进/占领/补给结算") end
      markacted(k)
     end
     if #all_units("EN")==0 then
      return finish("全歼敌军")
     end
    end
   end
  end
  -- 本回合清场后：同回合补占首都（胜利条件）
  if try_capture_capital(turn) then
   uninstall(); savestate.save(BASE.."states/"..SAVE_PREFIX.."_capital.State")
   return finish("占領敌方首都")
  end
  if #all_units("EN")>0 then
   current_trace_round("completed")
   local okm,msgm=endturn()
   report[#report+1]=msgm
   if r8(CTX)==8 then return finish("回合结算") end
   if not okm then
    client.speedmode(100)
    return "FAIL ENDTURN: "..msgm
   end
   savestate.save(BASE.."states/"..SAVE_PREFIX.."_t"..turn..".State")
   progress()
  end
 end
 client.speedmode(100)
 return "AUTOCLEAR v2 结束: "..table.concat(report," | ")
end
local function animation_test()
 uninstall()
 local original_state=BASE .. "states/animation_user_before.State"
 savestate.save(original_state)
 savestate.load(BASE .. "states/first_clear_start.State"); adv(30); restore_keyboard()
 local ok,msg=teleport_mem(0,18,29); assert(ok,msg)
 native_call(0x080169D4,{18,29}); native_call(0x08016BE0,{})
 uninstall()
 local baseline=BASE .. "states/animation_ab_base.State"
 savestate.save(baseline)
 local results={}
 for _,mode in ipairs({"OFF","ON"}) do
  savestate.load(baseline); adv(2); restore_keyboard()
  animation(mode)
  recordName=(mode=="ON") and "animation_on" or "animation_off"
  recordFrame=0; recordTick=0
  log("ANIMATION_TEST " .. mode .. " begin")
  local msg=attack(0,0)
  recordName=nil
  local u,e=unit("MY",0),unit("EN",0)
  local frames=native_frames[0x08023188]
  results[#results+1]=string.format('  {"mode":"%s","value":%d,"battle_frames":%d,"my_hp":%d,"enemy_hp":%d,"my_ammo":%d,"acted":%s}',mode,r8(CTX+0xC55),frames,u.hp,e.hp,u.ammo,tostring(u.acted))
  log("ANIMATION_TEST " .. mode .. " frames=" .. frames .. " " .. msg)
  uninstall()
  savestate.save(BASE .. "states/animation_" .. mode:lower() .. "_verified.State")
 end
 writefile(BASE .. "logs/animation_ab.json","[\n" .. table.concat(results,",\n") .. "\n]\n")
 savestate.load(original_state); adv(2); restore_keyboard()
 return "OK ANIMATION_TEST complete; original battle restored; logs/animation_ab.json"
end
-- Read-only full map/army export. VIEWMAP is the game's R shoulder button.
local function mapdata()
 local base=memory.read_u32_le(CTX+0x18)
 assert(base>=0x02000000 and base+48*48*4<=0x02040000,"map is not loaded")
 local cells,roster,units={},{},{}
 for y=0,47 do for x=0,47 do
  local a=base+x*4+y*0xC0
  cells[#cells+1]=string.format('[%d,%d,%d,%d,%d,%d]',x,y,r8(a),r8(a+1),r8(a+2),r8(a+3))
 end end
 for k=0,98 do
  local a=CTX+0x188+k*4
  local id=memory.read_u16_le(a)
  if id~=0 then roster[#roster+1]=string.format('{"slot":%d,"id":%d,"exp":%d,"exp_address":%d,"flag":%d}',k,id,r8(a+2),a+2,r8(a+3)) end
 end
 for side=0,1 do for k=0,63 do
  local u=unit(side==0 and "MY" or "EN",k)
  if u then
   local a=U-2+side*PB+k*STRIDE
   units[#units+1]=string.format('{"side":%d,"slot":%d,"id":%d,"x":%d,"y":%d,"hp":%d,"fuel":%d,"exp":%d,"exp_address":%d}',side,k,u.id,u.x,u.y,u.hp,u.fuel,r8(a+5),a+5)
  end
 end end
 local text=string.format('{"state":%d,"turn":%d,"roster_money":%d,"terrain_base":%d,"cell_format":["x","y","terrain","durability","owner","flags"],"cells":[%s],"roster":[%s],"units":[%s]}\n',
  r8(CTX),r8(CTX+0x20),memory.read_u32_le(CTX+0x68),base,table.concat(cells,","),table.concat(roster,","),table.concat(units,","))
 writefile(RUN.."map.json",text)
 return "OK MAPDATA shots/native_attack/map.json (read-only 48x48 terrain, units, roster and experience)"
end
local function experience(mode)
 local function grade(e) return e>=240 and "A" or e>=150 and "B" or e>=80 and "C" or e>=30 and "D" or "E" end
 local rows={}
 if mode=="" or mode=="ROSTER" then
  for k=0,98 do
   local a=CTX+0x188+k*4; local id=memory.read_u16_le(a)
   if id~=0 then rows[#rows+1]=string.format("ROSTER slot=%d id=%d exp=%d grade=%s address=0x%08X",k,id,r8(a+2),grade(r8(a+2)),a+2) end
  end
 else
  assert(mode=="MY" or mode=="EN","XP ROSTER|MY|EN")
  for _,u in ipairs(all_units(mode)) do
   local a=U-2+(mode=="MY" and 0 or PB)+u.idx*STRIDE+5
   rows[#rows+1]=string.format("%s slot=%d id=%d exp=%d grade=%s address=0x%08X",mode,u.idx,u.id,r8(a),grade(r8(a)),a)
  end
 end
 return "OK XP\n"..table.concat(rows,"\n")
end
local function inspect(seq,result)
 local text=build_state() .. string.format("CTX state=%d sub=%d phase=%d side=%d player=%d animation=%d hook=%s PC=0x%08X\n",
 r8(CTX),r8(CTX+1),r8(CTX+0x21),r8(CTX+0x22),r8(CTX+0x990),r8(CTX+0xC55),tostring(installed),emu.getregister("R15"))
 client.screenshot(RUN .. "current.png")
 client.screenshot(RUN .. string.format("%04d.png",seq))
 writefile(RUN .. "state.txt",text)
 writefile(RUN .. "reply.txt","seq=" .. seq .. "\n" .. result .. "\n")
 log("COMMAND " .. seq .. " " .. result)
end
-- Current-game entry policy, v2 (multi-faction + city resupply aware).
-- 与 v1 的区别：开局打印所有阵营（含名称/资金/敌对关系），并把玩家阵营写进日志，
-- 战术侧用 ctx+0x990 自动识别「我方 vs 所有敌对阵营」。

-- 场景数据块（ctx+0x14）在 RAM 里的完整拷贝：
--   +0x00 标题(16B)  +0x10+i*0x18 阵营 i { 名称(16B), 类型(1=本国/2=他国), 保留, u16, 资金 }
local function current_factions()
 local p = memory.read_u32_le(CTX + 0x14)
 local out = {}
 if not (p >= 0x02000000 and p < 0x0A000000) then return out end
 local function s_at(a, n)
  local t = {}
  for i = 0, n - 1 do
   local c = r8(a + i)
   if c == 0 then break end
   t[#t + 1] = string.char(c)
  end
  return table.concat(t)
 end
 out.title = s_at(p, 16)
 for i = 0, 5 do
  local a = p + 0x10 + i * 0x18
  local nm = s_at(a, 16)
  if #nm == 0 and r8(a + 0x10) == 0 then break end
  out[#out + 1] = { index = i, name = (#nm > 0) and nm or ("国家" .. i),
   kind = r8(a + 0x10), money = memory.read_u32_le(a + 0x14) }
 end
 return out
end

local function current_log_factions()
 local pside = memory.read_u8(CTX + 0x990)
 local list = current_factions()
 log(string.format("FACTIONS title=%s player_side=%d count=%d", tostring(list.title), pside, #list))
 for _, f in ipairs(list) do
  local alive = r8(CTX + 0x24 + f.index * 0xC + 4)
  log(string.format("FACTION #%d %-8s kind=%d status=%d money=%d %s",
   f.index, f.name, f.kind, alive, f.money,
   f.index == pside and "(我方)" or (alive >= 1 and alive <= 3 and "(敌对)" or "(未参战)")))
 end
 local foe = {}
 for _, f in ipairs(list) do
  local alive = r8(CTX + 0x24 + f.index * 0xC + 4)
  if f.index ~= pside and alive >= 1 and alive <= 3 then foe[#foe + 1] = f.name end
 end
 log("FACTION 敌对阵营 = " .. table.concat(foe, ","))
end

local function current_campaign()
 local p = memory.read_u32_le(CTX + 0x14)
 assert(p >= 0x02000000 and p < 0x0A000000, "Scenario data is not loaded")
 for stage, ref in ipairs({ 0x08762B10, 0x08763E8C, 0x087652BC }) do
  local same = true
  for j = 0, 15 do if r8(p + j) ~= r8(ref + j) then same = false end end
  if same then return stage end
 end
 log(string.format("CURRENT unrecognized scenario at 0x%08X; using generic configuration", p))
 return 0 -- No scenario whitelist: unknown maps use the non-stage-1 defaults.
end

local function prepare_current_army()
 local wanted = CAMPAIGN == 1 and { [187] = 9, [241] = 4, [305] = 4, [324] = 2, [339] = 1 }
                             or { [187] = 9, [241] = 5, [305] = 2, [324] = 2, [339] = 2 }
 local old, counts, empty = {}, {}, {}
 for k = 0, 98 do
  local a = CTX + 0x188 + k * 4; local id = memory.read_u16_le(a)
  if id == 0 then empty[#empty + 1] = k else
   assert(wanted[id], "Army differs from verified plan; retained unchanged, id=" .. id)
   counts[id] = (counts[id] or 0) + 1
   old[#old + 1] = { slot = k, id = id, exp = r8(a + 2) }
  end
 end
 local additions, cost = {}, 0
 for _, id in ipairs({ 187, 241, 305, 324, 339 }) do
  assert((counts[id] or 0) <= wanted[id], "Army exceeds verified plan; retained unchanged")
  for i = 1, wanted[id] - (counts[id] or 0) do
   additions[#additions + 1] = id
   cost = cost + memory.read_u16_le(0x08798A98 + id * 0x5C + 0x1A)
  end
 end
 local money = memory.read_u32_le(CTX + 0x68)
 assert(money >= cost and #empty >= #additions, "Insufficient funds or roster space")
 for i, id in ipairs(additions) do
  local a = CTX + 0x188 + empty[i] * 4
  memory.write_u16_le(a, id); memory.write_u8(a + 2, 0); memory.write_u8(a + 3, 0)
 end
 memory.write_u32_le(CTX + 0x68, money - cost)
 local checkpoint = BASE .. "states/" .. SAVE_PREFIX .. "_army.State"
 savestate.save(checkpoint)
 local deployed = false
 for trial = 1, 2 do
  savestate.load(checkpoint); adv(15); restore_keyboard()
  tap("A", 180); if trial == 1 then tap("A", 40) end
  for i = 1, 20 do tap("A", 35); if i < 20 then tap("Down", 35) end end
  tap("Start", 90); tap("A", 120); adv(500)
  if #all_units("MY") == 20 then deployed = true; break end
 end
 assert(deployed, "Deployment not completed; checkpoint retained")
 for _, v in ipairs(old) do
  local k = r8(CTX + 0x188 + v.slot * 4 + 3) % 100 - 1
  assert(k >= 0 and k < 64, "Missing veteran association")
  local a = U - 2 + k * STRIDE
  assert(memory.read_u16_le(a) == v.id and r8(a + 5) == v.exp, "Veteran mismatch")
 end
 tap("Start", 90); tap("A", 120)
end

local function play_current(speed)
 client.unpause()
 uninstall()
 local s = r8(CTX)
 assert(s == 3 or s == 4 or s == 6 or s == 7, "Open scenario selection/details, predeployment, or battlefield first; state=" .. s)
 local token = os.date("%Y%m%d_%H%M%S")
 SAVE_PREFIX = "current_" .. token
 savestate.save(BASE .. "states/" .. SAVE_PREFIX .. "_before.State")
 local points, rank = memory.read_u32_le(CTX + 0x6C), r8(CTX + 0x65)
 client.speedmode(tonumber(speed) or 200)
 if s == 3 then
  for i = 1, 6 do tap("A", 100); if r8(CTX) == 4 then break end end
  assert(r8(CTX) == 4, "Could not open currently highlighted scenario")
 end
 CAMPAIGN = current_campaign()
 current_log_factions()
 log("CURRENT tactics=missions-v4(multi-faction) run=" .. SAVE_PREFIX .. " detected scenario=" .. CAMPAIGN .. " " .. commander())
 if r8(CTX) == 4 then tap("A", 100); assert(r8(CTX) == 6, "Could not enter deployment") end
 if r8(CTX) == 6 then
  local deployed = #all_units("MY")
  if deployed == 0 then prepare_current_army() else
   log("CURRENT using existing deployed army count=" .. deployed)
   tap("Start", 90); tap("A", 120)
  end
 end
 local ready = false
 for i = 1, 40 do
  if r8(CTX) == 7 and r8(CTX + 1) == 1 and r8(CTX + 0x21) == 3 and r8(CTX + 0x22) == 0 then ready = true; break end
  assert(r8(CTX) == 6 or r8(CTX) == 7, "Unexpected state preparing battle")
  adv(60); tap("A", 40)
 end
 assert(ready, "Player phase not ready; checkpoint retained")
 to_map(); adv(60)
 assert(memory.read_u32_le(CTX + 0x6C) == points and r8(CTX + 0x65) == rank, "Commander continuity mismatch")
 assert(#all_units("MY") > 0 and #all_units("EN") > 0, "No active battle")
 current_log_factions()
 savestate.save(BASE .. "states/" .. SAVE_PREFIX .. "_ready.State")
 return "OK " .. autoclear(speed)
end

local function main()
 client.speedmode(100); client.frameskip(0)
 pcall(client.setsoundon,true) -- 桥运行期间保留声音（旧调试脚本习惯静音，会让人以为"模拟器没声音"）
 adv(20); savestate.load(LOAD_STATE); adv(40); restore_keyboard()
 memory.write_u8(CTX+0xC55,0) -- Clean fight: full battle presentation off.
 local seq=0; inspect(0,"READY native attack research; real keyboard active")
 while true do
  local f=io.open(RUN .. "command.txt","r"); local txt=f and f:read("*a") or ""; if f then f:close() end
  local id,line=txt:match("seq=(%d+)\n([^\r\n]+)"); id=tonumber(id)
  if id and id>seq then
   seq=id; step=seq
   local cmd,rest=line:match("^(%S+)%s*(.*)$")
   local result="OK " .. line
   local command_ok,command_error=pcall(function()
   if cmd=="CURRENT" then result=play_current(rest)
   elseif cmd=="INSTALL" then install()
   elseif cmd=="UNINSTALL" then uninstall()
   elseif cmd=="DIST" then
    local a={}; for n in rest:gmatch("%-?%d+") do a[#a+1]=tonumber(n) end
    assert(#a==4,"DIST x1 y1 x2 y2")
    result="OK DIST " .. native_call(0x08002E74,a)
   elseif cmd=="ATTACK" then
    local i,e=rest:match("(%d+)%s+(%d+)"); result="OK " .. attack(tonumber(i),tonumber(e))
   elseif cmd=="POSITION" then
    local i,x,y=rest:match("(%d+)%s+(%d+)%s+(%d+)")
    local ok,msg=teleport_mem(tonumber(i),tonumber(x),tonumber(y)); result=(ok and "OK " or "FAIL ") .. msg
    if ok then native_call(0x080169D4,{tonumber(x),tonumber(y)}); native_call(0x08016BE0,{}) end
   elseif cmd=="ANIMATION" then result="OK " .. animation(rest)
   elseif cmd=="ENDTURN" then local ok,msg=endturn(); result=(ok and "OK " or "FAIL ")..msg
   elseif cmd=="AUTOCLEAR" then result="OK " .. autoclear(rest)
   elseif cmd=="PROFILE" then result="OK PROFILE "..commander()
   elseif cmd=="PREFIX" then
    assert(rest:match("^[%w_%-]+$") and #rest<70,"invalid save prefix"); SAVE_PREFIX=rest
   elseif cmd=="REPLAYFIRST" then result=replay_first(rest)
   elseif cmd=="SETTLE" then
    local p,r=rest:match("^(%d+)%s+(%d+)$"); assert(p,"SETTLE previous_points previous_rank")
    local promoted=settle_result(tonumber(p),tonumber(r))
    result="OK "..(promoted and "PROMOTED " or "CREDITED ")..commander()
   elseif cmd=="SPEED" then
    local n=tonumber(rest); assert(n and n>=10 and n<=1600,"SPEED 10..1600"); client.speedmode(n)
   elseif cmd=="VM" then
    local k,x,y=rest:match("(%d+)%s+(%d+)%s+(%d+)")
    assert(k and x and y,"VM 槽 x y")
    result="OK " .. vm(tonumber(k),tonumber(x),tonumber(y))
   elseif cmd=="CAP" then
    local k=rest:match("(%d+)")
    assert(k,"CAP 槽号")
    result="OK " .. cap(tonumber(k))
   elseif cmd=="ANIMATIONTEST" then result=animation_test()
   elseif cmd=="KEY" then
    local key,frames,gap=rest:match("(%S+)%s+(%d+)%s+(%d+)"); hold(key,tonumber(frames)); adv(tonumber(gap))
   elseif cmd=="ADV" then adv(tonumber(rest) or 1)
   elseif cmd=="MAP" then to_map()
   elseif cmd=="VIEWMAP" then
    assert(r8(CTX)==6,"VIEWMAP is verified for the deployment screen (state=6)")
    tap("R",100); client.screenshot(RUN.."map_preview.png")
    result="OK VIEWMAP R shoulder pressed; use B to return from preview"
   elseif cmd=="MAPSCROLL" then
    assert(r8(CTX)==6,"MAPSCROLL requires deployment preview")
    local direction,count=rest:match("^(%a+)%s+(%d+)$"); count=tonumber(count)
    assert(direction=="Up" or direction=="Down" or direction=="Left" or direction=="Right","MAPSCROLL Up|Down|Left|Right steps")
    assert(count and count>=1 and count<=40,"steps must be 1..40")
    for _=1,count do hold(direction,14); adv(8) end
    client.screenshot(RUN.."map_preview.png")
   elseif cmd=="MAPDATA" then result=mapdata()
   elseif cmd=="XP" then result=experience(rest)
   elseif cmd=="READ" then
    local addr,n=rest:match("(%S+)%s+(%d+)"); addr=tonumber(addr); n=tonumber(n)
    local b={}; for i=0,n-1 do b[#b+1]=string.format("%02X",r8(addr+i)) end; result="OK READ " .. table.concat(b," ")
   elseif cmd=="RECORD" then
    if rest=="OFF" then recordName=nil else assert(rest:match("^[%w_%-]+$")); recordName=rest; recordFrame=0; recordTick=0 end
   elseif cmd=="SAVE" then
    assert(rest:match("^[%w_%-]+$")); uninstall(); savestate.save(BASE .. "states/" .. rest .. ".State")
   elseif cmd=="LOAD" then
    assert(rest:match("^[%w_%-]+$")); uninstall(); savestate.load(BASE .. "states/" .. rest .. ".State"); adv(30); restore_keyboard()
   elseif cmd=="EXIT" then uninstall(); inspect(seq,result); logf:close(); client.exit(); return
   elseif cmd~="SNAP" then error("unknown command " .. cmd) end
   end)
   if not command_ok then
    if installed and memory.read_u32_le(MAILBOX)==2 then error(command_error) end
    if installed and memory.read_u32_le(MAILBOX)==1 then memory.write_u32_le(MAILBOX,0) end
    if cmd=="CURRENT" then uninstall(); client.speedmode(100) end
    result="FAIL " .. tostring(command_error)
   end
   inspect(seq,result)
  else client.sleep(10); emu.yield() end
 end
end
local ok,err=xpcall(main,debug.traceback)
if not ok then
 log("FATAL " .. tostring(err)); client.screenshot(RUN .. "error.png")
 writefile(RUN .. "error.txt",tostring(err)); pcall(client.pause)
end
