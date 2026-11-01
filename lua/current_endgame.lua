-- Endgame allocation and diagnostics; appended inside autoclear after current_tactics.
local current_progress={stalled=0,hp=nil,cities=0,resources={}}
local function current_ranges(u,e)
 local ranges={}
 local maximum=0
 for wa=0,3 do
  if uammo(u.idx,wa)>0 then maximum=math.max(maximum,math.min(46,r8(wslot(u.id,wa)+13))) end
 end
 for d=maximum,1,-1 do if my_best(u,d,e.id)>0 then ranges[#ranges+1]=d end end
 return ranges
end
local function current_solution(u,e)
 local direct=hexd(u.x,u.y,e.x,e.y)
 if my_best(u,direct,e.id)>0 then return {distance=0,pref=direct} end
 if u.fuel<=0 or not current_has_ammo(u) then return nil end
 local _,cat=vm_ctx(u.idx)
 local best=nil
 for _,pref in ipairs(current_ranges(u,e)) do
  local distance=current_route(e,pref,cat)[u.x..","..u.y]
  if distance and distance<=u.fuel and (not best or distance<best.distance) then best={distance=distance,pref=pref} end
 end
 return best
end
local function current_finish_plan()
 local my,en=all_units("MY"),all_units("EN")
 local hp,cities,gained=0,0,false
 for _,e in ipairs(en) do hp=hp+e.hp end
 for y=1,46 do for x=1,46 do if current_friendly_city(x,y) then cities=cities+1 end end end
 for _,u in ipairs(my) do
  local old=current_progress.resources[u.idx]
  if old and (u.hp>old.hp or u.fuel>old.fuel) then gained=true end
  current_progress.resources[u.idx]={hp=u.hp,fuel=u.fuel}
 end
 if current_progress.hp and hp>=current_progress.hp and cities<=current_progress.cities and not gained then
  current_progress.stalled=current_progress.stalled+1
 else current_progress.stalled=0 end
 current_progress.hp,current_progress.cities=hp,cities
 if #en>3 and current_progress.stalled<3 then return end
 -- Recompute paths rather than keeping a stale siege/capture assignment forever.
 current_routes={}
 local assigned,solutions=0,0
 for _,e in ipairs(en) do
  local candidates={}
  for _,u in ipairs(my) do
   if not u.acted and u.hp>0 and current_guard(u,en) and my_best(u,hexd(u.x,u.y,e.x,e.y),e.id)>0 then
    solutions=solutions+1 -- The stationary garrison may still win by firing from its post.
   elseif not u.acted and u.hp>0 and not current_guard(u,en) then
    local solution=current_solution(u,e)
    if solution then
     solutions=solutions+1
     if not is_capturer(u.id) then candidates[#candidates+1]={u=u,solution=solution} end
    end
   end
  end
  table.sort(candidates,function(a,b) return a.solution.distance<b.solution.distance end)
  for i=1,math.min(3,#candidates) do
   local c=candidates[i]
   if not current_orders[c.u.idx] or current_orders[c.u.idx].kind~="cleanup" then
    current_orders[c.u.idx]={x=e.x,y=e.y,pref=c.solution.pref,value=-150,kind="cleanup",enemy=e.idx,path_cost=c.solution.distance}
    assigned=assigned+1
    log(string.format("CLEANUP U%d E%d path_cost=%d fuel=%d range=%d",c.u.idx,e.idx,c.solution.distance,c.u.fuel,c.solution.pref))
   end
  end
  if #candidates==0 then
   log(string.format("BLOCKED E%d at=%d,%d no armed non-garrison unit has a fuel-feasible firing path",e.idx,e.x,e.y))
  end
 end
 local capturers=0
 for _,u in ipairs(my) do if is_capturer(u.id) and u.hp>0 then capturers=capturers+1 end end
 log(string.format("ENDGAME enemies=%d firing_solutions=%d cleanup_units=%d capturers=%d stalled=%d",#en,solutions,assigned,capturers,current_progress.stalled))
 if capturers==0 then log("BLOCKED no surviving capture unit; capital occupation victory unavailable") end
 if current_progress.stalled>=3 then
  uninstall()
  savestate.save(BASE.."states/"..SAVE_PREFIX.."_stalled.State")
  -- Preserve terrain and unit data for offline diagnosis of the actual remaining enemy.
  local cells={}
  for y=0,47 do for x=0,47 do
   cells[#cells+1]=string.format('[%d,%d,%d,%d]',x,y,terrain_at(x,y),r8(tb()+x*4+y*0xC0+2))
  end end
  writefile(RUN.."stalled_map.json",'{"columns":["x","y","terrain","owner"],"cells":['..table.concat(cells,",")..']}')
  log("STALEMATE checkpoint saved; target paths and resources reassessed")
 end
 if current_progress.stalled>=6 and solutions==0 and capturers==0 then
  return "NO_CURRENT_PLAN: no fuel-feasible armed firing path and no surviving capture unit; stalled checkpoint retained"
 end
end
