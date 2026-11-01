-- 关键验证：B 键在地图上到底干什么？A 键在空格上干什么？
-- 如果 B 会开总菜单，那 to_map() 的 B×4 就是把游戏推进菜单的元凶
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/test_bkey.txt"
local MAIL, ROML = 0x03007F00, 0x080015F4
local mailOK = false

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/bk_" .. n .. ".png") end
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80 }
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
  if #hits == 0 and rv ~= 0x04000130 and rv ~= MAIL then w("邮箱不可用"); return end
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  if rv == 0x04000130 then memory.write_u32_le(ROML, MAIL) end
  memory.write_u16_le(MAIL, 0x3FF)
  mailOK = true
  w("邮箱就绪")
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(30)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(70)

  -- 清演出（此时还没 patch，用 joypad）
  for i = 1, 10 do
    local x0, y0 = cur()
    hold("Right", 13, 8)
    local x1, y1 = cur()
    if x0 ~= x1 or y0 ~= y1 then hold("Left", 13, 8); break end
    hold("A", 4, 35)
  end
  patch_mail()
  w(string.format("准备完 cursor=(%d,%d)", cur()))
  shot("00_ready")

  -- 测 B：在地图上按一次 B
  w(">>> 地图上按 B")
  hold("B", 4, 45); shot("01_B1")
  w(string.format("B×1 后 cursor=(%d,%d)", cur()))
  hold("B", 4, 45); shot("02_B2")
  hold("B", 4, 45); shot("03_B3")
  w(string.format("B×3 后 cursor=(%d,%d)", cur()))

  -- 若 B 开了菜单，方向键会是菜单导航而不是移光标 → 用 Right 试
  local x0, y0 = cur()
  hold("Right", 5, 10)
  local x1, y1 = cur()
  w(string.format("B×3 后按 Right: (%d,%d)->(%d,%d) %s", x0, y0, x1, y1,
    (x0 ~= x1 or y0 ~= y1) and "光标动了(说明不在菜单)" or "光标不动(可能在菜单)"))

  -- 测 A 在空格
  w(">>> 按 A")
  hold("A", 4, 45); shot("04_A1")
  hold("A", 4, 45); shot("05_A2")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
