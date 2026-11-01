-- flag_probe.lua: 对比日本档与 USA 档的池标志/计数/旗标, 确定"已选"的内存表示
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/flag_probe.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local CTX = 0x03000480
local function st()  return memory.read_u8(CTX) end

local function dump_state(tag, path)
  pcall(savestate.load, path)
  adv(50)
  w("==== " .. tag .. " (" .. path .. ") state=" .. st() .. " ====")
  local n = 0
  for i = 0, 20 do
    local base = CTX + 0x188 + i * 4
    local id  = memory.read_u16_le(base)
    local b2  = memory.read_u8(base + 2)
    local b3  = memory.read_u8(base + 3)
    if id ~= 0 or b2 ~= 0 or b3 ~= 0 then
      n = n + 1
      w(string.format("  slot%02d id=0x%03X +2=%d +3=%d", i, id, b2, b3))
    end
  end
  w("  (shown " .. n .. " slots)")
  w(string.format("  count 0x020095B4 = %d", memory.read_u32_le(0x020095B4)))
  w(string.format("  g 0x020095B8 = %d", memory.read_u32_le(0x020095B8)))
  w(string.format("  ctx+0x991 = %d", memory.read_u8(CTX + 0x991)))
  w(string.format("  ctx+0x990(player) = %d", memory.read_u8(CTX + 0x990)))
  w(string.format("  ctx+0x64(country) = %d", memory.read_u8(CTX + 0x64)))
  w(string.format("  money = %d", memory.read_u32_le(CTX + 0x68)))
  local cptr = memory.read_u32_le(CTX + 0x14)
  w(string.format("  cmd=0x%08X  cmd+0x21=%d cmd+0x24=%d", cptr,
      memory.read_u8(cptr + 0x21), memory.read_u32_le(cptr + 0x24)))
  -- ctx+0x2b/0x2c 区 (init 会拷贝的来源)
  local s = "  ctx+0x20..0x40: "
  for a = 0x20, 0x40 do s = s .. string.format("%02X ", memory.read_u8(CTX + a)) end
  w(s)
  -- UI 状态区
  local s2 = "  ctx+0x637C..0x6390: "
  for a = 0x637C, 0x6390 do s2 = s2 .. string.format("%02X ", memory.read_u8(CTX + a)) end
  w(s2)
  -- 战场表头几个
  local s3 = "  p0 tbl[0..3]: "
  for i = 0, 3 do
    local a = CTX + 0x2760 + i * 24
    s3 = s3 .. string.format("[%d]=%04X ", i, memory.read_u16_le(a))
  end
  w(s3)
end

pcall(client.speedmode, 100)
adv(30)
dump_state("JAPAN pre_battle", BASE .. "states/pre_battle.State")
dump_state("USA pre_battle_usa", BASE .. "states/pre_battle_usa.State")
dump_state("USA battle_usa", BASE .. "states/battle_usa.State")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
