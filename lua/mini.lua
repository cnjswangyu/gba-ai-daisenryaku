local f = io.open("D:/prog/gba-ai/logs/mini.txt","w")
if f then f:write("hello from lua\n"); f:close() end
local f2 = io.open("D:/prog/gba-ai/logs/probe_usa_fields.txt","a")
if f2 then f2:write("mini ok frame="..emu.framecount().."\n"); f2:close() end
pcall(client.exit)
