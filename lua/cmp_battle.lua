-- 对比 battle_usa.State(美) 与 battle_start.State(日) 的战场数据结构
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/cmp_battle.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end

local CTX = 0x03000480

local function dump_battle(tag)
  w("======== " .. tag .. " ========")
  w(string.format("state=%d sub=%d p990=%d p991=%d money=%d",
    memory.read_u8(CTX), memory.read_u8(CTX+1),
    memory.read_u8(CTX+0x990), memory.read_u8(CTX+0x991),
    memory.read_u32_le(CTX+0x68)))
  -- 战场表 ctx+0x2760, 24B/条
  local n = 0
  for i = 0, 63 do
    local a = CTX + 0x2760 + i * 24
    local id = memory.read_u16_le(a)
    if id ~= 0 then
      n = n + 1
      local x  = memory.read_u8(a+0)
      local y  = memory.read_u8(a+1)
      local hp = memory.read_u8(a+2)
      local kind = memory.read_u8(a+6)
      local raw = {}
      for j = 0, 23 do raw[#raw+1] = string.format("%02X", memory.read_u8(a+j)) end
      if n <= 24 then
        w(string.format("  u%02d id=%3d x=%2d y=%2d hp=%3d kind=%2d | %s",
          i, id, x, y, hp, kind, table.concat(raw, " ")))
      end
    end
  end
  w("  total units = " .. n)
  -- 光标
  w(string.format("cursor: 0x030067FE=%d 0x030067FF=%d",
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
  -- 输入状态
  w(string.format("input: new=0x%04X held=0x%04X",
    memory.read_u16_le(0x0300048C), memory.read_u16_le(0x0300048E)))
  -- 几个可能存回合/阶段的全局
  for _, a in ipairs({0x02005034, 0x0200504C, 0x02007068, 0x020095B4, 0x02007060}) do
    w(string.format("  [0x%08X] = 0x%08X", a, memory.read_u32_le(a)))
  end
  -- ctx 前 0x100 字节的关键字段
  local parts = {}
  for i = 0, 0x70 do
    parts[#parts+1] = string.format("%02X", memory.read_u8(CTX+i))
  end
  w("  ctx[0..0x70] = " .. table.concat(parts, " "))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/battle_usa.State")
  adv(90)
  dump_battle("battle_usa (USA 20-unit army)")

  savestate.load(BASE .. "states/battle_start.State")
  adv(90)
  dump_battle("battle_start (Japan default)")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
