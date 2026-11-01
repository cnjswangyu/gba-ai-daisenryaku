-- rearm.lua —— 字段级复刻 FUN_08003568：在已部署存档上直接换装
-- 3×74式MBT(200) → M1A2(187)，模板 = battle_usa_live 原生放置记录（x/y 保留原位）
-- 轻步兵 305×4、FH70 239×2、補給車 344 保留
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/rearm.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/rm_" .. n .. ".png") end

local CTX = 0x03000480
local U   = 0x03002BE2
-- M1A2 模板（battle_usa_live 原生记录；下标 3,4 = x,y 运行时填）
local T187 = {0xBB,0x00,0x00,0x00,0x32,0x00,0x10,0x00,0x04,0x04,0x00,0x00,
              0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}

local function state() return memory.read_u8(CTX) end
local function dump_my(tag)
  local lines = {}
  for k = 0, 63 do
    local b = U + k * 24 - 2
    local id = memory.read_u16_le(b)
    if id ~= 0 then
      lines[#lines + 1] = string.format("U%02d id=%-3d (%2d,%2d) fuel=%d LV=%d HP=%d st=%d ammo=%d,%d,%d,%d",
        k, id, memory.read_u8(b + 2), memory.read_u8(b + 3),
        memory.read_u8(b + 4), memory.read_u8(b + 5), memory.read_u8(b + 6),
        memory.read_u8(b + 7), memory.read_u8(b + 8), memory.read_u8(b + 9),
        memory.read_u8(b + 10), memory.read_u8(b + 11))
    end
  end
  w("--- " .. tag .. " ---")
  for _, l in ipairs(lines) do w(l) end
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, false)
  adv(30)
  savestate.load(BASE .. "states/stage1_ready2.State")
  adv(60)
  w(string.format("载入: state=%d sub=%d ph=%d side=%d", state(),
    memory.read_u8(CTX + 1), memory.read_u8(CTX + 0x21), memory.read_u8(CTX + 0x22)))
  dump_my("换装前")

  -- 找 200 槽位并换装
  local n = 0
  for k = 0, 63 do
    local b = U + k * 24 - 2
    if memory.read_u16_le(b) == 200 then
      local x, y = memory.read_u8(b + 2), memory.read_u8(b + 3)
      for i = 0, 23 do
        local v = T187[i + 1]
        if i == 2 then v = x end
        if i == 3 then v = y end
        memory.write_u8(b + i, v)
      end
      n = n + 1
      w(string.format("槽 %d: 200 -> 187 @ (%d,%d)", k, x, y))
    end
  end
  w("共换装 " .. n .. " 个单位")
  adv(30)
  -- 读回校验（防止被游戏按帧回写）
  local bad = 0
  for k = 0, 63 do
    local b = U + k * 24 - 2
    if memory.read_u16_le(b) == 200 then bad = bad + 1 end
  end
  w("30 帧后仍为 200 的槽数: " .. bad .. "（0 = 换装稳定）")
  dump_my("换装后")
  shot("after_rearm")
  memory.write_u8(CTX + 0xC55, 0)  -- 关完整战斗演出
  savestate.save(BASE .. "states/stage1_rearmed.State")
  w("已存 states/stage1_rearmed.State")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
