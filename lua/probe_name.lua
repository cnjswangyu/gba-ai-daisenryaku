-- 逐屏推进：开机 → 标题 → 主菜单 → 新的游戏 → 姓名输入 → 确认
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_name.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/n_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })       -- 不传 player 索引
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function reg(n) local ok, v = pcall(emu.getregister, n); if ok and v then return v end return 0 end
local function mark(tag)
  w(string.format("%-12s f=%-5d R15=0x%08X DISPCNT=0x%04X", tag, emu.framecount(), reg("R15"), memory.read_u16_le(0x04000000)))
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90); mark("boot")
press("A", 5, 150)                 -- 过汉化开机图
mark("after_A")
adv(180); shot("01_title")

press("Start", 6, 90)              -- 标题：请按开始键
shot("02_after_start"); mark("after_start")
adv(60); shot("03_menu")

press("A", 6, 90)                  -- 主菜单第一项：新的游戏
shot("04_newgame"); mark("newgame")
adv(90); shot("05_after")
press("A", 6, 120)
shot("06_after2"); mark("after2")
adv(120); shot("07_after3")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
