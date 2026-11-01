"""Offline policy scenarios plus compilation of the independent generated bridge."""
from pathlib import Path
import hashlib
import re
import struct
import sys
import zipfile
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from tools.check_current_tactics2 import RESUP_FIXTURE, lua_check
from tools.build_air_supply import compose, build
from tools.native_attack import LUA
from tools.native_attack import make_stub

def fixture():
    # Reuse the existing mock VM, with distinct RAM/CTX and policy-local functions.
    src=RESUP_FIXTURE.split('\nUNITDB[187]={name="M1A2",dur=4}')[0]
    src+='\n'+re.search(r'local whitelist=\{[^\n]+',compose())[0]+'\n'
    rom=(ROOT/'roms/0219 - Daisenryaku.gba').read_bytes()
    for i in (149,168,187,305,339):
        record=rom[0x798a98+i*92:0x798a98+(i+1)*92]
        src+=f'\nUNITDB[{i}]={{dur={record[14]},fuel={record[25]}}}\n'
        src+='\n'.join(f'MEM[{0x08798a98+i*92+j}]={b}' for j,b in enumerate(record))
    src+='''
local funds,calls=1500,0
local supplied,reloads={},0
memory.read_u32_le=function(a) return a==CTX+0x24 and funds or 0 end
function vm_nbrs(x,y) return {{x+1,y},{x-1,y},{x,y+1},{x,y-1}} end
vm_cost=vm_cost or function(t,cat) return 1 end
vm_ctx=function(k)
 local u=unit("MY",k);assert(u and not u.acted)
 return u,r8(0x08798A98+u.id*92+5),math.min(u.fuel,r8(0x08798A98+u.id*92+13))
end
vm_land=function(k,u,x,y,cost)
 assert(cost<=u.fuel,"movement cannot create fuel")
 local a=CTX+0x3F60+u.x*4+u.y*0xC0;w8(a,0);w8(a+1,0)
 a=CTX+0x3F60+x*4+y*0xC0;assert(r8(a)==0,"cannot stack logistics units")
 w8(a,1);w8(a+1,k+1)
 w8(U+k*STRIDE,x);w8(U+k*STRIDE+1,y);w8(U+k*STRIDE+2,u.fuel-cost)
end
local function put(k,id,x,y,fuel,ammo)
 local b=U+k*STRIDE-2
 w8(b,id%256);w8(b+1,math.floor(id/256));w8(b+2,x);w8(b+3,y)
 w8(b+4,fuel);w8(b+6,UNITDB[id].dur*4);w8(b+7,0)
 for w=0,3 do w8(b+8+w,ammo or 0) end
 local a=CTX+0x3F60+x*4+y*0xC0;w8(a,1);w8(a+1,k+1)
end
local function cell(x,y,t,owner)
 w8(TB+x*4+y*0xC0,t);w8(TB+x*4+y*0xC0+2,owner)
end
w8(CTX+0x24+4,1);w8(CTX+0x24+12+4,2);w8(CTX+0x990,0)
'''
    src+=(ROOT/'lua/air_supply_policy.lua').read_text(encoding='utf-8')
    src+='''
-- Model the native boundary for policy scheduling, independently ROM-probed above.
function native_call(address,args)
 assert(whitelist[address],"actual generated bridge rejects native supply entry point")
 if address==0x08022388 then
  calls=calls+1
  local truck,u=unit("MY",args[2]),unit("MY",(args[3]-(U-2))/STRIDE)
  supplied[#supplied+1]=u.idx
  assert(hexd(truck.x,truck.y,u.x,u.y)==1,"native supply requires adjacency")
  assert(not u.acted,"do not supply an acted recipient")
  local pool=air_stock(truck)
  local used=math.min(pool,r8(air_base(u)+25)-u.fuel)
  w8(air_record(u)+4,u.fuel+used);pool=pool-used
  for w=0,3 do
   local max=r8(air_base(u)+0x26+w*16)
   local ammo=r8(air_record(u)+8+w)
   local price=r8(air_base(u)+0x28+w*16)
   if max>ammo and price>0 and pool>0 and not air_truck(u) then
    local spend=math.min(pool,(max-ammo)*price)
    w8(air_record(u)+8+w,ammo+math.ceil(spend/price));pool=pool-spend
   end
  end
  for w=0,3 do if r8(air_base(truck)+0x27+w*16)==2 then
   local n=math.min(pool,r8(air_base(truck)+0x26+w*16));w8(air_record(truck)+8+w,n);pool=pool-n
  end end
 elseif address==0x0801F078 then
  local u=unit("MY",args[2]);assert(u.fuel>air_burn(u),"test aircraft must have survival fuel")
  w8(air_record(u)+4,u.fuel-air_burn(u))
 elseif address==0x08021F78 then
  local u=unit("MY",args[2]);assert(air_facility(u,u.x,u.y),"wrong base type")
  assert(not u.acted,"paid repeated reload must occur before marking truck acted")
  reloads=reloads+1
  local cost=r8(air_base(u)+25)-u.fuel;w8(air_record(u)+4,r8(air_base(u)+25))
  for w=0,3 do
   local cap=r8(air_base(u)+0x26+w*16);local old=r8(air_record(u)+8+w)
   cost=cost+math.max(0,cap-old)*math.max(1,r8(air_base(u)+0x28+w*16))
   w8(air_record(u)+8+w,cap)
  end
  assert(funds>=cost,"test base must have enough funds");funds=funds-cost
 else error("unexpected native call") end
 return 1
end
put(0,339,5,5,50,40);put(1,149,6,5,35,0)
local u=air_transfer(unit("MY",0),unit("MY",1))
assert(u.fuel==45 and r8(air_record(u)+8)==2 and air_stock(unit("MY",0))==5,"fuel first, then real cargo pays for ammo")
assert(not u.acted and not unit("MY",0).acted,"supply must preserve both actions")
assert(u.hp==4,"field logistics must not heal aircraft")
local old=calls
local ok=pcall(air_transfer,unit("MY",0),{idx=1,id=149,side=0,x=10,y=10})
assert(not ok and calls==old,"nonadjacent pair must be rejected before native call")
put(2,168,10,10,50,0)
assert(not cs_needs_supply(unit("MY",2)),"unarmed transport helicopter must not seek ammo forever")
cell(6,5,0x11,1);cell(15,15,0x12,1)
assert(not air_facility(u,6,5) and air_facility(u,15,15),"helicopters need an airfield, not a ground town")
assert(air_facility(unit("MY",0),6,5) and not air_facility(unit("MY",0),15,15),"trucks need a ground supply base")
cell(15,15,0x12,2);assert(not air_facility(u,15,15),"enemy airport cannot replenish aircraft")
cell(15,15,0x12,1)
local moved=unit("MY",1)
local before=moved.fuel
air_move(moved,8,5,2)
local fresh=unit("MY",1)
assert(fresh.fuel==before-2,"rendezvous movement must spend fuel")
assert(select(3,vm_ctx(1))==4,"rendezvous must not reset the helicopter's six-point movement budget")
put(3,149,11,10,5,0);w8(air_record(unit("MY",0))+8,0)
local empty=unit("MY",0)
assert(not air_compatible(empty,unit("MY",3)),"empty supply truck cannot create resources")
-- A full logistics phase must move the truck, refill, and leave aircraft action free.
for a in pairs(MEM) do if a>=CTX+0x3F60 and a<CTX+0x3F60+48*0xC0 then MEM[a]=nil end end
put(0,339,5,5,50,40);put(1,149,8,5,10,0)
w8(U+2*STRIDE-2,0);w8(U+2*STRIDE-1,0);w8(U+3*STRIDE-2,0);w8(U+3*STRIDE-1,0)
current_begin_round();calls=0;actions={}
air_logistics_round()
local aircraft=unit("MY",1)
assert(calls>=1 and aircraft.fuel>10,"scheduled rendezvous must execute native supply")
assert(not aircraft.acted,"supplied helicopter may still attack or advance")
assert(unit("MY",0).acted and actions[0]==1,"truck movement consumes exactly one action")
assert(air_stock(unit("MY",0))<40,"scheduled supply must consume cargo")
assert(select(3,vm_ctx(1))<=6,"post-refill movement budget must remain bounded")
local before_wait=aircraft.fuel
air_before_acted(1,aircraft)
assert(unit("MY",1).fuel==before_wait-air_burn(aircraft),"waiting must charge native flight upkeep")
-- Depleted truck goes back to a real base and pays to reload.
cell(5,5,0x11,1)
local truck=unit("MY",0);w8(air_record(truck)+7,0);w8(air_record(truck)+8,0)
local oldfunds=funds
current_begin_round();air_logistics_round()
assert(funds<oldfunds,"truck reload must use native base funds")
air_old_candidates=function()return {{unit=unit("MY",1),enemy={}}} end
w8(air_record(unit("MY",1))+4,2)
assert(#cs_fire_candidates(false)==0,"aircraft below native upkeep must not launch an attack")
w8(air_record(unit("MY",1))+4,20)
assert(#cs_fire_candidates(false)==1,"fuel-safe aircraft should retain attack opportunities")
put(1,149,14,14,2,0)
current_begin_round()
local blocked=air_logistics_round()
assert(not blocked and air_exhausted[1],"stranded aircraft must not halt remaining army actions")
assert(unit("MY",1) and unit("MY",1).fuel==2 and not unit("MY",1).acted,"stranded aircraft fuel resolution must be deferred to native endturn, not frozen or forced early")
-- User-described depot cycle: reload after each recipient, then serve the next.
for a in pairs(MEM) do if a>=CTX+0x3F60 and a<CTX+0x3F60+48*0xC0 then MEM[a]=nil end end
put(0,339,5,5,50,40);put(1,149,6,5,8,0);put(2,149,5,6,3,0)
cell(5,5,0x11,1);funds=10000;supplied={};reloads=0;actions={}
current_begin_round()
assert(not air_logistics_round(),"depot cycle should finish normally")
assert(supplied[1]==2,"lowest endurance aircraft must get cargo before lower slot number")
assert(unit("MY",1).fuel==45 and unit("MY",2).fuel==45,"one city truck must refill multiple aircraft in the same round")
assert(r8(air_record(unit("MY",1))+8)==2 and r8(air_record(unit("MY",2))+8)==2,"depot must reload and supply ammunition too")
assert(reloads>=2 and funds<10000 and air_stock(unit("MY",0))==40,"each depot replenishment must spend funds and restore real cargo")
assert(unit("MY",0).x==5 and unit("MY",0).y==5 and actions[0]==1,"city truck holds depot and ends action only once after all cycles")
assert(not unit("MY",1).acted and not unit("MY",2).acted,"both aircraft must retain their post-supply actions")
print("PASS city depot repeated paid reloads, urgent-first service and no fleet-wide low-fuel stop")
-- 2026-10-21 live failure: the nearest depot held a garrison, so the empty truck
-- parked beside it forever. It must reload at a free facility instead.
local function reset_map()
 for a in pairs(MEM) do if (a>=CTX+0x3F60 and a<CTX+0x3F60+48*0xC0) or (a>=TB and a<TB+48*0xC0) then MEM[a]=nil end end
 for k=0,5 do w8(U+k*STRIDE-2,0);w8(U+k*STRIDE-1,0) end
end
reset_map()
put(0,339,8,8,50,0);put(3,305,7,8,40,4)
cell(7,8,0x10,1);cell(16,8,0x11,1)
funds=10000;reloads=0;actions={}
current_begin_round();air_logistics_round()
assert(unit("MY",0).x>=12,"empty truck must head for the free depot, not wait beside the garrisoned one")
w8(air_record(unit("MY",0))+7,0) -- next turn
current_begin_round();air_logistics_round()
assert(unit("MY",0).x==16 and unit("MY",0).y==8,"empty truck must reach the free depot")
assert(reloads>=1 and air_stock(unit("MY",0))==40,"truck must actually reload inside the free depot")
-- A loaded truck near a free city stations there instead of crawling after aircraft.
reset_map()
put(0,339,8,8,50,40);put(1,149,14,8,40,2)
cell(10,8,0x11,1)
current_begin_round();air_logistics_round()
assert(unit("MY",0).x==10 and unit("MY",0).y==8,"loaded truck within two turns of a free city must hold it as a depot")
-- Only one depot: a second truck keeps the front supplied.
reset_map()
put(0,339,10,8,50,40);put(2,339,8,8,50,40);put(1,149,14,8,40,2)
cell(10,8,0x11,1);cell(6,8,0x11,1)
current_begin_round();air_logistics_round()
assert(unit("MY",0).x==10 and unit("MY",0).y==8,"existing depot truck holds its city")
assert(unit("MY",2).x>8,"second truck must follow aircraft rather than occupy another rear city")
-- With no depot nearby, the truck still follows the aircraft along the ground.
reset_map()
put(0,339,8,8,50,40);put(1,149,14,8,40,2)
cell(30,30,0x11,1)
current_begin_round();air_logistics_round()
assert(hexd(unit("MY",0).x,unit("MY",0).y,14,8)<6,"without a nearby depot the truck must keep following aircraft")
print("PASS occupied depot skipped, nearby city stationing, distant follow fallback")
-- Large-map live run: every depot held, empty trucks idle while aircraft burn out.
reset_map()
put(0,339,8,8,50,0);put(4,187,10,8,50,4)
cell(10,8,0x11,1)
funds=10000;reloads=0;actions={}
current_begin_round();air_logistics_round()
assert(unit("MY",0).x==10 and unit("MY",0).y==8,"empty truck must take over a town held by a rested unit")
assert(reloads>=1 and air_stock(unit("MY",0))==40,"truck must reload after the swap")
assert((unit("MY",4).x~=10 or unit("MY",4).y~=8) and unit("MY",4).acted,"occupant must step out and spend its action exactly once")
-- Capitals and units that need the town keep it.
reset_map()
put(0,339,8,8,50,0);put(4,187,10,8,50,4)
cell(10,8,0x10,1)
current_begin_round();air_logistics_round()
assert(unit("MY",4).x==10 and unit("MY",4).y==8,"capital garrison must not be displaced for a truck")
reset_map()
put(0,339,8,8,50,0);put(4,187,10,8,50,4);w8(air_record(unit("MY",4))+6,8)
cell(10,8,0x11,1)
current_begin_round();air_logistics_round()
assert(unit("MY",4).x==10 and unit("MY",4).y==8,"a damaged unit repairing in town must not be displaced")
-- Native turn-change supply drains cargo into full neighbours.
reset_map()
put(0,339,8,8,50,40);put(4,187,9,8,50,4);put(1,149,7,8,10,2)
assert(air_drain(unit("MY",0),8,8)==1,"count full eligible neighbours only, not needy aircraft")
-- Live run: U39 "supplied" U38 six times with no fuel or cargo change.
put(2,339,9,9,30,40)
assert(not air_compatible(unit("MY",0),unit("MY",2)),"trucks must not resupply each other")
print("PASS depot swap with rested occupant, capital/refuelling units kept, native drain counted")
-- Towns are for infantry: tanks must not use an uncaptured town as a firing post.
reset_map()
put(4,187,8,8,50,4);put(5,305,9,9,40,4)
cell(10,8,0x11,2)
local tank_reach=air_keep_towns_free(unit("MY",4),{["10,8"]=2,["9,8"]=1})
assert(not tank_reach["10,8"] and tank_reach["9,8"],"tank firing posts must exclude uncaptured towns")
assert(air_keep_towns_free(unit("MY",5),{["10,8"]=2})["10,8"],"infantry keep uncaptured towns")
-- A capturer garrisons the capital only while enemies are near.
cell(8,8,0x10,1)
put(5,305,8,8,40,4)
assert(not cs_guard(unit("MY",5),{{x=30,y=30}}),"quiet capital releases its capturer")
assert(cs_guard(unit("MY",5),{{x=12,y=9}}),"threatened capital keeps its capturer")
put(4,187,8,8,50,4)
assert(cs_guard(unit("MY",4),{{x=30,y=30}}),"a tank keeps guarding the capital")
put(0,339,8,8,50,40)
assert(not cs_guard(unit("MY",0),{{x=30,y=30}}),"a truck on the capital is a depot, not a guard")
-- The depot follows the front once a nearer town is ours.
reset_map()
cs_campaign.objective={x=20,y=8}
put(0,339,6,8,50,40)
cell(6,8,0x11,1);cell(11,8,0x11,1)
funds=10000;actions={}
current_begin_round();air_logistics_round()
assert(unit("MY",0).x==11 and unit("MY",0).y==8,"idle depot must relocate to the town nearer the front")
assert(air_stock(unit("MY",0))==40,"relocated depot keeps or restores real cargo")
-- But not while an aircraft is flying back to it for fuel.
reset_map()
put(0,339,6,8,50,40);put(1,149,9,8,6,2)
cell(6,8,0x11,1);cell(11,8,0x11,1)
assert(air_depot_busy(unit("MY",0)),"low-fuel aircraft planning on this depot keeps it busy")
cs_campaign.objective=nil
print("PASS towns kept for infantry, capital capturer released when quiet, depot follows the front")
print("PASS air/truck rendezvous, real cargo, action and movement budgets, airport type, unarmed transport and paid reload")
'''
    return src

def state_replay(state,ids,real_danger=False):
    """Load a real savestate into the policy fixture with the generated route/movement code."""
    import zstandard
    with zipfile.ZipFile(state) as z:
        raw=zstandard.ZstdDecompressor().decompress(z.read('Core.bin.zst'),max_output_size=1<<23)
    iw,ew=0x19004,0x21004
    tiles=struct.unpack_from('<I',raw,iw+0x498)[0]
    src=fixture().split('put(0,339,5,5,50,40)')[0]
    if real_danger:
        # Swap the fixture's zero-threat mocks for the generated threat model.
        gen=compose()
        helpers=gen[gen.index(' local DB=0x08798AF4'):]
        helpers=helpers[:helpers.index('\n',helpers.index('local function tcls'))+1]
        counter=gen[gen.index(' local function enemy_counter'):gen.index(' local function tb()')]
        src=src.replace('local function estimate(a,b,p) return p end','')
        src=src.replace('local function enemy_counter(e,id,d) return 0 end',helpers+counter)
    src=src.replace('local function r8(a) return MEM[a] or 0 end','''
local ROM=assert(io.open("D:/prog/gba-ai/roms/0219 - Daisenryaku.gba","rb")):read("*a")
local function r8(a)
 if MEM[a]~=nil then return MEM[a] end
 if a>=0x08000000 and a<0x08000000+#ROM then return ROM:byte(a-0x08000000+1) end
 return 0
end''')
    src+='''
memory.read_u32_le=function(a)
 if a==CTX+0x24 then return funds end
 return r8(a)+r8(a+1)*256+r8(a+2)*65536+r8(a+3)*16777216
end
'''
    hexfn=LUA[LUA.index('local function hexd'):LUA.index('local function free_cell_near')]
    src+=hexfn.replace('local function hexd(','hexd=function(')
    movement=LUA[LUA.index('local function vm_cost'):LUA.index('-- 落格字段写')]
    movement=movement.replace('local function vm_nbrs(','vm_nbrs=function(').replace('local function vm_reach(','air_old_reach=function(')
    src+=movement.replace('ny<=34','ny<=46')
    routing=LUA[LUA.index(' local function route_field'):LUA.index(' local function best_advance_cell')]
    src+=routing.replace('local function route_field(','route_field=function(').replace('y<=34','y<=46').replace('for y=1,34','for y=1,46')
    for a in range(128):
        src+=f'\nMEM[{a}]={raw[iw+0x480+a]}'
    for a in range(4*0x600):
        src+=f'\nMEM[{0x10000-2+a}]={raw[iw+0x2be0+a]}'
    for y in range(48):
        for x in range(48):
            for b in range(4):
                tile=raw[ew+tiles-0x02000000+y*0xc0+x*4+b]
                grid=raw[iw+0x480+0x3f60+y*0xc0+x*4+b]
                src+=f'\nMEM[{0x20000+y*0xc0+x*4+b}]={tile};MEM[{0x3f60+y*0xc0+x*4+b}]={grid}'
    rom=(ROOT/'roms/0219 - Daisenryaku.gba').read_bytes()
    for i in ids:
        r=rom[0x798a98+i*92:0x798a98+(i+1)*92]
        src+=f'\nUNITDB[{i}]={{dur={r[14]},fuel={r[25]}}}'
    return src,raw

def failed_run_fixture():
    """Replay the actual turn-3 map in the real generated route/movement code."""
    state=ROOT/'states/current_air_20261019_225254_t2.State'
    if not state.exists():
        return None
    src,raw=state_replay(state,(138,149,168,187,241,305,307,308,339))
    assert struct.unpack_from('<H',raw,0x19004+0x2be0)[0]==138
    assert raw[0x19004+0x4a0]==3
    src+='''
current_begin_round();air_in_logistics=false
local u=unit("MY",0)
assert(u.id==138 and u.x==21 and u.y==20 and u.fuel==29,"failed-run state mapping must match recorded trajectory")
local service=air_service_plan(u,u.x,u.y)
assert(service,"actual map needs a truck service route")
assert(not air_fuel_safe(u,18,14,6),"reject the historical six-point flight that abandoned its fuel return route")
local _,cat,budget=vm_ctx(0)
local reach=vm_reach(u,cat,budget)
assert(not reach["18,14"],"actual movement candidates must exclude the failed northward sortie")
local count=0
for key,cost in pairs(reach) do
 local x,y=key:match("(%d+),(%d+)");x,y=tonumber(x),tonumber(y)
 if x~=u.x or y~=u.y then
  assert(air_fuel_safe(u,x,y,cost),"every offensive cell must preserve travel and upkeep to service")
  count=count+1
 end
end
assert(count>0,"fuel safety must not immobilize all aircraft")
print("PASS actual failed-run turn-3 map, ROM routing and AH1F fuel return envelope; safe cells="..count.." service fuel="..service.fuel)
'''
    return src

def cutoff_fixture():
    """2026-10-21 large map, turn 4: enemies sit between AH1F U0 and field truck U39."""
    state=ROOT/'states/current_air_20261021_014310_t3.State'
    if not state.exists():
        return None
    src,_=state_replay(state,range(400),real_danger=True)
    src+='''
current_begin_round();air_in_logistics=true
local u,field,depot=unit("MY",0),unit("MY",39),unit("MY",38)
assert(u.id==138 and u.x==20 and u.y==37 and u.fuel==20,"state must match recorded trajectory")
assert(field.x==14 and field.y==34 and depot.x==11 and depot.y==31,"truck positions must match recorded trajectory")
local _,cat=vm_ctx(0)
assert(current_route(field,1,cat)["20,37"]==7,"plain distance alone looks like an easy 7-hex return")
assert(not air_safe_field(u,field,1,cat)["20,37"],"enemy screen must cut every survivable return to the field truck")
local p=air_service_plan(u,u.x,u.y)
assert(p and p.truck==38 and p.fuel>u.fuel,"only the town depot remains, and it is out of fuel range")
assert(air_wants(u),"a cut-off aircraft must be flagged for supply")
print("PASS actual cut-off map: enemy screen severs field-truck return; depot fuel "..p.fuel.." > "..u.fuel)
'''
    return src

def main():
    source=compose()
    lua_check(source)
    assert 'not air_exhausted[k]' in source,"stranded aircraft must leave main army loop free to continue"
    recovery=(ROOT/'lua/air_bridge_recover.lua').read_text(encoding='utf-8')
    stub=','.join(str(b) for b in make_stub()[0])
    lua_check('''
local HOOK,CAVE,MAILBOX,CTX,BASE=1000,2000,2512,4000,""
local original={0x30,0xB5,0xE9,0xF7,0x79,0xFC,0,6}
local expected=string.char('''+stub+''')
local MEM,writes,state={},0,7
local function r8(a)if a==CTX then return state elseif a==CTX+1 then return 1 end return MEM[a] or 0 end
local function write(a,v)MEM[a]=v;writes=writes+1 end
local function put32(a,v)for i=0,3 do MEM[a+i]=math.floor(v/256^i)%256 end end
local memory={read_u16_le=function(a)return r8(a)+256*r8(a+1)end,
 read_u32_le=function(a)return r8(a)+256*r8(a+1)+65536*r8(a+2)+16777216*r8(a+3)end,
 write_u32_le=put32,write_u8=write}
local io={open=function()return {read=function()return expected end,close=function()end}end}
local function log()end
local function stale(status)
 MEM={};writes=0
 MEM[HOOK]=0;MEM[HOOK+1]=0x4B;MEM[HOOK+2]=0x18;MEM[HOOK+3]=0x47;put32(HOOK+4,CAVE+1)
 for i=1,#expected do MEM[CAVE+i-1]=expected:byte(i) end
 put32(MAILBOX,status)
end
'''+recovery+'''
stale(3);air_recover_idle_bridge()
for i=1,8 do assert(r8(HOOK+i-1)==original[i],"idle hook restore")end
assert(r8(CAVE)==0,"owned idle cave should be cleared")
stale(2);assert(not pcall(air_recover_idle_bridge) and writes==0,"busy native call must remain untouched")
stale(3);MEM[CAVE]=123
assert(not pcall(air_recover_idle_bridge) and writes==0,"unknown stub must remain untouched")
for _,scene in ipairs({3,4,6,7,8}) do
 state=scene;stale(3);air_recover_idle_bridge()
 for i=1,8 do assert(r8(HOOK+i-1)==original[i],"idle recovery must work outside battlefield too")end
end
state=6;stale(0)
for i=0,0x23F do MEM[CAVE+i]=0 end
air_recover_idle_bridge()
for i=1,8 do assert(r8(HOOK+i-1)==original[i],"save reload with blank RAM must remove the known dangling ROM hook")end
assert(writes==8,"blank RAM recovery must only restore ROM hook bytes")
state=6;stale(2)
assert(not pcall(air_recover_idle_bridge) and writes==0,"busy hook in deployment must remain untouched")
print("PASS startup recovery across selection/details/deployment/battle/results and blank-RAM reload")
print("PASS stale idle bridge recovery; busy/unknown hooks retained")
''',execute=True)
    call=source[source.index('local whitelist='):source.index('local function distance(a,b)')]
    lua_check('''
local CTX,MAILBOX,CAVE=1000,2000,3000
local RUN,CURRENT_SPEED="",200
local MEM,stub,native_frames={},"x",{}
local ticks,installs,cleanups,executions=0,0,0,0
local mode,restored="recover",false
local function r8(a)
 if a==CTX then return 7 elseif a==CTX+1 then return 1 elseif a==CAVE then return 120 end
 return 0
end
local memory={read_u32_le=function(a)return MEM[a] or 0 end,write_u32_le=function(a,v)MEM[a]=v end}
local function install()installs=installs+1 end
local function uninstall()assert((MEM[MAILBOX] or 0)~=2,"must not uninstall a running call")end
local function to_map()
 assert(MEM[MAILBOX]==0,"cancel unstarted request before input cleanup")
 cleanups=cleanups+1;restored=true
end
local function adv(n)
 ticks=ticks+n
 if MEM[MAILBOX]==1 then
  if mode=="busy" then MEM[MAILBOX]=2
  elseif mode=="recover" and restored then
   MEM[MAILBOX]=3;MEM[MAILBOX+32]=42;MEM[MAILBOX+40]=99;MEM[MAILBOX+44]=99
   executions=executions+1
  end
 end
end
local emu={framecount=function()return ticks end,getregister=function()return 0x080006C2 end}
local client={speedmode=function()end}
local function log(s)end
local function writefile()end
'''+call+'''
assert(native_call(0x08022388,{0,18,0,0},3)==42,"retry must return the native result")
assert(installs==2 and cleanups==1 and executions==1,"unstarted recovery must execute supply exactly once")
MEM={};mode="busy";restored=false;cleanups=0;installs=0
assert(not pcall(native_call,0x08022388,{},2),"busy timeout must fail without replay")
assert(MEM[MAILBOX]==2 and cleanups==0 and installs==1,"running call must not be reset or repeated")
MEM={};mode="never";restored=false;cleanups=0;installs=0
assert(not pcall(native_call,0x08022388,{},2),"permanent non-entry must fail")
assert(installs==2 and cleanups==1,"map recovery must be bounded to one retry")
print("PASS actual generated native caller: recover unstarted once, never replay busy calls")
''',execute=True)
    endturn=source[source.index('local function endturn()'):source.index('local function hexd(')]
    lua_check('''
local CTX,turn,dirty,cleanups=0,1,false,0
local function r8(a)
 if a==0 then return 7 elseif a==1 then return 1 elseif a==0x21 then return 3 elseif a==0x20 then return turn end
 return 0
end
local function uninstall()end
local function to_map()dirty=false;cleanups=cleanups+1 end
local function tap()end
local function adv(n)if n>=200 then turn=2 end end
local function mobile()dirty=true;return true end
local function all_units()return {} end
local function log()assert(not dirty,"cursor readiness probe must be dismissed before continuing")end
'''+endturn+'''
assert(endturn() and cleanups==2 and not dirty,"endturn must restore idle map after mobile probe")
print("PASS actual generated endturn cleanup after readiness probe")
''',execute=True)
    move=source[source.index('local function vm_land'):source.index('local function vm(k,x,y)')]
    lua_check('''
local CTX,U,STRIDE=0x03000480,0x03002BE2,24
local MEM={};local function r8(a)return MEM[a] or 0 end
local memory={write_u8=function(a,v)MEM[a]=v end}
local bit={band=function(a,b)return a&b end}
local VMLAND_REFRESH=false
'''+move+'''
MEM[U-2+7]=4;MEM[U-2+12]=2
MEM[CTX+2]=77;MEM[CTX+3]=88
vm_land(0,{x=5,y=5,fuel=50},8,7,3)
assert(MEM[U+STRIDE]==8 and MEM[U+STRIDE+1]==7,"transport passenger coordinates must follow carrier")
assert(MEM[CTX+2]==77 and MEM[CTX+3]==88,"transport movement must not corrupt context header")
print("PASS actual generated carrier/passenger movement")
''',execute=True)
    assert 'if (r8(base+5)&0x80)~=0 then return nil end' in source
    assert 'air_before_acted(k,u)' in source
    lua_check('local function test()\n'+fixture()+'\nend\nlocal ok,err=xpcall(test,debug.traceback);assert(ok,err)',execute=True)
    for replay in (failed_run_fixture(),cutoff_fixture()):
        if replay:
            lua_check(replay,execute=True)
    # Build only the NEW artifacts; prove the old entry points and live protocol survive.
    preserved=['Play-Current.cmd','tools/play_current2.py','tools/current_tactics2.py',
               'lua/current_battle2.lua','shots/current_battle2/command.txt']
    before={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in preserved if (ROOT/p).exists()}
    build()
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest for p,digest in before.items())
    print('PASS independent build preserves original CMD, strategy, generated bridge and command mailbox')

if __name__=='__main__':
    main()
