-- 先看清假名键盘：光标初始位置 + 每次移动一格的表现
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_name2.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/k_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90)
press("A", 5, 150)          -- 过开机图
adv(180)
press("Start", 6, 90)       -- 标题
adv(60)
press("A", 6, 120)          -- 新的游戏
adv(150)
shot("00_prompt")

press("A", 6, 40)           -- 试：按 A 打开/确认
adv(30); shot("01_afterA")

press("Down", 4, 20)
shot("02_down1")
press("Right", 4, 20)
shot("03_right1")

w("done")
local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
