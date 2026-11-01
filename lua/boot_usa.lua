-- boot_usa.lua v2: 冷启动 → 新游戏 → 姓名 → 国家选美国(自适应LEFT) → 国歌 → 确认 → 存档 → 剧本 → 出击编成表
-- 到编成表后: 取消自动部署对话框, dump 池/钱/上限, 存 pre_battle_usa.State
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/boot_usa.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/u_" .. n .. ".png") end

local CTX = 0x03000480
local UNIT_DB = 0x08798A98
local function st()  return memory.read_u8(CTX) end
local function sub() return memory.read_u8(CTX + 1) end
local function wait_st(s, b, cap)
  cap = cap or 900
  for i = 1, cap do
    if st() == s and (b == nil or sub() == b) then return true end
    adv(1)
  end
  return false
end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 5)
  joypad.set({})
  adv(gap or 30)
end
local function key(n, times) for _ = 1, times do press(n, 4, 8) end end

-- 从单位DB取名字的 ASCII 部分
local function uname(uid)
  if uid == 0 then return "" end
  local ok, ptr = pcall(memory.read_u32_le, UNIT_DB + uid * 0x5C)
  if not ok or ptr < 0x08000000 or ptr > 0x0A000000 then return "?" end
  local s = ""
  for i = 0, 11 do
    local ok2, c = pcall(memory.read_u8, ptr + i)
    if not ok2 then break end
    if c == 0 then break end
    if c >= 32 and c < 127 then s = s .. string.char(c) else s = s .. "." end
  end
  return s
end

local function dump_pool(tag)
  w("---- pool dump: " .. tag .. " (state=" .. st() .. " sub=" .. sub() .. ") ----")
  local n = 0
  for i = 0, 98 do
    local id = memory.read_u16_le(CTX + 0x188 + i * 4)
    local f3 = memory.read_u8(CTX + 0x188 + i * 4 + 3)
    if id ~= 0 then
      n = n + 1
      w(string.format("  slot%02d id=0x%03X flag=%d %s", i, id, f3, uname(id)))
    end
  end
  w("  total non-zero slots = " .. n)
  w(string.format("  money(ctx+0x68) = %d", memory.read_u32_le(CTX + 0x68)))
  local cptr = memory.read_u32_le(CTX + 0x14)
  local pidx = memory.read_u8(CTX + 0x990)
  w(string.format("  commander ptr = 0x%08X player=%d limit=%d funds=%d",
      cptr, pidx, memory.read_u8(cptr + 0x21 + pidx * 0x18),
      memory.read_u32_le(cptr + 0x24 + pidx * 0x18)))
  w(string.format("  global sel count (0x020095B4) = %d", memory.read_u32_le(0x020095B4)))
  w(string.format("  country idx ctx+0x64 = %d", memory.read_u8(CTX + 0x64)))
end

pcall(client.speedmode, 100)
pcall(client.setsoundon, false)

adv(120); shot("00_splash")
press("A", 5, 150)          -- 汉化开机图
adv(180); shot("01_title")
press("Start", 6, 90)       -- 标题：请按开始键
adv(120); shot("02_menu")
press("A", 6, 150)          -- 新的游戏
press("A", 6, 60)           -- 姓名提示 → 输入框
press("Right", 4, 40)       -- 唤出键盘
press("A", 6, 50)           -- あ
press("Right", 4, 20)
press("A", 6, 50)           -- い
key("Down", 5); key("Right", 8)
press("A", 6, 90)           -- OK 确定姓名

-- 等国家界面 (state2, substep2)
local ok = wait_st(2, 2, 1200)
w("country screen reached = " .. tostring(ok) .. " state=" .. st() .. " sub=" .. sub())
adv(60); shot("03_country")
local cur = memory.read_u8(CTX + 4)
w("start country idx (ctx+4) = " .. cur)
-- 自适应: 按一次 LEFT 等一会再看 ctx+4, 直到 0 (美国)
for i = 1, 7 do
  cur = memory.read_u8(CTX + 4)
  if cur == 0 then break end
  press("Left", 8, 50)
  adv(30)
  w(string.format("  LEFT#%d -> ctx+4 = %d", i, memory.read_u8(CTX + 4)))
end
adv(40)
w("before confirm: ctx+4 = " .. memory.read_u8(CTX + 4))
shot("04_country_usa")
press("A", 6, 150)          -- 确认美国
adv(40)
w(string.format("after A: state=%d sub=%d ctx+0x64=%d", st(), sub(), memory.read_u8(CTX + 0x64)))
shot("05_after_country")
press("A", 6, 150)          -- 国歌
shot("06_song")

-- 自适应连按 A 直到 state6 (出击编成表)
local presses = 0
while st() ~= 6 and presses < 26 do
  press("A", 6, 60)
  presses = presses + 1
  adv(90)
  w(string.format("  A#%d -> state=%d sub=%d", presses, st(), sub()))
end
w("reached state=" .. st() .. " sub=" .. sub() .. " after " .. presses .. " A presses")
adv(60); shot("07_deploy_list")

-- 若弹自动部署对话框, 按 B 取消 (留在编成表)
if st() == 6 then
  press("B", 6, 60)
  adv(40)
  w("after B: state=" .. st() .. " sub=" .. sub())
  shot("08_after_B")
end

dump_pool("deploy list (USA)")

-- 存档: 出击编成表 + 美国 + 全池
local ok2 = pcall(savestate.save, BASE .. "states/pre_battle_usa.State")
w("savestate.save pre_battle_usa.State = " .. tostring(ok2))

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
