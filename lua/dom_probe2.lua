-- 验证：System Bus 域的批量读是否返回真实数据（战场存档，已知 0x030004A4=1500）
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/dom_probe2.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

adv(10)
savestate.load(BASE .. "states/battle_start.State")
adv(60)

w("ref u8 @0x030004A4..A8 = " .. memory.read_u8(0x030004A4) .. " " .. memory.read_u8(0x030004A5)
  .. " " .. memory.read_u8(0x030004A6) .. " " .. memory.read_u8(0x030004A7))
w("ref u32 @0x030004A4 = " .. memory.read_u32_le(0x030004A4))

local function try(desc, fn)
  local ok, r = pcall(fn)
  if ok and type(r) == "string" then
    w(string.format("%-56s -> len=%d head=%s", desc, #r,
      (r:sub(1, 8):gsub(".", function(c) return string.format("%02X ", string.byte(c)) end))))
  else w(string.format("%-56s -> ERR %s", desc, tostring(r):sub(1, 90))) end
end

try("SystemBus 0x030004A0 len16", function() return memory.read_bytes_as_binary_string(0x030004A0, 16, "System Bus") end)
try("SystemBus 0x03000000 len64", function() return memory.read_bytes_as_binary_string(0x03000000, 64, "System Bus") end)
try("SystemBus 0x02000000 len64", function() return memory.read_bytes_as_binary_string(0x02000000, 64, "System Bus") end)
try("SystemBus 0x06000000 len64", function() return memory.read_bytes_as_binary_string(0x06000000, 64, "System Bus") end)
try("CombinedWRAM 0x40000 len64", function() return memory.read_bytes_as_binary_string(0x40000, 64, "Combined WRAM") end)
try("EWRAM 0 len64", function() return memory.read_bytes_as_binary_string(0, 64, "EWRAM") end)
try("VRAM 0 len64", function() return memory.read_bytes_as_binary_string(0, 64, "VRAM") end)
try("OAM 0 len64", function() return memory.read_bytes_as_binary_string(0, 64, "OAM") end)
try("PALRAM 0 len64", function() return memory.read_bytes_as_binary_string(0, 64, "PALRAM") end)
try("ROM 0x400000 len64", function() return memory.read_bytes_as_binary_string(0x400000, 64, "ROM") end)

local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n") .. "\n"); f:close()
pcall(client.exit)
