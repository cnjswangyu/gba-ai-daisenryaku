-- current_tactics2.lua —— 接管当前战局的 v2 战术（多阵营 + 城市补给）
--
-- 逆向依据（2026-10-18 实测/反编译）：
--  * 势力数上限 4。单位为 ctx+0x2760+side*0x600，stride 0x18。
--  * 阵营记录 ctx+0x24+side*0xC：+0 资金(u32)，+4 状态（1..3=参战，FUN_080023c4）。
--  * 玩家阵营 = ctx+0x990；格表 +0 = 阵营+1。
--  * 战斗结算 FUN_08023188(我方阵营, 槽, 武器, 敌方阵营, 敌槽, 反击武器) —— 目标阵营是明文参数，
--    旧桥把它写死成 1，所以只认一个敌人。
--  * **城市补给**：势力回合开始时，站在「地形 ∈ {0x10 首都, 0x11 市街, 0x14 村落} 且归属=自己」
--    的单位 HP/燃料/弹药 全部补满（25 种建筑矩阵实测）。
local cs_player = player_side()
local cs_owner = cs_player + 1
local CS_SUPPLY = { [0x10] = true, [0x11] = true, [0x14] = true }

local function cs_side_of_unit(u) return u.side or cs_player end
local function cs_is_foe_side(s) return s ~= cs_player and side_alive(s) end
local function cs_supply_cell(x, y)
 return CS_SUPPLY[terrain_at(x, y)] and r8(tb() + x * 4 + y * 0xC0 + 2) == cs_owner
end
local function cs_ammo_total(k)
 local n = 0
 for wa = 0, 3 do n = n + r8(U + k * STRIDE - 2 + 8 + wa) end
 return n
end
local function cs_armed(u)
 -- 还有弹药（任一武器槽 > 0）就能开火
 for wa = 0, 3 do
  if r8(U + u.idx * STRIDE - 2 + 8 + wa) > 0 then return true end
 end
 return false
end
local function cs_needs_supply(u)
 if u.maxhp > 0 and u.hp <= u.maxhp * 0.7 then return true end
 if u.fuel <= 12 then return true end
 if not cs_armed(u) then return true end
 return false
end

local current_orders, current_previous_en, current_capture_jobs = {}, {}, {}
local current_routes, current_my_cities, current_my_capital = {}, {}, nil
local current_foes = {}
local cs_campaign={objective=nil,primary=nil,turn=-1}
local function cs_attack_priority(e)
 local value=cs_campaign.primary==e.side*64+e.idx and 80 or 0
 local goal=cs_campaign.objective
 if goal and hexd(e.x,e.y,goal.x,goal.y)<=6 then value=value+40 end
 return value
end

local function cs_friendly_city(x, y)
 return cs_supply_cell(x, y)
end
local function cs_danger(u, x, y, en)
 local risk = 0
 for _, e in ipairs(en) do
  local d = hexd(x, y, e.x, e.y)
  -- 保守估计：敌方整条移动力预算 + 武器射程
  local mv = r8(0x08798A98 + e.id * 0x5C + 0x0D)
  local power = enemy_counter(e, u.id, math.max(1, d - math.min(mv, e.fuel or 0)))
  if power > 0 then
   local hit = estimate(e, u, power, x, y)
   risk = risk + hit * (enemy_counter(e, u.id, d) > 0 and 1 or 0.4)
  end
 end
 return risk
end
-- 我方最靠近的家（首都优先）：取代旧代码里写死的 (21,30)
local function cs_home_distance(x, y)
 if current_my_capital then return hexd(x, y, current_my_capital.x, current_my_capital.y) end
 local best = 99
 for _, c in ipairs(current_my_cities) do best = math.min(best, hexd(x, y, c.x, c.y)) end
 return best
end
local function cs_guard(u, en)
 return terrain_at(u.x, u.y) == 0x10 and r8(tb() + u.x * 4 + u.y * 0xC0 + 2) == cs_owner
end
local function cs_near_supply(k, u, reach)
 -- 本回合结束时能否站在自家补给点上（含原地）
 if cs_supply_cell(u.x, u.y) then return true end
 for key in pairs(reach) do
  local x, y = key:match("(%-?%d+),(%-?%d+)")
  x, y = tonumber(x), tonumber(y)
  if x and cs_supply_cell(x, y) then return true end
 end
 return false
end
local function cs_hold(u, en)
 -- 首都守卫永不擅自离岗
 if cs_guard(u, en) then return true, "capital_garrison" end
 if current_orders[u.idx] and (current_orders[u.idx].kind == "intercept" or current_orders[u.idx].kind == "escort") then return false end
 local on_supply = cs_supply_cell(u.x, u.y)
 if on_supply then
  local risk = cs_danger(u, u.x, u.y, en)
  if risk >= u.hp * 0.9 then return false end
  -- 站在自家补给点上且需要补给 → 原地待机，下回合补满
  if cs_needs_supply(u) then return true, "resupply_in_city" end
 end
 if not on_supply then return false end
 if cs_clock.urgency>=1 then return false end -- Release healthy forward units as time runs out.
 for _, e in ipairs(en) do
  local d = hexd(u.x, u.y, e.x, e.y)
  if d <= 6 and (enemy_counter(e, u.id, 1) > 0 or my_best(u, d, e.id) > 0) then
   return true, "hold_frontline_city"
  end
 end
 return false
end
local function cs_hold_action(k, u, en, reason)
 local target, score = nil, -1e9
 for _, e in ipairs(en) do
  local d = hexd(u.x, u.y, e.x, e.y)
  local hit = estimate(u, e, my_best(u, d, e.id))
  local loss = estimate(e, u, enemy_counter(e, u.id, d), u.x, u.y)
  if hit > 0 and loss < u.hp * 0.6 then
   local value = math.min(hit, e.hp) * 16 - loss * 20 + (hit >= e.hp and 180 or 0)
   if value > score then target, score = e, value end
  end
 end
 if target then
  local ok, msg = pcall(attack, k, target)
  log(string.format("HOLD U%d %s attack=E%d(side%d) %s %s", k, reason, target.idx, target.side,
   tostring(ok), tostring(msg)))
  if r8(CTX) == 8 or #all_units("EN") == 0 then return end
 end
 markacted(k)
 log(string.format("HOLD U%d %s hp=%d/%d fuel=%d at=%d,%d", k, reason, u.hp, u.maxhp, u.fuel, u.x, u.y))
end

local function current_begin_round()
 current_orders={}
 current_routes, current_my_cities = {}, {}
 current_my_capital = nil
 for y = 1, 46 do
  for x = 1, 46 do
   if cs_supply_cell(x, y) then
    current_my_cities[#current_my_cities + 1] = { x = x, y = y, capital = terrain_at(x, y) == 0x10 }
    if terrain_at(x, y) == 0x10 and not current_my_capital then
     current_my_capital = { x = x, y = y }
    end
   end
  end
 end
 current_foes = {}
 for s = 0, 3 do
  if cs_is_foe_side(s) then current_foes[#current_foes + 1] = s end
 end
 log(string.format("SIDES player=%d foes=[%s] my_supply_cities=%d", cs_player,
  table.concat(current_foes, ","), #current_my_cities))
end
local function current_route(goal, pref, cat)
 local key = goal.x .. "," .. goal.y .. "," .. pref .. "," .. cat
 if not current_routes[key] then current_routes[key] = route_field(goal, pref, cat) end
 return current_routes[key]
end

-- 守住自家补给城市（首都优先）；被威胁的城市再加一个预备队
local function current_defend_capitals()
 local en = all_units("EN")
 local assigned = {}
 local assigned_count,defense_budget=0,math.max(1,math.floor(#all_units("MY")*0.2))
 local queue = {}
 for _, c in ipairs(current_my_cities) do
  if c.capital then queue[#queue + 1] = c end
 end
 for _, c in ipairs(current_my_cities) do
  if not c.capital then queue[#queue + 1] = c end
 end
 for _, capital in ipairs(queue) do
  local threatened = false
  for _, e in ipairs(en) do
   local speed = math.min(r8(0x08798A98 + e.id * 0x5C + 0x0D), e.fuel or 0)
   local reach = capital.capital and math.max(10, speed + 3) or math.max(4, speed)
   if hexd(e.x, e.y, capital.x, capital.y) <= reach then threatened = true; break end
  end
  local occupied = r8(CTX + 0x3F60 + capital.x * 4 + capital.y * 0xC0) == cs_owner
  -- A permanent capital guard stays; safe cities do not each immobilize extra squads.
  local roles={}
  if capital.capital and not occupied then roles[#roles+1]=0 end
  if threatened and cs_clock.urgency<2 then roles[#roles+1]=1 end
  for _, pref in ipairs(roles) do
   if pref>0 and assigned_count>=defense_budget then break end
   local chosen, best = nil, 1e30
   for _, u in ipairs(all_units("MY")) do
    local grid = CTX + 0x3F60 + u.x * 4 + u.y * 0xC0
    if not u.acted and u.hp > 0 and not assigned[u.idx] and not cs_guard(u, en)
        and not (u.id >= 339 and u.id <= 345) and r8(grid) == cs_owner and r8(grid + 1) == u.idx + 1 then
     local _, cat, budget = vm_ctx(u.idx)
     local routes = current_route(capital, pref, cat)
     local distance = routes[u.x .. "," .. u.y]
     if distance and (distance == 0 or budget > 0) then
      local ratio = u.hp / math.max(1, u.maxhp)
      local armed = cs_armed(u)
      local score = distance * 10 + (1 - ratio) * 30 + (armed and 0 or 100) + (is_capturer(u.id) and 150 or 0)
      if score < best then chosen, best = u, score end
     end
    end
   end
   if chosen then
    assigned[chosen.idx] = true
    assigned_count=assigned_count+1
    local _, cat, budget = vm_ctx(chosen.idx)
    local reach = vm_reach(chosen, cat, budget)
    local routes = current_route(capital, pref, cat)
    local bx, by, bs = chosen.x, chosen.y, -1e30
    for key, cost in pairs(reach) do
     local x, y = key:match("(%d+),(%d+)"); x, y = tonumber(x), tonumber(y)
     if routes[key] and ((x == chosen.x and y == chosen.y) or r8(CTX + 0x3F60 + x * 4 + y * 0xC0) == 0) then
      local score = -routes[key] * 100 - cs_danger(chosen, x, y, en) * 4 - cost
      if routes[key] == 0 then score = score + 1000 end
      if cs_supply_cell(x, y) then score = score + 120 end
      if score > bs then bx, by, bs = x, y, score end
     end
    end
    local ok, msg = true, "hold"
    local moved = bx ~= chosen.x or by ~= chosen.y
    if moved then ok, msg = pcall(vm_land, chosen.idx, chosen, bx, by, reach[bx .. "," .. by]) end
    if ok then
     if not moved then cs_hold_action(chosen.idx, chosen, en, "capital_reserve")
     else markacted(chosen.idx) end
    end
    log(string.format("DEFEND city=%d,%d U%d role=%s destination=%d,%d ok=%s %s",
     capital.x, capital.y, chosen.idx, pref == 0 and "garrison" or "reserve", bx, by, tostring(ok), tostring(msg)))
    if r8(CTX) == 8 or #all_units("EN") == 0 then return end
   else
    log(string.format("DEFEND WARNING city=%d,%d no available %s", capital.x, capital.y,
     pref == 0 and "garrison" or "reserve"))
   end
  end
 end
end

local function current_advance(k, u, reach, cat, en)
 local risks = {}
 local function risk_at(x, y)
  local key = x .. "," .. y
  if risks[key] == nil then risks[key] = cs_danger(u, x, y, en) end
  return risks[key]
 end
 local capturer = is_capturer(u.id)
 local needy = cs_needs_supply(u)
 local start_risk = risk_at(u.x, u.y)
 local retreat = start_risk >= u.hp * 0.9
 local goals = {}
 -- 目标一：自家补给城市（缺编/LV低时优先回去补）
 for _, c in ipairs(current_my_cities) do
  local occ = r8(CTX + 0x3F60 + c.x * 4 + c.y * 0xC0)
  if needy and (occ == 0 or (c.x == u.x and c.y == u.y)) then
   local risk = risk_at(c.x, c.y)
   if risk < u.hp * 0.8 or (c.x == u.x and c.y == u.y) then
    local value = hexd(u.x, u.y, c.x, c.y) + (risk / math.max(1, u.hp)) * 8
    if c.capital then value = value - 4 end
    goals[#goals + 1] = { x = c.x, y = c.y, pref = 0, value = value,
     kind = needy and "resupply" or "defend_city" }
   end
  end
 end
 -- 目标二：可占领的敌/中立建筑（能占领到的补给地形价值最高：占下来就是补给站）
 for y = 1, 46 do
  for x = 1, 46 do
   if on_building(x, y) then
    local owner = r8(tb() + x * 4 + y * 0xC0 + 2)
    local occ = r8(CTX + 0x3F60 + x * 4 + y * 0xC0)
    if capturer and (occ == 0 or (x == u.x and y == u.y)) and owner ~= cs_owner and not needy then
     local risk = risk_at(x, y)
     if risk < u.hp * 0.7 then
      local value = hexd(u.x, u.y, x, y) + (risk / math.max(1, u.hp)) * 8
      local terr = terrain_at(x, y)
      if CS_SUPPLY[terr] then value = value - 14 end     -- 补给建筑优先占
      if terr == 0x10 then value = value - 2 end          -- 敌首都（胜利条件）
      goals[#goals + 1] = { x = x, y = y, pref = 0, value = value, kind = "capture" }
     end
    end
   end
  end
 end
 if needy or retreat then
  local supply = {}
  for _, goal in ipairs(goals) do
   if goal.kind == "resupply" then supply[#supply + 1] = goal end
  end
  if #supply > 0 then goals = supply end
 end
 -- 目标三：向我方能打的敌人靠拢（多阵营一起考虑）
 if not needy and not retreat then
  for _, e in ipairs(en) do
   local pref, armed = 1, false
   for d = 3, 1, -1 do if my_best(u, d, e.id) > 0 then pref, armed = d, true; break end end
   if armed or not capturer then
    goals[#goals + 1] = { x = e.x, y = e.y, pref = armed and pref or 4,
     value = hexd(u.x, u.y, e.x, e.y) + (armed and 8 or 18), kind = armed and "engage" or "support" }
   end
  end
 end
 local order = current_orders[k]
 if order and (not needy and not retreat or order.kind == "intercept") then goals = { order } end
 table.sort(goals, function(a, b) return a.value < b.value end)
 local bx, by, best, bwhy = nil, nil, -1e30, "no_route"
 local cells = {}
 for key, cost in pairs(reach) do cells[key] = cost end
 cells[u.x .. "," .. u.y] = 0
 local reachable_goals = 0
 for i = 1, #goals do
  local goal = goals[i]; local routes = current_route(goal, goal.pref, cat)
  local initial = routes[u.x .. "," .. u.y]
  if initial and initial<=u.fuel then
   reachable_goals = reachable_goals + 1
   for key, cost in pairs(cells) do
    local x, y = key:match("(%d+),(%d+)"); x, y = tonumber(x), tonumber(y)
    local remaining = routes[key]
    local same = x == u.x and y == u.y
    if remaining and (same or r8(CTX + 0x3F60 + x * 4 + y * 0xC0) == 0) then
     local risk = risk_at(x, y)
     if risk < u.hp * 0.9 or risk < start_risk * 0.7 then
      local offensive=goal.kind=="engage" or goal.kind=="intercept"
      local score = (initial - remaining) * (offensive and 65 or 35) - goal.value * 8 - risk * 18 + tdef(terrain_at(x, y)) - cost * 0.2
      local time_cost,feasible=cs_time_cost(goal,remaining,r8(0x08798A98+u.id*0x5C+0x0D),same)
      score=score+time_cost
      if not feasible then score=-1e30 end
      if cs_supply_cell(x, y) then
       -- 结束在自家补给点上：下一回合 HP/燃料/弹药全补满
       score = score + (needy and 260 or 45)
      end
      if not same and cs_supply_cell(u.x, u.y) and not needy then score = score - 25 end
      if remaining == 0 and goal.kind == "capture" then score = score + 160 end
      if remaining == 0 and goal.kind == "resupply" then score = score + 200 end
      if remaining == 0 and goal.kind == "defend_city" then score = score + 120 end
      if not capturer and on_building(x,y) and r8(tb()+x*4+y*0xC0+2)~=cs_owner then score=score-400 end
      if score > best then bx, by, best, bwhy = x, y, score, goal.kind end
     end
    end
   end
  end
  if reachable_goals >= 8 then break end
 end
 if not bx then
  for key, cost in pairs(cells) do
   local x, y = key:match("(%d+),(%d+)"); x, y = tonumber(x), tonumber(y)
   if (x == u.x and y == u.y) or r8(CTX + 0x3F60 + x * 4 + y * 0xC0) == 0 then
    local score = -risk_at(x, y) * 18 + tdef(terrain_at(x, y)) - cost
    if cs_supply_cell(x, y) then score = score + 80 end
    if not capturer and on_building(x,y) and r8(tb()+x*4+y*0xC0+2)~=cs_owner then score=score-400 end
    if score > best then bx, by, best, bwhy = x, y, score, "cover" end
   end
  end
 end
 local moved = bx and (bx ~= u.x or by ~= u.y)
 if moved then
  local ok, msg = pcall(vm_land, k, u, bx, by, cells[bx .. "," .. by])
  log(string.format("ADVANCE U%d %s %d,%d->%d,%d ok=%s %s", k, bwhy, u.x, u.y, bx, by, tostring(ok), tostring(msg)))
  if not ok then return end
 end
 local now = unit("MY", k)
 if now and capturer and on_building(now.x, now.y) and r8(tb() + now.x * 4 + now.y * 0xC0 + 2) ~= cs_owner then
  local ok, msg = pcall(cap, k)
  log(string.format("CAPTURE U%d ok=%s %s", k, tostring(ok), tostring(msg)))
 elseif not moved then
  local count = 0; for _ in pairs(reach) do count = count + 1 end
  local why = u.fuel == 0 and "no_fuel" or (count <= 1 and "no_reachable_cell" or bwhy)
  log(string.format("WAIT U%d %s hp=%d/%d fuel=%d reachable_cells=%d", k, why, u.hp, u.maxhp, u.fuel, count))
 end
end

-- 灭国判定：多阵营地图上「灭掉某一方」会让游戏进灭国演出，原生战斗调用再也回不来
-- （实测 1800/6000 帧都不返回，PC 停在 0x080006C2，游戏被卡死）。
-- 所以：只要还有别的敌对阵营活着，就不打「某方的最后一个单位」—— 改为先削其他阵营、
-- 并去占它的首都（场景胜利条件）。单一阵营（other==0）时最后一击 = 正常胜利路径。
local function cs_eliminates_faction(e, en)
 local same, other = 0, 0
 for _, o in ipairs(en) do
  if o.hp > 0 then
   if o.side == e.side then same = same + 1 else other = other + 1 end
  end
 end
 return same <= 1 and other >= 1
end
local function cs_transition_blocks_cell(x,y)
 -- User handles elimination dialogs manually; they must not exclude a target.
 return false
end

-- 追击/护卫任务时过滤攻击目标；多阵营下按 (side,slot) 唯一键
local function current_attack_targets(u, en)
 local function usable(list)
  local out = {}
  for _, e in ipairs(list) do
   if e.hp > 0 then out[#out + 1] = e end
  end
  return out
 end
 local order = current_orders[u.idx]
 if order and order.kind == "intercept" then
  local targets = usable(en)
  -- Orders guide movement, but never hide a nearby attack opportunity.
  return targets
 end
 if order and order.kind == "escort" then
  local foot = unit("MY", order.subject)
  local picked = {}
  for _, e in ipairs(usable(en)) do
   if hexd(e.x,e.y,u.x,u.y)<=3 or hexd(e.x, e.y, order.x, order.y) <= 6 or (foot and hexd(e.x, e.y, foot.x, foot.y) <= 6) then
    picked[#picked + 1] = e
   end
  end
  return picked
 end
 return usable(en)
end

local function current_plan_round()
 current_orders = {}
 local en, my = all_units("EN"), all_units("MY")
 local threats = {}
 for _, e in ipairs(en) do
  local closest = 1e9
  if current_my_capital then closest = hexd(e.x, e.y, current_my_capital.x, current_my_capital.y) end
  for _, c in ipairs(current_my_cities) do closest = math.min(closest, hexd(e.x, e.y, c.x, c.y)) end
  local old = current_previous_en[e.side * 64 + e.idx]
  local closing = old and closest < old.distance
  if closest <= 18 or (closing and closest <= 24) then
   threats[#threats + 1] = { unit = e, priority = closest - (is_capturer(e.id) and 6 or 0) - (closing and 3 or 0) }
  end
 end
 table.sort(threats, function(a, b) return a.priority < b.priority end)
 local allocated, limit = 0, math.max(1, math.floor(#my * (cs_clock.urgency>=1 and 0.15 or 0.25)))
 for _, threat in ipairs(threats) do
  local e = threat.unit
  for role = 1, 2 do
   if allocated >= limit then break end
   local selected, score = nil, 1e30
   for _, u in ipairs(my) do
    if not u.acted and u.hp > 0 and not current_orders[u.idx] and not cs_guard(u, en)
        and not is_capturer(u.id) and not (u.id >= 339 and u.id <= 345) then
     local pref = nil
     for d = 3, 1, -1 do if my_best(u, d, e.id) > 0 then pref = d; break end end
     if pref then
      local _, cat, budget = vm_ctx(u.idx)
      local distance = current_route(e, pref, cat)[u.x .. "," .. u.y]
      if distance and (distance == 0 or budget > 0) then
       local value = distance + (1 - u.hp / math.max(1, u.maxhp)) * 15
       if cs_needs_supply(u) then value = value + 20 end   -- 缺编的先去补给，不接活
       if value < score then selected, score = { u = u, pref = pref }, value end
      end
     end
    end
   end
   if selected then
    local u = selected.u
    current_orders[u.idx] = { x = e.x, y = e.y, pref = selected.pref, value = -100,
     kind = "intercept", foe_side = e.side, foe_slot = e.idx }
    allocated = allocated + 1
    log(string.format("ORDER U%d intercept E%d(side%d) at=%d,%d", u.idx, e.idx, e.side, e.x, e.y))
   end
  end
 end
 -- 步兵专职任务：优先抢补给建筑（占下来就是自家补给站）
 local claimed = {}
 for _, u in ipairs(my) do
  if not u.acted and u.hp > 0 and is_capturer(u.id) and not cs_guard(u, en) then
   local _, cat = vm_ctx(u.idx)
   local chosen, score = nil, 1e30
   for y = 1, 46 do
    for x = 1, 46 do
     if on_building(x, y) and r8(tb() + x * 4 + y * 0xC0 + 2) ~= cs_owner and not claimed[x .. "," .. y] and not cs_transition_blocks_cell(x,y) then
      local pref = r8(CTX + 0x3F60 + x * 4 + y * 0xC0) > 1 and 1 or 0
      local distance = current_route({ x = x, y = y }, pref, cat)[u.x .. "," .. u.y]
      if distance then
       local risk = cs_danger(u, x, y, en)
       local terr = terrain_at(x, y)
       local value = distance + risk * 2
       if CS_SUPPLY[terr] then value = value - 22 end     -- 补给地形价值极高
       if terr == 0x10 then value = value - 10 end
       local old = current_capture_jobs[u.idx]
       if old and old.x == x and old.y == y then value = value - 12 end
       if value < score then chosen, score = { x = x, y = y, pref = pref, value = -30, kind = "capture" }, value end
      end
     end
    end
   end
   if chosen then
    current_orders[u.idx] = chosen; current_capture_jobs[u.idx] = chosen; claimed[chosen.x .. "," .. chosen.y] = true
    log(string.format("ORDER U%d capture target=%d,%d staging=%d terr=0x%02X",
     u.idx, chosen.x, chosen.y, chosen.pref, terrain_at(chosen.x, chosen.y)))
    local escort, best = nil, 1e30
    for _, candidate in ipairs(my) do
     if not candidate.acted and candidate.hp > 0 and not current_orders[candidate.idx]
         and not cs_guard(candidate, en) and not is_capturer(candidate.id)
         and not (candidate.id >= 339 and candidate.id <= 345) then
      local armed = false
      for _, e in ipairs(en) do if my_best(candidate, 1, e.id) > 0 then armed = true; break end end
      if armed then
       local value = hexd(u.x, u.y, candidate.x, candidate.y) + (1 - candidate.hp / math.max(1, candidate.maxhp)) * 10
       if value < best then escort, best = candidate, value end
      end
     end
    end
    if escort then
     current_orders[escort.idx] = { x = chosen.x, y = chosen.y, pref = 1, value = -25, kind = "escort", subject = u.idx }
     log(string.format("ORDER U%d escort U%d target=%d,%d", escort.idx, u.idx, chosen.x, chosen.y))
    end
   else
    log("ORDER U" .. u.idx .. " capture no reachable city")
   end
  end
 end
 current_previous_en = {}
 for _, e in ipairs(en) do
  local distance = 1e9
  if current_my_capital then distance = hexd(e.x, e.y, current_my_capital.x, current_my_capital.y) end
  for _, c in ipairs(current_my_cities) do distance = math.min(distance, hexd(e.x, e.y, c.x, c.y)) end
  current_previous_en[e.side * 64 + e.idx] = { x = e.x, y = e.y, distance = distance }
 end
end

local function cs_deadline_orders()
 if cs_clock.urgency<1 and cs_clock.stalled<3 then return end
 for _,u in ipairs(all_units("MY")) do
  if not u.acted and is_capturer(u.id) and not cs_guard(u,{}) and not cs_needs_supply(u) then
   local _,cat=vm_ctx(u.idx)
   local chosen,best=nil,1e30
   for _,capital in ipairs(enemy_capitals()) do
    local transition_blocked=cs_transition_blocks_cell(capital.x,capital.y)
    local occupant=r8(CTX+0x3F60+capital.x*4+capital.y*0xC0)
    local pref=(occupant==0 or occupant==cs_owner) and 0 or 1
    local distance=current_route(capital,pref,cat)[u.x..","..u.y]
    if transition_blocked then log(string.format("DEADLINE BLOCKED capital=%d,%d last-faction-unit native transition restriction",capital.x,capital.y)) end
    if not transition_blocked and distance and distance<=u.fuel then
     local eta=math.max(1,math.ceil(distance/math.max(1,r8(0x08798A98+u.id*0x5C+0x0D))))+(pref==1 and 1 or 0)
     if (not cs_clock.left or eta<=cs_clock.left) and eta<best then chosen,best={x=capital.x,y=capital.y,pref=pref,value=-100,kind="capture"},eta end
    end
   end
   if chosen then current_orders[u.idx]=chosen;log(string.format("DEADLINE U%d capital=%d,%d estimated_turns=%d left=%s",u.idx,chosen.x,chosen.y,best,tostring(cs_clock.left)))
   else log("DEADLINE U"..u.idx.." no capital reachable within fuel/deadline") end
  end
 end
end

local function current_capture_action(k, u, en)
 local order = current_orders[k]
 if not order or order.kind ~= "capture" then return false end
 local _, cat, budget = vm_ctx(k)
 current_advance(k, u, vm_reach(u, cat, budget), cat, en)
 if r8(CTX) ~= 8 and #all_units("EN") > 0 then markacted(k) end
 return true
end

local function current_trace_round(phase)
 local rows = {}
 for _, side in ipairs({ "MY", "EN" }) do
  for _, u in ipairs(all_units(side)) do
   local order = (side == "MY") and current_orders[u.idx] or nil
   rows[#rows + 1] = string.format('{"side":"%s","faction":%d,"slot":%d,"id":%d,"x":%d,"y":%d,"hp":%d,"fuel":%d,"acted":%s,"ammo":[%d,%d,%d,%d],"order":"%s","goal_x":%d,"goal_y":%d}',
    side,u.side or cs_player, u.idx, u.id, u.x, u.y, u.hp, u.fuel,tostring(u.acted),
    r8(U+(u.side or cs_player)*PB+u.idx*STRIDE-2+8),r8(U+(u.side or cs_player)*PB+u.idx*STRIDE-2+9),
    r8(U+(u.side or cs_player)*PB+u.idx*STRIDE-2+10),r8(U+(u.side or cs_player)*PB+u.idx*STRIDE-2+11),
    order and order.kind or "", order and order.x or -1, order and order.y or -1)
  end
 end
 local f = assert(io.open(BASE .. "logs/" .. SAVE_PREFIX .. "_trajectory.jsonl", "a"))
 f:write(string.format('{"turn":%d,"phase":"%s","units":[%s]}\n', r8(CTX + 0x20), phase, table.concat(rows, ",")))
 f:close()
end

-- 原生战斗调用卡住时的自救：多阵营地图上「灭掉其中一个敌对阵营」会让游戏进入
-- 灭国演出/弹窗（等输入），此时 FUN_08023188 不会返回，mailbox 停在 busy。
-- 做法：卸掉 hook → 用 A 推过演出/对话 → 状态还是我方地图态就装回 hook 继续。
local cs_stuck_aborted = false
local function cs_recover_stuck(k)
 cs_stuck_aborted = true
 client.speedmode(100)
 log(string.format("STUCK U%d 原生调用异常，停止自动指令并保留现场；不自动按A、不清除mailbox或调用栈",k))
end

-- 敌人列表里每个单位带 side/key：给旧打分代码用的威胁距离
local function current_home_threat(e)
 return cs_home_distance(e.x, e.y)
end
