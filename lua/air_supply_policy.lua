-- Independent air/logistics variant. ROM evidence: docs/AIR_SUPPLY_REVERSE.md.
local AIR_DB=0x08798A98
local air_spent={}
local air_active=nil
local air_in_logistics=false
local air_service_plan=nil
local air_fuel_safe=nil
local air_exhausted={}
local air_refill_at_base=nil
local air_drain=nil
local air_keep_towns_free=nil
-- Enemies this close (hexes) to the capital keep a capturer on garrison duty.
local AIR_CAPITAL_ALERT=8
-- Depot trucks relocating toward the front: truck slot -> {x,y}.
local air_depot_target={}
local function air_record(u) return U+(u.side or cs_player)*PB+u.idx*STRIDE-2 end
local function air_base(u) return AIR_DB+u.id*0x5C end
local function air_is_air(u) return r8(air_base(u)+4)==0 end
local function air_burn(u)
 return (r8(air_base(u)+8)&4)~=0 and math.floor(r8(air_base(u)+13)/2) or 0
end
air_before_acted=function(k,u)
 if air_is_air(u) and air_burn(u)>0 then
  -- Native waiting also burns flight fuel; do not let bridge waiting evade it.
  native_call(0x0801F078,{cs_player,k,0},2400)
  log("AIR_UPKEEP U"..k.." native fuel consumption")
 end
end
local air_old_candidates=cs_fire_candidates
cs_fire_candidates=function(verbose,only_slot)
 local out={}
 for _,c in ipairs(air_old_candidates(verbose,only_slot)) do
  if not air_is_air(c.unit) or (c.unit.fuel>air_burn(c.unit) and air_fuel_safe(c.unit,c.unit.x,c.unit.y,0)) then out[#out+1]=c end
 end
 return out
end
local function air_truck(u) return r8(air_base(u)+6)==7 end
local function air_stock(u)
 local n=0
 for w=0,3 do if r8(air_base(u)+0x27+w*16)==2 then n=n+r8(air_record(u)+8+w) end end
 return n
end
local function air_weapon_state(u)
 local has,armed,missing=false,false,false
 for w=0,3 do
  local b=air_base(u)+0x1C+w*16
  local capacity=r8(b+10)
  if capacity>0 and r8(b+11)~=2 and r8(b+11)~=3 then
   has=true
   local rounds=r8(air_record(u)+8+w)
   if rounds>0 then armed=true end
   if rounds==0 then missing=true end
  end
 end
 return has,armed,missing
end
local function air_wants(u)
 local _,armed,missing=air_weapon_state(u)
 local reserve=math.max(12,air_burn(u)*3)
 if air_is_air(u) and air_service_plan then
  local p=air_service_plan(u,u.x,u.y)
  if p then reserve=math.max(reserve,p.fuel+r8(air_base(u)+13)+air_burn(u)*2+1) end
 end
 return u.fuel<=reserve or missing or (air_truck(u) and air_stock(u)<=10)
end
local function air_facility(u,x,y)
 if r8(tb()+x*4+y*0xC0+2)~=cs_owner or (r8(tb()+x*4+y*0xC0+3)&2)~=0 then return false end
 local sub,t=r8(air_base(u)+6),terrain_at(x,y)
 if sub<8 then return t==0x10 or t==0x11 or t==0x14 end
 if sub<19 then return t==0x12 end
 return t==0x13
end
local air_old_supply=cs_supply_cell
local air_old_guard=cs_guard
cs_guard=function(u,en)
 -- Aircraft never garrison; a truck on the capital is a depot, not a guard.
 if air_is_air(u) or air_truck(u) or not air_old_guard(u,en) then return false end
 -- Live run: the paratrooper held a quiet capital for 17 turns while only two
 -- infantry were left to take towns. Release capturers until enemies close in.
 if is_capturer(u.id) and en and #en>0 then
  for _,e in ipairs(en) do
   if hexd(e.x,e.y,u.x,u.y)<=AIR_CAPITAL_ALERT then return true end
  end
  return false
 end
 return true
end
-- Non-capturers must not stop on towns they cannot take; infantry need them.
air_keep_towns_free=function(u,reach)
 if is_capturer(u.id) then return reach end
 local out={}
 for key,cost in pairs(reach) do
  local x,y=key:match("(%-?%d+),(%-?%d+)");x,y=tonumber(x),tonumber(y)
  if not (on_building(x,y) and r8(tb()+x*4+y*0xC0+2)~=cs_owner) then out[key]=cost end
 end
 return out
end
cs_supply_cell=function(x,y)
 if air_active then return air_facility(air_active,x,y) end
 return air_old_supply(x,y)
end
cs_needs_supply=function(u)
 local has,armed=air_weapon_state(u)
 return u.hp<=u.maxhp*0.7 or air_wants(u) or (has and not armed)
end
local air_old_ctx=vm_ctx
vm_ctx=function(k)
 local u,cat,budget=air_old_ctx(k)
 local remaining=math.max(0,r8(air_base(u)+13)-(air_spent[k] or 0))
 return u,cat,math.min(remaining,math.max(0,u.fuel-air_burn(u)-(air_is_air(u) and 1 or 0)))
end
local air_old_hold=cs_hold
cs_hold=function(u,en)
 air_active=u
 local hold,why=air_old_hold(u,en)
 air_active=nil
 return hold,why
end
local air_old_advance=current_advance
current_advance=function(k,u,reach,cat,en)
 air_active=u
 local result=air_old_advance(k,u,reach,cat,en)
 air_active=nil
 return result
end
local air_old_handoff=cs_supply_handoff
cs_supply_handoff=function()
 -- Legacy city swaps are ground-only; never send a helicopter to a town.
 local cities,needs=current_my_cities,cs_needs_supply
 current_my_cities={}
 for _,c in ipairs(cities) do if terrain_at(c.x,c.y)~=0x12 and terrain_at(c.x,c.y)~=0x13 then current_my_cities[#current_my_cities+1]=c end end
 cs_needs_supply=function(u) return not air_is_air(u) and needs(u) end
 local ok,why=pcall(air_old_handoff)
 current_my_cities,cs_needs_supply=cities,needs
 if not ok then error(why) end
end
local function air_move(u,x,y,cost)
 if x==u.x and y==u.y then return end
 assert(cost>=0 and cost<=u.fuel,"logistics movement exceeds fuel")
 vm_land(u.idx,u,x,y,cost)
 air_spent[u.idx]=(air_spent[u.idx] or 0)+cost
 current_routes={}
end
local function air_compatible(truck,u)
 -- Trucks reload at towns; truck-to-truck transfer only shuffles cargo (live run
 -- looped U39->U38 six times with fuel 50->50, stock 40->40).
 return truck.idx~=u.idx and air_truck(truck) and not air_truck(u) and air_stock(truck)>0
  and (r8(air_base(u)+8)&8)~=0 and (r8(air_record(truck)+7)&0x80)==0
  and (r8(air_record(u)+7)&0x80)==0
end
-- Fuel to reach a service point when every overnight stop must be survivable.
-- Live failure: enemies moved between the aircraft and its truck; every stop
-- toward the truck was unsafe, so the aircraft fled away and burned out.
-- Backward Dijkstra over (cell, moves already used this turn): aircraft may fly
-- over danger, but may only end a turn on an empty cell below the same danger
-- threshold the return move uses. Result: fuel[x,y] at the start of a turn.
local air_safe_cache,air_safe_sig={},nil
local function air_enemy_sig(en)
 local parts={}
 for _,e in ipairs(en) do parts[#parts+1]=e.x..","..e.y..","..e.hp end
 return table.concat(parts,";")
end
local function air_safe_field(u,goal,pref,cat)
 local en=all_units("EN")
 local sig=air_enemy_sig(en)
 if sig~=air_safe_sig then air_safe_cache,air_safe_sig={},sig end
 local key=table.concat({u.id,u.hp,u.x,u.y,goal.x,goal.y,pref,cat},",")
 if air_safe_cache[key] then return air_safe_cache[key] end
 local speed=math.max(1,r8(air_base(u)+13))
 local burn=air_burn(u)
 local limit=r8(air_base(u)+25)+speed
 local danger={}
 local function overnight(x,y)
  local k=x..","..y
  if danger[k]==nil then
   local occ=r8(CTX+0x3F60+x*4+y*0xC0)
   danger[k]=(occ==0 or (x==u.x and y==u.y)) and cs_danger(u,x,y,en)<u.hp*0.8
  end
  return danger[k]
 end
 local function passable(x,y)
  return x>=1 and x<=46 and y>=1 and y<=46 and vm_cost(terrain_at(x,y),cat)>0
   and r8(CTX+0x3F60+x*4+y*0xC0)<=1
 end
 local dist,buckets,top={},{},0
 local function push(x,y,m,d)
  local k=x..","..y..","..m
  if d<=limit and (not dist[k] or d<dist[k]) then
   dist[k]=d
   buckets[d]=buckets[d] or {}
   table.insert(buckets[d],{x,y,m})
   if d>top then top=d end
  end
 end
 for y=1,46 do for x=1,46 do
  if hexd(x,y,goal.x,goal.y)==pref and passable(x,y) and overnight(x,y) then
   for m=0,speed do push(x,y,m,burn) end
  end
 end end
 local d=0
 while d<=top do
  local list=buckets[d]
  if list then
   for _,s in ipairs(list) do
    local x,y,m=s[1],s[2],s[3]
    if dist[x..","..y..","..m]==d then
     local tc=vm_cost(terrain_at(x,y),cat)
     if m-tc>=0 then
      for _,n in ipairs(vm_nbrs(x,y)) do
       if passable(n[1],n[2]) then push(n[1],n[2],m-tc,d+tc) end
      end
     end
     if m==0 and overnight(x,y) then
      for m2=1,speed do push(x,y,m2,d+burn) end
     end
    end
   end
  end
  d=d+1
 end
 local field={}
 for y=1,46 do for x=1,46 do
  local f=dist[x..","..y..",0"]
  if f then field[x..","..y]=f end
 end end
 air_safe_cache[key]=field
 return field
end
air_service_plan=function(u,x,y,sortie,anchored)
 local cat=r8(air_base(u)+5)
 local speed=math.max(1,r8(air_base(u)+13))
 local best=nil
 local pool,burn=0,0
 for _,a in ipairs(all_units("MY")) do
  if air_truck(a) then pool=pool+air_stock(a) elseif air_is_air(a) then burn=burn+air_burn(a) end
 end
 local scarce=pool<burn*3
 local function consider(goal,pref,truck,delay,refill)
  local distance=current_route(goal,pref,cat)[x..","..y]
  if distance then
   local turns=math.max(math.ceil(distance/speed),delay or 0)
   local fuel=distance+turns*air_burn(u)
   if air_is_air(u) then
    -- A route the enemy has cut is no service route at all.
    local safe=air_safe_field(u,goal,pref,cat)[x..","..y]
    if not safe then return end
    fuel=math.max(fuel,safe+math.max(0,(delay or 0)-math.ceil(distance/speed))*air_burn(u))
   end
   if not best or fuel<best.fuel then best={x=goal.x,y=goal.y,pref=pref,distance=distance,fuel=fuel,truck=truck,refill=refill} end
  end
 end
 for _,truck in ipairs(all_units("MY")) do
  -- Anchored plans only trust trucks holding a town: a field truck can be cut off
  -- by the enemy's next move, a depot behind the line cannot be bypassed so easily.
  local held=air_facility(truck,truck.x,truck.y)
  if air_compatible(truck,u) and not (sortie and scarce) and (held or not anchored) then consider(truck,1,truck.idx) end
  -- Empty returning trucks are future service points, with reload travel time.
  -- Do not pretend a nearly empty truck can fund the whole fleet's next sortie.
  if air_truck(truck) and not anchored and (r8(air_base(u)+8)&8)~=0
     and memory.read_u32_le(CTX+0x24+cs_player*12)>0 and (air_stock(truck)<=10 or scarce) then
   local tcat=r8(air_base(truck)+5)
   local bestcity,bestcost=nil,1e30
   for _,city in ipairs(current_my_cities) do
    local occ=r8(CTX+0x3F60+city.x*4+city.y*0xC0)
    if air_facility(truck,city.x,city.y) and (not city.capital or occ==0 or (city.x==truck.x and city.y==truck.y)) then
     local cost=current_route(city,0,tcat)[truck.x..","..truck.y]
     if cost and cost<=truck.fuel and cost<bestcost then bestcity,bestcost=city,cost end
    end
   end
   if bestcity then
    local delay=math.ceil(bestcost/math.max(1,r8(air_base(truck)+13)))
    consider(bestcity,1,truck.idx,delay,true)
   end
  end
 end
 for _,c in ipairs(current_my_cities) do
  if air_facility(u,c.x,c.y) then consider(c,0,nil) end
 end
 return best
end
air_fuel_safe=function(u,x,y,cost)
 if not air_is_air(u) then return true end
 -- With a depot in place, every sortie must keep fuel to get home to it safely.
 local service
 if air_service_plan(u,u.x,u.y,true,true) then service=air_service_plan(u,x,y,true,true)
 else service=air_service_plan(u,x,y,true) end
 if not service then return false end
 return u.fuel-cost-air_burn(u)>=service.fuel+air_burn(u)+1
end
local function air_urgency(u)
 if not air_is_air(u) then return 0 end
 local service=air_service_plan(u,u.x,u.y)
 local margin=u.fuel-(service and service.fuel or 0)
 return 10000-margin/math.max(1,air_burn(u))*1000
end
local air_old_reach=vm_reach
vm_reach=function(u,cat,budget)
 local reach=air_old_reach(u,cat,budget)
 if air_is_air(u) and not air_in_logistics then
  local filtered={[u.x..","..u.y]=0}
  for key,cost in pairs(reach) do
   local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
   if air_fuel_safe(u,x,y,cost) then filtered[key]=cost end
  end
  return filtered
 end
 return reach
end
local function air_transfer(truck,u)
 assert(hexd(truck.x,truck.y,u.x,u.y)==1 and air_compatible(truck,u),"invalid supply pair")
 assert(not u.acted,"recipient already acted")
 local ur,tr=air_record(u),air_record(truck)
 local before_fuel,before_stock,us,ts=u.fuel,air_stock(truck),r8(ur+7),r8(tr+7)
 -- Native supply core: consumes real cargo, fuel first then ammunition; no free refill.
 native_call(0x08022388,{cs_player,truck.idx,ur,air_base(u)},1200)
 assert(r8(ur+7)==us and r8(tr+7)==ts,"native supply unexpectedly consumed an action")
 local now=unit("MY",u.idx)
 log(string.format("AIR_SUPPLY U%d -> U%d fuel=%d->%d stock=%d->%d action_preserved=true",truck.idx,u.idx,before_fuel,now.fuel,before_stock,air_stock(unit("MY",truck.idx))))
 -- A city truck is a paid, reusable depot, not a one-load delivery vehicle.
 air_refill_at_base(unit("MY",truck.idx),true)
 return now
end
air_refill_at_base=function(u,force)
 if not u.acted and air_facility(u,u.x,u.y) and memory.read_u32_le(CTX+0x24+cs_player*12)>0 then
  if force or u.fuel<r8(air_base(u)+0x19) or air_wants(u) then
   native_call(0x08021F78,{cs_player,u.idx},2400)
   log("AIR_BASE_REFILL U"..u.idx.." native funds/cargo accounting")
  end
 end
end
local function air_resupply_adjacent()
 local receivers=all_units("MY")
 table.sort(receivers,function(a,b) return air_urgency(a)>air_urgency(b) end)
 for _,u in ipairs(receivers) do
  if not u.acted and air_wants(u) then
   for _,truck in ipairs(all_units("MY")) do
    if hexd(truck.x,truck.y,u.x,u.y)==1 and air_compatible(truck,u) then
     for cycle=1,4 do
      local before=u.fuel+cs_ammo_total(u.idx)
      u=air_transfer(unit("MY",truck.idx),u)
      local donor=unit("MY",truck.idx)
      if not air_wants(u) or not air_facility(donor,donor.x,donor.y)
         or not air_compatible(donor,u) or u.fuel+cs_ammo_total(u.idx)<=before then break end
     end
     if not air_wants(u) then break end
    end
   end
  end
 end
end
local function air_goal(u,en)
 if cs_campaign.objective then return cs_campaign.objective end
 local best,score=nil,1e30
 for _,e in ipairs(en) do
  local d=hexd(u.x,u.y,e.x,e.y)
  if d<score then best,score=e,d end
 end
 return best or u
end
-- A rested, full-strength ground unit may step out of a town so a truck can reload.
-- Capitals keep their garrison; units that still need the town keep it.
local function air_vacatable(city,u)
 local cell=CTX+0x3F60+city.x*4+city.y*0xC0
 if city.capital or r8(cell)~=cs_owner then return nil end
 local o=unit("MY",r8(cell+1)-1)
 if not o or o.idx==u.idx or o.acted or air_is_air(o) or air_truck(o) or cs_needs_supply(o) then return nil end
 if o.hp<o.maxhp*0.9 or o.fuel<r8(air_base(o)+25)*0.8 then return nil end
 return o
end
local function air_vacate(o,city,en)
 local _,cat,budget=vm_ctx(o.idx)
 local reach=vm_reach(o,cat,budget)
 local bx,by,bc,score=nil,nil,nil,-1e30
 for key,cost in pairs(reach) do
  local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
  if r8(CTX+0x3F60+x*4+y*0xC0)==0 and cs_danger(o,x,y,en)<o.hp*0.6 then
   local value=tdef(terrain_at(x,y))-cost*4-hexd(x,y,city.x,city.y)*3
   if value>score then bx,by,bc,score=x,y,cost,value end
  end
 end
 if not bx then return false end
 air_move(o,bx,by,bc)
 markacted(o.idx)
 log(string.format("AIR_DEPOT_SWAP U%d leaves %d,%d for %d,%d",o.idx,city.x,city.y,bx,by))
 return true
end
local function air_return_to_base(u,en)
 local _,cat,budget=vm_ctx(u.idx)
 local reach=vm_reach(u,cat,budget)
 -- Every free depot is held: ask a rested town occupant to make room this turn.
 if air_truck(u) then
  local free=false
  for _,city in ipairs(current_my_cities) do
   local occ=r8(CTX+0x3F60+city.x*4+city.y*0xC0)
   if air_facility(u,city.x,city.y) and reach[city.x..","..city.y]
      and (occ==0 or (city.x==u.x and city.y==u.y)) then free=true end
  end
  if not free then
   for _,city in ipairs(current_my_cities) do
    local cost=reach[city.x..","..city.y]
    local o=cost and air_facility(u,city.x,city.y) and cs_danger(u,city.x,city.y,en)<u.hp*0.6 and air_vacatable(city,u)
    if o and air_vacate(o,city,en) then
     air_move(u,city.x,city.y,cost)
     log(string.format("AIR_TO_DEPOT U%d at=%d,%d on_facility=true",u.idx,city.x,city.y))
     air_refill_at_base(unit("MY",u.idx))
     return true
    end
   end
  end
 end
 local bx,by,bc,best=nil,nil,nil,-1e30
 for _,city in ipairs(current_my_cities) do
  -- A held depot cannot be entered; approach it only if its occupant can make room.
  local occ=r8(CTX+0x3F60+city.x*4+city.y*0xC0)
  if air_facility(u,city.x,city.y) and (occ==0 or (city.x==u.x and city.y==u.y) or (air_truck(u) and air_vacatable(city,u))) then
   local route=current_route(city,0,cat)
   local initial=route[u.x..","..u.y]
   local required=initial and (initial+math.ceil(initial/math.max(1,r8(air_base(u)+13)))*air_burn(u)) or nil
   if required and required+1<=u.fuel then
    for key,cost in pairs(reach) do
     local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
     if route[key] and (r8(CTX+0x3F60+x*4+y*0xC0)==0 or (x==u.x and y==u.y))
        and cs_danger(u,x,y,en)<u.hp*0.6 then
      local score=-route[key]*30-cost
      if score>best then bx,by,bc,best=x,y,cost,score end
     end
    end
   end
  end
 end
 if bx then
  air_move(u,bx,by,bc)
  log(string.format("AIR_TO_DEPOT U%d at=%d,%d on_facility=%s",u.idx,bx,by,tostring(air_facility(u,bx,by))))
  air_refill_at_base(unit("MY",u.idx))
  return true
 end
 log("AIR_NO_BASE_ROUTE U"..u.idx.." fuel="..u.fuel)
 return false
end
-- Native turn change tops up every eligible unit next to a truck, even nearly
-- full ones (live run: 40 cargo -> 12 in one turn, no AIR_SUPPLY). Count them.
air_drain=function(truck,x,y)
 local n=0
 for _,nb in ipairs(vm_nbrs(x,y)) do
  local occ=r8(CTX+0x3F60+nb[1]*4+nb[2]*0xC0)
  local o=occ==cs_owner and unit("MY",r8(CTX+0x3F60+nb[1]*4+nb[2]*0xC0+1)-1) or nil
  if o and o.idx~=truck.idx and not air_truck(o) and (r8(air_base(o)+8)&8)~=0 and not air_wants(o) then n=n+1 end
 end
 return n
end
-- Move a truck one turn along the ground route to goal; reload if it arrives.
local function air_drive_to(truck,goal,en)
 local _,cat,budget=vm_ctx(truck.idx)
 local reach=vm_reach(truck,cat,budget)
 local route=current_route(goal,0,cat)
 local bx,by,bc,score=nil,nil,nil,1e30
 for key,cost in pairs(reach) do
  local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
  if route[key] and (r8(CTX+0x3F60+x*4+y*0xC0)==0 or (x==truck.x and y==truck.y))
     and cs_danger(truck,x,y,en)<truck.hp*0.5 then
   local value=route[key]*30+cost+air_drain(truck,x,y)*15
   if value<score then bx,by,bc,score=x,y,cost,value end
  end
 end
 if not bx then return false end
 air_move(truck,bx,by,bc)
 if bx==goal.x and by==goal.y then air_refill_at_base(unit("MY",truck.idx)) end
 return true
end
-- Where the fighting is: the campaign objective, else the nearest enemy.
local function air_front(truck,en)
 local o=cs_campaign.objective
 if type(o)=="table" and o.x then return o end
 local best,d=nil,1e30
 for _,e in ipairs(en) do
  local h=hexd(truck.x,truck.y,e.x,e.y)
  if h<d then best,d=e,h end
 end
 return best
end
-- A free, safe town at least 4 hexes nearer the front and within 3 turns' drive.
-- Live run: the depot stayed at (11,31) all game while the front moved past
-- y25, so every helicopter sortie was capped by the return leg.
local function air_forward_depot(truck,en)
 local front=air_front(truck,en)
 if not front then return nil end
 local here=hexd(truck.x,truck.y,front.x,front.y)
 local _,cat=vm_ctx(truck.idx)
 local speed=math.max(1,r8(air_base(truck)+13))
 local best,bd=nil,here-4
 for _,city in ipairs(current_my_cities) do
  if air_facility(truck,city.x,city.y) and r8(CTX+0x3F60+city.x*4+city.y*0xC0)==0 then
   local d=hexd(city.x,city.y,front.x,front.y)
   local cost=current_route(city,0,cat)[truck.x..","..truck.y]
   if d<=bd and cost and cost<=truck.fuel and math.ceil(cost/speed)<=3
      and cs_danger(truck,city.x,city.y,en)<truck.hp*0.5 then best,bd=city,d end
  end
 end
 return best
end
-- Aircraft already flying back to this truck keep it in place.
local function air_depot_busy(truck)
 for _,u in ipairs(all_units("MY")) do
  if air_is_air(u) and air_wants(u) then
   local p=air_service_plan(u,u.x,u.y)
   if p and p.truck==truck.idx then return true end
  end
 end
 return false
end
-- Turns for a ground unit to reach a free facility it can reload at; nil if none.
local function air_depot_eta(u)
 local _,cat=vm_ctx(u.idx)
 local best=nil
 for _,city in ipairs(current_my_cities) do
  local occ=r8(CTX+0x3F60+city.x*4+city.y*0xC0)
  if air_facility(u,city.x,city.y) and (occ==0 or (city.x==u.x and city.y==u.y)) then
   local cost=current_route(city,0,cat)[u.x..","..u.y]
   if cost and (not best or cost<best) then best=cost end
  end
 end
 return best and math.ceil(best/math.max(1,r8(air_base(u)+13))) or nil
end
local function air_logistics_work()
 air_spent={}
 air_exhausted={}
 -- Include actual airfields/ports; the per-unit facility predicate filters them.
 for y=1,46 do for x=1,46 do
  local t=terrain_at(x,y)
  if (t==0x12 or t==0x13) and r8(tb()+x*4+y*0xC0+2)==cs_owner then
   current_my_cities[#current_my_cities+1]={x=x,y=y,capital=false}
  end
 end end
 for _,u in ipairs(all_units("MY")) do if not u.acted then air_refill_at_base(u) end end
 air_resupply_adjacent()
 local en=all_units("EN")
 local assigned_receivers={}
 local depot_held=false
 for _,t in ipairs(all_units("MY")) do
  if air_truck(t) and (air_facility(t,t.x,t.y) or air_depot_target[t.idx]) then depot_held=true end
 end
 for _,u in ipairs(all_units("MY")) do
  if air_is_air(u) then
   local p=air_service_plan(u,u.x,u.y)
   log(string.format("AIR_STATUS U%d fuel=%d max=%d upkeep=%d service_fuel=%s needs=%s",u.idx,u.fuel,r8(air_base(u)+25),air_burn(u),p and tostring(p.fuel) or "unreachable",tostring(air_wants(u))))
  end
 end
 for _,truck in ipairs(all_units("MY")) do
  if air_truck(truck) and not truck.acted and not cs_guard(truck,en) then
   if air_stock(truck)<=10 or truck.fuel<=12 then
    air_return_to_base(truck,en)
   else
    local _,cat,budget=vm_ctx(truck.idx)
    local reach=vm_reach(truck,cat,budget)
    local depot=air_facility(truck,truck.x,truck.y) and memory.read_u32_le(CTX+0x24+cs_player*12)>0
     and cs_danger(truck,truck.x,truck.y,en)<truck.hp*0.5
    if depot then reach={[truck.x..","..truck.y]=0} end
    local chosen,best=nil,-1e30
    for _,u in ipairs(all_units("MY")) do
     if not u.acted and air_wants(u) and air_compatible(truck,u) then
      local _,ucat,ubudget=vm_ctx(u.idx)
      -- Leave airborne recipients enough fuel for native per-action upkeep.
      ubudget=math.min(ubudget,math.max(0,u.fuel-air_burn(u)-1))
      local ur=vm_reach(u,ucat,ubudget)
      local goal=air_goal(u,en)
      for key,cost in pairs(reach) do
       local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
       if r8(CTX+0x3F60+x*4+y*0xC0)==0 or (x==truck.x and y==truck.y) then
        if cs_danger(truck,x,y,en)<truck.hp*0.55 then
         for _,n in ipairs(vm_nbrs(x,y)) do
          local xx,yy=n[1],n[2];local uk=xx..","..yy
          local uc=ur[uk]
          if uc and xx>=1 and xx<=46 and yy>=1 and yy<=46
             and (r8(CTX+0x3F60+xx*4+yy*0xC0)==0 or (xx==u.x and yy==u.y))
             and cs_danger(u,xx,yy,en)<u.hp*0.7 then
           local progress=hexd(u.x,u.y,goal.x,goal.y)-hexd(xx,yy,goal.x,goal.y)
           local priority=air_urgency(u)
           local score=priority+progress*12-cost*3-uc*2
           if score>best then chosen,best={u=u,x=x,y=y,c=cost,ux=xx,uy=yy,uc=uc},score end
          end
         end
        end
       end
      end
     end
    end
    if chosen then
     -- Both endpoints were checked empty before either move; never stack units.
     air_move(truck,chosen.x,chosen.y,chosen.c)
     air_move(chosen.u,chosen.ux,chosen.uy,chosen.uc)
     air_transfer(unit("MY",truck.idx),unit("MY",chosen.u.idx))
     assigned_receivers[chosen.u.idx]=true
     log(string.format("LOGISTICS rendezvous truck=U%d receiver=U%d remaining_move=%d",truck.idx,chosen.u.idx,select(3,vm_ctx(chosen.u.idx))))
     air_resupply_adjacent()
    else
     -- No rendezvous this turn: follow a needy aircraft along a ground route.
     local target,d=nil,1e30
     for _,u in ipairs(all_units("MY")) do
      if air_is_air(u) and not u.acted and not assigned_receivers[u.idx] and air_compatible(truck,u) then
       local dist=hexd(truck.x,truck.y,u.x,u.y)-air_urgency(u)/100
       if dist<d then target,d=u,dist end
      end
     end
     -- Trucks crawl (~2 hexes/turn on rough ground) while helicopters fly 6.
     -- A nearby city lets one truck serve many aircraft with paid reloads.
     -- One depot is enough; the other trucks keep following the front.
     local eta=(not depot and not depot_held) and air_depot_eta(truck) or nil
     local moving=air_depot_target[truck.idx]
     if moving and truck.x==moving.x and truck.y==moving.y then air_depot_target[truck.idx]=nil;moving=nil end
     if moving and (truck.x~=moving.x or truck.y~=moving.y) and air_facility(truck,moving.x,moving.y)
        and r8(CTX+0x3F60+moving.x*4+moving.y*0xC0)==0 and air_drive_to(truck,moving,en) then
      local now=unit("MY",truck.idx)
      if now.x==moving.x and now.y==moving.y then air_depot_target[truck.idx]=nil end
      log(string.format("AIR_DEPOT_FORWARD U%d to=%d,%d at=%d,%d",truck.idx,moving.x,moving.y,now.x,now.y))
     elseif moving and (truck.x~=moving.x or truck.y~=moving.y) then
      -- Target lost (occupied, recaptured or unreachable): stop relocating.
      air_depot_target[truck.idx]=nil
      log(string.format("AIR_DEPOT_FORWARD U%d abandon %d,%d",truck.idx,moving.x,moving.y))
     elseif depot and not air_depot_busy(truck) and air_forward_depot(truck,en) then
      local city=air_forward_depot(truck,en)
      air_depot_target[truck.idx]={x=city.x,y=city.y}
      air_drive_to(truck,city,en)
      local now=unit("MY",truck.idx)
      if now.x==city.x and now.y==city.y then air_depot_target[truck.idx]=nil end
      log(string.format("AIR_DEPOT_FORWARD U%d from=%d,%d to=%d,%d at=%d,%d",truck.idx,truck.x,truck.y,city.x,city.y,now.x,now.y))
     elseif eta and eta<=2 and air_return_to_base(truck,en) then
      depot_held=true
      log(string.format("AIR_STATION U%d depot_eta=%d hold city as service point",truck.idx,eta))
     elseif target and not depot then
      assigned_receivers[target.idx]=true
      local route=current_route(target,1,cat)
      local bx,by,bc,score=nil,nil,nil,1e30
      for key,cost in pairs(reach) do
       local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
       if r8(CTX+0x3F60+x*4+y*0xC0)==0 and cs_danger(truck,x,y,en)<truck.hp*0.5 then
        -- If aircraft is over terrain inaccessible to trucks, advance toward a
        -- reachable corridor instead of discarding the entire support mission.
        local value=(route[key] or hexd(x,y,target.x,target.y)*2)*10+cost+air_drain(truck,x,y)*15
        if value<score then bx,by,bc,score=x,y,cost,value end
       end
      end
      if bx then
       air_move(truck,bx,by,bc)
       log(string.format("AIR_TRUCK_FOLLOW U%d receiver=U%d at=%d,%d distance=%d stock=%d",truck.idx,target.idx,bx,by,hexd(bx,by,target.x,target.y),air_stock(truck)))
      else log("AIR_TRUCK_BLOCKED U"..truck.idx.." no safe ground advance") end
     elseif depot then log("AIR_DEPOT U"..truck.idx.." hold city for repeated paid reloads") end
    end
   end
   -- Keep the truck unacted through all supply/paid-reload cycles this round.
  end
 end
 -- Fuel-critical aircraft return to a real airfield; no town-healing assumption.
 for _,u in ipairs(all_units("MY")) do
  if air_is_air(u) and not u.acted and air_wants(u) then
   if air_return_to_base(u,en) then
    log("AIR_RETURN U"..u.idx.." remaining_move="..select(3,vm_ctx(u.idx)))
   else
    -- Fly back toward the actual truck, including multi-turn upkeep in reachability.
    local service=air_service_plan(u,u.x,u.y)
    if service and service.truck and service.fuel+1<u.fuel then
     local _,cat,budget=vm_ctx(u.idx)
     -- Follow the survivable corridor, not the straight line through the enemy.
     local route=air_safe_field(u,service,service.pref,cat)
     local reach=vm_reach(u,cat,budget)
     local bx,by,bc,best=nil,nil,nil,1e30
     for key,cost in pairs(reach) do
      local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
      if route[key] and (r8(CTX+0x3F60+x*4+y*0xC0)==0 or (x==u.x and y==u.y)) and cs_danger(u,x,y,en)<u.hp*0.8 then
       local value=route[key]*30+cost
       if value<best then bx,by,bc,best=x,y,cost,value end
      end
     end
     if bx then
      air_move(u,bx,by,bc)
      air_resupply_adjacent()
      u=unit("MY",u.idx)
      log(string.format("AIR_RETURN_TRUCK U%d truck=U%d at=%d,%d fuel=%d",u.idx,service.truck,u.x,u.y,u.fuel))
     end
    end
    u=unit("MY",u.idx)
    if u and u.fuel<=air_burn(u) then
     -- Leave this aircraft to native end-of-turn fuel accounting. Other units
     -- may win first; a stranded aircraft must not halt the entire army.
     air_exhausted[u.idx]=true
     log("AIR_STRANDED U"..u.idx.." fuel="..u.fuel.."; defer native fuel resolution until other units finish")
    end
    if u and not air_exhausted[u.idx] and air_wants(u) then
     markacted(u.idx);log("AIR_WAIT_SUPPLY U"..u.idx.." fuel budget exhausted for a safe sortie")
    end
   end
  end
 end
 for _,truck in ipairs(all_units("MY")) do
  if air_truck(truck) and not truck.acted then markacted(truck.idx) end
 end
end
local function air_logistics_round()
 air_in_logistics=true
 local ok,result=pcall(air_logistics_work)
 air_in_logistics=false
 if not ok then error(result) end
 return result
end
