local B="D:/prog/gba-ai/"
local f=io.open(B.."logs/mini_call2.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
local TRAP=0x0203FF00
pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/battle_usa_ready.State")
for _=1,60 do emu.frameadvance() end
memory.write_u16_le(TRAP,0xE7FE)

local saved={}
for i=0,15 do saved[i]=emu.getregister("R"..i) end
local cpsr=emu.getregister("CPSR")
w(string.format("saved R15=0x%08X R14=0x%08X R13=0x%08X CPSR=0x%08X", saved[15], saved[14], saved[13], cpsr))

emu.setregister("R0",19); emu.setregister("R1",29); emu.setregister("R2",24); emu.setregister("R3",26)
emu.setregister("R14",TRAP+1)
emu.setregister("R15",0x08002E75)
w(string.format("设置后 R15=0x%08X R14=0x%08X", emu.getregister("R15"), emu.getregister("R14")))
for i=1,6 do
  emu.frameadvance()
  w(string.format("  frame%d R15=0x%08X R0=%d R13=0x%08X", i, emu.getregister("R15"), emu.getregister("R0"), emu.getregister("R13")))
end
-- 恢复
for i=0,15 do emu.setregister("R"..i, saved[i]) end
emu.setregister("CPSR", cpsr)
w(string.format("恢复后 R15=0x%08X", emu.getregister("R15")))
f:close()
pcall(client.exit)
