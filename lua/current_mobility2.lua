-- Supply handoffs and the final stationary-shot check before consuming an action.
-- Vacate hostile buildings before fire consumes the blocking vehicle's action.
local function cs_capture_handoff()
 local en,my=all_units("EN"),all_units("MY")
 for _,outgoing in ipairs(my) do
  local x,y=outgoing.x,outgoing.y
  if not outgoing.acted and not is_capturer(outgoing.id) and on_building(x,y)
     and r8(tb()+x*4+y*0xC0+2)~=cs_owner then
   local incoming,in_cost,best=nil,nil,1e30
   for _,u in ipairs(all_units("MY")) do
    if not u.acted and is_capturer(u.id) and not cs_guard(u,en) then
     local _,cat,budget=vm_ctx(u.idx)
     local cost=vm_reach(u,cat,budget)[x..","..y]
     if cost and cost<=u.fuel and cs_danger(u,x,y,en)<u.hp*0.9 and cost<best then
      incoming,in_cost,best=u,cost,cost
     end
    end
   end
   if incoming then
    local _,cat,budget=vm_ctx(outgoing.idx)
    local reach=vm_reach(outgoing,cat,budget)
    local bx,by,score=nil,nil,-1e30
    for key,cost in pairs(reach) do
     local xx,yy=key:match("(%d+),(%d+)");xx,yy=tonumber(xx),tonumber(yy)
     if r8(CTX+0x3F60+xx*4+yy*0xC0)==0 and cs_danger(outgoing,xx,yy,en)<outgoing.hp*0.8 then
      local value=-cost*4+tdef(terrain_at(xx,yy))
      -- Do not move the blocker onto another uncaptured building.
      if on_building(xx,yy) and r8(tb()+xx*4+yy*0xC0+2)~=cs_owner then value=value-1000 end
      if value>score then bx,by,score=xx,yy,value end
     end
    end
    if bx then
     local checkpoint=BASE.."states/"..SAVE_PREFIX.."_capture_handoff.State"
     uninstall();savestate.save(checkpoint)
     local ok,msg=pcall(function()
      vm_land(outgoing.idx,outgoing,bx,by,reach[bx..","..by])
      vm_land(incoming.idx,incoming,x,y,in_cost)
     end)
     if not ok then
      savestate.load(checkpoint);restore_keyboard()
      log("CAPTURE_SWAP rolled back "..tostring(msg));return
     end
     log(string.format("CAPTURE_SWAP city=%d,%d outgoing=U%d incoming=U%d",x,y,outgoing.idx,incoming.idx))
     -- No rollback across a native capture/transition: preserve manual dialogs.
     local captured,why=pcall(cap,incoming.idx)
     if not captured then return "FAIL capture handoff: "..tostring(why) end
     if r8(CTX)==8 or #all_units("EN")==0 then return end
     markacted(incoming.idx)
     if r8(CTX)==8 then return end
     markacted(outgoing.idx)
     if r8(CTX)==8 then return end
    else log("CAPTURE_SWAP no safe exit U"..outgoing.idx) end
   end
  end
 end
end

-- Plan one main axis, then allocate firepower using route cost and target HP.
local function cs_offensive_orders()
 local my,en=all_units("MY"),all_units("EN")
 local cleanup=#en<=math.max(3,math.floor(#my*0.15))
 local objective,foot,best=nil,nil,1e30
 for y=1,46 do for x=1,46 do
  local owner=r8(tb()+x*4+y*0xC0+2)
  if terrain_at(x,y)==0x10 and owner~=cs_owner and owner>0 and side_alive(owner-1) then
   local occ=r8(CTX+0x3F60+x*4+y*0xC0)
   local pref=(occ==0 or occ==cs_owner) and 0 or 1
   for _,u in ipairs(my) do
    if not u.acted and is_capturer(u.id) and not cs_guard(u,en) and not cs_needs_supply(u) then
     local _,cat=vm_ctx(u.idx)
     local cost=current_route({x=x,y=y},pref,cat)[u.x..","..u.y]
     if cost and cost<=u.fuel then
      local value=cost+(pref==1 and 6 or 0)
      if cs_campaign.objective and cs_campaign.objective.x==x and cs_campaign.objective.y==y and cs_clock.stalled<3 then value=value-8 end
      if value<best then objective,foot,best={x=x,y=y,pref=pref},u,value end
     end
    end
   end
  end
 end end
 cs_campaign.objective=objective
 cs_campaign.turn=cs_clock.turn
 if foot then
  current_orders[foot.idx]={x=objective.x,y=objective.y,pref=objective.pref,value=-110,kind="capture"}
 end
 -- Preserve close threats to home; release remote intercepts and stale escorts.
 local assigned,taken={},{}
 for _,u in ipairs(my) do
  local o=current_orders[u.idx]
  if o and (o.kind=="intercept" or o.kind=="escort") and not u.acted and not cs_needs_supply(u) then
   local urgent=false
   if o.kind=="intercept" and current_my_capital then
    for _,e in ipairs(en) do
     if e.side==o.foe_side and e.idx==o.foe_slot and hexd(e.x,e.y,current_my_capital.x,current_my_capital.y)<=8 then urgent=true end
    end
   end
   if urgent then
    local key=o.foe_side*64+o.foe_slot;assigned[key]=(assigned[key] or 0)+1;taken[u.idx]=true
   else current_orders[u.idx]=nil end
  end
 end
 -- Escorts follow the capturing unit, never race alone to its distant destination.
 if foot and not cleanup then
  local threatened=false
  for _,e in ipairs(en) do if hexd(e.x,e.y,foot.x,foot.y)<=8 then threatened=true end end
  if threatened then
   local options={}
   for _,u in ipairs(my) do
    if not u.acted and not taken[u.idx] and not cs_guard(u,en) and not is_capturer(u.id)
       and not cs_needs_supply(u) and not (u.id>=339 and u.id<=345) then
     local armed=false
     for _,e in ipairs(en) do if my_best(u,1,e.id)>0 then armed=true end end
     if armed then
      local _,cat=vm_ctx(u.idx)
      local distance=current_route(foot,1,cat)[u.x..","..u.y]
      if distance and distance<=u.fuel then options[#options+1]={u=u,cost=distance} end
     end
    end
   end
   table.sort(options,function(a,b) return a.cost<b.cost end)
   for i=1,math.min(#options,#my>=12 and 2 or 1) do
    local u=options[i].u;taken[u.idx]=true
    current_orders[u.idx]={x=foot.x,y=foot.y,pref=1,value=-70,kind="escort",subject=foot.idx}
   end
  end
 end
 local candidates,primary,primary_score={},nil,1e30
 for _,u in ipairs(my) do
  if not u.acted and not taken[u.idx] and not cs_guard(u,en) and not is_capturer(u.id)
     and not (u.id>=339 and u.id<=345) and not cs_needs_supply(u) then
   local _,cat=vm_ctx(u.idx)
   for _,e in ipairs(en) do
    for d=1,3 do
     local power=my_best(u,d,e.id)
     if power>0 then
      local distance=current_route(e,d,cat)[u.x..","..u.y]
      if distance and distance<=u.fuel then
       local hit=math.max(1,estimate(u,e,power))
       local priority=distance+(objective and hexd(e.x,e.y,objective.x,objective.y)*2 or 0)
       if terrain_at(e.x,e.y)==0x10 then priority=priority-20 end
       if cs_campaign.primary==e.side*64+e.idx then priority=priority-5 end
       if current_my_capital and hexd(e.x,e.y,current_my_capital.x,current_my_capital.y)<=8 then priority=priority-60 end
       if priority<primary_score then primary,primary_score=e,priority end
       candidates[#candidates+1]={u=u,e=e,pref=d,cost=distance,hit=hit,priority=priority}
      end
     end
    end
   end
  end
 end
 cs_campaign.primary=primary and primary.side*64+primary.idx or nil
 for _,c in ipairs(candidates) do
  -- Concentrate on the selected sector, with a bonus for its immediate target.
  if primary then
   c.priority=c.priority+hexd(c.e.x,c.e.y,primary.x,primary.y)*2
   if c.e.side==primary.side and c.e.idx==primary.idx then c.priority=c.priority-18 end
  end
 end
 table.sort(candidates,function(a,b) if a.priority~=b.priority then return a.priority<b.priority end return a.u.idx<b.u.idx end)
 local damage={}
 -- First pass avoids overconcentration; the second gives remaining troops a task.
 for pass=1,2 do
  for _,c in ipairs(candidates) do
   local key=c.e.side*64+c.e.idx
   local count=assigned[key] or 0
   local enough=count>=2 and (damage[key] or 0)>=c.e.hp*1.5
   if not taken[c.u.idx] and (pass==2 or (count<(cleanup and 8 or 6) and not enough)) then
    current_orders[c.u.idx]={x=c.e.x,y=c.e.y,pref=c.pref,value=-90,kind="intercept",foe_side=c.e.side,foe_slot=c.e.idx}
    taken[c.u.idx]=true;assigned[key]=count+1;damage[key]=(damage[key] or 0)+c.hit
    log(string.format("OFFENSE U%d E%d(side%d) route=%d cleanup=%s reserved_damage=%d",c.u.idx,c.e.idx,c.e.side,c.cost,tostring(cleanup),damage[key]))
   end
  end
 end
 log(string.format("STRATEGY objective=%s capture_unit=%s primary=%s cleanup=%s",objective and (objective.x..","..objective.y) or "enemy-force",foot and tostring(foot.idx) or "none",primary and (primary.side..":"..primary.idx) or "none",tostring(cleanup)))
end
local function cs_refresh_order(k,en)
 local o=current_orders[k]
 if not o then return end
 if o.kind=="escort" then
  local foot=unit("MY",o.subject)
  if foot and foot.hp>0 then o.x,o.y=foot.x,foot.y else current_orders[k]=nil end
 elseif o.kind=="intercept" then
  for _,e in ipairs(en) do
   if e.side==o.foe_side and e.idx==o.foe_slot then o.x,o.y=e.x,e.y;return end
  end
  current_orders[k]=nil
  -- The previous target died earlier this turn: redistribute unacted forces now.
  log("REPLAN target destroyed before U"..k)
  current_routes={}
  cs_offensive_orders()
 end
end
cs_before_wait=function(k)
 local u=unit("MY",k)
 if not u or u.acted or r8(CTX)~=7 then return false end
 local candidates=cs_fire_candidates(false,k)
 if #candidates==0 then
  cs_fire_candidates(true,k)
  log("WAIT_REASON U"..k.." no safe stationary shot with current ammunition/range")
  return false
 end
 local e=candidates[1].enemy
 local ok,msg=pcall(attack,k,e)
 log(string.format("WAIT_FIRE U%d E%d(side%d) ok=%s %s",k,e.idx,e.side,tostring(ok),tostring(msg)))
 if not ok and (tostring(msg):find("did not return") or tostring(msg):find("mailbox busy")) then cs_recover_stuck(k) end
 return ok
end
local function cs_supply_handoff()
 local en=all_units("EN")
 for _,city in ipairs(current_my_cities) do
  local cell=CTX+0x3F60+city.x*4+city.y*0xC0
  if not city.capital and r8(cell)==cs_owner then
   local slot=r8(cell+1)-1
   local outgoing=slot>=0 and slot<64 and unit("MY",slot) or nil
   local maximum=outgoing and (db(outgoing.id) or {}).fuel or 0
   local ready=outgoing and not outgoing.acted and not cs_needs_supply(outgoing)
    and outgoing.hp>=outgoing.maxhp*0.9 and outgoing.fuel>=maximum*0.8
   if ready then
    local incoming,incoming_cost,best=nil,nil,-1e30
    for _,u in ipairs(all_units("MY")) do
     if u.idx~=slot and not u.acted and not cs_guard(u,en) and cs_needs_supply(u) then
      local _,cat,budget=vm_ctx(u.idx)
      local cost=vm_reach(u,cat,budget)[city.x..","..city.y]
      if cost and cost<=u.fuel then
       local priority=(1-u.hp/math.max(1,u.maxhp))*100+(u.fuel<=3 and 80 or 0)+(cs_armed(u) and 0 or 50)-cost
       if priority>best then incoming,incoming_cost,best=u,cost,priority end
      end
     end
    end
    if incoming then
     local _,cat,budget=vm_ctx(slot)
     local reach=vm_reach(outgoing,cat,budget)
     local bx,by,score=nil,nil,-1e30
     for key,cost in pairs(reach) do
      local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
      if r8(CTX+0x3F60+x*4+y*0xC0)==0 and cs_danger(outgoing,x,y,en)<outgoing.hp*0.6 then
       local value=tdef(terrain_at(x,y))-cost*4-hexd(x,y,city.x,city.y)*3
       if value>score then bx,by,score=x,y,value end
      end
     end
     if bx then
      local checkpoint=BASE.."states/"..SAVE_PREFIX.."_handoff.State"
      uninstall();savestate.save(checkpoint)
      local ok,msg=pcall(vm_land,slot,outgoing,bx,by,reach[bx..","..by])
      if ok then
       local filled,why=pcall(vm_land,incoming.idx,incoming,city.x,city.y,incoming_cost)
       log(string.format("SUPPLY_SWAP city=%d,%d outgoing=U%d incoming=U%d filled=%s %s",city.x,city.y,slot,incoming.idx,tostring(filled),tostring(why)))
       if not filled then
        savestate.load(checkpoint);restore_keyboard()
        log("SUPPLY_SWAP rolled back; city was not left vacant")
        return
       end
       -- Re-check opportunities after relocating, then mark each action exactly once.
       markacted(slot)
       if r8(CTX)==8 then return end
       if filled then markacted(incoming.idx) end
      else
       savestate.load(checkpoint);restore_keyboard()
       log("SUPPLY_SWAP failed and rolled back "..tostring(msg))
       return
      end
     else log("SUPPLY_SWAP U"..slot.." no safe exit; handoff postponed") end
    end
   end
  end
 end
end
