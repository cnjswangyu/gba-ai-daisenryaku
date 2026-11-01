-- 寄存器对照：验证 emu.getregister 在这个核心上是否可用
local OUT = "D:/prog/gba-ai/logs/probe_regs.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function reg(n) local ok, v = pcall(emu.getregister, n); return (ok and v) or "ERR" end
local function hexv(v) if type(v) ~= "number" then return tostring(v) end return string.format("0x%08X", v) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)

w("registers available: ")
local ok, t = pcall(emu.getregisters)
if ok and type(t) == "table" then
  local names = {}
  for k, _ in pairs(t) do names[#names + 1] = tostring(k) end
  table.sort(names)
  w("  " .. table.concat(names, ", "))
  for _, n in ipairs(names) do
    w(string.format("  %-6s = %s", n, hexv(reg(n))))
  end
else
  w("  (none) ok=" .. tostring(ok))
end

w("")
w("=== PC 轨迹（每 30 帧） ===")
for i = 0, 14 do
  for _ = 1, 30 do emu.frameadvance() end
  w(string.format("  f=%-5d PC=%s LR=%s R0=%s DISPCNT=0x%04X IWRAM_nonzero8k=%s",
    emu.framecount(), hexv(reg("R15")), hexv(reg("R14")), hexv(reg("R0")),
    memory.read_u16_le(0x04000000),
    (function()
      local ok2, b = pcall(memory.readbyterange, 0x03000000, 0x1000)
      if not (ok2 and b) then return "?" end
      local nz = 0
      for j = 0, 4095 do if (b[j] or 0) ~= 0 then nz = nz + 1 end end
      return tostring(nz)
    end)()))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
