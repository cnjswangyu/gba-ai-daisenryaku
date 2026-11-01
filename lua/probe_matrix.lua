-- probe_matrix.lua —— 分离「勾选」与「池内容」对部署的影响
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe_matrix.txt"
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
    local b = U + k * 24 - 2
    if memory.read_u16_le(b) ~= 0 then n = n + 1 end
  end
  return n
end
local function pool_str()
  local t = {}
  for i = 0, 17 do
    local v = memory.read_u16_le(CTX + 0x188 + i * 4)
    if v ~= 0 then t[#t + 1] = string.format("%03X/%02X/%02X", v,
      memory.read_u8(CTX + 0x188 + i * 4 + 2), memory.read_u8(CTX + 0x188 + i * 4 + 3)) end
  end
  return table.concat(t, " ")
end

-- 写池
local function write_pool(list)
  for i = 0, 98 do
    local b = CTX + 0x188 + i * 4
    memory.write_u8(b, 0); memory.write_u8(b + 1, 0)
    memory.write_u8(b + 2, 0); memory.write_u8(b + 3, 0)
  end
  local slot = 0
  for _, e in ipairs(list) do
    for _ = 1, e[2] do
      memory.write_u16_le(CTX + 0x188 + slot * 4, e[1])
      slot = slot + 1
    end
  end
  return slot
end

-- path B：B→A→(state4)→A→(入口框)→A→(清单)→[checks]→START→A(确认)
local function deploy_via_list(checks)
  press("B", 6, 60); press("A", 6, 90)         -- -> state4
  press("A", 6, 120)                            -- -> 入口框
  press("A", 6, 120)                            -- -> 清单
  if checks then
    local n = 0
    for i = 0, 98 do if memory.read_u16_le(CTX + 0x188 + i * 4) ~= 0 then n = n + 1 end end
    for i = 1, n do
      press("A", 6, 55)
      if i < n then press("Down", 6, 55) end
    end
  end
  press("Start", 6, 90)
  press("A", 6, 120)                            -- 确认部署
  adv(600)
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 800)
  pcall(client.setsoundon, false)
  adv(30)
  local MYARMY = { {187,6}, {241,2}, {208,2}, {305,4}, {324,2}, {339,1} }
  local DEFARMY = { {200,3}, {239,2}, {305,4}, {344,1} }

  -- V1: 我的池 + 勾选
  savestate.load(BASE .. "states/stage1_ready.State"); adv(60)
  write_pool(MYARMY)
  deploy_via_list(true)
  w(string.format("V1 我的池+勾选: state=%d MY=%d money=%d pool=[%s]",
    state(), mycount(), memory.read_u32_le(CTX + 0x68), pool_str()))

  -- V2: 我的池 + 不勾选
  savestate.load(BASE .. "states/stage1_ready.State"); adv(60)
  write_pool(MYARMY)
  deploy_via_list(false)
  w(string.format("V2 我的池+不勾: state=%d MY=%d money=%d pool=[%s]",
    state(), mycount(), memory.read_u32_le(CTX + 0x68), pool_str()))

  -- V4: 默认池 + 不勾选
  savestate.load(BASE .. "states/stage1_ready.State"); adv(60)
  write_pool(DEFARMY)
  deploy_via_list(false)
  w(string.format("V4 默认池+不勾: state=%d MY=%d money=%d pool=[%s]",
    state(), mycount(), memory.read_u32_le(CTX + 0x68), pool_str()))
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
