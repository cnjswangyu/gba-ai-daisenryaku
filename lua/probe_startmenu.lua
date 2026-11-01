-- 探针 6：用"光标可动"判定演出结束 → 存干净战场态 battle_usa_ready.State
--         再从干净态探 START 总菜单
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_live.State"
local DST  = BASE .. "states/battle_usa_ready.State"
local OUT  = BASE .. "logs/probe_startmenu.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/sm4_" .. n .. ".png") end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function tap(k, gap)
  for _ = 1, 4 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 30)
end
local function hold(k, f, gap)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 18)
end
-- 光标能动 = 已到可操作地图态
local function mobile()
  local x0, y0 = cur()
  hold("Right", 14, 12)
  local x1, y1 = cur()
  if x0 ~= x1 or y0 ~= y1 then hold("Left", 14, 12); return true end
  return false
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(60)

  local ready = false
  for i = 1, 12 do
    if mobile() then
      w(string.format("光标可动，演出结束于第 %d 轮 cursor=(%d,%d)", i, cur()))
      ready = true
      break
    end
    w(string.format("第 %d 轮光标不动，按 A 推进", i))
    tap("A", 40)
  end
  if not ready then w("!! 12 轮后光标仍不动") end
  shot("00_ready")
  w("save ready=" .. tostring(pcall(savestate.save, DST)))

  -- 探 START
  tap("Start", 70); shot("01_start")
  for i = 1, 7 do
    tap("Down", 45)
    shot(string.format("%02d_down", i + 1))
  end
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
