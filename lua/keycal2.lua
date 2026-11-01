-- 按键位标定 v2：每个键重新载档，逐帧采样 ctx+0xC/0x0E
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/keycal2.txt"
local lines = {}
local function w(s) lines[#lines+1] = s end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

local CTX = 0x03000480
local keys = {"A","B","Select","Start","Right","Left","Up","Down","R","L"}

for _, k in ipairs(keys) do
  pcall(savestate.load, BASE .. "states/pre_battle_usa.State")
  adv(40)
  local st0 = memory.read_u8(CTX)
  -- 按住 8 帧，逐帧读
  joypad.set({ [k] = true })
  local trace = {}
  for i = 1, 8 do
    adv(1)
    local c = memory.read_u16_le(CTX+0xC)
    local e = memory.read_u16_le(CTX+0xE)
    trace[#trace+1] = string.format("f%d:c=%04X,e=%04X", i, c, e)
  end
  joypad.set({})
  adv(10)
  local st1 = memory.read_u8(CTX)
  w(string.format("%-7s state %d->%d | %s", k, st0, st1, table.concat(trace, " ")))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
