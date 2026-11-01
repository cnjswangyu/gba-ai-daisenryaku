-- 战场探针: DISPCNT/BG网格(地形)/我军表/敌军表扫描/光标/选单位菜单
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/battle_probe.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/bp_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 40)
end

local CTX = 0x03000480
local UNIT_DB = 0x08798A98
local function uname(uid)
  if uid == 0 then return "" end
  local ok, ptr = pcall(memory.read_u32_le, UNIT_DB + uid * 0x5C)
  if not ok or ptr < 0x08000000 or ptr > 0x0A000000 then return "?" end
  local s = ""
  for i = 0, 11 do
    local ok2, c = pcall(memory.read_u8, ptr + i)
    if not ok2 then break end
    if c == 0 then break end
    if c >= 32 and c < 127 then s = s .. string.char(c) else s = s .. "." end
  end
  return s
end

local function dump_units(tag)
  w("---- " .. tag .. " ----")
  local n = 0
  for i = 0, 63 do
    local a = CTX + 0x2760 + i * 24
    local id = memory.read_u16_le(a)
    if id ~= 0 then
      n = n + 1
      w(string.format("  u%02d %-14s (%s) x=%d y=%d hp=%d b5=%d b6=%d b7=%d b8=%d b9=%d",
        i, uname(id), id,
        memory.read_u8(a+2), memory.read_u8(a+3), memory.read_u8(a+4),
        memory.read_u8(a+5), memory.read_u8(a+6), memory.read_u8(a+7),
        memory.read_u8(a+8), memory.read_u8(a+9)))
    end
  end
  w("  count=" .. n)
end

-- 扫描 ctx 附近找其它 24B 步长的单位表 (x/y 合理 + hp 合理)
local function scan_tables()
  w("---- 扫描 ctx+0x0000..0x8000 找 24B 步长表 ----")
  for base = 0x2000, 0x7000, 4 do
    local hits = 0
    local first = nil
    for i = 0, 15 do
      local a = CTX + base + i * 24
      local x = memory.read_u8(a+2)
      local y = memory.read_u8(a+3)
      local hp = memory.read_u8(a+4)
      local id = memory.read_u16_le(a)
      if id > 0 and id < 400 and x < 80 and y < 80 and hp >= 1 and hp <= 100 then
        hits = hits + 1
        if not first then first = {id=id, x=x, y=y, hp=hp} end
      end
    end
    if hits >= 8 then
      w(string.format("  ctx+0x%04X: %d/16 hits, first=%s(%d) @(%d,%d) hp=%d",
        base, hits, uname(first.id), first.id, first.x, first.y, first.hp))
    end
  end
end

local function dump_disp()
  local disp = memory.read_u16_le(0x04000000)
  w(string.format("DISPCNT=0x%04X mode=%d", disp, disp % 8))
  local BGCNT = {0x04000008, 0x0400000A, 0x0400000C, 0x0400000E}
  for i = 0, 3 do
    local cnt = memory.read_u16_le(BGCNT[i])
    local on = math.floor(disp / 256) % 2 == 1
    if on then
      local charBase = 0x06000000 + (math.floor(cnt / 4) % 4) * 0x4000
      local mapBase  = 0x06000000 + (math.floor(cnt / 256) % 32) * 0x800
      w(string.format("  BG%d on cnt=0x%04X char=0x%08X map=0x%08X bpp8=%d",
        i, cnt, charBase, mapBase, math.floor(cnt / 128) % 2))
    end
  end
  return disp
end

-- 读某一层 30x20 图块网格 (只读前 12 行看地形规律)
local function dump_grid(mapBase, tag)
  w(string.format("  GRID %s (map=0x%08X):", tag, mapBase))
  for ty = 0, 11 do
    local t = {}
    for tx = 0, 29 do
      local e = memory.read_u16_le(mapBase + (ty * 32 + tx) * 2)
      t[#t+1] = string.format("%3d", e % 1024)
    end
    w("    " .. table.concat(t, " "))
  end
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/battle_usa.State")
  adv(90)
  w("===== 初始(地图, 光标闪烁) =====")
  local disp = dump_disp()
  w(string.format("cursor=(%d,%d) input new=0x%04X held=0x%04X",
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF),
    memory.read_u16_le(0x0300048C), memory.read_u16_le(0x0300048E)))
  dump_units("我军 (ctx+0x2760)")
  shot("00_map")

  -- 找地图层并 dump 网格
  local BGCNT = {0x04000008, 0x0400000A, 0x0400000C, 0x0400000E}
  for i = 0, 3 do
    local cnt = memory.read_u16_le(BGCNT[i])
    if math.floor(disp / 256) % 2 == 1 or i == 0 then
      local mapBase = 0x06000000 + (math.floor(cnt / 256) % 32) * 0x800
      dump_grid(mapBase, "BG" .. i)
    end
  end

  scan_tables()

  -- 按 A 选单位 → 看菜单
  press("A", 6, 60)
  w("===== 按 A 之后 =====")
  w(string.format("state=%d sub=%d cursor=(%d,%d)",
    memory.read_u8(CTX), memory.read_u8(CTX+1),
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
  dump_disp()
  shot("01_after_A")
  adv(60); shot("02_after_A2")

  -- 再按 A (菜单第一项?)
  press("A", 6, 90)
  w("===== 再按 A =====")
  w(string.format("state=%d sub=%d cursor=(%d,%d)",
    memory.read_u8(CTX), memory.read_u8(CTX+1),
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
  shot("03_after_A2")

  -- B 返回
  press("B", 6, 60)
  adv(40)
  w("===== 按 B =====")
  w(string.format("state=%d sub=%d cursor=(%d,%d)",
    memory.read_u8(CTX), memory.read_u8(CTX+1),
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
  shot("04_after_B")

  -- 方向键移动光标测试
  press("Right", 14, 30)
  press("Down", 14, 30)
  w("===== 移动光标后 =====")
  w(string.format("cursor=(%d,%d)", memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
  shot("05_moved")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
