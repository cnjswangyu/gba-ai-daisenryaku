"""check_current_tactics2.py — v2 桥脚本的离线校验（BizHawk 自带 lua54.dll，不碰模拟器）

1. 语法：编译 lua/current_battle2.lua
2. 文本断言：原生战斗/反击/首都/占领都按目标阵营参数化（不再写死 1）
3. 语义夹具：多阵营枚举、补给地形判定、缺编判定、缺编单位的推进目标
"""
from __future__ import annotations

import ctypes
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools.current_tactics2 import patch_prefix, apply_current_tactics2  # noqa: E402
from tools.native_attack import LUA


def lua_check(source: str, execute: bool = False) -> None:
    dll = ctypes.CDLL(str(ROOT / "tools/dll/lua54.dll"))
    dll.luaL_newstate.restype = ctypes.c_void_p
    dll.luaL_openlibs.argtypes = [ctypes.c_void_p]
    dll.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t,
                                     ctypes.c_char_p, ctypes.c_char_p]
    dll.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                               ctypes.c_ssize_t, ctypes.c_void_p]
    dll.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
    dll.lua_tolstring.restype = ctypes.c_char_p
    dll.lua_close.argtypes = [ctypes.c_void_p]
    state = dll.luaL_newstate()
    try:
        dll.luaL_openlibs(state)
        data = source.encode("utf-8")
        status = dll.luaL_loadbufferx(state, data, len(data), b"offline", None)
        if status == 0 and execute:
            status = dll.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            raise AssertionError(dll.lua_tolstring(state, -1, None).decode("utf-8", "replace"))
    finally:
        dll.lua_close(state)


def multi_side_block() -> str:
    prefix = (ROOT / "lua/usa_ai_state.lua").read_text(encoding="utf-8")
    patched = patch_prefix(prefix)
    return patched[patched.index("local MAX_SIDES"):patched.index("local function build_state")]


FIXTURE = '''
local CTX,U,PB,STRIDE,SLOTS,MAX_SIDES=0x0,0x0,0x600,24,64,4
local MEM={}
local function r8(a) return MEM[a] or 0 end
local function w8(a,v) MEM[a]=v end
local memory={read_u8=r8,read_u16_le=function(a) return (MEM[a] or 0)+(MEM[a+1] or 0)*256 end}
local UNITDB={}
local function db(id) return UNITDB[id] end
'''
FIXTURE += multi_side_block() + '''
-- 测试用单位表：阵营 0（我）2 个，阵营 1（敌）3 个，阵营 2（敌）1 个；阵营 3 未参战
-- 记录布局（相对 id 地址 b）：+2 x, +3 y, +4 燃料, +6 HP, +7 状态, +8.. 弹药
local function put(side,slot,id,x,y,hp,fuel,acted)
 local b=U+side*PB+slot*STRIDE-2
 MEM[b]=id%256; MEM[b+1]=math.floor(id/256)
 MEM[b+2]=x; MEM[b+3]=y; MEM[b+4]=fuel; MEM[b+6]=hp; MEM[b+7]=acted and 1 or 0
 for i=0,3 do MEM[b+8+i]=4 end
end
UNITDB[187]={name="M1A2",dur=4}
UNITDB[188]={name="T-72B",dur=4}
put(0,0,187,5,5,16,50,false)
put(0,1,187,6,5,16,50,false)
put(1,0,188,10,10,16,50,false)
put(1,1,188,11,10,16,50,false)
put(1,2,188,12,10,16,50,false)
put(2,0,188,20,20,16,50,false)
-- 阵营参战状态：ctx+0x24+side*0xC+4
w8(CTX+0x24+0*0xC+4,1)   -- 玩家
w8(CTX+0x24+1*0xC+4,2)   -- 敌对
w8(CTX+0x24+2*0xC+4,2)   -- 敌对
w8(CTX+0x24+3*0xC+4,0)   -- 未参战
w8(CTX+0x990,0)          -- 玩家阵营

local mie=all_units("EN")
assert(#mie==4,"敌对阵营并集应为 4，实得 "..#mie)
local seen={}
for _,u in ipairs(mie) do seen[u.side]=true end
assert(seen[1] and seen[2],"两个敌对阵营都要出现")
assert(not seen[3],"未参战阵营不能出现")
assert(#all_units("MY")==2,"我方 2 个单位")
assert(unit("MY",0).id==187 and unit("EN",0).side==1,"旧接口 MY/EN 仍需可用")
local keys={}
for _,u in ipairs(mie) do keys[u.key]=(keys[u.key] or 0)+1 end
local nk=0 for _ in pairs(keys) do nk=nk+1 end
assert(nk==4,"(side,slot) 复合键必须唯一")
print("PASS multi-faction unit enumeration")
'''

RESUP_FIXTURE = '''
local CTX,U,PB,STRIDE,SLOTS,MAX_SIDES=0x0,0x10000,0x600,24,64,4
local MEM={}
local function r8(a) return MEM[a] or 0 end
local function w8(a,v) MEM[a]=v end
local memory={read_u8=r8,read_u16_le=function(a) return (MEM[a] or 0)+(MEM[a+1] or 0)*256 end}
local UNITDB={}
local function db(id) return UNITDB[id] end
local TB=0x20000
local function tb() return TB end
local function terrain_at(x,y) return r8(TB+x*4+y*0xC0) end
local function on_building(x,y) local t=terrain_at(x,y) return t>=0x10 and t<=0x28 end
local function tdef(t) return t==0x11 and 20 or 0 end
local function hexd(ax,ay,bx,by) return math.abs(ax-bx)+math.abs(ay-by) end
local function is_capturer(id) return id==305 end
local function estimate(a,b,p) return p end
local function my_best(u,d,eid) return 0 end
local function enemy_counter(e,id,d) return 0 end
local function log(s) end
local actions={}
local function markacted(k) actions[k]=(actions[k] or 0)+1;w8(U+k*STRIDE+5,1) end
local function cap(k) end
local function attack(k,foe) end
local VM={}
local function vm_ctx(k) return nil,2,4 end
local function vm_reach(u,cat,budget)
 local out={}
 for x=1,16 do for y=1,16 do
  local d=math.abs(x-u.x)+math.abs(y-u.y)
  if d<=budget then out[x..","..y]=d end
 end end
 return out
end
local function vm_land(k,u,x,y,c)
 local old=CTX+0x3F60+u.x*4+u.y*0xC0
 w8(old,0);w8(old+1,0)
 local cell=CTX+0x3F60+x*4+y*0xC0
 w8(cell,1);w8(cell+1,k+1)
 u.x,u.y=x,y;w8(U+k*STRIDE,x);w8(U+k*STRIDE+1,y)
end
local function route_field(goal,pref,cat)
 local out={}
 for x=1,16 do for y=1,16 do out[x..","..y]=math.abs(x-goal.x)+math.abs(y-goal.y) end end
 return out
end
local SAVE_PREFIX="tester"
local BASE="./"
local function uninstall() end
local function restore_keyboard() end
local savestate={save=function()end,load=function()error("unexpected rollback")end}
local function cs_fire_candidates() return {} end
'''
RESUP_FIXTURE += multi_side_block()
RESUP_FIXTURE += (ROOT / "lua/current_deadline2.lua").read_text(encoding="utf-8")
RESUP_FIXTURE += (ROOT / "lua/current_tactics2.lua").read_text(encoding="utf-8")
RESUP_FIXTURE += (ROOT / "lua/current_mobility2.lua").read_text(encoding="utf-8")
RESUP_FIXTURE += '''
UNITDB[187]={name="M1A2",dur=4}
local function put(side,slot,id,x,y,hp,fuel,ammo)
 local b=U+side*PB+slot*STRIDE-2
 MEM[b]=id%256; MEM[b+1]=math.floor(id/256)
 MEM[b+2]=x; MEM[b+3]=y; MEM[b+4]=fuel; MEM[b+6]=hp; MEM[b+7]=0
 for i=0,3 do MEM[b+8+i]=ammo or 4 end
end
local function cell(x,y,terr,owner)
 w8(TB+x*4+y*0xC0,terr); w8(TB+x*4+y*0xC0+2,owner)
end
w8(CTX+0x24+0*0xC+4,1) w8(CTX+0x24+1*0xC+4,2) w8(CTX+0x24+2*0xC+4,2) w8(CTX+0x990,0)
put(0,0,187,3,3,16,50,4)
-- 只有自家 0x10/0x11/0x14 是补给点
cell(9,9,0x10,1) cell(10,9,0x11,1) cell(11,9,0x14,1) cell(12,9,0x12,1)
cell(13,9,0x10,2) cell(14,9,0x01,1) cell(15,9,0x16,1)
assert(cs_is_foe_side(1) and cs_is_foe_side(2) and not cs_is_foe_side(3),"敌对阵营判定")
assert(cs_supply_cell(9,9),"自家首都应可补给")
assert(cs_supply_cell(10,9) and cs_supply_cell(11,9),"自家市街/村落应可补给")
assert(not cs_supply_cell(12,9),"自家 0x12 不能补给（实测）")
assert(not cs_supply_cell(13,9),"敌方首都不能补给")
assert(not cs_supply_cell(14,9) and not cs_supply_cell(15,9),"野地/0x16 不能补给")
-- 缺编判定
local u=unit("MY",0)
assert(not cs_needs_supply(u),"满编满油满弹：不需要补给")
u.hp=6  assert(cs_needs_supply(u),"低血需要补给")
u.hp=16 u.fuel=3  assert(cs_needs_supply(u),"低油需要补给")
u.fuel=50 for i=0,3 do w8(U+0*STRIDE-2+8+i,0) end
assert(cs_needs_supply(u),"没弹药需要补给")
for i=0,3 do w8(U+0*STRIDE-2+8+i,4) end
-- 缺编单位推进时应当选补给点收尾（预算 9 够走到最近的首都 (9,9)）
current_begin_round()
assert(#current_my_cities==3,"自家补给城市 3 座（首都/市街/村落）")
put(0,0,187,5,5,2,4,0)          -- 残血、油量低、无弹
local nu=unit("MY",0)
current_advance(0,nu,vm_reach(nu,2,9),2,{})
assert(cs_supply_cell(nu.x,nu.y),"缺编单位应当收尾在自家补给点上: "..nu.x..","..nu.y)
assert(not (nu.x==5 and nu.y==5),"缺编单位不该原地不动")
-- 站在自家市街上：缺编 → 原地驻守补给；满编 → 可以出去打
put(0,0,187,10,9,6,10,0)
local wounded=unit("MY",0)
local hold1,why1=cs_hold(wounded,{})
assert(hold1 and why1=="resupply_in_city","缺编单位应原地驻守补给自己: "..tostring(why1))
put(0,0,187,10,9,16,50,4)
local healthy=unit("MY",0)
assert(not cs_hold(healthy,{}),"满编单位不该被钉在城里")
-- A healthy occupant makes room for a needy unit that can actually arrive this turn.
UNITDB[187].fuel=50
put(0,0,187,10,9,16,50,4);put(0,1,187,8,9,4,3,0)
w8(CTX+0x3F60+10*4+9*0xC0,1);w8(CTX+0x3F60+10*4+9*0xC0+1,1)
w8(CTX+0x3F60+8*4+9*0xC0,1);w8(CTX+0x3F60+8*4+9*0xC0+1,2)
actions={};current_begin_round();cs_supply_handoff()
assert(unit("MY",1).x==10 and unit("MY",1).y==9,"needy unit must enter the vacated supply city")
assert(unit("MY",0).x~=10 or unit("MY",0).y~=9,"healthy occupant must not keep the supply slot")
assert(actions[0]==1 and actions[1]==1,"each handoff participant consumes only one action")
-- A friendly vehicle on an enemy capital must yield to an adjacent capturer.
UNITDB[305]={name="infantry",dur=6}
put(0,0,187,13,9,16,50,4);put(0,1,305,12,9,24,30,4)
put(1,0,187,14,14,16,40,4)
for _,p in ipairs({{13,9,0},{12,9,1}}) do
 local a=CTX+0x3F60+p[1]*4+p[2]*0xC0;w8(a,1);w8(a+1,p[3]+1)
end
local captured=0
cap=function(k)
 local u=unit("MY",k)
 assert(u.x==13 and u.y==9 and is_capturer(u.id),"capturer must actually enter the capital")
 cell(13,9,0x10,1);captured=captured+1
end
actions={};current_begin_round()
assert(not cs_capture_handoff(),"handoff should succeed")
assert(captured==1 and unit("MY",1).x==13 and unit("MY",1).y==9,"vehicle must yield and infantry capture")
assert(actions[0]==1 and actions[1]==1,"capture handoff must not double-consume actions")
-- With a single distant foe, an available combat unit gets an offensive task.
put(0,0,187,5,5,16,50,4);put(1,0,187,14,14,16,40,4)
my_best=function(u,d,id) return 10 end
current_begin_round();cs_clock.left=1;cs_clock.urgency=2
cs_offensive_orders()
assert(current_orders[0] and current_orders[0].kind=="intercept","late combat unit must pursue the remaining enemy")
assert(current_orders[0].foe_side==1 and current_orders[0].foe_slot==0,"pursuit must retain faction and slot")
local before=unit("MY",0)
current_advance(0,before,vm_reach(before,2,4),2,all_units("EN"))
local after=unit("MY",0)
assert(hexd(after.x,after.y,14,14)<18,"deadline must not turn pursuit into cover waiting")
-- Neither pursuit nor capital handoffs may displace the home garrison.
put(0,0,187,9,9,16,50,4)
current_begin_round();cs_offensive_orders()
assert(not current_orders[0],"home capital guard must keep its defensive role")
-- Main-axis planning keeps a capture unit on its objective and escorts at its side.
cell(15,15,0x10,2)
put(0,1,305,10,10,24,30,4)
for k=2,8 do put(0,k,187,10,k+8,16,50,4) end
put(1,0,187,14,14,16,40,4)
put(1,1,187,2,2,16,40,4)
put(1,2,187,13,14,16,40,4)
put(1,3,187,14,13,16,40,4)
current_begin_round();cs_clock.left=15;cs_clock.urgency=0.25;cs_clock.stalled=0
cs_offensive_orders()
assert(cs_campaign.objective.x==15 and cs_campaign.objective.y==15,"main axis should use a reachable hostile capital")
assert(current_orders[1].kind=="capture" and current_orders[1].x==15,"capturer must share the campaign objective")
local escorts,attacks,near=0,0,0
local escort_slot=nil
for k,o in pairs(current_orders) do
 if o.kind=="escort" then
  escorts=escorts+1;escort_slot=k
  assert(o.x==10 and o.y==10,"escorts must follow the foot unit, not its distant capital")
 elseif o.kind=="intercept" then
  attacks=attacks+1
  if o.foe_slot~=1 then near=near+1 end
 end
end
assert(escorts==1 and attacks>=4 and near>=3,"keep an escort while concentrating combat troops on the main sector")
put(0,1,305,11,10,24,29,4)
cs_refresh_order(escort_slot,all_units("EN"))
assert(current_orders[escort_slot].x==11,"escort must track infantry movement within the same round")
-- A remote movement order must not hide a close attackable enemy.
current_orders[2]={kind="intercept",foe_side=1,foe_slot=1,x=2,y=2}
assert(#current_attack_targets(unit("MY",2),all_units("EN"))==4,"assigned target must not filter out other attack opportunities")
put(1,1,0,2,2,0,40,4)
cs_refresh_order(2,all_units("EN"))
assert(current_orders[2] and current_orders[2].foe_slot~=1,"destroyed target must trigger same-turn redistribution")
put(1,1,187,10,9,16,40,4)
current_orders[8]={kind="intercept",foe_side=1,foe_slot=1,x=10,y=9,pref=1,value=-100}
cs_offensive_orders()
assert(current_orders[8].foe_slot==1 and current_orders[8].foe_side==1,"main offensive must preserve an urgent home interception")
print("PASS campaign objective, concentrated force, following escort and same-turn retargeting")
print("PASS hostile-capital handoff, late pursuit movement and home guard preservation")
print("PASS city resupply awareness")
'''


def main() -> None:
    prefix=(ROOT/'lua/usa_ai_state.lua').read_text(encoding='utf-8').split('-- ============ 启动 ============')[0]
    prefix,tail=apply_current_tactics2(prefix,LUA,ROOT)
    src=prefix+tail
    assert not re.search(r'\b(?:ny|y)<=34\b|for (?:y|yy)=1,34 do',tail),"multi-faction bridge must not retain the row-34 restriction"
    movement=tail[tail.index('local function vm_nbrs'):tail.index('-- 落格字段写')]
    lua_check('''
local CTX=0
local function r8(a) return 0 end
local function terrain_at(x,y) return 1 end
local function vm_cost(t,cat) return 1 end
'''+movement+'''
local reach=vm_reach({x=10,y=37},0,3)
assert(reach["10,36"] and reach["10,35"] and reach["10,34"],"lower-left deployment must connect to the playable map")
assert(not vm_reach({x=10,y=37},0,0)["10,36"],"movement budget still applies")
print("PASS actual multi-faction lower-row movement")
''',execute=True)
    lua_check(src)
    # 阵营参数化断言
    for must, why in (
        ('native_call(0x08023188,{player_side(),idx,wa,eside,eidx,wb}', "战斗结算要带目标阵营"),
        ('U+(eside or 1)*PB+eidx*STRIDE-2', "反击读的是目标阵营的单位表"),
        ('local ammo=r8(U+(e.side or 1)*PB+e.idx*STRIDE-2+8+wa)', "敌方弹药按 e.side"),
        ('native_call(0x08020B20,{player_side(),k})', "占领按玩家阵营"),
        ('local function enemy_capitals()', "多阵营敌首都列表"),
        ('apply', ""),
    ):
        if why and must not in src:
            raise AssertionError(why)
    assert 'native_call(0x08023188,{0,idx,wa,1,eidx,wb}' not in src, "旧的写死阵营 1 必须消失"
    assert 'local function current_tactics2' not in src
    lua_check(FIXTURE, execute=True)
    lua_check(RESUP_FIXTURE, execute=True)
    deadline_fixture='''
local CTX=0
local turn=1
local memory={read_u32_le=function(a) return 0x02001000 end}
local function r8(a) if a==0x02001079 then return 30 elseif a==0x20 then return turn end;return 0 end
local function all_units(side) return side=="MY" and {{idx=0,id=305,hp=24,fuel=40}} or {{hp=16}} end
local function on_building(x,y) return false end
local function tb() return 0 end
local function player_side() return 0 end
local function is_capturer(id) return id==305 end
local function log(s) end
local function terrain_at(x,y) return x==9 and 0x10 or 1 end
'''+(ROOT/'lua/current_deadline2.lua').read_text(encoding='utf-8')+'''
cs_update_clock()
assert(cs_clock.left==30 and cs_clock.urgency==0.25,"read the actual scenario deadline")
local early=cs_time_cost({x=1,y=1,kind="engage"},5,5,true)
turn=27;cs_update_clock()
assert(cs_clock.left==4 and cs_clock.urgency==2,"urgency must increase near the deadline")
local late=cs_time_cost({x=1,y=1,kind="engage"},5,5,true)
assert(late<early,"waiting and route duration must cost more late in the game")
local _,possible,eta=cs_time_cost({x=1,y=1,kind="engage"},20,5,false)
assert(possible and eta==5,"pursuit must remain active even when the complete route exceeds the deadline")
local capital=cs_time_cost({x=9,y=1,kind="capture"},0,5,false)
local city=cs_time_cost({x=1,y=1,kind="capture"},0,5,false)
assert(capital>city,"prefer a reachable winning capital over a detour city")
turn=30;cs_update_clock()
assert(select(2,cs_time_cost({x=1,y=1,kind="capture"},0,5,false)),"capture reached this turn is still feasible")
assert(not select(2,cs_time_cost({x=1,y=1,kind="capture"},1,5,false)),"one more move cannot fit after the last turn")
assert(not select(2,cs_time_cost({x=1,y=1,kind="resupply"},0,5,false)),"refill benefiting next turn is too late on the final turn")
print("PASS deadline reading, urgency, ETA feasibility, wait penalty and capital priority")
'''
    lua_check(deadline_fixture,execute=True)
    fire_fixture='''
local CTX,U,STRIDE=0,0x10000,24
local my={{idx=0,id=187,x=1,y=1,hp=16,fuel=40},{idx=1,id=187,x=1,y=2,hp=16,fuel=40},{idx=2,id=187,x=1,y=3,hp=16,fuel=40}}
local en={{side=1,idx=0,id=305,x=2,y=1,hp=8},{side=2,idx=0,id=305,x=3,y=1,hp=4}}
local calls={}
local function r8(a)
 if a==0 then return 7 end
 if a>=U then return 4 end
 local off=(a-0x2000)%32
 if off==8 then return 4 elseif off==13 then return 3 end
 return 0
end
local function wslot(id,wa) return 0x2000+wa*32 end
local function tcls(id) return 0 end
local function hexd(ax,ay,bx,by) return math.max(math.abs(ax-bx),math.abs(ay-by)) end
local function estimate(a,b,power) return power end
local function enemy_counter(e,id,d) return 0 end
local function terrain_at(x,y) return x==2 and y==1 and 0x10 or 1 end
local function is_capturer(id) return id==305 end
local function cs_guard(u,en) return false end
local function cs_needs_supply(u) return false end
local function log(s) end
local function all_units(side)
 if side=="MY" then return my end
 local alive={};for _,e in ipairs(en) do if e.hp>0 then alive[#alive+1]=e end end;return alive
end
local function unit(side,k) return my[k+1] end
local function attack(k,e)
 calls[#calls+1]={slot=k,side=e.side,idx=e.idx,before=e.hp}
 my[k+1].acted=true;e.hp=math.max(0,e.hp-4);return "OK"
end
local cs_stuck_aborted=false
local function cs_recover_stuck(k) error("unexpected") end
local current_orders={}
'''+(ROOT/'lua/current_fireplan2.lua').read_text(encoding='utf-8')+'''
cs_fire_phase()
assert(#calls==3,"all stationary firing units must be evaluated before movement")
assert(calls[1].side==1 and calls[1].idx==0 and calls[2].side==1 and calls[2].before==4,"capital focus fire must re-read actual remaining HP")
assert(calls[3].side==2 and calls[3].idx==0,"same slot in another faction must remain a distinct target")
assert(my[1].x==1 and my[2].x==1 and my[3].x==1,"stationary fire must not spend movement")
print("PASS global fire scan, dynamic capital focus, no-move attacks and last-faction targets")
'''
    fire_fixture+=(ROOT/'lua/current_mobility2.lua').read_text(encoding='utf-8')+'''
my[1].acted=false
en={{side=2,idx=3,id=305,x=2,y=1,hp=4}}
assert(cs_before_wait(0),"a fresh stationary attack must be rechecked before waiting")
assert(calls[#calls].idx==3 and my[1].x==1,"before-wait fallback must attack without moving")
print("PASS final before-wait attack fallback")
'''
    lua_check(fire_fixture,execute=True)
    wait_loop=tail[tail.index(' local i,manual=0,false'):tail.index(' assert(done,string.format("native call')]
    lua_check('''
local addr,maxframes,done=0x08023188,6000,false
local tick,notifications,speed=0,0,200
local MAILBOX,RUN,CURRENT_SPEED=0,"",200
local memory={read_u32_le=function(a) return tick<1300 and 2 or 3 end}
local function adv(n) tick=tick+n end
local client={speedmode=function(value) speed=value end}
local marker=""
local function writefile(path,text) marker=text end
local function log(s) if s:find("MANUAL_WAIT") then notifications=notifications+1 end end
local function tap() error("manual confirmation must not be automated") end
'''+wait_loop+'''
assert(done and notifications==1 and marker=="" and speed==200,"wait for manual confirmation and resume only after native return")
print("PASS manual dialog wait without auto-A or mailbox reset")
''',execute=True)
    print("PASS: Lua syntax; multi-faction enumeration; city-resupply awareness; "
          "all native calls are side-parameterised.")


if __name__ == "__main__":
    main()
