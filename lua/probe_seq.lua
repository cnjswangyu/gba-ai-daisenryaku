-- 每按一次 A 截一张图，把「确认设置」之后的所有画面全部记录下来
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_seq.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/s_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function key(n, times) for _ = 1, times do press(n, 4, 8) end end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

-- 已知可靠前缀：开机 → 标题 → 菜单 → 姓名 → 国家 → 国歌
adv(90)
press("A", 5, 150)          -- 开机图
adv(180)
press("Start", 6, 90)       -- 标题
adv(120)
press("A", 6, 150)          -- 新的游戏
press("A", 6, 60)           -- 姓名提示
press("Right", 4, 40)       -- 键盘
press("A", 6, 50)           -- あ
press("Right", 4, 20)
press("A", 6, 50)           -- い
key("Down", 5); key("Right", 8)
press("A", 6, 90)           -- 确定姓名
adv(120)
shot("00_country")
press("A", 6, 120)          -- 国家：日本
shot("01_song")
press("A", 6, 120)          -- 国歌
shot("02_confirm")

-- 从这里开始，一步一图
for i = 1, 14 do
  press("A", 6, 100)
  adv(30)
  shot(string.format("a%02d", i))
end

w("done")
local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
