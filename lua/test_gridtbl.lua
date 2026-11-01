-- 验证格表布局：格项 = ctx + 0x3F60 + x*4 + y*0xC0，+0=阵营 +1=槽号(1-based)
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_gridtbl.txt"
local CTX  = 0x03000480
local GRID = 0x3F60

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function g(x, y)
  local a = CTX + GRID + x * 4 + y * 0xC0
  return memory.read_u8(a), memory.read_u8(a + 1), memory.read_u8(a + 2), memory.read_u8(a + 3)
end
local function unitxy(side, k)
  local base = 0x03002BE0 + (side == "MY" and 0 or 0x600) + k * 24
  return memory.read_u8(base + 2), memory.read_u8(base + 3), memory.read_u16_le(base)
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(30)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(80)

  w("=== 我方前 8 个单位 vs 其所在格的格表值 ===")
  w("槽  id   坐标     格表[阵营,槽号,+2,+3]")
  for k = 0, 7 do
    local x, y, id = unitxy("MY", k)
    if x > 0 and x < 64 and y > 0 and y < 64 then
      local a, b, c, d = g(x, y)
      w(string.format("%2d  %4d (%2d,%2d)  [%d,%d,%d,%d]  %s", k, id, x, y, a, b, c, d,
        (b == k + 1) and "槽号吻合" or "!! 不符"))
    end
  end

  w("")
  w("=== 敌方前 5 个单位 vs 其所在格 ===")
  for k = 0, 4 do
    local x, y, id = unitxy("EN", k)
    if x > 0 and x < 64 and y > 0 and y < 64 then
      local a, b, c, d = g(x, y)
      w(string.format("%2d  %4d (%2d,%2d)  [%d,%d,%d,%d]  %s", k, id, x, y, a, b, c, d,
        (b == k + 1) and "槽号吻合" or "!! 不符"))
    end
  end

  w("")
  w("=== 空格抽查 ===")
  for _, p in ipairs({ { 1, 1 }, { 5, 5 }, { 10, 10 }, { 40, 40 } }) do
    local a, b, c, d = g(p[1], p[2])
    w(string.format("(%2d,%2d) [%d,%d,%d,%d]", p[1], p[2], a, b, c, d))
  end
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
