-- probe_capture2.lua —— 步兵在敌城上遍历行动菜单，逐项截图 + 监控城市格字节
local BASE = "D:/prog/gba-ai/"
local fh = io.open(BASE .. "logs/probe_capture2.txt", "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/cp2_" .. n .. ".png") end
local function r8(a) return memory.read_u8(a) end
local CTX = 0x03000480
local U = 0x03002BE2
local function cur() return r8(0x030067FE), r8(0x030067FF) end
local function press(k, hold, gap)
  for _ = 1, (hold or 6) do joypad.set({ [k] = true }); adv(1) end
  joypad.set({}); adv(gap or 50)
end
local function city(x, y)
  local tb = memory.read_u32_le(CTX + 0x18)
  return string.format("%02X %02X %02X %02X",
    r8(tb+x*4+y*0xC0), r8(tb+x*4+y*0xC0+1), r8(tb+x*4+y*0xC0+2), r8(tb+x*4+y*0xC0+3))
end
local function head(tag)
  local cxp, cyp = cur()
  w(string.format("%-16s state=%d sub=%d ph=%d cur=(%d,%d) city(17,29)=%s ctx10=%02X11=%02X",
    tag, r8(CTX), r8(CTX+1), r8(CTX+0x21), cxp, cyp, city(17,29), r8(CTX+0x10), r8(CTX+0x11)))
end
local ok, err = xpcall(function()
  pcall(client.speedmode, 300)
  adv(30)
  savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
  -- 步兵 U13 → 敌空城 (17,29)：字段落格（探针调试用）
  local k, x, y = 13, 17, 29
  local ur = U + k*24 - 2
  local ox, oy = r8(ur+2), r8(ur+3)
  local g1 = CTX + 0x3F60 + ox*4 + oy*0xC0
  memory.write_u8(g1, 0); memory.write_u8(g1+1, 0)
  local g2 = CTX + 0x3F60 + x*4 + y*0xC0
  memory.write_u8(g2, 1); memory.write_u8(g2+1, k+1)
  memory.write_u8(ur+2, x); memory.write_u8(ur+3, y)
  memory.write_u8(CTX + 0x637E, x); memory.write_u8(CTX + 0x637F, y)
  adv(30)
  head("落格后")
  press("A", 6, 70)              -- 打开单位菜单
  head("菜单打开"); shot("menu0")
  for i = 1, 5 do
    press("Down", 6, 40)
    shot("menu" .. i); head("光标下移" .. i)
  end
  -- 回到第一项，逐项执行看城市变化
  for _ = 1, 5 do press("Up", 6, 20) end
  for i = 1, 5 do
    press("A", 6, 120)           -- 执行当前项
    adv(120)
    head("执行项" .. i); shot("exec" .. i)
    press("B", 6, 80); press("B", 6, 80)   -- 尽量退回
    press("A", 6, 80)            -- 重开菜单
    press("Down", 6, 30)
  end
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
