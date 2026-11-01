-- probe_late.lua —— 验证：部署是否增量进行 / 标杆存档单位数
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_late.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

local CTX = 0x03000480
local U   = 0x03002BE2
local function state() return memory.read_u8(CTX) end
local function units_count()
  local my, en = 0, 0
  for k = 0, 63 do
    if memory.read_u16_le(U + k * 24 - 2) ~= 0 then my = my + 1 end
    if memory.read_u16_le(U + 0x600 + k * 24 - 2) ~= 0 then en = en + 1 end
  end
  return my, en
end
local function pool_marks()
  local t = {}
  for i = 0, 17 do
    local v = memory.read_u16_le(CTX + 0x188 + i * 4)
    if v ~= 0 then t[#t + 1] = string.format("%03X", v) end
  end
  return table.concat(t, ",")
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 800)
  pcall(client.setsoundon, false)
  adv(30)

  w("=== A: stage1_stuck 推进观察（部署是否增量）===")
  savestate.load(BASE .. "states/stage1_stuck.State")
  adv(60)
  local last = 0
  for _, pt in ipairs({ 300, 800, 1800, 3000 }) do
    adv(pt - last); last = pt
    local my, en = units_count()
    w(string.format("t=+%5d f=%d state=%d MY=%d EN=%d pool=[%s]",
      pt, emu.framecount(), state(), my, en, pool_marks()))
  end

  w("=== B: battle_start.State 标杆（零勾选路径）===")
  savestate.load(BASE .. "states/battle_start.State")
  adv(120)
  local my, en = units_count()
  w(string.format("battle_start: state=%d MY=%d EN=%d pool=[%s]",
    state(), my, en, pool_marks()))
  adv(1500)
  my, en = units_count()
  w(string.format("battle_start +1500f: state=%d MY=%d EN=%d", state(), my, en))

  w("=== C: battle_usa_live.State 标杆（usa 链真战斗）===")
  savestate.load(BASE .. "states/battle_usa_live.State")
  adv(120)
  my, en = units_count()
  w(string.format("usa_live: state=%d sub=%d ph=%d MY=%d EN=%d",
    state(), memory.read_u8(CTX + 1), memory.read_u8(CTX + 0x21), my, en))
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
