-- 验证"权威源"存在：写坐标后做各种动作，看表是否被刷回旧值
-- 若被刷回 → 游戏另有权威源，且刷新发生在特定动作（选中/回合切换）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_overwrite.txt"
local U    = 0x03002BE2
local K    = 17
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80 }
local mailOK = false
local function hold(k, f, g)
  if mailOK then
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    for _ = 1, (f or 5) do emu.frameadvance() end
    memory.write_u16_le(MAIL, 0x3FF)
  else
    for _ = 1, (f or 13) do joypad.set({ [k] = true }); emu.frameadvance() end
    joypad.set({})
  end
  adv(g or 8)
end
local function patch_mail()
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  local rv = memory.read_u32_le(ROML)
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  if rv == 0x04000130 then memory.write_u32_le(ROML, MAIL) end
  memory.write_u16_le(MAIL, 0x3FF)
  mailOK = true
end
local function u17() local o = U + K * 24; return memory.read_u8(o), memory.read_u8(o + 1) end
local function rec(tag)
  local x, y = u17()
  w(string.format("%-22s U17=(%d,%d) cursor=(%d,%d)", tag, x, y, cur()))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(30)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(70)
  for i = 1, 10 do
    local x0, y0 = cur()
    hold("Right", 13, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); break end
    hold("A", 4, 35)
  end
  patch_mail()
  rec("0-准备")

  local o = U + K * 24
  memory.write_u8(o, 18); memory.write_u8(o + 1, 31)
  rec("1-写入(18,31)")
  adv(60); rec("2-等60帧")
  adv(200); rec("3-等260帧")

  w(">>> 按 A（空格/无效位置）")
  hold("A", 4, 50); rec("4-按A后")
  hold("B", 4, 40); rec("5-按B后")

  w(">>> 光标走到 (18,31) 再按 A")
  for _ = 1, 30 do
    local x, y = cur()
    if x == 18 and y == 31 then break end
    local dx, dy = 18 - x, 31 - y
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, 5, 5)
  end
  rec("6-到(18,31)")
  hold("A", 4, 50); rec("7-在该格按A")
  hold("B", 4, 40); rec("8-B")

  w(">>> 结束回合（会重建状态）")
  hold("Start", 4, 60)
  for _ = 1, 6 do hold("Up", 4, 10) end
  hold("A", 4, 70); rec("9-确认框")
  hold("A", 4, 150); rec("10-确认后")
  adv(400); rec("11-敌方回合中")
  for i = 1, 12 do
    hold("A", 4, 60)
    adv(60)
    local x, y = u17()
    if x ~= 18 then w("  U17 已被改写于第" .. i .. "次"); break end
  end
  rec("12-回合后")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
