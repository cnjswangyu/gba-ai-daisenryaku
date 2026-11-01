-- 把 9 个单位也点上"配"，看剩余预算变化，然后出击
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/deploy_all.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/v_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 4)
  joypad.set({})
  adv(gap or 24)
end
local function oamcount()
  local n = 0
  for i = 0, 127 do
    local a0 = memory.read_u16_le(0x07000000 + i * 8)
    local a1 = memory.read_u16_le(0x07000000 + i * 8 + 2)
    local a2 = memory.read_u16_le(0x07000000 + i * 8 + 4)
    local dis = math.floor(a0 / 512) % 2 == 1
    local x, y = a1 % 512, a0 % 256
    if not dis and not (a0 == 0 and a1 == 0 and a2 == 0) and x < 260 and y < 200 then n = n + 1 end
  end
  return n
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
pcall(savestate.load, STATE)
adv(40)
shot("00_start")

-- 光标在第 1 行（已配）。往下走，逐个按 A 选配
for i = 2, 10 do
  press("Down", 4, 20)
  press("A", 4, 24)
  if i == 2 or i == 6 or i == 10 then shot(string.format("row%02d", i)) end
end
shot("11_all_selected")

press("Start", 6, 60)          -- 出击
shot("12_dialog")
press("A", 6, 120)             -- 确认自动部署
shot("13_deployed")
adv(120); shot("14_map")
adv(150); shot("15_map2")
w("OAM 单位数≈" .. oamcount())

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
