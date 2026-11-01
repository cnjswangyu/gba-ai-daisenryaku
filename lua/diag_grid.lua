local B="D:/prog/gba-ai/"
local CTX,U,STRIDE=0x03000480,0x03002BE2,24
local f=io.open(B.."logs/diag_grid.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/battle_usa_ready.State")
for _=1,20 do emu.frameadvance() end
-- 不按任何键，只载入存档后读当前状态（此时是游戏中最新进度？savestate 会覆盖）
-- 先读当前（未载入）状态
w("== 载入存档后的状态 ==")
for side,base,lim in pairs({}) do end
local function dump(side, base, n)
  local cnt=0
  for k=0,n-1 do
    local id=memory.read_u16_le(base+k*STRIDE-2)
    if id~=0 then
      local x=memory.read_u8(base+k*STRIDE)
      local y=memory.read_u8(base+k*STRIDE+1)
      local g=CTX+0x3F60+x*4+y*0xC0
      local gc=memory.read_u8(g); local gs=memory.read_u8(g+1)
      local want=(side=="MY") and 1 or 2
      local ok=(gc==want and gs==k+1)
      w(string.format("%s%d id%d (%d,%d) 格表=[%d,%d] 期望=[%d,%d] %s",
        side,k,id,x,y,gc,gs,want,k+1, ok and "OK" or "<<< 不一致"))
      cnt=cnt+1
    end
  end
  w(side.." 非空单位数 = "..cnt)
end
dump("MY",U,64)
dump("EN",0x030031E2,64)
f:close()
pcall(client.exit)
