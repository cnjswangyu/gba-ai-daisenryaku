--[[
  GBA 内存扫描器：把 RAM 结构化成文本，供纯文本模型分析。

  输出（logs/mem_scan.txt）：
    1. 内存域列表与大小
    2. EWRAM / IWRAM 按 4KB 分块的"占用率 + 指纹"
    3. 间隔 N 帧后的变化块（哪些区域在动 = 游戏状态区）
    4. 变化最活跃的几块的 hexdump

  这套东西不依赖视觉，也不需要先知道游戏内部结构。
]]

local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/mem_scan.txt"

local lines = {}
local function w(s) lines[#lines + 1] = s end
local function hex(v, n) return string.format("%0" .. (n or 2) .. "X", v or 0) end

-- ---------- 工具 ----------
local function block_scan(base, size, blk)
  local n = math.floor(size / blk)
  local out = {}
  for i = 0, n - 1 do
    local addr = base + i * blk
    local ok, bytes = pcall(memory.readbyterange, addr, blk)
    local nz, h = 0, 5381
    if ok and bytes then
      for j = 0, blk - 1 do
        local v = bytes[j] or 0
        if v ~= 0 then nz = nz + 1 end
        h = (h * 33 + v) % 65536
      end
    end
    out[i] = { addr = addr, nz = nz, hash = h, bytes = ok and bytes or nil }
  end
  return out
end

local function summarize(name, blocks, blk)
  w("")
  w(string.format("=== %s：%d 块 x %d 字节 ===", name, #blocks, blk))
  local active = 0
  for i = 0, #blocks - 1 do
    local b = blocks[i]
    local pct = math.floor(b.nz * 100 / blk)
    if b.nz > 0 then active = active + 1 end
    w(string.format("  0x%08X  used=%3d%%  fp=%s", b.addr, pct, hex(b.hash, 4)))
  end
  w(string.format("  非空块：%d / %d", active, #blocks))
end

-- ---------- 推进到游戏内 ----------
client.speedmode(0)
pcall(client.setsoundon, false)

local function press(k)
  joypad.set({ [k] = true })
  for _ = 1, 4 do emu.frameadvance() end
  joypad.set({})
  for _ = 1, 25 do emu.frameadvance() end
end

for _ = 1, 90 do emu.frameadvance() end
press("A"); press("A")
for _ = 1, 60 do emu.frameadvance() end

-- ---------- 1. 内存域 ----------
w("=== memory domains ===")
local okd, list = pcall(memory.getmemorydomainlist)
if okd and list then
  for _, d in ipairs(list) do
    local oks, sz = pcall(memory.getmemorydomainsize, d)
    w(string.format("  %s  size=%s", tostring(d), tostring(oks and sz or "?")))
  end
else
  w("  (getmemorydomainlist failed)")
end

-- ---------- 2. 首次快照 ----------
local EWRAM, IWRAM, BLK = 0x02000000, 0x03000000, 4096
local e1 = block_scan(EWRAM, 0x40000, BLK)
local i1 = block_scan(IWRAM, 0x8000, BLK)

summarize("EWRAM", e1, BLK)
summarize("IWRAM", i1, BLK)

-- ---------- 3. 间隔 60 帧后再扫，找变化块 ----------
for _ = 1, 60 do emu.frameadvance() end

local e2 = block_scan(EWRAM, 0x40000, BLK)
local i2 = block_scan(IWRAM, 0x8000, BLK)

local changed = {}
for i = 0, #e1 - 1 do
  if e1[i].hash ~= e2[i].hash then
    changed[#changed + 1] = { tag = "EWRAM", addr = e1[i].addr, a = e1[i], b = e2[i] }
  end
end
for i = 0, #i1 - 1 do
  if i1[i].hash ~= i2[i].hash then
    changed[#changed + 1] = { tag = "IWRAM", addr = i1[i].addr, a = i1[i], b = i2[i] }
  end
end

w("")
w(string.format("=== 60 帧内发生变化的块：%d 个 ===", #changed))
for k = 1, math.min(#changed, 40) do
  local c = changed[k]
  w(string.format("  %s 0x%08X  used %d%% -> %d%%  fp %s -> %s",
    c.tag, c.addr, math.floor(c.a.nz * 100 / BLK), math.floor(c.b.nz * 100 / BLK),
    hex(c.a.hash, 4), hex(c.b.hash, 4)))
end
if #changed == 0 then
  w("  （画面静止：当前停在等待输入的状态，这正是下指令的好时机）")
end

-- ---------- 4. 活跃块的 hexdump（取变化最多的前 3 块）----------
w("")
w("=== 活跃块 hexdump ===")
for k = 1, math.min(#changed, 3) do
  local c = changed[k]
  w(string.format("-- %s 0x%08X --", c.tag, c.addr))
  local bytes = c.b.bytes
  if bytes then
    for row = 0, 15 do
      local t = {}
      for col = 0, 15 do
        t[#t + 1] = hex(bytes[row * 16 + col] or 0, 2)
      end
      w(string.format("  +%03X  %s", row * 16, table.concat(t, " ")))
    end
  end
end

-- ---------- 输出 ----------
local text = table.concat(lines, "\n") .. "\n"
local okw = pcall(function()
  local f = io.open(OUT, "w")
  if not f then error("io.open failed") end
  f:write(text)
  f:close()
end)
if not okw then pcall(comm.mmfWrite, "mem_scan.txt", text) end

client.pause()
