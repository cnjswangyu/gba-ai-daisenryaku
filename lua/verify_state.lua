-- 只读验证：载入存档，截图并读取单位表/格表。不按键、不写内存。
local B = "D:/prog/gba-ai/"
local ST = B .. "states/teleport_test.State"

savestate.load(ST)
for _ = 1, 90 do emu.frameadvance() end

local CTX = 0x03000480
local o = 0x03002BE0 + 17 * 24
local x, y, fuel, hp = memory.read_u8(o + 2), memory.read_u8(o + 3), memory.read_u8(o + 4), memory.read_u8(o + 6)
local function g(px, py)
  local a = CTX + 0x3F60 + px * 4 + py * 0xC0
  return memory.read_u8(a), memory.read_u8(a + 1)
end
local old1, old2 = g(19, 29)
local new1, new2 = g(24, 26)

local f = io.open(B .. "logs/tp_verify.txt", "w")
f:write(string.format("U17 = (%d,%d) fuel=%d hp=%d\n", x, y, fuel, hp))
f:write(string.format("旧格(19,29) = [%d,%d]\n", old1, old2))
f:write(string.format("新格(24,26) = [%d,%d]\n", new1, new2))
f:close()

pcall(client.screenshot, B .. "shots/tp_verify.png")
pcall(client.exit)
