-- 等待外部触发文件（go.txt）后截图，用于验证物理键盘输入是否生效
local BASE = "D:/prog/gba-ai/"
local GO = BASE .. "shots/go.txt"
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)
adv(90)
pcall(client.screenshot, BASE .. "shots/k_before.png")

for i = 1, 400 do
  local f = io.open(GO, "r")
  if f then f:close(); break end
  pcall(client.sleep, 50)
  adv(1)
end

adv(20)
pcall(client.screenshot, BASE .. "shots/k_after.png")

local lines = {}
lines[#lines + 1] = string.format("R15=0x%08X DISPCNT=0x%04X KEYINPUT=0x%03X",
  emu.getregister("R15") or 0, memory.read_u16_le(0x04000000), memory.read_u16_le(0x04000130) % 1024)
local ok, b = pcall(memory.readbyterange, 0x03000000, 0x1000)
local nz = 0
if ok and b then for j = 0, 4095 do if (b[j] or 0) ~= 0 then nz = nz + 1 end end end
lines[#lines + 1] = "IWRAM非零=" .. nz
local f = io.open(BASE .. "logs/probe_kbd.txt", "w")
if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
