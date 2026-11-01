-- Round deadline state shared by the multi-faction policy. No game-state writes.
local cs_clock={turn=0,limit=nil,left=nil,urgency=0,stalled=0}
local cs_clock_previous={hp=nil,cities=0,units={}}
local function cs_update_clock()
 local scenario=memory.read_u32_le(CTX+0x14)
 local limit=nil
 if scenario>=0x02000000 and scenario<0x0A000000 then
  local value=r8(scenario+0x79)
  if value>=1 and value<=255 then limit=value end
 end
 local turn=r8(CTX+0x20)
 local left=limit and math.max(0,limit-turn+1) or nil
 local urgency=left and (left<=5 and 2 or (left<=10 and 1 or 0.25)) or 0
 local hp,cities,gained,mobile,capturers=0,0,false,0,0
 local my,en=all_units("MY"),all_units("EN")
 for _,e in ipairs(en) do hp=hp+e.hp end
 for _,u in ipairs(my) do
  if u.fuel>0 then mobile=mobile+1 end
  if is_capturer(u.id) then capturers=capturers+1 end
  local old=cs_clock_previous.units[u.idx]
  if old and (u.hp>old.hp or u.fuel>old.fuel) then gained=true end
  cs_clock_previous.units[u.idx]={hp=u.hp,fuel=u.fuel}
 end
 for y=1,46 do for x=1,46 do
  if on_building(x,y) and r8(tb()+x*4+y*0xC0+2)==player_side()+1 then cities=cities+1 end
 end end
 local stalled=cs_clock_previous.hp and hp>=cs_clock_previous.hp and cities<=cs_clock_previous.cities and not gained
 cs_clock.stalled=stalled and cs_clock.stalled+1 or 0
 cs_clock_previous.hp,cs_clock_previous.cities=hp,cities
 cs_clock.turn,cs_clock.limit,cs_clock.left,cs_clock.urgency=turn,limit,left,urgency
 log(string.format("EVAL turn=%d limit=%s left=%s urgency=%.2f my=%d enemies=%d enemy_hp=%d mobile=%d capturers=%d stalled=%d",
  turn,tostring(limit),tostring(left),urgency,#my,#en,hp,mobile,capturers,cs_clock.stalled))
end
local function cs_time_cost(goal,remaining,movement,same)
 local eta=remaining==0 and 1 or 1+math.ceil(remaining/math.max(1,movement))
 if goal.kind=="resupply" then eta=eta+1 end -- Include the round boundary that refills it.
 -- Offensive progress still matters when the full trip exceeds the deadline.
 -- Keep the strict cutoff for capture/refill promises, not for pursuing an enemy.
 if cs_clock.left and eta>cs_clock.left and goal.kind~="engage" and goal.kind~="intercept" then return -10000,false,eta end
 local penalty=eta*cs_clock.urgency*18
 if same and remaining>0 then penalty=penalty+cs_clock.urgency*(60+cs_clock.stalled*20) end
 if goal.kind=="capture" and terrain_at(goal.x,goal.y)==0x10 then penalty=penalty-cs_clock.urgency*160 end
 return -penalty,true,eta
end
