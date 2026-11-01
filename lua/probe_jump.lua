-- 绕过按键等待：直接把 R15 设到 crt0 (0x080000C0)，等价于"按下 A"之后走的路
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_jump.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function reg(n) local ok, v = pcall(emu.getregister, n); if ok and v then return v end return 0 end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)

-- 先让开机画面出来
adv(60)
w(string.format("跳转前 R15=0x%08X DISPCNT=0x%04X", reg("R15"), memory.read_u16_le(0x04000000)))
pcall(client.screenshot, BASE .. "shots/j0_splash.png")

-- 强制跳转到 crt0
local ok, err = pcall(emu.setregister, "R15", 0x080000C0)
w("设置 R15 -> 0x080000C0 : " .. tostring(ok) .. " " .. tostring(err))
adv(2)
w(string.format("跳转后即 R15=0x%08X CPSR=0x%08X", reg("R15"), reg("CPSR")))

local shots = { { 60, "j1_1s" }, { 120, "j2_2s" }, { 180, "j3_3s" }, { 300, "j4_5s" }, { 300, "j5_8s" }, { 300, "j6_12s" } }
for _, s in ipairs(shots) do
  adv(s[1])
  pcall(client.screenshot, BASE .. "shots/" .. s[2] .. ".png")
  local ok2, b = pcall(memory.readbyterange, 0x03000000, 0x1000)
  local nz = 0
  if ok2 and b then for j = 0, 4095 do if (b[j] or 0) ~= 0 then nz = nz + 1 end end end
  local ok3, e = pcall(memory.readbyterange, 0x02000000, 0x1000)
  local nz2 = 0
  if ok3 and e then for j = 0, 4095 do if (e[j] or 0) ~= 0 then nz2 = nz2 + 1 end end end
  w(string.format("  %-8s f=%-5d R15=0x%08X DISPCNT=0x%04X IWRAM非零=%d EWRAM非零=%d",
    s[2], emu.framecount(), reg("R15"), memory.read_u16_le(0x04000000), nz, nz2))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
