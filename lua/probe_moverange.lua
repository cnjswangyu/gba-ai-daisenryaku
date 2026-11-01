-- probe_moverange.lua —— 移动范围逆向探针
-- 1) 读 ROM 字面量：移耗表 A/B 指针、可达位图基址
-- 2) 进寻路态（选中 U0 → A×3），dump 游戏算的 48 宽可达位图（FUN_08002468 公式）
-- 3) dump 移耗表内容 + 各兵种移耗类别
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_moverange.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/mr_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end
local CTX = 0x03000480
local DBA = 0x08798AF4   -- 单位库真基址（entry(n)=DBA+(n-1)*0x5C）
local function r8(a) return memory.read_u8(a) end
local function state() return r8(CTX) end
local function cur() return r8(0x030067FE), r8(0x030067FF) end

local ok, err = xpcall(function()
  pcall(client.speedmode, 400)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
  w(string.format("载入 state=%d sub=%d ph=%d side=%d", state(), r8(CTX+1), r8(CTX+0x21), r8(CTX+0x22)))

  -- ROM 字面量指针
  local pTblA = memory.read_u32_le(0x080029b8)
  local pTblB = memory.read_u32_le(0x0800299c)
  local pBmp  = memory.read_u32_le(0x08002488)
  local oBmp  = memory.read_u32_le(0x0800248c)
  w(string.format("移耗表A=0x%08X  特殊组表B=0x%08X  位图基址=0x%08X 偏移=0x%X", pTblA, pTblB, pBmp, oBmp))

  -- 各兵种移耗类别（db+5）与属性
  for _, id in ipairs({187, 241, 305, 324, 339, 188, 301, 224, 235}) do
    local e = DBA + (id-1)*0x5C
    w(string.format("id%d: 移耗类别(+5)=%d 属性 +0..7= %02X %02X %02X %02X %02X %02X %02X %02X",
      id, r8(e+5), r8(e), r8(e+1), r8(e+2), r8(e+3), r8(e+4), r8(e+5), r8(e+6), r8(e+7)))
  end

  -- 进寻路态：A 选中 → A 菜单 → A 移動
  local cx, cy = cur()
  w(string.format("光标 (%d,%d) —— 应在 U0 M1A2 上", cx, cy))
  press("A", 6, 60);  shot("sel1")
  w(string.format("选中后 state=%d sub=%d ph=%d", state(), r8(CTX+1), r8(CTX+0x21)))
  press("A", 6, 60);  shot("menu2")
  press("A", 6, 90);  shot("path3")
  w(string.format("寻路态 state=%d sub=%d ph=%d cur=(%d,%d)", state(), r8(CTX+1), r8(CTX+0x21), cur()))

  -- dump 可达位图（FUN_08002468: byte @ pBmp+oBmp+x+y*0x30 & 2）
  local base = pBmp + oBmp
  local rows = {}
  local cnt = 0
  for y = 0, 35 do
    local row = {}
    for x = 0, 47 do
      local b = r8(base + x + y * 0x30)
      local v = (b % 4 >= 2) and 1 or 0   -- bit1
      row[#row+1] = tostring(v)
      cnt = cnt + v
    end
    rows[#rows+1] = table.concat(row)
  end
  w("可达位图 bit1 计数 = " .. cnt)
  for y, row in ipairs(rows) do w(string.format("y%02d %s", y-1, row)) end
  -- 原始字节前几行（备查其他 bit 含义）
  for y = 0, 3 do
    local t = {}
    for x = 0, 47 do t[#t+1] = string.format("%02X", r8(base + x + y*0x30)) end
    w(string.format("raw y%02d %s", y, table.concat(t, " ")))
  end
  savestate.save(BASE .. "states/moverange_path.State")
  w("已存寻路态存档 moverange_path.State")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
