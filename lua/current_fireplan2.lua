-- Global stationary fire phase: evaluated before any unit receives movement orders.
local function cs_direct_power(u,e)
 local distance=hexd(u.x,u.y,e.x,e.y)
 local power=0
 for wa=0,3 do
  local slot=wslot(u.id,wa)
  if r8(U+u.idx*STRIDE-2+8+wa)>0 and distance<=r8(slot+13)
      and (r8(slot+15)~=4 or distance>=2) then
   power=math.max(power,r8(slot+8+tcls(e.id)))
  end
 end
 return power,distance
end
local function cs_fire_candidates(verbose,only_slot)
 local my,en=all_units("MY"),all_units("EN")
 local candidates={}
 for _,u in ipairs(my) do
  if not u.acted and u.hp>0 and (only_slot==nil or u.idx==only_slot) then
   local targets={}
   for _,e in ipairs(en) do
    local power,distance=cs_direct_power(u,e)
    if power>0 then
     local blocked=false -- Elimination dialogs are confirmed by the user.
     local hit=estimate(u,e,power)
     local kill=hit>=e.hp
     local loss=estimate(e,u,enemy_counter(e,u.id,distance),u.x,u.y)
     local safe=hit>0 and (loss<u.hp*0.6 or (kill and loss<u.hp))
     targets[#targets+1]=string.format('S%d:E%d hp=%d hit=%d loss=%d %s',e.side,e.idx,e.hp,hit,loss,
      blocked and "BLOCKED_FACTION_TRANSITION" or (safe and "fire" or "unsafe"))
     if not blocked and safe then
      local capital=terrain_at(e.x,e.y)==0x10
      local value=math.min(hit,e.hp)*20-loss*25+(kill and 250 or 0)+(capital and 600 or 0)
      if is_capturer(e.id) then value=value+40 end
      candidates[#candidates+1]={unit=u,enemy=e,value=value}
     end
    end
   end
   if verbose then
    local role=cs_guard(u,en) and "capital_guard" or (cs_needs_supply(u) and "resupply" or (is_capturer(u.id) and "capture" or "combat"))
    log(string.format("ATTACKMAP U%d role=%s targets=[%s]",u.idx,role,table.concat(targets,"; ")))
   end
  end
 end
 table.sort(candidates,function(a,b)
  if a.value~=b.value then return a.value>b.value end
  return a.unit.idx<b.unit.idx
 end)
 return candidates
end
local function cs_fire_phase()
 local failed={}
 local shots=0
 -- Re-read all units and re-score after every shot; never reserve stale estimated damage.
 for attempt=1,64 do
  local candidates=cs_fire_candidates(attempt==1)
  local selected=nil
  for _,candidate in ipairs(candidates) do
   if not failed[candidate.unit.idx] then selected=candidate;break end
  end
  if not selected then break end
  local u,e=selected.unit,selected.enemy
  log(string.format("FIREPLAN U%d target=S%d:E%d stationary=true capital=%s",u.idx,e.side,e.idx,tostring(terrain_at(e.x,e.y)==0x10)))
  local ok,msg=pcall(attack,u.idx,e)
  log("FIREPLAN result="..tostring(ok).." "..tostring(msg))
  if not ok then
   failed[u.idx]=true
   local why=tostring(msg)
   if why:find("did not return") or why:find("mailbox busy") then
    cs_recover_stuck(u.idx)
    if cs_stuck_aborted then return "FAIL STUCK during stationary fire; checkpoint retained" end
   end
  else shots=shots+1 end
  if r8(CTX)==8 or #all_units("EN")==0 then break end
 end
 log(string.format("FIREPLAN stationary_shots=%d; remaining units proceed to role planning",shots))
end
local function cs_log_roles()
 for _,u in ipairs(all_units("MY")) do
  local order=current_orders[u.idx]
  local role=u.acted and "action_complete" or (cs_guard(u,{}) and "capital_guard" or
   (cs_needs_supply(u) and "resupply" or (order and order.kind or "advance")))
  log(string.format("PLAN U%d role=%s goal=%s",u.idx,role,order and order.x..","..order.y or "none"))
 end
end
