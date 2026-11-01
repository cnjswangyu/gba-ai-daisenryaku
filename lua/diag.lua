-- 诊断：battle_usa.State 载入后到底卡在哪
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa.State"
local OUT  = BASE .. "logs/diag.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
say("t0 frame=" .. emu.framecount())
adv(20)
say("t1 frame=" .. emu.framecount())
local ok, err = pcall(savestate.load, SRC)
say("load=" .. tostring(ok) .. " err=" .. tostring(err))
adv(10)
say("t2 frame=" .. emu.framecount() .. " cursor=" .. cur() .. " paused=" .. tostring(client.get_pausestate and "?" or "?"))
-- 尝试 joypad 动光标
local x0 = cur()
for i = 1, 5 do joypad.set({ Right = true }); emu.frameadvance() end
joypad.set({})
say("after right: " .. cur() .. " (was " .. x0 .. ")")
adv(30)
say("t3 frame=" .. emu.framecount())
-- 读几个关键内存
say(string.format("DISPCNT=0x%04X", memory.read_u16_le(0x04000000)))
say(string.format("ctx=0x%08X", memory.read_u32_le(0x02007060)))
say(string.format("u0=%d,%d fuel=%d hp=%d acted=%d",
  memory.read_u8(0x03002BE2), memory.read_u8(0x03002BE3),
  memory.read_u8(0x03002BE6), memory.read_u8(0x03002BE8),
  memory.read_u8(0x03002BE9)))
say("done")
pcall(client.exit)
