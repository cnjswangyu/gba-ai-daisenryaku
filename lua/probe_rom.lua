--[[
  通用 ROM 冒烟探测：加载后按固定节奏推进，并在关键节点截图 + dump 内存指纹。
  目的：确认 ROM 能否在 BizHawk 里正常启动（不是黑屏/白屏/崩溃）。
  输出：logs/probe_rom.txt + shots/rom_*.png
]]

local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_rom.txt"
local SHOT = BASE .. "shots/"

local lines = {}
local function w(s) lines[#lines + 1] = s end
local function log(s) pcall(console.log, "[probe] " .. tostring(s)) end

local function hex(v, n) return string.format("%0" .. (n or 2) .. "X", v or 0) end

-- 屏幕指纹：用 VRAM/OAM/PALRAM 抽样，不依赖截图
local function memfp()
  local acc = 5381
  local function mix(v) acc = (acc * 33 + v) % 1000003 end
  for _, a in ipairs({ 0x05000000, 0x06000000, 0x07000000 }) do
    for off = 0, 0x1000 - 1, 32 do
      local ok, v = pcall(memory.read_u16_le, a + off)
      if ok then mix(v or 0) end
    end
  end
  return acc
end

local function snap(tag, frame)
  local ok = pcall(client.screenshot, SHOT .. "rom_" .. tag .. ".png")
  w(string.format("%-10s frame=%-6d fp=%-8d shot=%s", tag, frame, memfp(), ok and "ok" or "FAIL"))
end

local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

local function press(key, hold, gap)
  pcall(joypad.set, { [key] = true }, 1)
  adv(hold or 3)
  pcall(joypad.set, {}, 1)
  adv(gap or 20)
end

-- ---------- 启动 ----------
pcall(client.speedmode, 0)          -- 全速
pcall(client.setsoundon, false)

w("=== ROM probe ===")
local oks, sys = pcall(emu.getsystemid)
w("system   = " .. tostring(oks and sys or "ERR"))
local okr, romname = pcall(emu.getromname)
w("romname  = " .. tostring(okr and romname or "ERR"))
local okg, romhash = pcall(emu.getromhash)
w("romhash  = " .. tostring(okg and romhash or "ERR"))
w("")

-- 0.5 秒后先看第一帧（黑屏就是没起来）
adv(30)
snap("f030", emu.framecount())

-- 标题画面通常 2~4 秒
adv(120)
snap("f150", emu.framecount())
adv(120)
snap("f270", emu.framecount())

-- 尝试进入游戏：A / START / 连按
press("A", 4, 60)
snap("after_A1", emu.framecount())
press("Start", 4, 90)
snap("after_ST", emu.framecount())
press("A", 4, 60)
snap("after_A2", emu.framecount())

-- 停留 3 秒看是否进入标题后画面/演示
adv(180)
snap("f_end", emu.framecount())

-- ---------- 内存布局 ----------
w("")
w("=== 内存域 ===")
local okd, domains = pcall(memory.getmemorydomains)
if okd and domains then
  for _, d in ipairs(domains) do w("  " .. tostring(d)) end
else
  w("  (failed)")
end

w("")
w("=== 活跃 RAM 块（非零抽样） ===")
for _, r in ipairs({
  { "EWRAM", 0x02000000, 8 }, { "IWRAM", 0x03000000, 8 },
  { "VRAM", 0x06000000, 6 }, { "OAM", 0x07000000, 1 }, { "PALRAM", 0x05000000, 1 },
}) do
  local tag, base, nblk = r[1], r[2], r[3]
  for b = 0, nblk - 1 do
    local addr = base + b * 4096
    local ok, bytes = pcall(memory.readbyterange, addr, 4096)
    local nz = 0
    if ok and bytes then
      for j = 0, 4095, 16 do if (bytes[j] or 0) ~= 0 then nz = nz + 1 end end
      nz = nz * 16
    end
    if nz > 0 then
      w(string.format("  %-7s 0x%08X 非空 %d%%", tag, addr, math.floor(nz * 100 / 4096)))
    end
  end
end

w("")
w("=== DISPCNT / BG 配置 ===")
local function bit(v, i) return math.floor(v / 2 ^ i) % 2 end
local disp = memory.read_u16_le(0x04000000)
w(string.format("  DISPCNT = 0x%s  (mode=%d BG0=%d BG1=%d BG2=%d BG3=%d OBJ=%d)",
  hex(disp, 4), disp % 8, bit(disp, 8), bit(disp, 9), bit(disp, 10), bit(disp, 11), bit(disp, 12)))
for i = 0, 3 do
  local cnt = memory.read_u16_le(0x04000008 + i * 2)
  local on = bit(disp, 8 + i)
  w(string.format("  BG%dCNT = 0x%s  %s  char=0x%08X map=0x%08X %s",
    i, hex(cnt, 4), on == 1 and "开启" or "关闭",
    0x06000000 + (math.floor(cnt / 4) % 4) * 0x4000,
    0x06000000 + (math.floor(cnt / 256) % 32) * 0x800,
    bit(cnt, 7) == 1 and "8bpp" or "4bpp"))
end

w("")
w("=== OAM 活跃精灵 ===")
local n = 0
for i = 0, 127 do
  local a0 = memory.read_u16_le(0x07000000 + i * 8)
  local a1 = memory.read_u16_le(0x07000000 + i * 8 + 2)
  local a2 = memory.read_u16_le(0x07000000 + i * 8 + 4)
  local disabled = math.floor(a0 / 512) % 2 == 1
  local x, y = a1 % 512, a0 % 256
  if not disabled and x < 260 and y < 200 then
    n = n + 1
    if n <= 20 then
      w(string.format("  #%03d x=%3d y=%3d tile=%4d pal=%d", i, x, y, a2 % 1024, math.floor(a2 / 4096)))
    end
  end
end
w("  合计 " .. n .. " 个")

-- ---------- 写文件 ----------
local text = table.concat(lines, "\n") .. "\n"
local okw = pcall(function()
  local f = io.open(OUT, "w")
  if not f then error("io.open failed") end
  f:write(text)
  f:close()
end)
if not okw then pcall(comm.mmfWrite, "probe_rom.txt", text) end

log("done")

-- 退出模拟器，避免留下 GUI 进程
pcall(client.exit)
