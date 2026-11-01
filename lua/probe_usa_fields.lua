-- 探针：在 battle_usa_live.State 战场上导出单位记录原始 24 字节，
-- 用 unitdb.tsv 的 fuel/dur 做锚点确认 +2/+4/+5/+6 各是什么。
-- 顺便 dump ctx 头部与光标格地形，并对"按 A 前后 ctx 差异"做一次快照 diff，
-- 目的：找出菜单层级的内存标志。
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_live.State"
local OUT  = BASE .. "logs/probe_usa_fields.txt"
local CTX  = 0x03000480
local U    = 0x03002BE2      -- 我方单位表
local PB   = 0x600           -- 敌方偏移
local STRIDE = 24

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/pf_" .. n .. ".png") end
local function tap(k, gap)
  for _ = 1, 3 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 30)
end

local function hexs(base, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02X", memory.read_u8(base + i)) end
  return table.concat(t, " ")
end

local function dump_units(tag, base)
  w("== " .. tag .. " base=0x" .. string.format("%08X", base) .. " ==")
  local n = 0
  for k = 0, 63 do
    local o = base + k * STRIDE
    -- 记录可能从 o-2 开始（id u16），把 o-2..o+23 全打出来
    local id = memory.read_u16_le(o - 2)
    local x, y = memory.read_u8(o), memory.read_u8(o + 1)
    local valid = (x > 0 and x < 64 and y > 0 and y < 64)
    if valid or id ~= 0 then
      n = n + 1
      w(string.format("  %02d id=%-4d (%2d,%2d) raw[-2..23]= %s", k, id, x, y, hexs(o - 2, 26)))
    end
  end
  w("  total=" .. n)
end

-- ctx 快照 / diff
local SNAP_N = 0x1000
local function snap()
  local ok, b = pcall(memory.readbyterange, CTX, SNAP_N)
  return ok and b or nil
end
local function diff(a, b, tag)
  if not a or not b then w("diff " .. tag .. " 失败"); return end
  local n = 0
  for i = 0, SNAP_N - 1 do
    if a[i] ~= b[i] then
      n = n + 1
      if n <= 60 then
        w(string.format("  DIFF ctx+0x%04X  %02X -> %02X", i, a[i], b[i]))
      end
    end
  end
  w("  DIFF " .. tag .. " 变化字节数=" .. n)
end

local function terrain(x, y)
  local p = memory.read_u32_le(CTX + 0x18)
  local cell = memory.read_u8(p + x * 4 + y * 0xC0)
  return p, cell
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(60)

  local x, y = cur()
  w(string.format("state=%d sub=%d state8=0x%02X money=%d cursor=(%d,%d) frame=%d",
    memory.read_u8(CTX), memory.read_u8(CTX + 1), memory.read_u8(CTX + 8),
    memory.read_u32_le(CTX + 0x68), x, y, emu.framecount()))
  w("ctx+0x14=0x" .. string.format("%08X", memory.read_u32_le(CTX + 0x14)))
  w("ctx+0x18=0x" .. string.format("%08X", memory.read_u32_le(CTX + 0x18)))
  w("ctx+0x1C=0x" .. string.format("%08X", memory.read_u32_le(CTX + 0x1C)))
  do
    local p, cell = terrain(x, y)
    w(string.format("terrain base=0x%08X cell=0x%02X @(%d,%d)", p, cell, x, y))
  end
  shot("00_map")

  dump_units("OURS", U)
  dump_units("ENEMY(+0x600)", U + PB)
  shot("01_units")

  -- 菜单层级探测：快照 -> A -> 快照 -> diff
  local s0 = snap()
  tap("A", 45)
  local s1 = snap()
  local x2, y2 = cur()
  w(string.format("afterA cursor=(%d,%d) state=%d sub=%d", x2, y2, memory.read_u8(CTX), memory.read_u8(CTX + 1)))
  diff(s0, s1, "map->A")
  shot("02_afterA")

  local s2 = snap()
  tap("B", 45)
  local s3 = snap()
  diff(s2, s3, "afterA->B")
  shot("03_afterB")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
