-- probe_stuck.lua —— 诊断：出击后的 state7 光标为何不动
-- 调试用（按键仅用于复现路径）；验证：①自动部署是否真的放了单位 ②输入通道状态
-- ③邮箱补丁（内存写按键）能否移动光标。卡住状态存为 stage1_stuck.State 供复用。
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_stuck.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/ps_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 60)
end

local CTX = 0x03000480
local U   = 0x03002BE2
local MAIL = 0x03007F00
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80 }

local function state() return memory.read_u8(CTX) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function keyinput() return memory.read_u16_le(0x04000130) end
local function snap(tag)
  w(string.format("%-14s f=%-6d state=%d sub=%d ph=%d side=%d KEYINPUT=%03X newkey=%03X hold=%03X cur=(%d,%d)",
    tag, emu.framecount(), state(), memory.read_u8(CTX + 1),
    memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22),
    keyinput(), memory.read_u16_le(CTX + 0x0C), memory.read_u16_le(CTX + 0x0E), cur()))
end
local function units_dump(tag)
  for _, side in ipairs({ "MY", "EN" }) do
    local base0 = (side == "MY") and U or (U + 0x600)
    local n, pos = 0, {}
    for k = 0, 63 do
      local b = base0 + k * 24 - 2
      local id = memory.read_u16_le(b)
      if id ~= 0 then
        n = n + 1
        if #pos < 20 then
          pos[#pos + 1] = string.format("%d:(%d,%d)hp%d", id,
            memory.read_u8(b + 2), memory.read_u8(b + 3), memory.read_u8(b + 6))
        end
      end
    end
    w(string.format("%s %d: %s", side, n, table.concat(pos, " ")))
  end
end

-- 邮箱补丁：把 IWRAM 读键字面量指向邮箱（逆向出的输入接口）
local function patch_mail()
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  memory.write_u16_le(MAIL, 0x3FF)
  w("邮箱补丁：IWRAM " .. #hits .. " 处 " ..
    ((#hits > 0) and ("首处 0x" .. string.format("%08X", hits[1])) or "(战场态可能还没复制)"))
  return #hits
end
-- 邮箱写按键：按下 hold 帧（每帧都要写，游戏每帧读）
local function mail_hold(k, frames)
  for _ = 1, (frames or 5) do
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    adv(1)
  end
  memory.write_u16_le(MAIL, 0x3FF)
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 400)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/stage1_ready.State")
  adv(60)
  -- 复现路径（调试）：确认自动部署 → 开始战斗 → 清横幅
  press("Start", 6, 90)
  press("A", 6, 120)
  adv(450)
  snap("setup_phase"); shot("setup"); units_dump("配置阶段")
  press("Start", 6, 90)
  press("A", 6, 120)      -- 「开始战斗」
  for i = 1, 24 do
    adv(60)
    if state() == 7 and memory.read_u8(CTX + 1) == 1
        and memory.read_u8(CTX + 0x21) == 3 and memory.read_u8(CTX + 0x22) == 0 then
      w("进入玩家操作阶段（第 " .. i .. " 探）"); break
    end
    press("A", 6, 40)
  end
  adv(120)
  snap("stuck_candidate"); shot("stuck"); units_dump("卡点")

  savestate.save(BASE .. "states/stage1_stuck.State")
  w("已存 stage1_stuck.State")

  -- ===== 输入通道诊断 =====
  w("--- 诊断 1：joypad 方向键（14 帧 hold）---")
  local x0, y0 = cur()
  press("Left", 14, 8)
  local x1, y1 = cur()
  w(string.format("joypad Left: (%d,%d) -> (%d,%d) %s", x0, y0, x1, y1,
    (x0 ~= x1 or y0 ~= y1) and "动了" or "没动"))
  snap("after_joy")

  w("--- 诊断 2：邮箱补丁 + 内存写按键 ---")
  local n = patch_mail()
  snap("after_patch")
  -- 写 Right 到邮箱，观察 KEYINPUT 视图与光标
  memory.write_u16_le(MAIL, 0x3FF - 0x10)
  adv(2)
  w(string.format("邮箱按住 Right 中: KEYINPUT硬件=%03X ctx新键=%03X ctx按住=%03X",
    keyinput(), memory.read_u16_le(CTX + 0x0C), memory.read_u16_le(CTX + 0x0E)))
  mail_hold("Right", 6)
  adv(6)
  local x2, y2 = cur()
  w(string.format("邮箱 Right 后光标: (%d,%d) -> (%d,%d) %s", x1, y1, x2, y2,
    (x1 ~= x2 or y1 ~= y2) and "动了" or "没动"))
  snap("after_mail")

  -- 若邮箱也不动，试 A 键（也许这不是地图态而是某个等待）
  w("--- 诊断 3：邮箱 A 键 ---")
  mail_hold("A", 4)
  adv(30)
  snap("after_mailA"); shot("after_mailA")
  units_dump("最后")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
