-- Daisenryaku (this project's ROM), BizHawk Lua Console.
-- Change MODE to ON, OFF, TOGGLE or STATUS and run once. No polling loop needed.
local MODE = "OFF"
local ctx = memory.read_u32_le(0x02007060)
assert(ctx == 0x03000480, "Daisenryaku game context is not initialized")
local addr = ctx + 0xC55 -- 0x030010D5; the actual in-battle presentation option.
local before = memory.read_u8(addr)
local target = before
if MODE == "ON" then target = 1
elseif MODE == "OFF" then target = 0
elseif MODE == "TOGGLE" then target = (before == 1) and 0 or 1
else assert(MODE == "STATUS", "MODE must be ON, OFF, TOGGLE or STATUS") end
memory.write_u8(addr, target)
assert(memory.read_u8(addr) == target, "Animation option write failed")
console.log(string.format("Attack animation: %s (0x%08X: %d -> %d)",
  target == 1 and "ON" or "OFF", addr, before, target))
