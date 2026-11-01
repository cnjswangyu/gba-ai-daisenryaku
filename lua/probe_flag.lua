-- probe_flag.lua —— 验证：池 flag 字节 = 部署选择，内存直写可替代全部勾选按键
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_flag.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end
local CTX = 0x03000480
local U   = 0x03002BE2
local function state() return memory.read_u8(CTX) end
local function mycount()
  local n = 0
  for k = 0, 63 do
    if memory.read_u16_le(U + k * 24 - 2) ~= 0 then n = n + 1 end
  end
  return n
end
local function pool_flags()
  local t = {}
  for i = 0, 17 do
    if memory.read_u16_le(CTX + 0x188 + i * 4) ~= 0 then
      t[#t + 1] = memory.read_u8(CTX + 0x188 + i * 4 + 3)
    end
  end
  return table.concat(t, ",")
end
local MYARMY = { {187,6}, {241,2}, {208,2}, {305,4}, {324,2}, {339,1} }
local function write_pool_with_flags()
  for i = 0, 98 do
    local b = CTX + 0x188 + i * 4
    memory.write_u8(b, 0); memory.write_u8(b + 1, 0)
    memory.write_u8(b + 2, 0); memory.write_u8(b + 3, 0)
  end
  local slot = 0
  for _, e in ipairs(MYARMY) do
    for _ = 1, e[2] do
      memory.write_u16_le(CTX + 0x188 + slot * 4, e[1])
      memory.write_u8(CTX + 0x188 + slot * 4 + 3, slot + 1)  -- flag = 部署序号
      slot = slot + 1
    end
  end
  return slot
end
local ok, err = xpcall(function()
  pcall(client.speedmode, 800)
  pcall(client.setsoundon, false)
  adv(30)
  -- V6: flag 直写 + 入口界面直接 START→A（最短路径）
  savestate.load(BASE .. "states/stage1_ready.State"); adv(60)
  local n = write_pool_with_flags()
  w("V6 池+flag直写(" .. n .. " units, flags=" .. pool_flags() .. ")")
  press("Start", 6, 90)
  press("A", 6, 120)
  adv(700)
  local my = mycount()
  w(string.format("V6 入口直START: state=%d MY=%d flags=[%s] money=%d",
    state(), my, pool_flags(), memory.read_u32_le(CTX + 0x68)))
  if my >= 15 then
    w("V6 成功！内存写 flag 即完成勾选，只需 START+A 两键触发出击")
  end
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
