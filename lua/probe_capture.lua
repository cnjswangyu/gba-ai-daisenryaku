-- probe_capture.lua —— 步兵上敌城，对比坦克/步兵行动菜单，抓菜单光标字节
local BASE = "D:/prog/gba-ai/"
local fh = io.open(BASE .. "logs/probe_capture.txt", "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/cap_" .. n .. ".png") end
local function r8(a) return memory.read_u8(a) end
local CTX = 0x03000480
local U = 0x03002BE2
local function cur() return r8(0x030067FE), r8(0x030067FF) end
-- joypad 仅调试
local function press(k, hold, gap)
  for _ = 1, (hold or 6) do joypad.set({ [k] = true }); adv(1) end
  joypad.set({}); adv(gap or 50)
end
local function head(tag)
  local t = {}
  for i = 0x0C, 0x30 do t[#t+1] = string.format("%02X", r8(CTX + i)) end
  w(string.format("%s state=%d sub=%d ph=%d cur=(%d,%d) ctx0C-30=%s",
    tag, r8(CTX), r8(CTX+1), r8(CTX+0x21), cur(), table.concat(t, "")))
end
local function citycell(x, y)
  local tb = memory.read_u32_le(CTX + 0x18)
  return string.format("(%d,%d)=%02X %02X %02X %02X", x, y,
    r8(tb+x*4+y*0xC0), r8(tb+x*4+y*0xC0+1), r8(tb+x*4+y*0xC0+2), r8(tb+x*4+y*0xC0+3))
end
adv(30)
savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
-- U13 = 軽歩兵 305 @ (20,32) → 直接字段落格到敌空城 (17,29)（探针，不受预算）
local k = 13
local ur = U + k*24 - 2
local ox, oy = r8(ur+2), r8(ur+3)
local g1 = CTX + 0x3F60 + ox*4 + oy*0xC0
memory.write_u8(g1, 0); memory.write_u8(g1+1, 0)
local g2 = CTX + 0x3F60 + 17*4 + 29*0xC0
memory.write_u8(g2, 1); memory.write_u8(g2+1, k+1)
memory.write_u8(ur+2, 17); memory.write_u8(ur+3, 29)
memory.write_u8(CTX + 0x637E, 17); memory.write_u8(CTX + 0x637F, 29)
adv(30)
w("步兵落格(17,29) " .. citycell(17,29))
-- 打开 U13 行动菜单：A
press("A", 6, 60); head("步兵菜单"); shot("inf_menu")
for i = 1, 6 do
  press("Down", 6, 40)
  press("A", 6, 80)          -- 误执行就执行了，先看每项截图
  head("步兵菜单Down" .. i); shot("inf_d" .. i)
  press("B", 6, 60)          -- 退出可能的子菜单
  press("B", 6, 60)
  press("A", 6, 80)          -- 重开菜单
end
if fh then fh:close() end
pcall(client.exit)
