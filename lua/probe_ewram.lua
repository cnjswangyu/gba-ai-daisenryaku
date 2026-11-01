-- probe_ewram.lua —— EWRAM+IWRAM 全域 diff 定位勾选位
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_ewram.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end
local CTX = 0x03000480
local function state() return memory.read_u8(CTX) end
-- 扫描段：EWRAM 前 256KB + IWRAM
local REGIONS = { {0x02000000, 0x40000}, {0x03000000, 0x8000} }
local function snapshot()
  local t = {}
  for _, r in ipairs(REGIONS) do
    for i = 0, r[2] - 1, 1 do t[#t + 1] = memory.read_u8(r[1] + i) end
  end
  return t
end
local function addr_of(i)
  if i <= REGIONS[1][2] then return REGIONS[1][1] + i - 1 end
  return REGIONS[2][1] + (i - REGIONS[1][2] - 1)
end
local ok, err = xpcall(function()
  pcall(client.speedmode, 400)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/stage1_ready.State"); adv(60)
  press("B", 6, 60); press("A", 6, 90); press("A", 6, 120); press("A", 6, 120)
  w("清单界面 state=" .. state())
  local s1 = snapshot(); adv(40); local s1b = snapshot()
  press("A", 6, 30); adv(20)
  local s2 = snapshot(); adv(40); local s2b = snapshot()
  -- 稳定过滤：s1==s1b 且 s2==s2b 的字节才算数
  local cands = {}
  for i = 1, #s1 do
    if s1[i] == s1b[i] and s2[i] == s2b[i] and s1[i] ~= s2[i] then
      cands[#cands + 1] = string.format("0x%08X: %02X->%02X", addr_of(i), s1[i], s2[i])
    end
  end
  w("稳定变化字节数: " .. #cands)
  for n, l in ipairs(cands) do
    if n > 80 then w("  ...(共 " .. #cands .. ")"); break end
    w("  " .. l)
  end
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
