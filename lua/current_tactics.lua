-- Inserted inside autoclear: current-game tactics, independent of legacy replays.
local current_orders,current_previous_en,current_capture_jobs={},{},{}
local current_strategy={mode="advance",threats={},sectors={N=0,E=0,S=0,W=0}}
local current_recovery={}
local function current_has_ammo(u)
 for wa=0,3 do
  if uammo(u.idx,wa)>0 and r8(wslot(u.id,wa)+13)>0 then
   for cls=0,4 do if r8(wslot(u.id,wa)+8+cls)>0 then return true end end
  end
 end
 return false
end
local function current_needs_recovery(u)
 local maximum=math.max(1,(db(u.id) or {}).fuel or u.fuel)
 local previous=current_recovery[u.idx]
 local needed=u.hp<math.max(1,u.maxhp)*0.75 or u.fuel<maximum*0.35 or not current_has_ammo(u)
 if previous and previous.active then needed=u.hp<u.maxhp*0.9 or u.fuel<maximum*0.8 or not current_has_ammo(u) end
 if previous and previous.force_supply then needed=true end
 return needed,maximum
end
local function current_quick_attack(u,en)
 if u.acted or u.hp<=0 then return false end
 local target,score=nil,-1e30
 for _,e in ipairs(en) do
  local d=hexd(u.x,u.y,e.x,e.y)
  local damage=estimate(u,e,my_best(u,d,e.id))
  if damage>=e.hp and damage>0 then
   local loss=estimate(e,u,enemy_counter(e,u.id,d),u.x,u.y)
   if loss<u.hp or damage>=e.hp*1.5 then
    local value=200-e.hp+(is_capturer(e.id) and 50 or 0)
    if value>score then target,score=e,value end
   end
  end
 end
 if not target then return false end
 local ok,msg=pcall(attack,u.idx,target.idx)
 log(string.format("FINISHER U%d E%d ok=%s %s",u.idx,target.idx,tostring(ok),tostring(msg)))
 return ok
end
local function current_friendly_city(x,y)
 return on_building(x,y) and r8(tb()+x*4+y*0xC0+2)==1
end
local function current_danger(u,x,y,en)
 local risk=0
 for _,e in ipairs(en) do
  local d=hexd(x,y,e.x,e.y)
  -- Conservative envelope: the enemy's full movement budget, plus weapon range.
  local mv=r8(0x08798A98+e.id*0x5C+0x0D)
  local power=enemy_counter(e,u.id,math.max(1,d-math.min(mv,e.fuel or 0)))
  if power>0 then
   local hit=estimate(e,u,power,x,y)
   risk=risk+hit*(enemy_counter(e,u.id,d)>0 and 1 or 0.4)
  end
 end
 return risk
end
local function current_guard(u,en)
 return terrain_at(u.x,u.y)==0x10 and current_friendly_city(u.x,u.y)
end
local function current_hold(u,en)
 -- A threatened/low-HP capital defender must never flee and expose the capital.
 if current_guard(u,en) then return true,"capital_garrison" end
 if not current_friendly_city(u.x,u.y) then return false end
 local risk=current_danger(u,u.x,u.y,en)
 -- Do not insist on holding a position forecast to lose the unit.
 if risk>=u.hp*0.9 then return false end
 local recovery,maximum=current_needs_recovery(u)
 local previous=current_recovery[u.idx]
 if recovery then
  local same=previous and previous.x==u.x and previous.y==u.y
  local stagnant=same and u.hp<=previous.hp and u.fuel<=previous.fuel and (previous.stagnant or 0)+1 or 0
  log(string.format("RECOVER U%d hp=%d/%d fuel=%d/%d delta_hp=%d delta_fuel=%d stagnant=%d",
   u.idx,u.hp,u.maxhp,u.fuel,maximum,previous and previous.hp and u.hp-previous.hp or 0,previous and previous.fuel and u.fuel-previous.fuel or 0,stagnant))
  current_recovery[u.idx]={active=true,x=u.x,y=u.y,hp=u.hp,fuel=u.fuel,stagnant=stagnant}
  if stagnant<3 then return true,"recover_in_city" end
 else current_recovery[u.idx]=nil end
 if current_orders[u.idx] and current_orders[u.idx].kind=="intercept" then return false end
 if current_guard(u,en) then return true,"defend_capital" end
 for _,e in ipairs(en) do
  local d=hexd(u.x,u.y,e.x,e.y)
  if current_strategy.mode=="defend" and d<=4 and (enemy_counter(e,u.id,1)>0 or my_best(u,d,e.id)>0) then
   return true,"hold_frontline_city"
  end
 end
 return false
end
local function current_hold_action(k,u,en,reason)
 if current_quick_attack(u,en) then return end
 local target,score=nil,-1e9
 for _,e in ipairs(en) do
  local d=hexd(u.x,u.y,e.x,e.y)
  local hit=estimate(u,e,my_best(u,d,e.id))
  local loss=estimate(e,u,enemy_counter(e,u.id,d),u.x,u.y)
  if hit>0 and loss<u.hp*0.6 then
   local value=math.min(hit,e.hp)*16-loss*20+(hit>=e.hp and 180 or 0)
   if value>score then target,score=e,value end
  end
 end
 if target then
  local ok,msg=pcall(attack,k,target.idx)
  log(string.format("HOLD U%d %s attack=%s %s",k,reason,tostring(ok),tostring(msg)))
  if r8(CTX)==8 or #all_units("EN")==0 then return end
 end
 markacted(k)
 log(string.format("HOLD U%d %s hp=%d/%d at=%d,%d",k,reason,u.hp,u.maxhp,u.x,u.y))
end
-- Cached per round: route fields depend on terrain and enemy blockers, not allies.
local current_routes={}
local current_capitals={}
local current_supply_nodes={}
local function current_begin_round()
 current_routes,current_capitals,current_supply_nodes={},{},{}
 for y=1,46 do for x=1,46 do
  if terrain_at(x,y)==0x10 and current_friendly_city(x,y) then
   current_capitals[#current_capitals+1]={x=x,y=y}
  end
  if current_friendly_city(x,y) and (terrain_at(x,y)~=0x10 or r8(CTX+0x3F60+x*4+y*0xC0)==0) then
   current_supply_nodes[#current_supply_nodes+1]={x=x,y=y}
  end
 end end
end
local function current_assess()
 local my,en=all_units("MY"),all_units("EN")
 local sectors={N=0,E=0,S=0,W=0}
 local threats,near,own_power,enemy_power,home_force={},0,0,0,0
 local origin=current_capitals[1] or {x=24,y=24}
 for _,u in ipairs(my) do
  own_power=own_power+u.hp/math.max(1,u.maxhp)*(current_has_ammo(u) and 1 or 0.1)*(u.fuel>0 and 1 or 0.25)
  for _,c in ipairs(current_capitals) do
   if hexd(u.x,u.y,c.x,c.y)<=10 and u.hp>=u.maxhp*0.5 then home_force=home_force+1; break end
  end
 end
 for _,e in ipairs(en) do
  enemy_power=enemy_power+e.hp/math.max(1,e.maxhp or e.hp)
  local dx,dy=e.x-origin.x,e.y-origin.y
  local sector=math.abs(dx)>math.abs(dy) and (dx>0 and "E" or "W") or (dy>0 and "S" or "N")
  sectors[sector]=sectors[sector]+1
  local distance=1e9
  for _,c in ipairs(current_capitals) do distance=math.min(distance,hexd(e.x,e.y,c.x,c.y)) end
  local old=current_previous_en[e.idx]
  local closing=old and distance<old.distance
  local speed=math.max(1,math.min(r8(0x08798A98+e.id*0x5C+0x0D),e.fuel or 0))
  local eta=math.max(0,distance-1)/speed
  if distance<=7 or (closing and eta<=(is_capturer(e.id) and 3 or 2)) then
   threats[e.idx]=true;near=near+1
  end
 end
 local mode=near>=3 and near>home_force*0.75 and "defend" or (near>0 and "intercept" or (own_power>enemy_power*1.6 and "exploit" or "advance"))
 local focus="N";for sector,count in pairs(sectors) do if count>sectors[focus] then focus=sector end end
 current_strategy={mode=mode,threats=threats,sectors=sectors,near=near,enemy_count=#en,friendly_count=#my,focus=focus,origin=origin}
 log(string.format("STRATEGY mode=%s my=%d enemy=%d home_threats=%d enemy_N=%d E=%d S=%d W=%d power=%.1f/%.1f",
  mode,#my,#en,near,sectors.N,sectors.E,sectors.S,sectors.W,own_power,enemy_power))
end
local function current_route(goal,pref,cat)
 local key=goal.x..","..goal.y..","..pref..","..cat
 if not current_routes[key] then current_routes[key]=route_field(goal,pref,cat) end
 return current_routes[key]
end
local function current_defend_capitals()
 local en=all_units("EN")
 local assigned={}
 for _,capital in ipairs(current_capitals) do
  local threatened=false
  for _,e in ipairs(en) do
   local speed=math.min(r8(0x08798A98+e.id*0x5C+0x0D),e.fuel or 0)
   if hexd(e.x,e.y,capital.x,capital.y)<=math.max(10,speed+3) then threatened=true; break end
  end
  local occupied=r8(CTX+0x3F60+capital.x*4+capital.y*0xC0)==1
  -- Fill an empty capital first; a threatened capital additionally gets a reserve.
 local pressure=current_strategy.near or 0
  local reserves=pressure>=3 and 2 or (pressure>0 and 1 or 0)
  local roles={}; if not occupied then roles[#roles+1]=0 end
  for ring=1,reserves do roles[#roles+1]=ring end
  for _,pref in ipairs(roles) do
   local chosen,best=nil,1e30
   for _,u in ipairs(all_units("MY")) do
    local grid=CTX+0x3F60+u.x*4+u.y*0xC0
    if not u.acted and u.hp>0 and not assigned[u.idx] and not current_guard(u,en)
        and not (u.id>=339 and u.id<=345) and r8(grid)==1 and r8(grid+1)==u.idx+1
        and (pref==0 or not current_needs_recovery(u)) then
     local _,cat,budget=vm_ctx(u.idx)
     local routes=current_route(capital,pref,cat)
     local distance=routes[u.x..","..u.y]
     if distance and (distance==0 or budget>0) then
      local ratio=u.hp/math.max(1,u.maxhp)
      local armed=false; for slot=0,3 do if uammo(u.idx,slot)>0 then armed=true end end
      local score=distance*10+(1-ratio)*30+(armed and 0 or 100)+(is_capturer(u.id) and 150 or 0)
      if score<best then chosen,best=u,score end
     end
    end
   end
   if chosen then
    assigned[chosen.idx]=true
    local _,cat,budget=vm_ctx(chosen.idx)
    local reach=vm_reach(chosen,cat,budget)
    local routes=current_route(capital,pref,cat)
    local bx,by,bs=chosen.x,chosen.y,-1e30
    -- Returning to defend has priority over attacking or capturing another city.
    for key,cost in pairs(reach) do
     local x,y=key:match("(%d+),(%d+)"); x,y=tonumber(x),tonumber(y)
     if routes[key] and ((x==chosen.x and y==chosen.y) or r8(CTX+0x3F60+x*4+y*0xC0)==0) then
      local score=-routes[key]*100-current_danger(chosen,x,y,en)*4-cost
      if routes[key]==0 then score=score+1000 end
      if score>bs then bx,by,bs=x,y,score end
     end
    end
    local ok,msg=true,"hold"
    local moved=bx~=chosen.x or by~=chosen.y
    if moved then ok,msg=pcall(vm_land,chosen.idx,chosen,bx,by,reach[bx..","..by]) end
    if ok then
     if not moved then current_hold_action(chosen.idx,chosen,en,"capital_reserve")
     else
      local now=unit("MY",chosen.idx)
      if not now or not current_quick_attack(now,all_units("EN")) then markacted(chosen.idx) end
     end
    end
    log(string.format("DEFEND capital=%d,%d U%d role=%s destination=%d,%d ok=%s %s",
     capital.x,capital.y,chosen.idx,pref==0 and "garrison" or "reserve",bx,by,tostring(ok),tostring(msg)))
    if r8(CTX)==8 or #all_units("EN")==0 then return end
   else
    log(string.format("DEFEND WARNING capital=%d,%d no available %s",capital.x,capital.y,pref==0 and "garrison" or "reserve"))
   end
  end
 end
end
local function current_advance(k,u,reach,cat,en)
 local risks={}
 local function failed_node(x,y)
  local previous=current_recovery[k]
  return previous and (previous.stagnant or 0)>=3 and previous.x==x and previous.y==y
 end
 local function risk_at(x,y)
  local key=x..","..y
  if risks[key]==nil then risks[key]=current_danger(u,x,y,en) end
  return risks[key]
 end
 local capturer=is_capturer(u.id)
 local function return_cost(x,y)
  local best=nil
  for _,node in ipairs(current_supply_nodes) do
   local distance=current_route(node,0,cat)[x..","..y]
   if distance and (not best or distance<best) then best=distance end
  end
  return best
 end
 local home_cost=return_cost(u.x,u.y)
 if home_cost and u.fuel<=home_cost+math.min(5,r8(0x08798A98+u.id*0x5C+0x0D)) then
  local previous=current_recovery[k] or {}
  previous.active=true;previous.force_supply=true;current_recovery[k]=previous
 end
 local wounded=current_needs_recovery(u)
 local start_risk=risk_at(u.x,u.y)
 local retreat=start_risk>=u.hp*0.9
 local goals={}
 -- Cities are strategic objectives beyond this turn's movement radius.
 for y=1,46 do for x=1,46 do
  if on_building(x,y) then
   local owner=r8(tb()+x*4+y*0xC0+2)
   local occ=r8(CTX+0x3F60+x*4+y*0xC0)
   local stagnant=failed_node(x,y)
   if not stagnant and (occ==0 or (x==u.x and y==u.y)) then
    local friendly=owner==1
    if (capturer and not friendly) or (friendly and (wounded or retreat)) then
     local risk=risk_at(x,y)
     if friendly or risk<u.hp*0.7 then
      local value=hexd(u.x,u.y,x,y)+(risk/math.max(1,u.hp))*8
      if not friendly and terrain_at(x,y)==0x10 then value=value-5 end
      goals[#goals+1]={x=x,y=y,pref=0,value=value,kind=friendly and "recover" or "capture"}
     end
    end
   end
  end
 end end
 if wounded or retreat then
  local recovery={}
  for _,goal in ipairs(goals) do if goal.kind=="recover" then recovery[#recovery+1]=goal end end
  if #recovery>0 then goals=recovery end
 end
 if not wounded and not retreat and not (u.id>=339 and u.id<=345) then
  for _,capital in ipairs(current_capitals) do
   if r8(CTX+0x3F60+capital.x*4+capital.y*0xC0)==0 then
    for _,e in ipairs(en) do
     if hexd(e.x,e.y,capital.x,capital.y)<=7 then
      goals[#goals+1]={x=capital.x,y=capital.y,pref=0,
       value=hexd(u.x,u.y,capital.x,capital.y)-20,kind="defend"}
      break
     end
    end
   end
  end
 end
 -- Prefer an enemy this unit can actually damage; transports keep their distance.
 if not wounded and not retreat then
  local cx,cy=enemy_capital()
  local surviving_capturer=false
  for _,ally in ipairs(all_units("MY")) do if is_capturer(ally.id) and ally.hp>0 then surviving_capturer=true end end
  if cx and not capturer and surviving_capturer then
   goals[#goals+1]={x=cx,y=cy,pref=2,value=hexd(u.x,u.y,cx,cy)+(current_strategy.mode=="exploit" and -12 or 5),kind="siege"}
  end
  for _,e in ipairs(en) do
   local pref,armed=1,false
   for d=3,1,-1 do if my_best(u,d,e.id)>0 then pref,armed=d,true; break end end
   if armed or not capturer then
    local friendly,hostile=0,0
    for _,ally in ipairs(all_units("MY")) do if hexd(ally.x,ally.y,e.x,e.y)<=8 then friendly=friendly+1 end end
    for _,other in ipairs(en) do if hexd(other.x,other.y,e.x,e.y)<=4 then hostile=hostile+1 end end
    local origin=current_strategy.origin or {x=u.x,y=u.y}
    local dx,dy=e.x-origin.x,e.y-origin.y
    local sector=math.abs(dx)>math.abs(dy) and (dx>0 and "E" or "W") or (dy>0 and "S" or "N")
    goals[#goals+1]={x=e.x,y=e.y,pref=armed and pref or 4,
      value=hexd(u.x,u.y,e.x,e.y)+(armed and 8 or 18)+math.max(0,hostile-friendly)*3-(sector==current_strategy.focus and 5 or 0),kind=armed and "engage" or "support"}
   end
  end
 end
 local order=current_orders[k]
 if order and not wounded and not retreat then
  goals={order}
 elseif order and order.kind=="cleanup" and not retreat and u.hp>=u.maxhp*0.6 and (order.path_cost or 1e9)<=u.fuel then
  goals={order}
 end
 table.sort(goals,function(a,b) return a.value<b.value end)
 local bx,by,best,bwhy=nil,nil,-1e30,"no_route"
 -- Include the current cell: staying put can beat walking out of cover.
 local cells={}
 for key,cost in pairs(reach) do cells[key]=cost end
 cells[u.x..","..u.y]=0
 local reachable_goals=0
 for i=1,#goals do
  local goal=goals[i]; local routes=current_route(goal,goal.pref,cat)
  local initial=routes[u.x..","..u.y]
  if initial and (goal.kind~="recover" or initial<=u.fuel) then
   reachable_goals=reachable_goals+1
   for key,cost in pairs(cells) do
    local x,y=key:match("(%d+),(%d+)"); x,y=tonumber(x),tonumber(y)
    local remaining=routes[key]
    local same=x==u.x and y==u.y
    if remaining and (same or r8(CTX+0x3F60+x*4+y*0xC0)==0) then
     local risk=risk_at(x,y)
     local infantry_safe=not capturer or risk<u.hp*0.4 or risk<start_risk*0.5
     if capturer and not same and risk>0 then
      local escort=false
      for _,ally in ipairs(all_units("MY")) do
       if not is_capturer(ally.id) and current_has_ammo(ally) and ally.hp>=ally.maxhp*0.5
           and hexd(x,y,ally.x,ally.y)<=3 then escort=true;break end
      end
      if not escort then infantry_safe=false end
     end
     local remaining_fuel=u.fuel-cost
     local return_path=return_cost(x,y)
     local supply_safe=capturer or not return_path or return_path<=remaining_fuel
     if infantry_safe and supply_safe and (risk<u.hp*0.9 or risk<start_risk*0.7) then
      local score=(initial-remaining)*35-goal.value*8-risk*18+tdef(terrain_at(x,y))-cost*0.2
      if current_friendly_city(x,y) and not failed_node(x,y) then score=score+(wounded and 100 or 15) end
      if not same and current_friendly_city(u.x,u.y) and not failed_node(u.x,u.y) then score=score-25 end
      if remaining==0 and goal.kind=="capture" then score=score+160 end
      if remaining==0 and goal.kind=="defend" then score=score+140 end
      if score>best then bx,by,best,bwhy=x,y,score,goal.kind end
     end
    end
   end
  end
  if reachable_goals>=8 then break end
 end
 -- No reachable objective: spread toward cover/safety instead of forcing an invalid route.
 if not bx then
  for key,cost in pairs(cells) do
   local x,y=key:match("(%d+),(%d+)"); x,y=tonumber(x),tonumber(y)
   if (x==u.x and y==u.y) or r8(CTX+0x3F60+x*4+y*0xC0)==0 then
    local score=-risk_at(x,y)*18+tdef(terrain_at(x,y))-cost
    if score>best then bx,by,best,bwhy=x,y,score,"cover" end
   end
  end
 end
 local moved=bx and (bx~=u.x or by~=u.y)
 if moved then
  local ok,msg=pcall(vm_land,k,u,bx,by,cells[bx..","..by])
  log(string.format("ADVANCE U%d %s %d,%d->%d,%d ok=%s %s",k,bwhy,u.x,u.y,bx,by,tostring(ok),tostring(msg)))
  if not ok then return end
 end
 local now=unit("MY",k)
 if now and capturer and on_building(now.x,now.y) and r8(tb()+now.x*4+now.y*0xC0+2)~=1 then
  local ok,msg=pcall(cap,k)
  log(string.format("CAPTURE U%d ok=%s %s",k,tostring(ok),tostring(msg)))
 elseif not moved then
  local count=0; for _ in pairs(reach) do count=count+1 end
  local why=u.fuel==0 and "no_fuel" or (count<=1 and "no_reachable_cell" or bwhy)
  log(string.format("WAIT U%d %s fuel=%d reachable_cells=%d",k,why,u.fuel,count))
 end
end
local function current_attack_targets(u,en)
 local order=current_orders[u.idx]
 if order and (order.kind=="intercept" or order.kind=="cleanup") then
  local targets={}
  for _,e in ipairs(en) do if e.idx==order.enemy then targets[#targets+1]=e end end
  if #targets==0 then
   current_orders[u.idx]=nil
   log("ORDER U"..u.idx.." intercept target destroyed; released")
   return en
  end
  return targets
 end
 if order and order.kind=="escort" then
  local foot=unit("MY",order.subject)
  local targets={}
  for _,e in ipairs(en) do
   if hexd(e.x,e.y,order.x,order.y)<=6 or (foot and hexd(e.x,e.y,foot.x,foot.y)<=6) then targets[#targets+1]=e end
  end
  return targets
 end
 return en
end
local function current_plan_round()
 current_orders={}
 local en,my=all_units("EN"),all_units("MY")
 local threats={}
 for _,e in ipairs(en) do
  local closest=1e9
  for _,capital in ipairs(current_capitals) do closest=math.min(closest,hexd(e.x,e.y,capital.x,capital.y)) end
  local old=current_previous_en[e.idx]
  local closing=old and closest<old.distance
  if current_strategy.threats[e.idx] then
   threats[#threats+1]={unit=e,priority=closest-(is_capturer(e.id) and 6 or 0)-(closing and 3 or 0)}
  end
 end
 table.sort(threats,function(a,b) return a.priority<b.priority end)
 local allocated,limit=0,math.min(math.max(1,#threats*2),math.max(1,math.floor(#my*(current_strategy.mode=="defend" and 0.3 or 0.2))))
 for _,threat in ipairs(threats) do
  local e=threat.unit
  local team=e.hp<math.max(1,e.maxhp or e.hp)*0.3 and 1 or 2
  for role=1,team do
   if allocated>=limit then break end
   local selected,score=nil,1e30
   for _,u in ipairs(my) do
    if not u.acted and u.hp>0 and not current_orders[u.idx] and not current_guard(u,en)
        and not is_capturer(u.id) and not (u.id>=339 and u.id<=345) and not current_needs_recovery(u) then
     local pref=nil
     for d=3,1,-1 do if my_best(u,d,e.id)>0 then pref=d; break end end
     if pref then
      local _,cat,budget=vm_ctx(u.idx)
      local distance=current_route(e,pref,cat)[u.x..","..u.y]
      if distance and (distance==0 or budget>0) then
       local value=distance+(1-u.hp/math.max(1,u.maxhp))*15
       if value<score then selected,score={u=u,pref=pref},value end
      end
     end
    end
   end
   if selected then
    local u=selected.u
    current_orders[u.idx]={x=e.x,y=e.y,pref=selected.pref,value=-100,kind="intercept",enemy=e.idx}
    allocated=allocated+1
    log(string.format("ORDER U%d intercept E%d at=%d,%d",u.idx,e.idx,e.x,e.y))
   end
  end
 end
 -- Dedicated infantry missions run before opportunistic attacks.
 local claimed={}
 for _,u in ipairs(my) do
  if not u.acted and u.hp>0 and is_capturer(u.id) and not current_guard(u,en) then
   local _,cat=vm_ctx(u.idx)
   local chosen,score=nil,1e30
   for y=1,46 do for x=1,46 do
    if on_building(x,y) and r8(tb()+x*4+y*0xC0+2)~=1 and not claimed[x..","..y] then
     local pref=r8(CTX+0x3F60+x*4+y*0xC0)>1 and 1 or 0
     local distance=current_route({x=x,y=y},pref,cat)[u.x..","..u.y]
     if distance then
      local risk=current_danger(u,x,y,en)
      local value=distance+risk*2-(terrain_at(x,y)==0x10 and 40 or 0)
      local old=current_capture_jobs[u.idx]
      if old and old.x==x and old.y==y then value=value-12 end
      if value<score then chosen,score={x=x,y=y,pref=pref,value=-30,kind="capture"},value end
     end
    end
   end end
   if chosen then
    current_orders[u.idx]=chosen; current_capture_jobs[u.idx]=chosen; claimed[chosen.x..","..chosen.y]=true
    log(string.format("ORDER U%d capture target=%d,%d staging=%d",u.idx,chosen.x,chosen.y,chosen.pref))
    local escort,best=nil,1e30
    for _,candidate in ipairs(my) do
     if not candidate.acted and candidate.hp>0 and not current_orders[candidate.idx]
         and not current_guard(candidate,en) and not is_capturer(candidate.id)
         and not (candidate.id>=339 and candidate.id<=345) then
      local armed=false
      for _,e in ipairs(en) do if my_best(candidate,1,e.id)>0 then armed=true; break end end
      if armed then
       local value=hexd(u.x,u.y,candidate.x,candidate.y)+(1-candidate.hp/math.max(1,candidate.maxhp))*10
       if value<best then escort,best=candidate,value end
      end
     end
    end
    if escort then
     current_orders[escort.idx]={x=u.x,y=u.y,pref=1,value=-25,kind="escort",subject=u.idx}
     log(string.format("ORDER U%d escort U%d target=%d,%d",escort.idx,u.idx,chosen.x,chosen.y))
    end
   else log("ORDER U"..u.idx.." capture no reachable city") end
  end
 end
 current_previous_en={}
 for _,e in ipairs(en) do
  local distance=1e9
  for _,capital in ipairs(current_capitals) do distance=math.min(distance,hexd(e.x,e.y,capital.x,capital.y)) end
  current_previous_en[e.idx]={x=e.x,y=e.y,distance=distance}
 end
end
local function current_capture_action(k,u,en)
 local order=current_orders[k]
 if not order or order.kind~="capture" then return false end
 local _,cat,budget=vm_ctx(k)
 current_advance(k,u,vm_reach(u,cat,budget),cat,en)
 if r8(CTX)~=8 and #all_units("EN")>0 then markacted(k) end
 return true
end
local function current_trace_round(phase)
 local rows={}
 for _,side in ipairs({"MY","EN"}) do
  for _,u in ipairs(all_units(side)) do
   local order=side=="MY" and current_orders[u.idx] or nil
   rows[#rows+1]=string.format('{"side":"%s","slot":%d,"id":%d,"x":%d,"y":%d,"hp":%d,"fuel":%d,"order":"%s","goal_x":%d,"goal_y":%d}',
    side,u.idx,u.id,u.x,u.y,u.hp,u.fuel,order and order.kind or "",order and order.x or -1,order and order.y or -1)
  end
 end
 local f=assert(io.open(BASE.."logs/"..SAVE_PREFIX.."_trajectory.jsonl","a"))
 f:write(string.format('{"turn":%d,"phase":"%s","strategy":"%s","focus":"%s","units":[%s]}\n',r8(CTX+0x20),phase,current_strategy.mode,current_strategy.focus or "N",table.concat(rows,",")))
 f:close()
end
