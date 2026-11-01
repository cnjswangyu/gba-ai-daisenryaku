-- 找"真身"：真实按键移动 U17 一格，前后各存一份全 RAM 快照，
-- 由 Python 对比找出同时包含 (旧坐标) 和 (新坐标) 的地址。
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/scan_truebody.txt"
local U    = 0x03002BE2
local K    = 17

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

-- 输入走邮箱（5 帧=1 格），不走 joypad
local MAIL, ROML = 0x03007F00, 0x080015F4
local mailOK = false
local STEP_FRAMES = 5
local function patch_mail()
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  local rv = memory.read_u32_le(ROML)
  if #hits == 0 and rv ~= 0x04000130 and rv ~= MAIL then
    w("邮箱：找不到读键字面量，回退 joypad"); mailOK = false; return false
  end
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  if rv == 0x04000130 then memory.write_u32_le(ROML, MAIL) end
  memory.write_u16_le(MAIL, 0x3FF)
  mailOK = true
  w(string.format("邮箱 IWRAM %d 处 + ROM %s", #hits, rv == 0x04000130 and "改" or "已改"))
  return true
end
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80 }
local function hold(k, f, g)
  if mailOK then
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0))
    for _ = 1, (f or STEP_FRAMES) do emu.frameadvance() end
    memory.write_u16_le(MAIL, 0x3FF)
  else
    for _ = 1, (f or 13) do joypad.set({ [k] = true }); emu.frameadvance() end
    joypad.set({})
  end
  adv(g or 5)
end
local function tap(k, g) hold(k, 4, g or 30) end
local function u17() local o = U + K * 24; return memory.read_u8(o), memory.read_u8(o + 1) end
local function goto_cell(tx, ty)
  for _ = 1, 80 do
    local x, y = cur()
    if x == tx and y == ty then return true end
    local dx, dy = tx - x, ty - y
    local k
    if dy ~= 0 and math.abs(dy) >= math.abs(dx) then k = (dy > 0) and "Down" or "Up"
    elseif dx ~= 0 then k = (dx > 0) and "Right" or "Left"
    else k = (dy > 0) and "Down" or "Up" end
    hold(k, STEP_FRAMES, 4)
  end
  return false
end
-- readbyterange 返回的是 table（0/1 索引因版本而异），逐字节转成二进制串
local function dumpbytes(addr, len)
  local out, CH = {}, 8192
  for off = 0, len - 1, CH do
    local n = math.min(CH, len - off)
    local t = memory.readbyterange(addr + off, n)
    local c = {}
    for i = 0, n - 1 do
      local v = t[i]
      if v == nil then v = t[i + 1] end
      c[i + 1] = string.char(v or 0)
    end
    out[#out + 1] = table.concat(c)
  end
  return table.concat(out)
end

-- 全内存域（EWRAM/IWRAM/PALRAM/VRAM/OAM）；这游戏拿 PALRAM 尾部当变量用，VRAM/OAM 也不能漏
local REGIONS = {
  { "EWRAM", 0x02000000, 0x40000 },
  { "IWRAM", 0x03000000, 0x08000 },
  { "PALRAM", 0x05000000, 0x00400 },
  { "VRAM", 0x06000000, 0x18000 },
  { "OAM", 0x07000000, 0x00400 },
}

local function snap(path)
  local f = io.open(path, "wb")
  if not f then w("!! 打不开 " .. path); return false end
  for _, r in ipairs(REGIONS) do
    local ok, s = pcall(dumpbytes, r[2], r[3])
    if ok and s then
      f:write(s)
      w(string.format("  %-6s 0x%08X %d", r[1], r[2], #s))
    else
      w("  !! " .. r[1] .. " 读失败 " .. tostring(s))
      f:write(string.rep("\0", r[3]))
    end
  end
  f:close()
  return true
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(80)

  for i = 1, 10 do
    local x0, y0 = cur()
    hold("Right", 13, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); w("演出结束@" .. i); break end
    tap("A", 35)
  end

  local x, y = u17()
  w(string.format("移动前 U17=(%d,%d)", x, y))
  patch_mail()
  snap(BASE .. "logs/snap_before.bin")

  -- 真实按键移动：选中 → 菜单① → 移動 → 左移一格 → 确认 → 待机
  goto_cell(x, y)
  tap("A", 32); tap("A", 32); tap("A", 32)
  hold("Left", STEP_FRAMES, 8)
  local cx, cy = cur()
  w(string.format("寻路后光标=(%d,%d)", cx, cy))
  tap("A", 45)
  tap("A", 40)
  adv(60)

  local nx, ny = u17()
  w(string.format("移动后 U17=(%d,%d)", nx, ny))
  snap(BASE .. "logs/snap_after.bin")
  w(string.format("RESULT old=%d,%d new=%d,%d", x, y, nx, ny))
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
