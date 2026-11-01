-- 验证 0x03001590 起的 48 宽掩码是否就是"移动范围"
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/mask.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/mk_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(16)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

local BASEADDR, STRIDE, ROWS, COLS = 0x03001590, 48, 40, 20

local function dump_mask(tag)
  say("--- " .. tag .. " ---")
  local marks = 0
  for r = 0, ROWS - 1 do
    local line, cnt = {}, 0
    for c = 0, COLS - 1 do
      local v = memory.read_u8(BASEADDR + r * STRIDE + c)
      if v == 0xF1 then line[#line + 1] = "."
      else line[#line + 1] = "#"; cnt = cnt + 1; marks = marks + 1 end
    end
    if cnt > 0 then say(string.format("r%02d %s  (%d)", r, table.concat(line), cnt)) end
  end
  say("合计标记 " .. marks)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
for _ = 1, 6 do
  local x0 = cur(); hold("Right", 12); local x1 = cur(); hold("Left", 12)
  if x0 ~= x1 then break end
  tap("A", 100)
end
say(string.format("cursor=(%d,%d)", cur()))
dump_mask("idle")

tap("A", 50)    -- 单位菜单
tap("A", 50)    -- 移動 → 显示范围
adv(40)
shot("range")
dump_mask("range")
tap("B", 50); tap("B", 50)
say("done")
pcall(client.exit)
