-- 姓名：先试 START 确认；不行再移动到 OK 按 A
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_name3.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/m_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function oam()
  local t = {}
  for i = 0, 127 do
    local a0 = memory.read_u16_le(0x07000000 + i * 8)
    local a1 = memory.read_u16_le(0x07000000 + i * 8 + 2)
    local a2 = memory.read_u16_le(0x07000000 + i * 8 + 4)
    local dis = math.floor(a0 / 512) % 2 == 1
    local x, y = a1 % 512, a0 % 256
    if not dis and not (a0 == 0 and a1 == 0 and a2 == 0) and x < 260 and y < 200 then
      t[#t + 1] = string.format("#%d(%d,%d)t%d", i, x, y, a2 % 1024)
    end
  end
  return #t, table.concat(t, " ")
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90)
press("A", 5, 150)              -- 开机图
adv(180)
press("Start", 6, 90)           -- 标题
adv(120)
press("A", 6, 150)              -- 新的游戏 → 提示
shot("00_prompt")
press("A", 6, 60)               -- 提示 → 输入框
shot("01_field")
press("Right", 4, 40)           -- 唤出键盘
shot("02_kb")
local n, d = oam(); w("键盘 OAM=" .. n .. " " .. d:sub(1, 300))

-- 方案 1：START 直接确认
press("Start", 6, 60)
shot("03_after_start")
adv(60); shot("04_start_wait")

-- 方案 2：走到 OK
for _ = 1, 5 do press("Down", 4, 10) end
for _ = 1, 9 do press("Right", 4, 10) end
shot("05_at_ok")
local n2, d2 = oam(); w("OK 处 OAM=" .. n2 .. " " .. d2:sub(1, 300))
press("A", 6, 60)
shot("06_after_ok")
adv(90); shot("07_after_ok2")
adv(120); shot("08_wait")
press("A", 6, 90)
shot("09_a")
adv(120); shot("10_a2")
press("A", 6, 90)
shot("11_a3")
adv(120); shot("12_a4")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
