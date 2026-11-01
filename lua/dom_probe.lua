-- 探针：确认 BizHawk GBA 内存域的寻址方式（域内相对 vs 绝对）
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/dom_probe.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end

local doms = memory.getmemorydomainlist()
for _, d in ipairs(doms) do
  local ok, sz = pcall(memory.getmemorydomainsize, d)
  w(string.format("domain %-16s size=%s", d, ok and tostring(sz) or "?"))
end
local okc, cur = pcall(memory.getcurrentmemorydomain)
w("current domain = " .. (okc and cur or "?"))

local function try(desc, fn)
  local ok, r = pcall(fn)
  if ok then
    if type(r) == "string" then
      w(string.format("%-58s -> len=%d  head=%02X %02X %02X %02X", desc, #r,
        string.byte(r,1) or 0, string.byte(r,2) or 0, string.byte(r,3) or 0, string.byte(r,4) or 0))
    else w(desc .. " -> " .. tostring(r)) end
  else w(string.format("%-58s -> ERR %s", desc, tostring(r):sub(1, 80))) end
end

try("SystemBus 0x03000000 len16", function() return memory.read_bytes_as_binary_string(0x03000000, 16, "System Bus") end)
try("EWRAM    0x02000000 len16", function() return memory.read_bytes_as_binary_string(0x02000000, 16, "EWRAM") end)
try("EWRAM    0x00000000 len16", function() return memory.read_bytes_as_binary_string(0x00000000, 16, "EWRAM") end)
try("CombinedWRAM 0 len16", function() return memory.read_bytes_as_binary_string(0, 16, "Combined WRAM") end)
try("CombinedWRAM 0x10000 len16", function() return memory.read_bytes_as_binary_string(0x10000, 16, "Combined WRAM") end)
try("VRAM 0 len16", function() return memory.read_bytes_as_binary_string(0, 16, "VRAM") end)
try("ROM 0 len16", function() return memory.read_bytes_as_binary_string(0, 16, "ROM") end)
try("no-domain 0x03000000 len16", function() return memory.read_bytes_as_binary_string(0x03000000, 16) end)
try("no-domain 0x02000000 len16", function() return memory.read_bytes_as_binary_string(0x02000000, 16) end)
try("IWRAM 0 len16", function() return memory.read_bytes_as_binary_string(0, 16, "IWRAM") end)
-- 参照：单字节读（已知绝对地址可用）
w("ref read_u8(0x03000000)=" .. memory.read_u8(0x03000000) ..
  " read_u8(0x03007F00)=" .. memory.read_u8(0x03007F00) ..
  " read_u8(0x02000000)=" .. memory.read_u8(0x02000000))

local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n") .. "\n"); f:close()
pcall(client.exit)
