-- 探针 2：枚举战场菜单各阶段的 ctx+0x08 值（AI 必须知道自己在哪一层），
-- 并通过"移动+待机"前后单位记录的 diff 找出"已行动"标志字节。
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle_usa_live.State"
local OUT  = BASE .. "logs/probe_menu_stage.txt"
local CTX  = 0x03000480
local U    = 0x03002BE2

local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function shot(n) pcall(client.screenshot, BASE .. "shots/pm_" .. n .. ".png") end
local function tap(k, gap)
  for _ = 1, 3 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 25)
end
local function hold(k, f, gap)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(gap or 20)
end

local function rec(prefix, tag)
  local st, sub, st8 = memory.read_u8(CTX), memory.read_u8(CTX + 1), memory.read_u8(CTX + 8)
  local x, y = cur()
  local b = {}
  for i = 0, 25 do b[#b + 1] = string.format("%02X", memory.read_u8(U - 2 + i)) end
  w(string.format("%-6s %-14s state=%d sub=%d ctx+8=0x%02X cursor=(%2d,%2d) u0=[%s]",
    prefix, tag, st, sub, st8, x, y, table.concat(b, " ")))
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, SRC)))
  adv(60)

  rec("S0", "地图"); shot("00_map")

  tap("A", 35);  rec("S1", "A->菜单①"); shot("01_menu1")
  tap("A", 35);  rec("S2", "A->寻路态"); shot("02_move")
  hold("Right", 14); rec("S2b", "寻路Right"); shot("03_move_right")
  hold("Down", 14);  rec("S2c", "寻路Down"); shot("04_move_down")

  tap("A", 35);  rec("S3", "A->菜单②"); shot("05_menu2")
  tap("A", 35);  rec("S4", "A->待机后"); shot("06_waited")

  adv(30); rec("S5", "稳定后"); shot("07_after")
  tap("B", 30); rec("S6", "B后"); shot("08_afterB")

  -- 光标在空格时按 A 的表现
  hold("Right", 14); hold("Right", 14); hold("Right", 14)
  rec("S7", "空格"); shot("09_empty")
  tap("A", 35); rec("S8", "空格+A"); shot("10_emptyA")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
