local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/_sm.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/sm_"..n..".png"); say("shot "..n) end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function mobilePad()
  local x0 = select(1, cur())
  for _ = 1, 14 do joypad.set({ Right = true }); emu.frameadvance() end
  joypad.set({})
  local x1 = select(1, cur())
  if x0 ~= x1 then
    for _ = 1, 14 do joypad.set({ Left = true }); emu.frameadvance() end
    joypad.set({}); return true
  end
  return false
end
pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, BASE .. "states/battle_usa_live.State")))
adv(60)
for i = 1, 12 do
  if mobilePad() then say("ready after " .. i); break end
  say("  banner? A")
  for _ = 1, 5 do joypad.set({ A = true }); emu.frameadvance() end
  joypad.set({}; adv(50)
end
shot("00_map")
for _ = 1, 5 do joypad.set({ B = true }); emu.frameadvance() end
joypad.set({}; adv(40)
for _ = 1, 5 do joypad.set({ Start = true }); emu.frameadvance() end
joypad.set({}); adv(70); shot("01_start_menu")
for i = 1, 6 do
  for _ = 1, 10 do joypad.set({ Down = true }); emu.frameadvance() end
  joypad.set({}); adv(20); shot("0" .. (i+1) .. "_down" .. i)
end
say("done")
client.exit()
