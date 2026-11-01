local B="D:/prog/gba-ai/"
local f=io.open(B.."logs/mini_romwr.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/battle_usa_ready.State")
for _=1,60 do emu.frameadvance() end

local a=0x08002494
local b0=memory.read_u8(a)
memory.write_u8(a,0x01)
local b1=memory.read_u8(a)
w(string.format("ROM 0x%08X: 原=%02X 写01后读回=%02X  %s", a,b0,b1, (b1==0x01) and "ROM可写" or "ROM不可写(被忽略)"))

-- 兵种表 speed
local s=0x0879F281
local s0=memory.read_u8(s)
memory.write_u8(s,0x1E)
local s1=memory.read_u8(s)
w(string.format("兵种speed 0x%08X: 原=%d 写30后读回=%d %s", s,s0,s1,(s1==30) and "可写" or "不可写"))

-- 对照：EWRAM 可写
local e=0x0203FF00
memory.write_u8(e,0xAB)
w(string.format("EWRAM 0x%08X 写AB 读回=%02X", e, memory.read_u8(e)))
f:close()
pcall(client.exit)
