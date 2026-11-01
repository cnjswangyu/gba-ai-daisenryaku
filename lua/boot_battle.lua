-- 一路推进到战场：开机图 → 标题 → 新游戏 → 姓名 → 国家/国歌 → 剧本 → 出击
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/boot_battle.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/b_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function key(n, times) for _ = 1, times do press(n, 4, 8) end end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90)
press("A", 5, 150)          -- 汉化开机图
adv(180)
press("Start", 6, 90)       -- 标题：请按开始键
adv(120)
press("A", 6, 150)          -- 新的游戏
press("A", 6, 60)           -- 姓名提示 → 输入框
press("Right", 4, 40)       -- 假名键盘
press("A", 6, 50)           -- あ
press("Right", 4, 20)
press("A", 6, 50)           -- い
key("Down", 5); key("Right", 8)
press("A", 6, 90)           -- OK 确定姓名
adv(120)
press("A", 6, 120)          -- 国家：日本
press("A", 6, 120)          -- 国歌
shot("00_before_confirm")

-- 已知：从「确认设置」连按 14 次 A 到出击编成表
for i = 1, 14 do
  press("A", 6, 100)
  adv(30)
end
shot("01_deploy_list")

press("Start", 6, 120)      -- START = 出击
shot("02_after_start")
adv(150); shot("03_map")
adv(150); shot("04_map2")
adv(180); shot("05_map3")

w("done")
local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
