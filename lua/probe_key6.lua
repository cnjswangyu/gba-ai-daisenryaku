-- 逐行落盘，避免 print 输出不到 stdout
local OUT = "D:/prog/gba-ai/logs/key6.txt"
local function say(s)
  pcall(console.log, tostring(s))
  local f = io.open(OUT, "a")
  if f then f:write(tostring(s), "\n"); f:close() end
end
pcall(client.setsoundon, false)
for _ = 1, 30 do emu.frameadvance() end

local function dump(t)
  if type(t) ~= "table" then return "not-table" end
  local n, parts = 0, {}
  for k, v in pairs(t) do n = n + 1; if n <= 20 then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end end
  return "n=" .. n .. " {" .. table.concat(parts, ",") .. "}"
end

say("[t] joypad.get()     -> " .. dump(joypad.get()))
say("[t] joypad.get(1)    -> " .. dump(joypad.get(1)))
say("[t] joypad.get(0)    -> " .. dump(joypad.get(0)))
say("[t] getimmediate(1)  -> " .. dump(joypad.getimmediate(1)))
say("[t] KEYINPUT before  = " .. string.format("%03X", memory.read_u16_le(0x04000130) % 1024))

joypad.set({ A = true })
emu.frameadvance()
say("[t] set{controller=nil} A -> KEYINPUT=" .. string.format("%03X", memory.read_u16_le(0x04000130) % 1024) .. "  get=" .. dump(joypad.get(1)))

joypad.set({ A = true, Start = true }, 1)
emu.frameadvance()
say("[t] set(A+Start,1)   -> KEYINPUT=" .. string.format("%03X", memory.read_u16_le(0x04000130) % 1024))

joypad.set({ ["P1 A"] = true }, 1)
emu.frameadvance()
say("[t] set(P1 A,1)      -> KEYINPUT=" .. string.format("%03X", memory.read_u16_le(0x04000130) % 1024))

say("[t] R15=" .. string.format("%08X", emu.getregister("R15") or 0))
pcall(client.exit)
