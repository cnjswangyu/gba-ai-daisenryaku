-- probe_check2.lua —— 验证 0x02005035 = 勾选存储（行字节），内存直写替代勾选
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_check2.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end
local CTX = 0x03000480
local U   = 0x03002BE2
local CHK  = 0x02005035
local function state() return memory.read_u8(CTX) end
local function mycount()
  local n = 0
  for k = 0, 63 do
    if memory.read_u16_le(U + k * 24 - 2) ~= 0 then n = n + 1 end
  end
  return n
end
local function chkstr(n)
  local t = {}
  for i = 0, (n or 19) do t[#t + 1] = memory.read_u8(CHK + i) end
  return table.concat(t, ",")
end
local ok, err = xpcall(function()
  pcall(client.speedmode, 400)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/stage1_ready.State"); adv(60)
  press("B", 6, 60); press("A", 6, 90); press("A", 6, 120); press("A", 6, 120)
  w("清单 state=" .. state() .. " chk[0..19]=[" .. chkstr() .. "]")
  -- 语义验证
  press("A", 6, 30)
  w("按A(行0)    chk=[" .. chkstr() .. "]")
  press("A", 6, 30)
  w("再按A(行0)  chk=[" .. chkstr() .. "]")
  press("Down", 8, 30)
  press("A", 6, 30)
  w("Down+A(行1) chk=[" .. chkstr() .. "]")
  -- ===== 内存直写全部 17 行勾选，替代按键 =====
  for i = 0, 16 do memory.write_u8(CHK + i, 1) end
  w("内存直写 chk[0..16]=1")
  -- START → 确认 → 部署
  press("Start", 6, 90)
  press("A", 6, 120)
  adv(700)
  w(string.format("直写勾选+START+A: state=%d MY=%d money=%d",
    state(), mycount(), memory.read_u32_le(CTX + 0x68)))
  if mycount() >= 16 then
    w("✔ 成功：勾选 = EWRAM 0x02005035 行字节，写 1 即勾选")
  end
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
