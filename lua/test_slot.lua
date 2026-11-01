-- 关键验证：ctx+0x990 是不是"光标下单位槽号"缓存？
-- 若是：直接写它就能选中任意单位，MOVE 可以完全跳过光标导航（真正的爆破）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_slot.txt"
local CTX  = 0x03000480
local MAIL, ROML = 0x03007F00, 0x080015F4

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/sl_" .. n .. ".png") end
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
local function slot() return memory.read_u8(CTX + 0x990) end
local function u17() local o = 0x03002BE2 + 17 * 24; return memory.read_u8(o), memory.read_u8(o + 1) end

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

  local cx, cy = cur()
  w(string.format("准备: cursor=(%d,%d) ctx+990=%d  U17=(%d,%d)", cx, cy, slot(), u17()))
  shot("00_ready")

  -- 光标在 (21,30)=U0(M1A2)。写 slot=17 指向 U17(19,29)
  w(">>> 写 ctx+0x990 = 17（U17 = M-3A2，在 19,29，不在光标处）")
  memory.write_u8(CTX + 0x990, 17)
  adv(5)
  w(string.format("写后 slot=%d", slot()))
  hold("A", 4, 45)
  w(string.format("按A后 slot=%d", slot()))
  shot("01_A_slot17")
  adv(40); shot("02_A_slot17b")

  -- 再按一次 A，看能不能进「移動/解散」
  hold("A", 4, 45); shot("03_A2")
  hold("B", 4, 40); shot("04_B")

  -- 对照：写 slot=0（U0 = 光标处的 M1A2）
  w(">>> 对照：写 ctx+0x990 = 0（U0 在光标处）")
  memory.write_u8(CTX + 0x990, 0)
  adv(5)
  hold("A", 4, 45); shot("05_A_slot0")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
