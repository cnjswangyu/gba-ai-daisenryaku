-- 开新游戏宏：汉化开机图 → 标题 → 新的游戏 → 输名 → 国家/国歌 → 存档槽 → 进战场
-- 每个关键节点截图，便于人工/视觉模型核对
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/boot_game.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/g_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function key(n, times) for _ = 1, times do press(n, 4, 8) end end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

-- 1) 汉化开机图（等 A/B/START）
adv(90); shot("01_splash")
press("A", 5, 150)
-- 2) 标题：请按开始键
shot("02_title")
press("Start", 6, 90)
adv(120)
-- 3) 主菜单
shot("03_menu")
press("A", 6, 150)         -- 新的游戏
press("A", 6, 60)          -- 姓名提示 → 输入框
press("Right", 4, 40)      -- 唤出键盘
shot("04_keyboard")
-- 4) 名字：あい
press("A", 6, 50)
press("Right", 4, 20)
press("A", 6, 50)
shot("05_typed")
key("Down", 5); key("Right", 8)
shot("06_ok_sel")
press("A", 6, 90)          -- 确定姓名
adv(120); shot("07_country")
-- 5) 国家 / 国歌 / 确认
press("A", 6, 120)         -- 选日本
shot("08_song")
press("A", 6, 120)         -- 选国歌
shot("09_confirm")
press("A", 6, 150)         -- A可以
shot("10_slot")
-- 6) 存档槽
press("A", 6, 180)         -- 决定（No.1）
shot("11_after_slot")
adv(180); shot("12_loading")
adv(180); shot("13_loading2")

w("done")
local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
