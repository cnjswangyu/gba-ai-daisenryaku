-- 精确路径：输入"あい" → 下5右8到 OK → A 确认 → 继续
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_name5.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/r_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function key(n, times)
  for _ = 1, times do press(n, 4, 8) end
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90)
press("A", 5, 150)              -- 开机图
adv(180)
press("Start", 6, 90)           -- 标题
adv(120)
press("A", 6, 150)              -- 新的游戏 → 提示
press("A", 6, 60)               -- → 输入框
press("Right", 4, 40)           -- 唤出键盘
shot("00_kb")

press("A", 6, 50)               -- 打「あ」
press("Right", 4, 20)
press("A", 6, 50)               -- 打「い」
shot("01_typed")

key("Down", 5)
key("Right", 8)                 -- col1 -> col9 = OK
shot("02_at_ok")
press("A", 6, 90)
shot("03_ok_pressed")
adv(120); shot("04_wait")

-- 之后一路 A 推进，逐屏记录
for i = 1, 6 do
  press("A", 6, 90)
  adv(60)
  shot(string.format("05_%02d", i))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
