-- USA: 部署1个单位后按 START（健壮版：逐行落盘+错误捕获）
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/usa_start.txt"
local fh = io.open(OUT, "w")
local function w(s)
  if fh then fh:write(s .. "\n"); fh:flush() end
end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/us_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 5)
  joypad.set({}); adv(gap or 30)
end

local CTX = 0x03000480
local function info(tag)
  local st = memory.read_u8(CTX)
  local sub = memory.read_u8(CTX+1)
  local cnt = memory.read_u32_le(0x020095B4)
  local n = 0
  for i = 0, 63 do
    if memory.read_u16_le(CTX+0x2760+i*24) ~= 0 then n = n + 1 end
  end
  local pool = {}
  for i = 0, 23 do
    local id = memory.read_u16_le(CTX+0x188+i*4)
    local fl = memory.read_u8(CTX+0x188+i*4+3)
    if id ~= 0 then pool[#pool+1] = string.format("%d:%02X", id, fl) end
  end
  w(string.format("%-10s f=%-5d state=%d sub=%d cnt=%d battle=%d pool=[%s]",
    tag, emu.framecount(), st, sub, cnt, n, table.concat(pool, " ")))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)
  w("speedmode done, frame=" .. emu.framecount())
  local lr = savestate.load(BASE .. "states/pre_battle_usa.State")
  w("savestate.load -> " .. tostring(lr))
  adv(60)
  info("loaded"); shot("00_list")

  press("A", 6, 60)
  info("afterA1"); shot("01_placemode")

  press("A", 6, 60)
  info("afterA2"); shot("02_placed")

  press("B", 6, 60)
  info("afterB"); shot("03_back")

  press("Start", 6, 90)
  info("afterStart"); shot("04_after_start")

  press("A", 6, 120)
  info("afterA"); shot("05_after_a")

  adv(150); info("adv150"); shot("06_final")
end, function(e)
  w("ERROR: " .. tostring(e))
end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
