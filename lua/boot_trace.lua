-- boot_trace.lua v2 —— 冷启动全流程 trace
-- 修复：v1 的内存域寻址错误（无效域名静默读零）。本版所有批量读走 "System Bus" + 绝对地址。
-- 每个界面切换点记录：
--   1) 屏幕指纹（DISPCNT 掩翻页位 + BG 配置 + OAM 活跃数 + VRAM 采样哈希）
--   2) IWRAM/EWRAM/VRAM/PALRAM/OAM 的 128 字节块级 diff（ROM 数据落点）
--   3) 窗口内 PC 直方图（哪些函数在跑）
--   4) 全量快照落盘 logs/boot_snaps/（供离线找"界面状态变量"）
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/boot_trace.txt"
local SHOT = BASE .. "shots/tr_"
local SNAP = BASE .. "logs/boot_snaps/"
local SB   = "System Bus"
local BLK  = 128

local REGIONS = {
  { "IWRAM",  0x03000000, 0x8000  },
  { "EWRAM",  0x02000000, 0x40000 },
  { "VRAM",   0x06000000, 0x18000 },
  { "PALRAM", 0x05000000, 0x400   },
  { "OAM",    0x07000000, 0x400   },
}

local lines = {}
local function w(s) lines[#lines + 1] = s end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

local frame = 0
local pcHist, winStart = {}, 0
local snaps = {}          -- name -> binary string
local lastSig, sigCount, pending = nil, 0, nil
local screenNo = 0

local function rd(a, l)
  local ok, s = pcall(memory.read_bytes_as_binary_string, a, l, SB)
  if ok and type(s) == "string" and #s == l then return s end
  error("read failed @" .. string.format("0x%08X", a))
end

local function oamActive()
  local n = 0
  for i = 0, 127 do
    local a0 = memory.read_u16_le(0x07000000 + i * 8)
    if a0 ~= 0 and (a0 & 0x0200) == 0 then n = n + 1 end
  end
  return n
end

local function sigNow()
  local d  = memory.read_u16_le(0x04000000) & 0xFFEF   -- 掩掉 mode4/5 翻页位
  local b0 = memory.read_u16_le(0x04000008)
  local b2 = memory.read_u16_le(0x0400000C)
  local n  = oamActive()
  local h  = 0
  for _, a in ipairs({ 0x06000000, 0x06000800, 0x0600A000, 0x0600A800 }) do
    local s = rd(a, 64)
    for i = 1, 64 do h = (h * 31 + string.byte(s, i)) & 0xFFFF end
  end
  return string.format("%04X/%04X/%04X/%03d/%04X", d, b0, b2, n, h)
end

local function changedBlocks(old, new, base)
  local out = {}
  if not old then return out end
  local i, n = 1, #old
  while i <= n do
    local e = i + BLK - 1
    for j = i, e do
      if string.byte(old, j) ~= string.byte(new, j) then
        out[#out + 1] = string.format("0x%08X", base + i - 1)
        break
      end
    end
    i = e + 1
  end
  return out
end

local function ranges(blocks)
  if #blocks == 0 then return "(无变化)" end
  local out, s, p = {}, blocks[1], blocks[1]
  for k = 2, #blocks do
    local c = blocks[k]
    if c == p + BLK then p = c
    else
      out[#out + 1] = (s == p) and string.format("0x%08X", s)
             or string.format("0x%08X-0x%08X", s, p + BLK - 1)
      s, p = c, c
    end
  end
  out[#out + 1] = (s == p) and string.format("0x%08X", s)
         or string.format("0x%08X-0x%08X", s, p + BLK - 1)
  local txt = table.concat(out, " ")
  if #txt > 900 then txt = txt:sub(1, 900) .. " ...(截断)" end
  return string.format("%d块 %s", #blocks, txt)
end

local function flush(reason)
  screenNo = screenNo + 1
  local tag = string.format("s%02d", screenNo)
  w("")
  w(string.format("===== SCREEN %d  tag=%s  frame=%d..%d (%d帧)  sig=%s  原因=%s",
    screenNo, tag, winStart, frame, frame - winStart, sigNow(), reason))
  for _, r in ipairs(REGIONS) do
    local name, base, len = r[1], r[2], r[3]
    local cur = rd(base, len)
    w(string.format("  %-6s 变化: %s", name, ranges(changedBlocks(snaps[name], cur, base))))
    snaps[name] = cur
    pcall(function()
      local f = io.open(SNAP .. tag .. "_" .. name:lower() .. ".bin", "wb"); f:write(cur); f:close()
    end)
  end
  w(string.format("  OAM 活跃精灵: %d", oamActive()))
  local arr = {}
  for pc, c in pairs(pcHist) do arr[#arr + 1] = { pc, c } end
  table.sort(arr, function(a, b) return a[2] > b[2] end)
  w("  PC 直方图 (top16, Thumb位已掩):")
  for k = 1, math.min(16, #arr) do
    w(string.format("    0x%08X  x%d", arr[k][1], arr[k][2]))
  end
  if #arr > 16 then w(string.format("    ...共 %d 个不同 PC", #arr)) end
  pcall(client.screenshot, SHOT .. tag .. ".png")
  pcHist, winStart = {}, frame + 1
end

local function mark(reason) flush(reason); pending = nil; lastSig = sigNow(); sigCount = 0 end

local function sample()
  local pc = emu.getregister("R15") or 0
  local k = pc & 0xFFFFFFFE
  pcHist[k] = (pcHist[k] or 0) + 1
  local s = sigNow()
  if s == lastSig then
    sigCount = sigCount + 1
    if sigCount == 12 and pending then flush(pending); pending = nil end
  else
    lastSig, sigCount, pending = s, 0, "sig变化"
  end
end

local function adv(n)
  for _ = 1, (n or 1) do
    emu.frameadvance()
    frame = frame + 1
    sample()
  end
end

local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 5)
  joypad.set({}); adv(gap or 30)
end
local function key(n, times) for _ = 1, times do press(n, 4, 8) end end
local function step(reason, fn) fn(); adv(20); mark(reason) end

-- ============ 驱动序列（HANDOFF §12 实测，每步打标记） ============
adv(90); flush("开机 BIOS/crt0")
step("1 汉化开机图 → A", function() press("A", 5, 150) end)
adv(180)
step("2 标题「请按开始键」 → START", function() press("Start", 6, 90) end)
adv(120)
step("3 主菜单 → A「新的游戏」", function() press("A", 6, 150) end)
step("4 姓名提示 → A", function() press("A", 6, 60) end)
step("5 输入框 → RIGHT 唤键盘", function() press("Right", 4, 40) end)
step("6 假名键盘 → A(あ)", function() press("A", 6, 50) end)
step("7 → RIGHT", function() press("Right", 4, 20) end)
step("8 → A(い)", function() press("A", 6, 50) end)
step("9 → DOWN×5 RIGHT×8 A(OK)", function() key("Down", 5); key("Right", 8); press("A", 6, 90) end)
adv(120)
step("10 国家选择 → A", function() press("A", 6, 120) end)
step("11 国歌选择 → A", function() press("A", 6, 120) end)
for i = 1, 14 do            -- 12 确认/存档/剧本选择（盲按，靠 trace 看实际屏幕）
  step(string.format("12.%d 盲目A #%d", i, i), function() press("A", 6, 100); adv(30) end)
end
step("13 出击编成表 → START", function() press("Start", 6, 120) end)
adv(150)
step("14 自动部署确认 → A", function() press("A", 6, 150) end)
adv(240)
mark("15 战场稳定")

-- 战场状态确认
w("")
w("# 战场状态确认")
local u = 0x03002BE2
for k = 0, 63 do
  local o = u + k * 24
  local x, y, fuel = memory.read_u8(o), memory.read_u8(o + 1), memory.read_u8(o + 2)
  if x > 0 and x < 64 and y > 0 and y < 64 and fuel > 0 then
    w(string.format("  US unit %d: (%d,%d) fuel=%d kind=%d", k, x, y, fuel, memory.read_u8(o + 6)))
  end
end
w(string.format("  cursor=(%d,%d) funds0=%d funds1=%d",
  memory.read_u8(0x030067FE), memory.read_u8(0x030067FF),
  memory.read_u32_le(0x030004A4), memory.read_u32_le(0x030004B0)))

local f = io.open(OUT, "w")
if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
