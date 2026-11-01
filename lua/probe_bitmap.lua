-- probe_bitmap.lua —— 干净定位「部署选择集」内存真身
-- 修正上次缺陷：进清单后先垫一次 A（防首按吞），再做单变量 toggle diff
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_bitmap.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end
local CTX = 0x03000480
-- 候选区域：ctx 界面字段区 + 上次命中的 EWRAM 区 + 更宽的 EWRAM
local REGIONS = {
  {0x03000480, 0x80},    -- ctx 头部（含 0x10/0x11）
  {0x02005000, 0x200},   -- 上次命中区
  {0x02000000, 0x400},   -- EWRAM 低区
}
local function snapshot()
  local t = {}
  for _, r in ipairs(REGIONS) do
    for i = 0, r[2] - 1 do t[#t + 1] = memory.read_u8(r[1] + i) end
  end
  return t
end
local function addr_of(i)
  for _, r in ipairs(REGIONS) do
    if i <= r[2] then return r[1] + i - 1, r[3] or r[1] end
    i = i - r[2]
  end
end
-- 直接三段式（改写 addr_of 逻辑：手工展开）
local function abs(i)
  local n1, n2, n3 = REGIONS[1][2], REGIONS[2][2], REGIONS[3][2]
  if i <= n1 then return REGIONS[1][1] + i - 1 end
  if i <= n1 + n2 then return REGIONS[2][1] + (i - n1 - 1) end
  return REGIONS[3][1] + (i - n1 - n2 - 1)
end
local function diff(s1, s2, tag)
  local out = {}
  for i = 1, #s1 do
    if s1[i] ~= s2[i] then
      out[#out + 1] = string.format("0x%08X: %02X->%02X", abs(i), s1[i], s2[i])
    end
  end
  w("== " .. tag .. " (" .. #out .. " 字节) ==")
  for _, l in ipairs(out) do w("  " .. l) end
  return out
end
local function state() return memory.read_u8(CTX) end
local ok, err = xpcall(function()
  pcall(client.speedmode, 400)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/pre_battle.State"); adv(60)
  press("B", 6, 60); press("A", 6, 90); press("A", 6, 120); press("A", 6, 120)
  adv(30)  -- 等清单稳定
  -- 垫一次 A（防首按吞，这次它真的会勾上行 0）
  press("A", 6, 60)
  adv(20)
  local s1 = snapshot(); adv(30); local s1b = snapshot()   -- 行0已勾选，稳定态
  press("A", 6, 30); adv(20)                               -- 取消行 0
  local s2 = snapshot(); adv(30); local s2b = snapshot()
  diff(s1, s2, "勾选->取消（toggle 集合 = 勾选真身）")
  -- 再勾回行 0（验证可逆），然后 Down+A 勾行 1，看行间偏移规律
  local s3 = snapshot()
  press("A", 6, 30); adv(20)
  local s4 = snapshot()
  diff(s3, s4, "取消->再勾选（应与上面镜像）")
  press("Down", 8, 30)
  local s5 = snapshot()
  press("A", 6, 30); adv(20)
  local s6 = snapshot()
  diff(s5, s6, "Down+A（行 1 勾选，看相对行 0 的偏移）")
  w("state=" .. state())
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
