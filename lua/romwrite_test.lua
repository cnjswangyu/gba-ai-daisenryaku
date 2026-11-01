-- 测 ROM 是否可写（决定能否把输入函数的 KEYINPUT 字面量改指向 RAM 邮箱）
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/romwrite.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(30)

local a = 0x080015F4
local before = memory.read_u32_le(a)
say(string.format("原始字面量 @%08X = 0x%08X (应是 0x04000130)", a, before))

local ok = pcall(memory.write_u32_le, a, 0x03007F00)
say("写入 ok=" .. tostring(ok))
local after = memory.read_u32_le(a)
say(string.format("写入后读回 = 0x%08X", after))
say("ROM 可写 = " .. tostring(after == 0x03007F00))

-- 立刻改回，避免影响后续
pcall(memory.write_u32_le, a, before)
say(string.format("已还原 = 0x%08X", memory.read_u32_le(a)))
say("done")
pcall(client.exit)
