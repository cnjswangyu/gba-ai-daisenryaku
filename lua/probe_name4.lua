-- 输入名字：L 切字种类 → 打一个字 → 走到 OK 确认 → 继续推进
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_name4.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/q_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90)
press("A", 5, 150)              -- 开机图
adv(180)
press("Start", 6, 90)           -- 标题
adv(120)
press("A", 6, 150)              -- 新的游戏 → 提示
press("A", 6, 60)               -- 提示 → 输入框
press("Right", 4, 40)           -- 唤出键盘
shot("00_kb_hira")

press("L", 5, 60)               -- 切换字种类
shot("01_after_L")
press("R", 5, 60)
shot("02_after_R")
press("L", 5, 60)               -- 回到上一个种类
shot("03_after_L2")

press("A", 6, 60)               -- 打第一个字符
shot("04_typed1")
press("Right", 4, 30)
press("A", 6, 60)               -- 再打一个
shot("05_typed2")

for _ = 1, 5 do press("Down", 4, 10) end
for _ = 1, 9 do press("Right", 4, 10) end
shot("06_at_ok")
press("A", 6, 90)
shot("07_confirmed")
adv(120); shot("08_wait")
press("A", 6, 120)
shot("09_next")
adv(120); shot("10_next2")
press("A", 6, 120)
shot("11_next3")
adv(150); shot("12_next4")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
