"""Offline Lua checks using BizHawk's bundled Lua DLL; never touches a live game."""
import ctypes
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from tools.current_tactics import apply_current_tactics
from tools.native_attack import LUA

def main():
    dll=ctypes.CDLL(str(ROOT/'tools/dll/lua54.dll'))
    dll.luaL_newstate.restype=ctypes.c_void_p
    dll.luaL_openlibs.argtypes=[ctypes.c_void_p]
    dll.luaL_loadbufferx.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p,ctypes.c_char_p]
    dll.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ctypes.c_void_p]
    dll.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.POINTER(ctypes.c_size_t)]
    dll.lua_tolstring.restype=ctypes.c_char_p
    dll.lua_close.argtypes=[ctypes.c_void_p]
    def check(source, execute=False):
        state=dll.luaL_newstate()
        try:
            dll.luaL_openlibs(state)
            data=source.encode('utf-8')
            status=dll.luaL_loadbufferx(state,data,len(data),b'offline_tactics',None)
            if status==0 and execute:
                status=dll.lua_pcallk(state,0,0,0,0,None)
            if status:
                raise AssertionError(dll.lua_tolstring(state,-1,None).decode('utf-8','replace'))
        finally:
            dll.lua_close(state)
    source=apply_current_tactics(LUA,ROOT)
    check(source)
    prefix=(ROOT/'lua/usa_ai_state.lua').read_text(encoding='utf-8').split('-- ============ 启动 ============')[0]
    check(prefix+source)
    assert not re.search(r'\b(?:ny|y)<=34\b|for (?:y|yy)=1,34 do',source)
    # Exercise the real movement search around the former row-34 cutoff.
    movement=source[source.index('local function vm_nbrs'):source.index('-- 落格字段写')]
    check('''
local CTX=0
local occupied={}
local function r8(a) return occupied[a] or 0 end
local function terrain_at(x,y) return x==4 and 0 or 1 end
local function vm_cost(t,cat) return t end
'''+movement+'''
local reach=vm_reach({x=2,y=35},0,2)
assert(reach["2,36"] and reach["2,37"],"lower-row troops must be able to move")
assert(not reach["4,35"],"impassable terrain must stay blocked")
assert(not reach["2,38"],"movement budget must be respected")
occupied[0x3F60+3*4+35*0xC0]=2
assert(not vm_reach({x=2,y=35},0,1)["3,35"],"enemy occupancy blocks movement")
assert(vm_reach({x=2,y=35},0,0)["2,35"]==0,"zero budget retains current cell")
''',True)
    fixture='''
local CTX,U,STRIDE=0,0,24
local cities,owners={},{}
local troop={idx=2,id=305,x=1,y=35,hp=24,maxhp=24,fuel=10}
local army,enemies={troop},{}
local threatPower,damage,attackPower=0,0,0
local ammoStock,weaponRange,romRange=1,3,2
local empty_ammo={}
local captures=0
local function key(x,y) return x..","..y end
local function tb() return 100000 end
local function r8(a)
 if a>100000 and a<120000 then return owners[a] or 0 end
 if a>=0x08798A98 then return romRange end
 for _,u in ipairs(army) do
  if a==0x3F60+u.x*4+u.y*0xC0 then return 1 end
  if a==0x3F60+u.x*4+u.y*0xC0+1 then return u.idx+1 end
 end
 return 0
end
local function terrain_at(x,y) return cities[key(x,y)] or 1 end
local function on_building(x,y) return cities[key(x,y)] or false end
local function hexd(ax,ay,bx,by) return math.abs(ax-bx)+math.abs(ay-by) end
local function enemy_counter(e,id,d) return d<=3 and threatPower or 0 end
local function my_best(u,d,id) return ammoStock>0 and not empty_ammo[u.idx] and d<=weaponRange and attackPower or 0 end
local function db(id) return {fuel=10} end
local function estimate(a,b,power) return power>0 and damage or 0 end
local function tdef(t) return t==0x11 and 20 or 0 end
local function is_capturer(id) return id==305 end
local function route_field(goal,pref,cat)
 local out={}
 for x=1,6 do out[key(x,35)]=math.abs(x-goal.x) end
 return out
end
local function vm_land(k,u,x,y,cost) u.x,u.y=x,y;u.fuel=u.fuel-cost end
local function unit(side,k) for _,u in ipairs(army) do if u.idx==k then return u end end end
local function all_units(side) return side=="MY" and army or enemies end
local function enemy_capital() return nil end
local fired=nil
local function attack(k,e) fired={slot=k,enemy=e};unit("MY",k).acted=true;return "OK" end
local function vm_ctx(k) return unit("MY",k),0,2 end
local function vm_reach(u,cat,budget)
 local out={}
 for x=1,6 do if math.abs(x-u.x)<=budget then out[key(x,35)]=math.abs(x-u.x) end end
 return out
end
local function uammo(k,slot) return empty_ammo[k] and 0 or ammoStock end
local function wslot(id,wa) return 0x08798A98+id*92+wa*16 end
local function cap(k) captures=captures+1; owners[tb()+troop.x*4+troop.y*0xC0+2]=1 end
local function log(s) end
local function markacted(k) unit("MY",k).acted=true end
local function city(x,y,owner) cities[key(x,y)]=0x11;owners[tb()+x*4+y*0xC0+2]=owner end
local BASE,RUN,SAVE_PREFIX="","","offline"
local saved,written=false,false
local savestate={save=function(path) saved=true end}
local function uninstall() end
local function writefile(path,text) written=true end
'''
    tests='''
city(1,35,1)
troop.hp=12
local held,reason=current_hold(troop,{})
assert(held and reason=="recover_in_city","wounded city defender should heal")
troop.hp=24
assert(not current_hold(troop,{}),"healthy rear city must release troops")
enemies={{id=187,x=3,y=35,hp=16,fuel=10}}
threatPower,damage=1,2
current_strategy.mode="defend"
assert(current_hold(troop,enemies),"frontline city should stay defended")
damage=30
assert(not current_hold(troop,enemies),"avoid insisting on a lethal city defense")
threatPower,damage=0,0
cities,owners={},{}
city(4,35,2)
current_advance(2,troop,{["1,35"]=0,["2,35"]=1,["3,35"]=2},0,{})
assert(troop.x==3 and troop.y==35,"infantry must approach cities beyond one-turn reach")
assert(troop.fuel==8,"movement must charge real path cost")
current_advance(2,troop,{["3,35"]=0,["4,35"]=1},0,{})
assert(troop.x==4 and captures==1,"infantry must capture on arrival")
troop.x,troop.hp=2,8
city(1,35,1);city(3,35,2)
current_routes={}
current_advance(2,troop,{["1,35"]=1,["2,35"]=0,["3,35"]=1},0,{})
assert(troop.x==1,"wounded infantry must prefer recovery to a new capture")
-- Capital duty is permanent and overrides ordinary low-HP retreat.
cities,owners={},{}
city(1,35,1);cities[key(1,35)]=0x10
troop.x,troop.hp,troop.acted=1,24,false
assert(current_guard(troop,{}),"capital must have a guard even with no nearby enemy")
assert(current_hold(troop,{}),"rear capital guard must not be released to attack")
threatPower,damage=1,30
troop.hp=4
assert(current_hold(troop,{{id=187,x=2,y=35,fuel=10}}),"wounded capital guard must not abandon its post")
-- Vacant capital is filled before the offense gets any actions.
cities,owners={},{}
city(5,35,1);cities[key(5,35)]=0x10
troop.x,troop.hp,troop.acted,troop.fuel=3,24,false,10
threatPower,damage=0,0
enemies={}
current_begin_round();current_defend_capitals()
assert(troop.x==5 and troop.acted,"vacant capital must receive a defender first")
-- A threatened, occupied capital gets a separate nearby reserve.
troop.acted=false
local reserve={idx=3,id=187,x=2,y=35,hp=16,maxhp=16,fuel=10,acted=false}
army={troop,reserve};enemies={{idx=8,id=305,x=6,y=35,hp=24,fuel=10}}
current_begin_round();current_assess();current_defend_capitals()
assert(troop.x==5,"reserve dispatch must not move the existing garrison")
assert(reserve.x==4 and reserve.acted,"threatened capital needs a dedicated reserve: x="..reserve.x.." acted="..tostring(reserve.acted))
-- Infiltrators receive explicit combat assignments; infantry retains capture duty.
local tank={idx=4,id=187,x=3,y=35,hp=16,maxhp=16,fuel=10,acted=false}
local foot={idx=5,id=305,x=2,y=35,hp=24,maxhp=24,fuel=10,acted=false}
army={troop,reserve,tank,foot};reserve.acted=false;troop.acted=false
enemies={{idx=8,id=305,x=1,y=35,hp=24,fuel=10}}
city(6,35,2);attackPower=4
current_begin_round();current_assess();current_plan_round()
assert(current_orders[tank.idx].kind=="intercept","nearby armor must intercept the infiltrator")
assert(current_orders[foot.idx].kind=="capture" and current_orders[foot.idx].x==6,"infantry needs a dedicated city mission")
assert(not current_orders[troop.idx],"capital garrison must not be assigned to attack")
assert(current_attack_targets(tank,{{idx=9,id=187,x=6,y=35},enemies[1]})[1].idx==8,"interception must not chase unrelated enemies")
assert(current_attack_targets(tank,{{idx=9,id=187,x=6,y=35}})[1].idx==9 and not current_orders[tank.idx],"destroyed interception targets must release assigned units")
-- Unreachable nearest cities cannot hide a reachable, more distant objective.
current_orders={};current_routes={};army={foot};troop=foot
troop.x,troop.acted,troop.hp=1,false,24
local original_route=route_field
route_field=function(goal,pref,cat) if goal.x<=10 then return {} end; return original_route(goal,pref,cat) end
cities,owners={},{}
for x=2,10 do city(x,35,2) end
city(12,35,2)
current_advance(5,troop,{["1,35"]=0,["2,35"]=1,["3,35"]=2},0,{})
assert(troop.x>1,"unreachable nearest goal must not stall the unit")
-- A lethal point-blank shot outranks a capture/intercept assignment.
route_field=original_route
troop.x,troop.hp,troop.acted,troop.fuel=2,2,false,10
current_orders[troop.idx]={kind="capture",x=6,y=35,pref=0}
attackPower,threatPower,damage=4,1,4
assert(current_quick_attack(troop,{{idx=18,id=187,x=3,y=35,hp=1,fuel=10}}),"adjacent low-HP target must not be skipped because of a mission")
assert(fired.enemy==18 and troop.x==2,"finisher must fire in place")
-- A distant front must not permanently pin extra armor around home.
troop.x,troop.hp,troop.maxhp,troop.acted=5,24,24,false
reserve.x,reserve.acted,reserve.fuel=4,false,10
army={troop,reserve};cities,owners={},{}
city(5,35,1);cities[key(5,35)]=0x10
enemies={{idx=8,id=187,x=40,y=10,hp=16,maxhp=16,fuel=10}}
current_begin_round();current_assess();current_defend_capitals()
assert(current_strategy.near==0 and not reserve.acted,"secure rear must release extra reserves")
assert(current_strategy.focus=="E" and current_strategy.enemy_count==1,"assessment must track enemy direction and count")
enemies={{idx=8,id=305,x=4,y=35,hp=24,maxhp=24,fuel=10},
 {idx=9,id=187,x=6,y=35,hp=16,maxhp=16,fuel=10},
 {idx=10,id=187,x=7,y=35,hp=16,maxhp=16,fuel=10}}
current_assess()
assert(current_strategy.near==3 and current_strategy.mode=="defend","enemy concentration near home must trigger defense")
-- Fuel starvation triggers a city visit even at full HP, with recovery hysteresis.
troop.x,troop.hp,troop.fuel,troop.acted=1,24,2,false
army={troop};enemies={};cities,owners={},{};city(1,35,1);city(6,35,1)
attackPower,threatPower,damage=0,0,0
current_recovery={};current_orders={};current_strategy.mode="advance"
assert(current_hold(troop,{}),"full-HP low-fuel unit must stay in a friendly city")
troop.fuel=5
assert(current_hold(troop,{}),"partially refueled unit must finish recovery")
troop.fuel=8
assert(not current_hold(troop,{}),"refueled unit must rejoin the attack")
-- Unsupported/nonworking recovery nodes are not trusted forever.
troop.fuel=2;current_recovery={}
for i=1,3 do assert(current_hold(troop,{})) end
assert(not current_hold(troop,{}),"city without actual HP/fuel gain must not trap the unit forever")
current_routes={}
current_advance(troop.idx,troop,{["1,35"]=0,["2,35"]=1,["3,35"]=2},0,{})
assert(troop.x==1,"do not start a recovery trip longer than remaining fuel")
city(3,35,1)
current_advance(troop.idx,troop,{["1,35"]=0,["2,35"]=1,["3,35"]=2},0,{})
assert(troop.x>1,"failed recovery node must prompt a route to another city")
-- Cleanup must use an armed, fuel-feasible path, including ranges above three.
troop.id,troop.x,troop.hp,troop.maxhp,troop.fuel,troop.acted=187,1,16,16,10,false
army={troop};enemies={{idx=8,id=305,x=6,y=35,hp=24,maxhp=24,fuel=10}}
cities,owners={},{};current_orders={};current_routes={};current_recovery={}
ammoStock,attackPower,weaponRange,romRange=1,4,5,5
assert(current_ranges(troop,enemies[1])[1]==5,"long-range weapons must not be capped at three hexes")
current_finish_plan()
assert(current_orders[troop.idx].kind=="cleanup" and current_orders[troop.idx].enemy==8,"last enemy must receive an executable cleanup mission")
ammoStock=0
assert(not current_solution(troop,enemies[1]),"empty ammunition must not count as a firing solution")
assert(current_needs_recovery(troop),"empty ammunition must request recovery")
-- No reachable firing solution and no infantry must stop instead of waiting until turn 30.
current_progress={stalled=0,hp=nil,cities=0,resources={}}
local reason
for i=1,7 do reason=current_finish_plan() end
assert(reason and reason:find("NO_CURRENT_PLAN") and saved and written,"deadlock must preserve map/checkpoint and report the missing plan")
-- A route longer than total remaining fuel is not an executable attack plan.
ammoStock,weaponRange,romRange=1,1,1
troop.fuel=2;current_routes={}
assert(not current_solution(troop,enemies[1]),"fuel-infeasible routes must not inflate combat strength")
-- Infantry must not enter a threatened approach alone; an actual nearby escort permits it.
troop.id,troop.x,troop.hp,troop.maxhp,troop.fuel,troop.acted=305,1,24,24,10,false
army={troop};ammoStock,weaponRange,romRange,attackPower,threatPower,damage=1,3,2,0,1,2
enemies={{idx=8,id=187,x=6,y=35,hp=16,maxhp=16,fuel=10}}
cities,owners={},{};city(6,35,2)
current_orders={};current_routes={};current_recovery={};current_supply_nodes={}
current_advance(troop.idx,troop,{["1,35"]=0,["2,35"]=1,["3,35"]=2},0,enemies)
assert(troop.x==1,"unsupported infantry must not advance into enemy fire")
local screen={idx=7,id=187,x=3,y=35,hp=16,maxhp=16,fuel=10,acted=false}
army={troop,screen};current_routes={}
current_advance(troop.idx,troop,{["1,35"]=0,["2,35"]=1,["3,35"]=2},0,enemies)
assert(troop.x==2,"infantry should advance when a real nearby screen protects the approach")
'''
    policy=(ROOT/'lua/current_tactics.lua').read_text(encoding='utf-8')+'\n'+(ROOT/'lua/current_endgame.lua').read_text(encoding='utf-8')
    check(fixture+policy+tests,True)
    # Check the actual movement-layer guard, including callers outside normal tactics.
    guard=source[source.index('local function vm_land'):source.index(' local ur=U+k*STRIDE-2')]
    check('''
local CTX=0
local capital=true
local memory={read_u32_le=function(a) return 100000 end}
local function terrain_at(x,y) return capital and 0x10 or 1 end
local function r8(a) return 1 end
'''+guard+'''return true end
local ok,err=pcall(vm_land,2,{x=5,y=35},6,35,1)
assert(not ok and tostring(err):find("Capital garrison"),"all movement paths must prohibit abandoning a capital")
assert(vm_land(2,{x=5,y=35},5,35,0),"guard can remain in place")
capital=false
assert(vm_land(2,{x=5,y=35},6,35,1),"ordinary units can still advance")
''',True)
    print('PASS: prior tactical regressions; real weapon ranges; fuel/ammo-feasible cleanup; stalemate checkpoint/diagnostics; no unsupported infantry advance; recovery path fuel bounds.')

if __name__=='__main__':
    main()
