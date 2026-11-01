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
local LOGF   = BASE .. "logs/usa_ai_state.txt"
local DBF    = BASE .. "lua/unitdb.tsv"
local LOAD_STATE = BASE .. "states/battle_usa_ready.State"

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
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return r8(0x030067FE), r8(0x030067FF) end

-- 每帧都 set 才是真按住；不要传 player 索引
local function hold(k, frames)
  if mailOK then
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    for _ = 1, (frames or HOLD_BTN) do emu.frameadvance() end
    memory.write_u16_le(MAIL, 0x3FF)       -- 必须松开，否则游戏一直读到按住
  else
    for _ = 1, (frames or HOLD_BTN) do
      joypad.set({ [k] = true })
      emu.frameadvance()
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
local function unit(side, k)
  local base = (side == "MY") and (U + k * STRIDE) or (U + PB + k * STRIDE)
  local id = memory.read_u16_le(base - 2)
  if id == 0 then return nil end
  local x, y = r8(base), r8(base + 1)
  if not (x > 0 and x < 64 and y > 0 and y < 64) then return nil end
  local d = db(id)
  return {
    side = side, idx = k, id = id,
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

local function all_units(side)
  local t = {}
  for k = 0, SLOTS - 1 do
    local u = unit(side, k)
    if u then t[#t + 1] = u end
  end
  return t
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
    L[#L + 1] = string.format("E%d id%d %s x%d y%d hp%d/%d f%d st%d act%d ammo%d",
      u.idx, u.id, u.name, u.x, u.y, u.hp, u.maxhp, u.fuel, u.st, u.acted and 1 or 0, u.ammo)
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

-- ============ 启动 ============
pcall(client.speedmode, 0)
pcall(client.setsoundon, true)   -- 保留声音（原为 false：静音调试用；声音另外还受 config.ini 的 MuteFrameAdvance 控制）
adv(20)

if LOAD_STATE and LOAD_STATE ~= "" then
  local f = io.open(LOAD_STATE, "r")
  if f then
    f:close()
    local ok = pcall(savestate.load, LOAD_STATE)
    log((ok and "已载入 " or "载入失败 ") .. LOAD_STATE)
    adv(40)
  else
    log("没找到存档点 " .. LOAD_STATE)
  end
end

patch_mail()   -- 必须在载入存档点之后打（savestate 会恢复 IWRAM，覆盖补丁）

-- 关闭完整战斗演出。原生结算读取 ctx+0xC55；载入存档后再设置。
-- 0x0300756F 只是设置菜单的临时副本，不能用作战场开关。
local function disable_battle_anim()
  assert(memory.read_u32_le(0x02007060) == CTX, "游戏上下文未初始化")
  memory.write_u8(CTX + 0xC55, 0)
  local off = (memory.read_u8(CTX + 0xC55) == 0)
  log("完整战斗演出(0x030010D5): " .. (off and "已关闭" or "!! 关闭失败"))
  return off
end

ensure_map()
disable_battle_anim()
ensure_map()
log("就绪，开始主循环")

while step < MAXSTEP do
  -- 1. 导出状态
  local okb, text = pcall(build_state)
  if not okb then
    log("!! build_state 失败: " .. tostring(text))
    break
  end
  log("step " .. step .. " 状态 " .. #text .. " 字节")
  local f = io.open(STATE, "w")
  if f then f:write(text); f:close() else log("!! 写 state.txt 失败") end
  pcall(client.screenshot, SHOT)

  -- 2. 等大脑回复
  local resp = nil
  for _ = 1, WAIT_TRIES do
    local g = io.open(ACTION, "r")
    if g then
      local txt = g:read("*a") or ""
      g:close()
      local got = txt:match("step=(%d+)")
      if got and tonumber(got) == step then resp = txt; break end
    end
    local oks = pcall(client.sleep, 50)
    if not oks then adv(1) end
  end

  -- 3. 执行
  results = {}
  if resp then
    for line in resp:gmatch("[^\r\n]+") do
      if not line:match("^step=") then
        local l = line:match("^%s*(.-)%s*$")
        -- PLAN: 与 END 只是人读的注释，不是指令
        if l and #l > 0 and not l:match("^PLAN") and l ~= "END" then
          local okc, err = pcall(run_directive, l)
          if not okc then results[#results + 1] = "ERR 执行异常 " .. tostring(err) end
          if battle_result() ~= nil then break end
        end
      end
    end
  else
    results[#results + 1] = "FAIL 等大脑超时"
  end

  -- 4. 写结果（下一轮给大脑反馈）
  local rf = io.open(RESULT, "w")
  if rf then
    rf:write("step=" .. step .. "\n")
    for _, r in ipairs(results) do rf:write(r .. "\n") end
    rf:write("END\n")
    rf:close()
  end
  for _, r in ipairs(results) do log("step " .. step .. ": " .. r) end

  local outcome = battle_result()
  if outcome ~= nil then
    local name = (outcome == 1 or outcome == 2) and "ai_victory" or "ai_finished"
    adv(180)
    pcall(savestate.save, BASE .. "states/" .. name .. ".State")
    pcall(client.screenshot, BASE .. "shots/" .. name .. ".png")
    log("游戏结束，原生结果=" .. outcome .. "，已保存 " .. name)
    break
  end

  -- 5. 确保下一步在地图态
  ensure_map()
  recenter()      -- 把视野拉回我方重心（瞬移会把光标带走，导致画面里看不到部队）
  step = step + 1
end

log(battle_result() ~= nil and "保留结算画面，停止下令" or "达到步数上限，停止")
if logf then logf:close() end
if battle_result() ~= nil then pcall(client.pause) else pcall(client.exit) end
