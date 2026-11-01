--[[
  GBA AI 代理：BizHawk 侧主循环
  用法：
    1) 先启动 brain.py（监听 8765）
    2) EmuHawk.exe <rom.gba> --lua="gba_agent.lua"

  每步流程：
    抓当前帧 + 上一帧 -> 发给 brain.py -> brain 判断画面是否稳定/该按什么键
    -> 本脚本执行按键并空转 wait 帧
--]]

-- ============ 配置 ============
local BASE   = "D:/prog/gba-ai/"
local URL    = "http://127.0.0.1:8765/step"
local SHOT_A = BASE .. "shots/cur.png"
local SHOT_B = BASE .. "shots/prev.png"
local SPEED  = 0        -- 0 = 不限速；100 = 原速
local HOLD   = 3        -- 每个按键按住多少帧
local GAP    = 3        -- 按键之间松开多少帧
local WARMUP = 0        -- 开跑前先空按几次 A（跳过标题画面用）
local MAXIDLE = 4000    -- 连续无有效响应的上限，防止死循环

-- ============ 键名映射（BizHawk GBA 控制器习惯写法）============
local KEYMAP = {
  A = "A", B = "B", L = "L", R = "R",
  START = "Start", SELECT = "Select",
  UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right",
}

local step, lastAct = 0, ""

local function log(s)
  console.log("[ai] " .. tostring(s))
end

local function press(key)
  local k = KEYMAP[key]
  if not k then return end
  joypad.set({ [k] = true })
  for _ = 1, HOLD do emu.frameadvance() end
  joypad.set({})
  for _ = 1, GAP do emu.frameadvance() end
end

local function idle(n)
  for _ = 1, (n or 10) do emu.frameadvance() end
end

-- ============ 启动 ============
-- BizHawk 的 Lua 方法名大小写不统一，统一用 pcall 兜住，缺哪个都不至于中断
local function try(f, ...)
  local ok, err = pcall(f, ...)
  if not ok then console.log("[ai] 跳过: " .. tostring(err):sub(1, 80)) end
end

try(client.setsoundon, false)
try(client.speedmode, SPEED)
try(client.displaymessages, false)
try(comm.httpsettimeout, 180000)

log("已连接 brain: " .. URL)
log("SpeedMode=" .. tostring(SPEED) .. "  按键保持=" .. HOLD .. "帧")

if WARMUP > 0 then
  for _ = 1, WARMUP do press("A") end
end

local idleCount = 0

while true do
  local frame = emu.framecount()

  -- 连抓两帧，交给 brain 判断画面是否已静止（静止=等待玩家输入）
  client.screenshot(SHOT_A)
  emu.frameadvance()
  client.screenshot(SHOT_B)

  local payload = string.format(
    "frame=%d\nshot=%s\nprev=%s\nstep=%d\nlast=%s\n",
    frame, SHOT_A, SHOT_B, step, lastAct
  )

  local ok, resp = pcall(comm.httpPost, URL, payload)

  if not ok or resp == nil or resp == "" then
    idleCount = idleCount + 1
    if idleCount % 20 == 0 then
      log("brain 无响应（" .. idleCount .. "），确认 brain.py 是否在跑")
    end
    if idleCount > MAXIDLE then
      log("放弃：连续无响应过多")
      client.pause()
      break
    end
    idle(30)
  else
    idleCount = 0
    local wait = 10
    local acts = {}

    for line in resp:gmatch("[^\r\n]+") do
      local k, v = line:match("^([%u_]+):%s*(.*)$")
      if k == "ACT" then
        table.insert(acts, v)
      elseif k == "WAIT" then
        wait = tonumber(v) or 10
      elseif k == "THOUGHT" then
        log(string.format("#%d %s", step, v))
      end
    end

    for _, a in ipairs(acts) do
      press(a)
      lastAct = a
    end
    idle(wait)
    step = step + 1
  end
end
