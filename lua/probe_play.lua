-- 进入游戏内部：开场 → 标题 → 菜单 → 战场，逐步截图
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_play.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/p_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })   -- 不传 player 索引
  adv(hold or 4)
  joypad.set({})
  adv(gap or 30)
end
local function oam()
  local list = {}
  for i = 0, 127 do
    local a0 = memory.read_u16_le(0x07000000 + i * 8)
    local a1 = memory.read_u16_le(0x07000000 + i * 8 + 2)
    local a2 = memory.read_u16_le(0x07000000 + i * 8 + 4)
    local disabled = math.floor(a0 / 512) % 2 == 1
    local x, y = a1 % 512, a0 % 256
    if not disabled and x < 260 and y < 200 then
      list[#list + 1] = string.format("(%d,%d)t%d", x, y, a2 % 1024)
    end
  end
  return #list, table.concat(list, " ")
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(90);  press("A", 5, 120)          -- 过开机图
adv(240); shot("01_title")            -- 标题
w("标题页 OK")

press("Start", 6, 90)                 -- 请按开始键
shot("02_menu")
local n, d = oam(); w(string.format("菜单后 OAM=%d %s", n, d:sub(1, 120)))

adv(60); shot("03_menu2")
press("A", 6, 90)                     -- 选第一项
shot("04_after_A")
adv(90); shot("05_after_A2")
press("A", 6, 120)
shot("06_after_A3")
adv(120); shot("07_later")
local n2, d2 = oam(); w(string.format("进入后 OAM=%d %s", n2, d2:sub(1, 200)))

-- 试探性移动
press("Right", 5, 40); shot("08_right")
press("Right", 5, 40); shot("09_right2")
press("Down", 5, 40);  shot("10_down")

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
