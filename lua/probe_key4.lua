-- 输入注入排查：player 索引 / 不同 API / 核心是否接受
local OUT = "D:/prog/gba-ai/logs/probe_key4.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function ki() return memory.read_u16_le(0x04000130) % 1024 end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

pcall(client.setsoundon, false)
adv(30)

for _, p in ipairs({ 0, 1, 2, 3 }) do
  pcall(joypad.set, {}, p)
  adv(2)
  local before = ki()
  local ok = pcall(joypad.set, { A = true }, p)
  adv(1)
  local during = ki()
  adv(1)
  local during2 = ki()
  pcall(joypad.set, {}, p)
  local okg, g = pcall(joypad.get, p)
  local n = 0
  if okg and type(g) == "table" then for _ in pairs(g) do n = n + 1 end end
  w(string.format("player=%d set_ok=%s before=%03X during=%03X,%03X  get表项=%d",
    p, tostring(ok), before, during, during2, n))
  adv(3)
end

-- 试 setfrommnemonicstr（走 movie 输入通道）
w("")
for _, s in ipairs({ "|    0,    0,    0,    0,    0,    0,    0,    0|", "|....S.B.A...|" }) do
  local ok, err = pcall(joypad.setfrommnemonicstr, s)
  adv(2)
  w(string.format("mnemonic %-40s ok=%s err=%s KEYINPUT=%03X", s, tostring(ok), tostring(err), ki()))
end

-- 试内存写 KEYINPUT（正常无效，验证寄存器确实只读）
memory.write_u16_le(0x04000130, 0x3FE)
adv(1)
w("直接写 KEYINPUT 后读到 = " .. string.format("%03X", ki()))

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
