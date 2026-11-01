--[[
  内存驱动版 AI 代理：不截图、不送图。
  每步把 GBA 的硬件状态（BG 层配置 / 图块网格 / OAM 精灵 / RAM 变化）导成文本，
  交给本地模型分析。模型只看到数字和结构，看不到像素。

  用法：
    1) python brain.py --profile strategy        （监听 8765）
    2) EmuHawk.exe <rom> --lua="state_agent.lua"
]]

-- ============ 配置 ============
local BASE   = "D:/prog/gba-ai/"
local STATE  = BASE .. "shots/state.txt"
local ACTION = BASE .. "shots/action.txt"
local SHOT   = BASE .. "shots/cur.png"          -- 视觉模式用（brain_file.py --vision）
local LOAD_STATE = BASE .. "states/battle_start.State"  -- SL 大法：有就载入，省掉开场的 40 秒
local SPEED  = 100
local HOLD   = 3
local HOLD_BTN = 3     -- A/B/START/SELECT：按 1~3 帧就够（菜单认"新按下"）
local HOLD_DIR = 14    -- 方向键：必须按住多帧，光标才会动（带重复延迟）
local GAP    = 3
local MAXSTEP = 500
local WAIT_TRIES  = 1200   -- 每次等 50ms，最多等 60 秒（模型首次加载会慢）

local KEYMAP = {
  A = "A", B = "B", L = "L", R = "R",
  START = "Start", SELECT = "Select",
  UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right",
}
local DIRKEYS = { Up = true, Down = true, Left = true, Right = true }

local step, lastAct = 0, ""
local prevFp = ""
local lastDecision = 0
local MIN_GAP   = 24    -- 两次决策之间至少空多少帧
local FORCE_GAP = 150   -- 这么久还没等到画面静止，就强制决策一次

-- ============ 硬件状态读取 ============
local function bit(v, i) return math.floor(v / 2 ^ i) % 2 end
local function hex(v, n) return string.format("%0" .. (n or 2) .. "X", v or 0) end

local BGCNT = { [0] = 0x04000008, [1] = 0x0400000A, [2] = 0x0400000C, [3] = 0x0400000E }

local function read_layers()
  local disp = memory.read_u16_le(0x04000000)
  local layers = {}
  for i = 0, 3 do
    local cnt = memory.read_u16_le(BGCNT[i])
    layers[i] = {
      on = bit(disp, 8 + i) == 1,
      cnt = cnt,
      charBase = 0x06000000 + (math.floor(cnt / 4) % 4) * 0x4000,
      mapBase  = 0x06000000 + (math.floor(cnt / 256) % 32) * 0x800,
      bpp8     = bit(cnt, 7) == 1,
    }
  end
  return disp, layers
end

-- 把某层的 30x20 图块编号读成行文本
local function read_grid(layer)
  local rows, fp = {}, 5381
  for ty = 0, 19 do
    local t = {}
    for tx = 0, 29 do
      local e = memory.read_u16_le(layer.mapBase + (ty * 32 + tx) * 2)
      local tile = e % 1024
      t[#t + 1] = string.format("%2d", tile)
      fp = (fp * 33 + tile) % 65536
    end
    rows[#rows + 1] = "  " .. table.concat(t, " ")
  end
  return rows, fp
end

-- OAM：精灵坐标（战棋里通常=单位）
local function read_oam()
  local list, fp = {}, 5381
  for i = 0, 127 do
    local a = 0x07000000 + i * 8
    local a0 = memory.read_u16_le(a)
    local a1 = memory.read_u16_le(a + 2)
    local a2 = memory.read_u16_le(a + 4)
    -- 关闭态：attr0 bit8=1 (disable)，或整条目全零（mGBA/多数游戏的未使用槽位）
    local disabled = math.floor(a0 / 512) % 2 == 1
    local x = a1 % 512
    local y = a0 % 256
    local unused = (a0 == 0 and a1 == 0 and a2 == 0) or y >= 200
    if not disabled and not unused and x < 260 then
      -- 尺寸：attr0 bits14-15
      local shape = math.floor(a0 / 16384) % 4
      local size = math.floor(a1 / 16384) % 4
      list[#list + 1] = string.format("  (%3d,%3d) shape=%d size=%d tile=%d pal=%d",
        x, y, shape, size, a2 % 1024, math.floor(a2 / 4096))
      fp = (fp * 33 + x * 7 + y * 13 + i) % 65536
    end
  end
  return list, fp
end

-- RAM 变化：只报"是否在动"和活跃块，不刷屏
local function read_mem_marks()
  local out = {}
  for _, r in ipairs({ { "IWRAM", 0x03000000, 4 }, { "EWRAM", 0x02000000, 5 } }) do
    local tag, base, nblk = r[1], r[2], r[3]
    for b = 0, nblk - 1 do
      local addr = base + b * 4096
      local ok, bytes = pcall(memory.readbyterange, addr, 4096)
      local nz = 0
      if ok and bytes then
        -- 抽样统计（每 16 字节取 1 个），足够判断"这块有没有在用"
        for j = 0, 4095, 16 do if (bytes[j] or 0) ~= 0 then nz = nz + 1 end end
        nz = nz * 16
      end
      if nz > 0 then
        out[#out + 1] = string.format("  %s 0x%08X 非空 %d%%", tag, addr, math.floor(nz * 100 / 4096))
      end
    end
  end
  return out
end

-- 生成完整状态文本；同时返回指纹用于判断画面是否静止
local function build_state(frame)
  local disp, layers = read_layers()
  local L = {}
  local fp = ""

  L[#L + 1] = "step=" .. step .. " frame=" .. frame
  L[#L + 1] = string.format("DISPCNT=0x%04X", disp)

  local mode = disp % 8
  L[#L + 1] = string.format("GFXMODE=%d (%s)", mode,
    (mode >= 3) and "位图模式，无 tilemap" or "文本/图块模式")

  for i = 0, 3 do
    local b = layers[i]
    if b.on then
      L[#L + 1] = string.format("BG%d: 开启 %s map=0x%08X char=0x%08X",
        i, b.bpp8 and "8bpp" or "4bpp", b.mapBase, b.charBase)
    end
  end

  if mode >= 3 then
    -- 位图模式（3=16bpp、4=8bpp+调色板、5=小尺寸16bpp）：
    -- VRAM 里是像素而非 tile 索引，读 GRID 只会得到垃圾，必须跳过。
    local acc, nz = 5381, 0
    local limit = (mode == 5) and 0xA000 or 0x12C00
    for off = 0, limit - 1, 0x100 do
      local v = memory.read_u16_le(0x06000000 + off)
      acc = (acc * 33 + v) % 65536
      if v ~= 0 then nz = nz + 1 end
    end
    L[#L + 1] = string.format("BITMAP: 显存抽样 %d/300 点非空, fp=%d（画面静止时不变）", nz, acc)
    L[#L + 1] = "GRID: 不适用（位图模式没有图块网格；不要据此臆测地图/光标）"
    fp = fp .. "b" .. acc
  else

  -- 优先输出"有内容"的那一层
  local best, bestNz = nil, -1
  for i = 0, 3 do
    if layers[i].on then
      local _, f = read_grid(layers[i])
      local nz = 0
      for ty = 0, 19 do
        for tx = 0, 29 do
          local e = memory.read_u16_le(layers[i].mapBase + (ty * 32 + tx) * 2)
          if e % 1024 ~= 0 then nz = nz + 1 end
        end
      end
      if nz > bestNz then best, bestNz = i, nz end
    end
  end

  if best then
    L[#L + 1] = string.format("GRID(BG%d 30x20, 0=空, 其他=图块编号, 网格非空格=%d):", best, bestNz)
    local rows, gfp = read_grid(layers[best])
    for _, r in ipairs(rows) do L[#L + 1] = r end
    fp = fp .. "g" .. gfp
  end

  end

  local oam, ofp = read_oam()
  L[#L + 1] = string.format("OAM: %d 个精灵（%s）", #oam, #oam == 0 and "无单位/无光标" or "坐标单位为像素")
  for _, o in ipairs(oam) do L[#L + 1] = o end
  fp = fp .. "o" .. ofp

  local mm = read_mem_marks()
  L[#L + 1] = "MEM: 活跃 RAM 块"
  for _, m in ipairs(mm) do L[#L + 1] = m end

  return table.concat(L, "\n") .. "\n", fp
end

-- ============ 动作 ============
local function log(s) console.log("[ai] " .. tostring(s)) end

local function press(key)
  local k = KEYMAP[key]
  if not k then return end
  -- 关键 1：不要传第二个参数（player 索引）。GBA 只有 1 个控制器，
  -- 传 1 会越界，BizHawk 静默丢弃，按键永远不生效（踩过，见 HANDOFF）。
  -- 关键 2：joypad.set 只对"当前一帧"有效，必须每帧 set 才是真的按住。
  -- 菜单只认"新按下"所以按 1 帧就够；但地图光标是按住才动（带重复延迟），
  -- 只 set 一次会出现"菜单能用、光标不动"的假死（踩了很久，见 HANDOFF §13）。
  local frames = DIRKEYS[k] and HOLD_DIR or HOLD_BTN
  for _ = 1, frames do
    joypad.set({ [k] = true })
    emu.frameadvance()
  end
  joypad.set({})
  for _ = 1, GAP do emu.frameadvance() end
end

local function idle(n) for _ = 1, (n or 10) do emu.frameadvance() end end

-- ============ 启动 ============
local function try(f, ...)
  local ok, err = pcall(f, ...)
  if not ok then console.log("[ai] 跳过: " .. tostring(err):sub(1, 60)) end
end
try(client.speedmode, SPEED)
try(client.setsoundon, false)
try(comm.httpsettimeout, 180000)

-- SL 大法：有存档点就直接跳进去，省掉开场 40 秒
if LOAD_STATE and LOAD_STATE ~= "" then
  local f = io.open(LOAD_STATE, "r")
  if f then
    f:close()
    local ok = pcall(savestate.load, LOAD_STATE)
    log((ok and "已载入存档点 " or "存档点载入失败 ") .. LOAD_STATE)
    for _ = 1, 10 do emu.frameadvance() end
  else
    log("没有存档点，从头开始")
  end
end

log("内存驱动模式启动，状态文件 " .. STATE)

while step < MAXSTEP do
  -- 抓两帧状态，相同 = 画面静止 = 等待玩家输入，这时才值得让模型决策。
  -- 但战场里光标会闪，画面永远"在动"，所以要加两个兜底：
  --   MIN_GAP  两次决策至少隔这么多帧（防止一路狂按）
  --   FORCE_GAP 隔太久没决策就强制决策一次（战场/菜单长动画）
  local s1, fp1 = build_state(emu.framecount())
  emu.frameadvance()
  local s2, fp2 = build_state(emu.framecount())

  local since = emu.framecount() - lastDecision
  local ready = (fp1 == fp2 and since > MIN_GAP) or since > FORCE_GAP

  if ready then
    lastDecision = emu.framecount()
    -- 视觉模式要的截图（brain_file.py --vision 会读它）
    pcall(client.screenshot, SHOT)
    -- 状态静止 = 游戏在等输入，此时才值得让模型决策
    local okw = pcall(function()
      local f = io.open(STATE, "w")
      if not f then error("open fail") end
      f:write(s2)
      f:close()
    end)
    if not okw then
      pcall(comm.mmfWrite, "state.txt", s2)   -- io 被沙箱禁用时的回退
      log("io 不可用，已回退 mmfWrite")
    end

    -- 等模型回复：轮询 action.txt，直到里面的 step 与本次相同
    local resp = nil
    for _ = 1, WAIT_TRIES do
      local f = io.open(ACTION, "r")
      if f then
        local txt = f:read("*a") or ""
        f:close()
        local got = txt:match("step=(%d+)")
        if got and tonumber(got) == step then
          resp = txt
          break
        end
      end
      -- 用真实时间等待，避免全速模式下"帧数很快就跑完"
      local oks = pcall(client.sleep, 50)
      if not oks then emu.frameadvance() end
    end

    if resp then
      local wait = 12
      local acts = {}
      for line in resp:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%u_]+):%s*(.*)$")
        if k == "ACT" then table.insert(acts, v)
        elseif k == "WAIT" then wait = tonumber(v) or 12
        elseif k == "THOUGHT" then log(string.format("#%d %s", step, v)) end
      end
      for _, a in ipairs(acts) do
        press(a)
        lastAct = a
      end
      idle(wait)
      step = step + 1
    else
      log("等待模型超时，跳过该步")
      idle(20)
      step = step + 1
    end
    prevFp = fp2
  else
    idle(6)
  end
end

log("达到步数上限，停止")
client.pause()
