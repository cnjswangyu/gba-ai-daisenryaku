-- 探针 7：验证「结束回合」的完整按键流程（START → UP×5 回第一项 → A → 确认框 → A）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/probe_endturn.txt"
local U    = 0x03002BE2
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/et_" .. n .. ".png") end
local function tap(k, gap)
  for _ = 1, 4 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 35)
end
local function acted()
  local t = {}
  for k = 0, 18 do
    local o = U + k * 24
    t[#t + 1] = tostring(memory.read_u8(o + 7))
  end
  return table.concat(t, "")
end
local function info(tag)
  w(string.format("%-14s frame=%-5d acted=%s cur=(%d,%d)", tag, emu.framecount(), acted(),
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(60)
  info("load"); shot("00")

  tap("Start", 70); shot("01_menu")
  for i = 1, 5 do tap("Up", 15) end
  shot("02_up")
  tap("A", 70); shot("03_afterA")
  adv(60); shot("04_adv60")
  tap("A", 90); shot("05_afterA2")
  adv(120); shot("06_adv120")
  info("after")
  tap("A", 90); shot("07_afterA3")
  adv(150); shot("08_adv150")
  info("final")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
