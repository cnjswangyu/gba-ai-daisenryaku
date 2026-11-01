-- 按键位标定：加载 pre_battle_usa.State，逐个按键，读 ctx+0xC(新按下)/0x0E(持续)
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/keycal.txt"
local lines = {}
local function w(s) lines[#lines+1] = s end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(30)
pcall(savestate.load, BASE .. "states/pre_battle_usa.State")
adv(60)

local CTX = 0x03000480
local keys = {"A","B","Select","Start","Right","Left","Up","Down","R","L"}
w("state=" .. memory.read_u8(CTX) .. " sub=" .. memory.read_u8(CTX+1))

for _, k in ipairs(keys) do
  -- 清空：等几帧
  adv(10)
  local c0 = memory.read_u16_le(CTX+0xC)
  local e0 = memory.read_u16_le(CTX+0xE)
  -- 按 2 帧
  joypad.set({ [k] = true })
  adv(2)
  local c1 = memory.read_u16_le(CTX+0xC)
  local e1 = memory.read_u16_le(CTX+0xE)
  -- 继续按住 4 帧
  adv(4)
  local c2 = memory.read_u16_le(CTX+0xC)
  local e2 = memory.read_u16_le(CTX+0xE)
  joypad.set({})
  adv(6)
  local c3 = memory.read_u16_le(CTX+0xC)
  local e3 = memory.read_u16_le(CTX+0xE)
  w(string.format("%-7s new: %04X->%04X->%04X  held: %04X->%04X->%04X  bits(new)=%s bits(held)=%s",
    k, c0, c1, c2, e0, e1, e2, 
    (function() local t={} for i=0,15 do if math.floor(c1/2^i)%2==1 then t[#t+1]=i end end return table.concat(t,",") end)(),
    (function() local t={} for i=0,15 do if math.floor(e2/2^i)%2==1 then t[#t+1]=i end end return table.concat(t,",") end)()))
  w(string.format("        after release: new=%04X held=%04X", c3, e3))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
