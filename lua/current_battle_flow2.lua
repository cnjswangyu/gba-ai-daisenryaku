-- Current-game entry policy, v2 (multi-faction + city resupply aware).
-- 与 v1 的区别：开局打印所有阵营（含名称/资金/敌对关系），并把玩家阵营写进日志，
-- 战术侧用 ctx+0x990 自动识别「我方 vs 所有敌对阵营」。

-- 场景数据块（ctx+0x14）在 RAM 里的完整拷贝：
--   +0x00 标题(16B)  +0x10+i*0x18 阵营 i { 名称(16B), 类型(1=本国/2=他国), 保留, u16, 资金 }
local function current_factions()
 local p = memory.read_u32_le(CTX + 0x14)
 local out = {}
 if not (p >= 0x02000000 and p < 0x0A000000) then return out end
 local function s_at(a, n)
  local t = {}
  for i = 0, n - 1 do
   local c = r8(a + i)
   if c == 0 then break end
   t[#t + 1] = string.char(c)
  end
  return table.concat(t)
 end
 out.title = s_at(p, 16)
 for i = 0, 5 do
  local a = p + 0x10 + i * 0x18
  local nm = s_at(a, 16)
  if #nm == 0 and r8(a + 0x10) == 0 then break end
  out[#out + 1] = { index = i, name = (#nm > 0) and nm or ("国家" .. i),
   kind = r8(a + 0x10), money = memory.read_u32_le(a + 0x14) }
 end
 return out
end

local function current_log_factions()
 local pside = memory.read_u8(CTX + 0x990)
 local list = current_factions()
 log(string.format("FACTIONS title=%s player_side=%d count=%d", tostring(list.title), pside, #list))
 for _, f in ipairs(list) do
  local alive = r8(CTX + 0x24 + f.index * 0xC + 4)
  log(string.format("FACTION #%d %-8s kind=%d status=%d money=%d %s",
   f.index, f.name, f.kind, alive, f.money,
   f.index == pside and "(我方)" or (alive >= 1 and alive <= 3 and "(敌对)" or "(未参战)")))
 end
 local foe = {}
 for _, f in ipairs(list) do
  local alive = r8(CTX + 0x24 + f.index * 0xC + 4)
  if f.index ~= pside and alive >= 1 and alive <= 3 then foe[#foe + 1] = f.name end
 end
 log("FACTION 敌对阵营 = " .. table.concat(foe, ","))
end

local function current_campaign()
 local p = memory.read_u32_le(CTX + 0x14)
 assert(p >= 0x02000000 and p < 0x0A000000, "Scenario data is not loaded")
 for stage, ref in ipairs({ 0x08762B10, 0x08763E8C, 0x087652BC }) do
  local same = true
  for j = 0, 15 do if r8(p + j) ~= r8(ref + j) then same = false end end
  if same then return stage end
 end
 log(string.format("CURRENT unrecognized scenario at 0x%08X; using generic configuration", p))
 return 0 -- No scenario whitelist: unknown maps use the non-stage-1 defaults.
end

local function prepare_current_army()
 local wanted = CAMPAIGN == 1 and { [187] = 9, [241] = 4, [305] = 4, [324] = 2, [339] = 1 }
                             or { [187] = 9, [241] = 5, [305] = 2, [324] = 2, [339] = 2 }
 local old, counts, empty = {}, {}, {}
 for k = 0, 98 do
  local a = CTX + 0x188 + k * 4; local id = memory.read_u16_le(a)
  if id == 0 then empty[#empty + 1] = k else
   assert(wanted[id], "Army differs from verified plan; retained unchanged, id=" .. id)
   counts[id] = (counts[id] or 0) + 1
   old[#old + 1] = { slot = k, id = id, exp = r8(a + 2) }
  end
 end
 local additions, cost = {}, 0
 for _, id in ipairs({ 187, 241, 305, 324, 339 }) do
  assert((counts[id] or 0) <= wanted[id], "Army exceeds verified plan; retained unchanged")
  for i = 1, wanted[id] - (counts[id] or 0) do
   additions[#additions + 1] = id
   cost = cost + memory.read_u16_le(0x08798A98 + id * 0x5C + 0x1A)
  end
 end
 local money = memory.read_u32_le(CTX + 0x68)
 assert(money >= cost and #empty >= #additions, "Insufficient funds or roster space")
 for i, id in ipairs(additions) do
  local a = CTX + 0x188 + empty[i] * 4
  memory.write_u16_le(a, id); memory.write_u8(a + 2, 0); memory.write_u8(a + 3, 0)
 end
 memory.write_u32_le(CTX + 0x68, money - cost)
 local checkpoint = BASE .. "states/" .. SAVE_PREFIX .. "_army.State"
 savestate.save(checkpoint)
 local deployed = false
 for trial = 1, 2 do
  savestate.load(checkpoint); adv(15); restore_keyboard()
  tap("A", 180); if trial == 1 then tap("A", 40) end
  for i = 1, 20 do tap("A", 35); if i < 20 then tap("Down", 35) end end
  tap("Start", 90); tap("A", 120); adv(500)
  if #all_units("MY") == 20 then deployed = true; break end
 end
 assert(deployed, "Deployment not completed; checkpoint retained")
 for _, v in ipairs(old) do
  local k = r8(CTX + 0x188 + v.slot * 4 + 3) % 100 - 1
  assert(k >= 0 and k < 64, "Missing veteran association")
  local a = U - 2 + k * STRIDE
  assert(memory.read_u16_le(a) == v.id and r8(a + 5) == v.exp, "Veteran mismatch")
 end
 tap("Start", 90); tap("A", 120)
end

local function play_current(speed)
 CURRENT_SPEED=tonumber(speed) or 200
 client.unpause()
 uninstall()
 local s = r8(CTX)
 assert(s == 3 or s == 4 or s == 6 or s == 7, "Open scenario selection/details, predeployment, or battlefield first; state=" .. s)
 local token = os.date("%Y%m%d_%H%M%S")
 SAVE_PREFIX = "current_" .. token
 savestate.save(BASE .. "states/" .. SAVE_PREFIX .. "_before.State")
 local points, rank = memory.read_u32_le(CTX + 0x6C), r8(CTX + 0x65)
 client.speedmode(tonumber(speed) or 200)
 if s == 3 then
  for i = 1, 6 do tap("A", 100); if r8(CTX) == 4 then break end end
  assert(r8(CTX) == 4, "Could not open currently highlighted scenario")
 end
 CAMPAIGN = current_campaign()
 current_log_factions()
log("CURRENT tactics=campaign-v10(multi-faction) run=" .. SAVE_PREFIX .. " detected scenario=" .. CAMPAIGN .. " " .. commander())
 if r8(CTX) == 4 then tap("A", 100); assert(r8(CTX) == 6, "Could not enter deployment") end
 if r8(CTX) == 6 then
  local deployed = #all_units("MY")
  if deployed == 0 then prepare_current_army() else
   log("CURRENT using existing deployed army count=" .. deployed)
   tap("Start", 90); tap("A", 120)
  end
 end
 local ready = false
 for i = 1, 40 do
  if r8(CTX) == 7 and r8(CTX + 1) == 1 and r8(CTX + 0x21) == 3 and r8(CTX + 0x22) == 0 then ready = true; break end
  assert(r8(CTX) == 6 or r8(CTX) == 7, "Unexpected state preparing battle")
  adv(60); tap("A", 40)
 end
 assert(ready, "Player phase not ready; checkpoint retained")
 to_map(); adv(60)
 assert(memory.read_u32_le(CTX + 0x6C) == points and r8(CTX + 0x65) == rank, "Commander continuity mismatch")
 assert(#all_units("MY") > 0 and #all_units("EN") > 0, "No active battle")
 current_log_factions()
 savestate.save(BASE .. "states/" .. SAVE_PREFIX .. "_ready.State")
 return "OK " .. autoclear(speed)
end
