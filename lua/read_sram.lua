local B="D:/prog/gba-ai/"
local f=io.open(B.."logs/sram.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/battle_usa_ready.State")
for _=1,60 do emu.frameadvance() end
-- 读 SRAM 前 512 字节（0x0E000000）
for base=0x0E000000, 0x0E0001F0, 16 do
  local t={}
  for i=0,15 do t[#t+1]=string.format("%02X", memory.read_u8(base+i)) end
  local asc=""
  for i=0,15 do local c=memory.read_u8(base+i); asc=asc..(c>=32 and c<127 and string.char(c) or ".") end
  w(string.format("%08X  %s  %s", base, table.concat(t," "), asc))
end
-- 也看 EWRAM 里疑似设置的块（找连续 4-8 个 0/1）
w("--- EWRAM 扫描：连续 4 字节都是 0/1 的位置 ---")
local cnt=0
for a=0x02000000, 0x02040000-8 do
  local ok=true
  for i=0,3 do local v=memory.read_u8(a+i); if v>1 then ok=false; break end end
  if ok then
    local vals={}
    for i=0,3 do vals[#vals+1]=memory.read_u8(a+i) end
    w(string.format("  0x%08X  %d %d %d %d", a, vals[1],vals[2],vals[3],vals[4]))
    cnt=cnt+1
    if cnt>=25 then break end
  end
end
f:close()
pcall(client.exit)
