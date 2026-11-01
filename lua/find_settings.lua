local B="D:/prog/gba-ai/"
local f=io.open(B.."logs/find_settings.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
local function snap(addr,len)
  local t=memory.readbyterange(addr,len); local c={}
  for i=0,len-1 do c[i+1]=string.char(t[i] or t[i+1] or 0) end
  return table.concat(c)
end
pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/battle_usa_ready.State")
for _=1,60 do emu.frameadvance() end

local pat=string.char(1,1,0,0,1,1,1,1)
local zones={{0x02000000,0x40000,"EWRAM"},{0x03000000,0x8000,"IWRAM"}}
for _,z in ipairs(zones) do
  local s=snap(z[1],z[2])
  local i=1; local n=0
  while true do
    local j=s:find(pat,i,true)
    if not j then break end
    n=n+1
    if n<=10 then
      w(string.format("  %s 0x%08X  %s", z[3], z[1]+j-1,
        string.format("%02X %02X %02X %02X %02X %02X %02X %02X",
          string.byte(s,j),string.byte(s,j+1),string.byte(s,j+2),string.byte(s,j+3),
          string.byte(s,j+4),string.byte(s,j+5),string.byte(s,j+6),string.byte(s,j+7))))
    end
    i=j+1
  end
  w(z[3].." 命中 "..n.." 处")
end
f:close()
pcall(client.exit)
