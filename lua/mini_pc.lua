local B="D:/prog/gba-ai/"
local f=io.open(B.."logs/mini_pc.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
for _=1,60 do emu.frameadvance() end
local before=emu.getregister("R15")
w(string.format("before R15=0x%08X CPSR=0x%08X", before, emu.getregister("CPSR")))
local ok,err=pcall(emu.setregister,"R15",0x08002E75)
w(string.format("setregister R15 ok=%s err=%s -> now 0x%08X", tostring(ok), tostring(err), emu.getregister("R15")))
-- 试试写 R14 看是否生效
local ok2,err2=pcall(emu.setregister,"R14",0x03007F81)
w(string.format("setregister R14 ok=%s -> now 0x%08X", tostring(ok2), emu.getregister("R14")))
-- 试探是否有 PC 别名
local ok3,err3=pcall(emu.setregister,"PC",0x08002E75)
w(string.format("setregister PC  ok=%s err=%s", tostring(ok3), tostring(err3)))
f:close()
pcall(client.exit)
