local B="D:/prog/gba-ai/"
local f=io.open(B.."logs/mini_trap.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/battle_usa_ready.State")
for _=1,60 do emu.frameadvance() end

local TRAP=0x0203FF00
w(string.format("初始 R15=0x%08X CPSR=0x%08X R13=0x%08X", emu.getregister("R15"), emu.getregister("CPSR"), emu.getregister("R13")))
memory.write_u16_le(TRAP, 0xE7FE)   -- b .
w("陷阱写入: "..string.format("%04X", memory.read_u16_le(TRAP)))
emu.setregister("R15", TRAP+1)
w(string.format("设R15后立即读: 0x%08X", emu.getregister("R15")))
emu.frameadvance()
w(string.format("1帧后 R15=0x%08X", emu.getregister("R15")))
emu.frameadvance()
w(string.format("2帧后 R15=0x%08X", emu.getregister("R15")))
f:close()
pcall(client.exit)
