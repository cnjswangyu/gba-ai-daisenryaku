-- probe_check.lua —— 逆向「勾选」状态的内存存储
-- 路径：出击编成表 → (B,A→state4) → A(入口框) → A(自动部署清单)
-- 实验 1：清单界面按一次 A 前后 diff ctx 区域（过滤掉连续两帧不变的字节）
-- 实验 2：同一行再按一次 A（toggle 回来），diff 应该命中同一批地址
-- 实验 3：勾满 17 行后，读出勾选存储，直接内存写全部勾选位 → 验证可免按键勾选
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_check.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/pc_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6)
  joypad.set({}); adv(gap or 60)
end

local CTX = 0x03000480
-- 扫描区：ctx 低地址界面字段 + 池 + 0x990 周边
local REGIONS = { {0x03000480, 0x500}, {0x030067C0, 0x50} }

local function state() return memory.read_u8(CTX) end
local function snap_region()
  local t = {}
  for _, r in ipairs(REGIONS) do
    for i = 0, r[2] - 1 do t[#t + 1] = memory.read_u8(r[1] + i) end
  end
  return t
end
-- 对比两个快照，返回 {偏移描述}
local function diff(s1, s2, maxn)
  local out = {}
  for i = 1, #s1 do
    if s1[i] ~= s2[i] then
      -- 换算成绝对地址
      local addr
      if i <= REGIONS[1][2] then addr = REGIONS[1][1] + i - 1
      else addr = REGIONS[2][1] + (i - REGIONS[1][2] - 1) end
      out[#out + 1] = string.format("0x%08X: %02X->%02X", addr, s1[i], s2[i])
      if #out >= (maxn or 40) then out[#out + 1] = "..."; break end
    end
  end
  return out
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 400)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/stage1_ready.State")
  adv(60)
  -- 到清单界面
  press("B", 6, 60)
  press("A", 6, 90)      -- -> state4
  w("到 state4: state=" .. state())
  press("A", 6, 120)     -- -> state6 入口框
  w("入口框: state=" .. state()); shot("entry")
  press("A", 6, 120)     -- -> 清单
  w("清单: state=" .. state()); shot("list")

  -- ===== 实验 1：按一次 A 的 diff =====
  local s1 = snap_region()
  adv(20)
  local s1b = snap_region()   -- 稳定性基线（无输入）
  press("A", 6, 30)
  adv(10)
  local s2 = snap_region()
  adv(30)
  local s3 = snap_region()    -- A 之后再无输入，稳定态
  local d12 = diff(s1b, s2, 60)
  local d23 = diff(s2, s3, 60)
  w("== A 按下瞬间 diff（过滤前 60）==")
  for _, l in ipairs(d12) do w("  " .. l) end
  w("== A 后静置 30 帧 diff（噪声参考）==")
  for _, l in ipairs(d23) do w("  " .. l) end
  shot("after1A")

  -- ===== 实验 2：同行再按一次 A（toggle 回来）=====
  local s4 = snap_region()
  press("A", 6, 30)
  adv(10)
  local s5 = snap_region()
  adv(30)
  local s6 = snap_region()
  local d45 = diff(s4, s5, 60)
  local d56 = diff(s5, s6, 60)
  w("== 第二次 A diff（toggle?）==")
  for _, l in ipairs(d45) do w("  " .. l) end
  w("== 第二次 A 后静置 diff ==")
  for _, l in ipairs(d56) do w("  " .. l) end
  shot("after2A")

  -- ===== 实验 3：Down 一次再 A（下一行勾选），确认偏移规律 =====
  press("Down", 8, 30)
  local s7 = snap_region()
  press("A", 6, 30)
  adv(10)
  local s8 = snap_region()
  w("== Down+A（第二行勾选）diff ==")
  for _, l in ipairs(diff(s7, s8, 60)) do w("  " .. l) end

  -- 池旗标现状
  local t = {}
  for i = 0, 17 do
    t[#t + 1] = memory.read_u16_le(CTX + 0x188 + i * 4) .. "/" ..
      memory.read_u8(CTX + 0x188 + i * 4 + 2) .. "/" ..
      memory.read_u8(CTX + 0x188 + i * 4 + 3)
  end
  w("pool id/lv/flag: " .. table.concat(t, " "))
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok))
if fh then fh:close() end
pcall(client.exit)
