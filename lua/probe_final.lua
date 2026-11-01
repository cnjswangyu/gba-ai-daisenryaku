-- 正确姿势验证：joypad.set 不传 player 索引
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_final.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function reg(n) local ok, v = pcall(emu.getregister, n); if ok and v then return v end return 0 end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/f_" .. n .. ".png") end
local function ram()
  local ok, b = pcall(memory.readbyterange, 0x03000000, 0x1000)
  local nz = 0
  if ok and b then for j = 0, 4095 do if (b[j] or 0) ~= 0 then nz = nz + 1 end end end
  local ok2, e = pcall(memory.readbyterange, 0x02000000, 0x1000)
  local nz2 = 0
  if ok2 and e then for j = 0, 4095 do if (e[j] or 0) ~= 0 then nz2 = nz2 + 1 end end end
  return nz, nz2
end
-- 关键：不要传第二个参数
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 4)
  joypad.set({})
  adv(gap or 30)
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90)
shot("00_splash")
w(string.format("开机画面 f=%d R15=0x%08X IWRAM非零=%d", emu.framecount(), reg("R15"), (ram())))

press("A", 5, 60)
shot("01_after_A")
w(string.format("按A后  f=%d R15=0x%08X DISPCNT=0x%04X IWRAM非零=%d", emu.framecount(), reg("R15"), memory.read_u16_le(0x04000000), (ram())))
adv(120)
shot("02_2s")
press("Start", 5, 60)
shot("03_after_START")
adv(180)
shot("04_4s")
press("A", 5, 60)
shot("05_after_A2")
adv(180)
shot("06_end")
local iw, ew = ram()
w(string.format("结束    f=%d R15=0x%08X DISPCNT=0x%04X IWRAM非零=%d EWRAM非零=%d",
  emu.framecount(), reg("R15"), memory.read_u16_le(0x04000000), iw, ew))

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
