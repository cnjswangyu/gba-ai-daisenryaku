--[[
  内存结构探测：确认 BizHawk 能否按 GBA 总线地址读内存，
  并把 IO 寄存器 / OAM / VRAM / WRAM 的实际内容 dump 出来。
]]

local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/mem_probe.txt"

local lines = {}
local function w(s) lines[#lines + 1] = s end

local function hex(v, n)
  return string.format("%0" .. (n or 2) .. "X", v or 0)
end

-- ---------- 启动 / 推进 ----------
client.speedmode(0)
pcall(client.setsoundon, false)

for _ = 1, 90 do emu.frameadvance() end

-- 按两次 A，尝试从标题进游戏
local function press(k)
  local km = { A = "A", START = "Start" }
  joypad.set({ [km[k] or k] = true })
  for _ = 1, 4 do emu.frameadvance() end
  joypad.set({})
  for _ = 1, 30 do emu.frameadvance() end
end
press("A")
press("A")

for _ = 1, 60 do emu.frameadvance() end

-- ---------- 1. 内存域 ----------
w("=== memory domains ===")
local okd, domains = pcall(memory.getmemorydomains)
if okd and domains then
  for _, d in ipairs(domains) do w("  " .. tostring(d)) end
else
  w("  (failed)")
end

w("")
w("=== frame = " .. emu.framecount() .. "  system = " .. tostring(emu.getsystemid()) .. " ===")

-- ---------- 2. 关键 IO 寄存器 ----------
w("")
w("=== IO registers (GBA 0x04000000) ===")
local io_regs = {
  { 0x04000000, "DISPCNT" },
  { 0x04000008, "BG0CNT" },
  { 0x0400000A, "BG1CNT" },
  { 0x0400000C, "BG2CNT" },
  { 0x0400000E, "BG3CNT" },
  { 0x04000010, "BG0HOFS" },
  { 0x04000012, "BG0VOFS" },
  { 0x04000014, "BG1HOFS" },
  { 0x04000016, "BG1VOFS" },
  { 0x04000018, "BG2HOFS" },
  { 0x0400001A, "BG2VOFS" },
  { 0x04000048, "WININ" },
  { 0x0400004A, "WINOUT" },
  { 0x04000050, "BLDCNT" },
  { 0x040000B0, "DMA0SAD_L" },
  { 0x04000208, "IME" },
  { 0x04000202, "IE" },
}
for _, r in ipairs(io_regs) do
  local ok, v = pcall(memory.read_u16_le, r[1])
  w(string.format("  %s 0x%08X = 0x%s (%d)", r[2], r[1], ok and hex(v, 4) or "ERR", ok and v or -1))
end

-- ---------- 3. OAM 精灵 ----------
w("")
w("=== OAM sprites (0x07000000, 128 entries) ===")
local shown = 0
for i = 0, 127 do
  local a = 0x07000000 + i * 8
  local ok0, a0 = pcall(memory.read_u16_le, a + 0)
  local ok1, a1 = pcall(memory.read_u16_le, a + 2)
  local ok2, a2 = pcall(memory.read_u16_le, a + 4)
  if ok0 and ok1 and ok2 then
    local y = a0 % 256
    local x = a1 % 512
    local tile = a2 % 1024
    local pal = math.floor(a2 / 4096)
    -- 只打印"看起来活跃"的：坐标在屏幕附近
    if x < 300 and y < 200 and (x > 0 or y > 0) then
      w(string.format("  #%03d x=%3d y=%3d tile=%4d pal=%d attr0=%s attr1=%s",
        i, x, y, tile, pal, hex(a0, 4), hex(a1, 4)))
      shown = shown + 1
      if shown >= 24 then break end
    end
  end
end
if shown == 0 then w("  (无活跃精灵)") end

-- ---------- 4. BG tilemap 摘要 ----------
w("")
w("=== BG screen blocks (0x0600E000 起，2KB/块) ===")
for blk = 0, 3 do
  local base = 0x0600E000 + blk * 0x800
  local nz, first = 0, nil
  for i = 0, 31 * 32 - 1, 1 do
    local ok, v = pcall(memory.read_u16_le, base + i * 2)
    if ok and v ~= 0 then
      nz = nz + 1
      if not first then first = { i, v } end
    end
  end
  w(string.format("  block %d: 非零 tile 数=%d  first=%s",
    blk, nz, first and string.format("idx%d=0x%s", first[1], hex(first[2], 4)) or "-"))
end

-- 打印 block 前 64 个 tile index（一行 16 个）
for blk = 0, 1 do
  local base = 0x0600E000 + blk * 0x800
  w("  block " .. blk .. " 前 64 项 tile index:")
  for row = 0, 3 do
    local t = {}
    for col = 0, 15 do
      local ok, v = pcall(memory.read_u16_le, base + (row * 32 + col) * 2)
      t[#t + 1] = ok and string.format("%3d", v % 1024) or "  ?"
    end
    w("    " .. table.concat(t, " "))
  end
end

-- ---------- 5. 内存区快照 ----------
local function dump_region(name, base, len)
  w("")
  w(string.format("=== %s 0x%08X (%d bytes) ===", name, base, len))
  local zero = 0
  for off = 0, len - 1 do
    local ok, v = pcall(memory.read_u8, base + off)
    if ok and v == 0 then zero = zero + 1 end
  end
  w(string.format("  零字节占比: %d/%d", zero, len))

  for row = 0, 7 do
    local t = {}
    for col = 0, 15 do
      local ok, v = pcall(memory.read_u8, base + row * 16 + col)
      t[#t + 1] = ok and hex(v, 2) or "??"
    end
    w(string.format("  +%04X  %s", row * 16, table.concat(t, " ")))
  end
end

dump_region("EWRAM", 0x02000000, 256)
dump_region("IWRAM", 0x03000000, 256)

-- ---------- 写文件 ----------
local text = table.concat(lines, "\n") .. "\n"
local okw = pcall(function()
  local f = io.open(OUT, "w")
  if not f then error("io.open failed") end
  f:write(text)
  f:close()
end)
if not okw then
  pcall(comm.mmfWrite, "mem_probe.txt", text)
end

client.pause()
