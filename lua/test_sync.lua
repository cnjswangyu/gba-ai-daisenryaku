-- 关键实验：同一帧内同时写「格表 + 单位表 + 光标 + 选中槽号」，让状态机的循环收敛
-- 之前每次只写一两个，会被"光标←选中单位 / 选中单位←查格表[光标]"的重算掰回去
local B = "D:/prog/gba-ai/"
local CTX = 0x03000480
local OUT = B .. "logs/test_sync.txt"
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX + 0x637E), memory.read_u8(CTX + 0x637F) end
local function shot(n) pcall(client.screenshot, B .. "shots/sy_" .. n .. ".png") end
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
local function ga(x, y) return CTX + 0x3F60 + x * 4 + y * 0xC0 end
local function gr(x, y)
  local a = ga(x, y); return memory.read_u8(a), memory.read_u8(a + 1)
end
local function ua(k) return 0x03002BE0 + k * 24 end
local function uxy(k) local a = ua(k); return memory.read_u8(a + 2), memory.read_u8(a + 3) end
local function slot() return memory.read_u8(CTX + 0x990) end
local function rec(tag)
  local cx, cy = cur()
  local ux, uy = uxy(17)
  local o1, o2 = gr(19, 29)
  local n1, n2 = gr(24, 26)
  w(string.format("%-10s cursor=(%2d,%2d) slot=%2d U17=(%2d,%2d) 旧格=[%d,%d] 新格=[%d,%d]",
    tag, cx, cy, slot(), ux, uy, o1, o2, n1, n2))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(30)
  w("load=" .. tostring(pcall(savestate.load, B .. "states/battle_usa_ready.State")))
  adv(70)
  for i = 1, 10 do
    local x0, y0 = cur()
    hold("Right", 13, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); break end
    hold("A", 4, 35)
  end
  patch_mail()
  rec("初始")
  shot("00_before")

  -- 同一批写：格表(清旧+写新) + 单位表 + 光标 + 选中槽号
  w(">>> 同时写 4 处（U17 -> 24,26）")
  local g1 = ga(19, 29); memory.write_u8(g1, 0); memory.write_u8(g1 + 1, 0)
  local g2 = ga(24, 26); memory.write_u8(g2, 1); memory.write_u8(g2 + 1, 18)
  local a = ua(17); memory.write_u8(a + 2, 24); memory.write_u8(a + 3, 26)
  memory.write_u8(CTX + 0x637E, 24)
  memory.write_u8(CTX + 0x637F, 26)
  memory.write_u8(CTX + 0x990, 17)

  adv(1);  rec("1帧后")
  adv(4);  rec("5帧后")
  adv(25); rec("30帧后")
  shot("01_after30")
  adv(60); rec("90帧后")
  shot("02_after90")

  w(">>> 按 A：若选中 M-3A2（而不是 M1A2）即成功")
  hold("A", 4, 45); shot("03_A")
  rec("按A后")
  hold("A", 4, 45); shot("04_A2")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
