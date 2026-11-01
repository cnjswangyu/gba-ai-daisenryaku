local B="D:/prog/gba-ai/"
local f=io.open(B.."logs/peek_pre.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/pre_battle.State")
for _=1,60 do emu.frameadvance() end
pcall(client.screenshot, B.."shots/pre_00.png")
w("已截图 pre_00")
-- 看看 ctx 附近状态
w(string.format("ctx+0x20=%d ctx+0x21=%d ctx+0x22=%d", memory.read_u8(0x03000480+0x20), memory.read_u8(0x03000480+0x21), memory.read_u8(0x03000480+0x22)))
f:close()
pcall(client.exit)
