-- 诊断：战场态到底有几处读键字面量？只改这些 + ROM，按键能不能用？
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/diag_mail.txt"
local MAIL = 0x03007F00
local ROML = 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/dm_" .. n .. ".png") end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(30)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(60)

  -- 1) 扫 IWRAM（含栈区外）所有 4 字节对齐的 0x04000130
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  w(string.format("IWRAM 命中 %d 处:", #hits))
  for _, a in ipairs(hits) do
    local ctx = {}
    for d = -4, 8, 2 do ctx[#ctx + 1] = string.format("%04X", memory.read_u16_le(a + d)) end
    w(string.format("  0x%08X  周围: %s", a, table.concat(ctx, " ")))
  end
  w(string.format("ROM 0x%08X = 0x%08X %s", ROML, memory.read_u32_le(ROML),
    memory.read_u32_le(ROML) == 0x04000130 and "(是读键字面量)" or "(不是)"))

  -- 2) 全改成邮箱
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  memory.write_u32_le(ROML, MAIL)
  memory.write_u16_le(MAIL, 0x3FF)
  w("已全改为邮箱，开始测试")

  -- 3) 测方向键：按住 Right 5 帧，光标应动
  local x0, y0 = cur()
  memory.write_u16_le(MAIL, 0x3FF - 0x10)   -- Right
  for _ = 1, 5 do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(10)
  local x1, y1 = cur()
  w(string.format("邮箱Right 5帧: (%d,%d)->(%d,%d) %s", x0, y0, x1, y1,
    (x0 ~= x1 or y0 ~= y1) and "光标动了" or "没动"))
  shot("1_right5")

  -- 4) 再试 14 帧
  local x2, y2 = cur()
  memory.write_u16_le(MAIL, 0x3FF - 0x10)
  for _ = 1, 14 do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(10)
  local x3, y3 = cur()
  w(string.format("邮箱Right 14帧: (%d,%d)->(%d,%d)", x2, y2, x3, y3))

  -- 5) 测 A：按住 5 帧，看是否弹出菜单（截图对比）
  memory.write_u16_le(MAIL, 0x3FF - 0x1)    -- A
  for _ = 1, 5 do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(40)
  w(string.format("邮箱A 5帧后 cursor=(%d,%d)", cur()))
  shot("2_a5")

  -- 6) 还不行就再按一次 A
  memory.write_u16_le(MAIL, 0x3FF - 0x1)
  for _ = 1, 5 do emu.frameadvance() end
  memory.write_u16_le(MAIL, 0x3FF)
  adv(40)
  shot("3_a5b")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
