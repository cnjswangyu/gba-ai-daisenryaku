"""Build/control a reversible Thumb mailbox calling the game's own functions.

The hook runs on the game's normal map call stack. It never writes CPU registers
from Lua, enemy HP, or a victory result. The original ROM file is not modified.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools import first_clear_control as bridge

RUN = ROOT / "shots" / "native_attack"
CAVE = 0x0203FC00
MAIL = 0x0203FE00


class Thumb:
    """Small label/literal encoder for the audited ARM7TDMI trampoline only."""
    def __init__(self):
        self.data = bytearray()
        self.labels = {}
        self.fixups = []
        self.listing = []

    def emit(self, word, text):
        self.listing.append((len(self.data), text))
        self.data += struct.pack("<H", word)

    def label(self, name):
        self.labels[name] = len(self.data)

    def literal(self, reg, value):
        self.fixups.append((len(self.data), "literal", (reg, value)))
        self.emit(0, f"ldr r{reg}, =0x{value:08X}")

    def branch(self, name, condition=None):
        self.fixups.append((len(self.data), "branch", (name, condition)))
        self.emit(0, f"b{condition or ''} {name}")

    def bl(self, name):
        self.fixups.append((len(self.data), "bl", name))
        self.emit(0, f"bl {name}")
        self.emit(0, "(BL second half)")

    def finish(self):
        if len(self.data) % 4:
            self.emit(0x46C0, "nop; align literal pool")
        pool = {}
        for at, kind, value in self.fixups:
            if kind == "literal":
                reg, constant = value
                if constant not in pool:
                    pool[constant] = len(self.data)
                    self.data += struct.pack("<I", constant)
                offset = pool[constant] - ((at + 4) & ~3)
                assert offset >= 0 and offset % 4 == 0 and offset < 1024
                struct.pack_into("<H", self.data, at, 0x4800 | reg << 8 | offset // 4)
            elif kind == "branch":
                name, condition = value
                offset = (self.labels[name] - at - 4) // 2
                assert -128 <= offset < 128
                word = (0xD100 | (offset & 255)) if condition == "ne" else (0xE000 | (offset & 2047))
                struct.pack_into("<H", self.data, at, word)
            else:
                offset = self.labels[value] - at - 4
                assert offset % 2 == 0 and -(1 << 22) <= offset < (1 << 22)
                struct.pack_into("<HH", self.data, at,
                                 0xF000 | ((offset >> 12) & 2047),
                                 0xF800 | ((offset >> 1) & 2047))
        return bytes(self.data)


def make_stub():
    a = Thumb()
    a.emit(0xB5F0, "push {r4-r7,lr}")
    a.literal(4, MAIL)
    a.emit(0x6825, "ldr r5,[r4,#0]")
    a.emit(0x2D01, "cmp r5,#1")
    a.branch("original", "ne")
    a.emit(0x2502, "movs r5,#2; busy")
    a.emit(0x6025, "str r5,[r4,#0]")
    a.emit(0xB083, "sub sp,#12; two stack args plus alignment")
    a.emit(0x69A6, "ldr r6,[r4,#24]")
    a.emit(0x9600, "str r6,[sp,#0]")
    a.emit(0x69E6, "ldr r6,[r4,#28]")
    a.emit(0x9601, "str r6,[sp,#4]")
    a.emit(0x466E, "mov r6,sp")
    a.emit(0x62A6, "str r6,[r4,#40]; stack before call")
    a.emit(0x6865, "ldr r5,[r4,#4]; native function")
    for reg, offset in enumerate((8, 12, 16, 20)):
        a.emit(0x6800 | (offset // 4) << 6 | 4 << 3 | reg, f"ldr r{reg},[r4,#{offset}]")
    a.bl("call_r5")
    a.emit(0x6220, "str r0,[r4,#32]")
    a.emit(0x6261, "str r1,[r4,#36]")
    a.emit(0x466E, "mov r6,sp")
    a.emit(0x62E6, "str r6,[r4,#44]; stack after call")
    a.emit(0xB003, "add sp,#12")
    a.emit(0x2503, "movs r5,#3; done")
    a.emit(0x6025, "str r5,[r4,#0]")
    a.emit(0xBDF0, "pop {r4-r7,pc}")
    a.label("original")
    a.emit(0xBCF0, "pop {r4-r7}")
    a.emit(0xBC08, "pop {r3}; original caller LR")
    a.emit(0x469E, "mov lr,r3")
    a.emit(0xB530, "push {r4,r5,lr}; original prologue")
    a.literal(3, 0x080023ED)
    a.bl("call_r3")
    a.emit(0x0600, "lsls r0,r0,#24; original instruction")
    a.literal(3, 0x08018AFD)
    a.emit(0x4718, "bx r3; original continuation")
    a.label("call_r5")
    a.emit(0x4728, "bx r5")
    a.label("call_r3")
    a.emit(0x4718, "bx r3")
    data = a.finish()
    assert len(data) < 0x1C0
    return data, a.listing


LUA = r'''
local RUN=BASE .. "shots/native_attack/"
local CAMPAIGN=1
local SAVE_PREFIX="stage1_v2"
local HOOK,CAVE,MAILBOX=0x08018AF4,0x0203FC00,0x0203FE00
local original={0x30,0xB5,0xE9,0xF7,0x79,0xFC,0x00,0x06}
local installed=false
local native_frames={}
local backup=nil
local stub=nil
local function writefile(path,text)
 local f=assert(io.open(path,"w")); f:write(text); f:close()
end
local function restore_keyboard()
 local n=0
 for addr=0x03000000,0x03007FFC,4 do
  if memory.read_u32_le(addr)==0x03007F00 then memory.write_u32_le(addr,0x04000130); n=n+1 end
 end
 if memory.read_u32_le(0x080015F4)==0x03007F00 then memory.write_u32_le(0x080015F4,0x04000130) end
 mailOK=false
 log("恢复原生键盘输入，IWRAM " .. n .. " 处")
end
local function uninstall()
 if not installed then return end
 assert(memory.read_u32_le(MAILBOX)~=2,"native call is still running")
 for i=1,8 do memory.write_u8(HOOK+i-1,original[i]) end
 for i=1,#backup do memory.write_u8(CAVE+i-1,backup[i]) end
 installed=false
 log("原生调用补丁已移除")
end
local function install()
 if installed then return end
 assert(r8(CTX)==7 and r8(CTX+1)==1 and r8(CTX+0x21)==3 and r8(CTX+0x22)==0,"not player map phase")
 for i=1,8 do assert(r8(HOOK+i-1)==original[i],"ROM entry differs from audited bytes") end
 local f=assert(io.open(BASE .. "lua/native_attack_stub.bin","rb")); stub=f:read("*a"); f:close()
 backup={}
 for i=0,0x23F do
  local b=r8(CAVE+i); assert(b==0,"EWRAM code/mailbox region is occupied"); backup[#backup+1]=b
 end
 for i=1,#stub do memory.write_u8(CAVE+i-1,stub:byte(i)) end
 for i=0,63 do memory.write_u8(MAILBOX+i,0) end
 memory.write_u16_le(HOOK,0x4B00); memory.write_u16_le(HOOK+2,0x4718)
 memory.write_u32_le(HOOK+4,CAVE+1)
 installed=true
 adv(8)
 log("已安装自然地图调用点 Thumb mailbox，" .. #stub .. " bytes")
end
local whitelist={ [0x08002E74]=true,[0x08023940]=true,[0x08023188]=true,[0x0801F078]=true,[0x0801F130]=true,[0x08016BE0]=true,[0x080169D4]=true,[0x08020B20]=true,[0x08020F14]=true }
local function native_call(addr,args,maxframes)
 assert(whitelist[addr],"function is not on audited whitelist")
 install()
 for i=1,#stub do assert(r8(CAVE+i-1)==stub:byte(i),"code cave changed") end
 assert(memory.read_u32_le(MAILBOX)~=2,"mailbox busy")
 memory.write_u32_le(MAILBOX+4,addr+1)
 for i=1,6 do memory.write_u32_le(MAILBOX+4+i*4,(args[i] or 0)&0xFFFFFFFF) end
 memory.write_u32_le(MAILBOX+32,0xDEADBEEF)
 memory.write_u32_le(MAILBOX,1)
 local start_frame=emu.framecount()
 local done=false
 for i=1,(maxframes or 1200) do
  adv(1)
  -- Last kill can open the native surrender confirmation before this call returns.
  -- Accept only during a battle with no surviving enemies, never during ordinary attacks.
  if addr==0x08023188 and i>120 and i%60==0 and #all_units("EN")==0 then
   log("SURRENDER confirming native last-enemy dialog")
   tap("A",20)
  end
  if memory.read_u32_le(MAILBOX)==3 then done=true; break end
 end
 assert(done,string.format("native call 0x%08X did not return; status=%d PC=0x%08X",addr,memory.read_u32_le(MAILBOX),emu.getregister("R15")))
 local before=memory.read_u32_le(MAILBOX+40)
 local after=memory.read_u32_le(MAILBOX+44)
 assert(before==after,"native call stack imbalance")
 assert(r8(CTX+0x990)==0,"player side changed")
 local value=memory.read_u32_le(MAILBOX+32)
 native_frames[addr]=emu.framecount()-start_frame
 log(string.format("CALL 0x%08X -> 0x%08X SP=0x%08X/0x%08X frames=%d",addr,value,before,after,native_frames[addr]))
 if value>=0x80000000 then value=value-0x100000000 end
 return value
end
local function distance(a,b)
 local dq=(a.x-math.floor(a.y/2))-(b.x-math.floor(b.y/2))
 local dr=a.y-b.y
 return math.max(math.abs(dq),math.abs(dr),math.abs(dq+dr))
end
local function attack(idx,eidx)
 assert(idx and eidx and idx>=0 and idx<64 and eidx>=0 and eidx<64,"slot out of bounds")
 local u,e=unit("MY",idx),unit("EN",eidx)
 assert(u and e and u.hp>0 and e.hp>0,"invalid unit/target")
 assert(not u.acted,"unit has already acted")
 memory.write_u8(CTX+0x637E,u.x); memory.write_u8(CTX+0x637F,u.y)
 native_call(0x080169D4,{u.x,u.y})
 native_call(0x08016BE0,{})
 local d=distance(u,e)
 local ur,er=U+idx*STRIDE-2,U+PB+eidx*STRIDE-2
 local classA=r8(0x08798A98+u.id*0x5C+4)
 local classB=r8(0x08798A98+e.id*0x5C+4)
 local wa=native_call(0x08023940,{ur,classB,d})
 local wb=native_call(0x08023940,{er,classA,d})
 assert(wa>=0 and wa<=3 and r8(ur+8+wa)>0,"no usable weapon in range")
 assert(r8(0x08798A98+u.id*0x5C+0x27+wa*16)~=4 or d>=2,"weapon minimum range is 2")
 if wb>=0 then assert(wb<=3 and r8(er+8+wb)>0,"invalid counter weapon") end
 if wb>=0 then assert(r8(0x08798A98+e.id*0x5C+0x27+wb*16)~=4 or d>=2,"counter weapon minimum range requires another weapon") end
 local ammoA,ammoB=r8(ur+8+wa),(wb>=0) and r8(er+8+wb) or -1
 log(string.format("DIRECT U%d -> E%d distance=%d weapons=%d/%d HP=%d/%d",idx,eidx,d,wa,wb,u.hp,e.hp))
 native_call(0x08023188,{0,idx,wa,1,eidx,wb},1800)
 local now=unit("MY",idx)
 if now and now.hp>0 and r8(CTX)==7 and r8(CTX+1)==1 then
  native_call(0x0801F078,{0,idx,0})
  now=unit("MY",idx)
  if now and now.hp>0 then native_call(0x0801F130,{ur}) end
 end
 if r8(CTX)==7 and r8(CTX+1)==1 then native_call(0x08016BE0,{}) end
 adv(30)
 local a,b=unit("MY",idx),unit("EN",eidx)
 return string.format("DIRECT U%d E%d | my HP %d->%d enemy HP %d->%d ammo %d->%d counter %d->%d acted=%s",
  idx,eidx,u.hp,a and a.hp or 0,e.hp,b and b.hp or 0,ammoA,r8(ur+8+wa),ammoB,
  wb>=0 and r8(er+8+wb) or -1,tostring(a and a.acted))
end
local function animation(mode)
 local addr=CTX+0xC55
 local old=r8(addr)
 if mode=="ON" then memory.write_u8(addr,1)
 elseif mode=="OFF" then memory.write_u8(addr,0)
 elseif mode=="TOGGLE" then memory.write_u8(addr,(old==1) and 0 or 1)
 elseif mode~="STATUS" and mode~="" then error("ANIMATION ON|OFF|TOGGLE|STATUS") end
 local now=r8(addr)
 return string.format("ANIMATION %s address=0x%08X value=%d previous=%d",(now==1) and "ON" or "OFF",addr,now,old)
end
local function endturn()
 local oldturn=r8(CTX+0x20)
 uninstall()
 to_map()
 tap("Start", 70)
 for _=1,6 do tap("Up", 12) end
 tap("A", 70)
 tap("A", 90)
 adv(200)
 local back=false
 for i=1,80 do
  if r8(CTX)==8 then
   return r8(CTX+0x2C)==2,"ENDTURN result="..r8(CTX+0x2C)
  end
  if r8(CTX)==7 and r8(CTX+1)==1 and r8(CTX+0x21)==3
      and r8(CTX+0x20)>oldturn and r8(CTX+0x22)==0 and mobile() then back=true; break end
  tap("A", 70); adv(60)
 end
 if not back then return false,"结束回合后未回到新回合可操作态" end
 local msg=string.format("ENDTURN ok turn=%d enemies=%d", r8(CTX+0x20), #all_units("EN"))
 log(msg)
 return true,msg
end
local function hexd(ax,ay,bx,by)
 local dq=(ax-math.floor(ay/2))-(bx-math.floor(by/2))
 local dr=ay-by
 return math.max(math.abs(dq),math.abs(dr),math.abs(dq+dr))
end
local function free_cell_near(tx,ty,want)
 for yy=1,34 do
  for xx=1,46 do
   if hexd(xx,yy,tx,ty)==want and r8(CTX+0x3F60+xx*4+yy*0xC0)==0 then return xx,yy end
  end
 end
 return nil
end
-- ===== 移动共享件（vm 与 autoclear 共用，全逆向：FUN_08002964 + FUN_0801e33e@0x12）=====
local VMLAND_REFRESH=false   -- 落格后是否主动整屏刷新（false = 交给游戏自身渲染，避免画面跳动）
local function vm_ctx(k)
 local u=unit("MY",k)
 assert(u,"槽 "..k.." 无单位")
 assert(not u.acted,"已行动")
 local cat=r8(0x08798A98+u.id*0x5C+5)
 -- TSV 'move' is a movement CATEGORY, not the per-turn budget. ROM +0x0D is speed.
 local mv=r8(0x08798A98+u.id*0x5C+0x0D)
 return u,cat,math.min(mv,u.fuel)
end
local function vm_cost(terr,cat)
 if terr>=0x10 and terr<0x29 then return r8(0x08046FC6+(terr-0x10)+cat*5) end
 local c=r8(memory.read_u32_le(0x080026d4)+terr)
 if c==0 then return 0 end
 return r8(0x08046F26+c+cat*0x10)
end
local function vm_nbrs(x,y)
 local d=(y%2==0) and -1 or 0
 return {{x+1,y},{x-1,y},{x+d,y-1},{x+d+1,y-1},{x+d+1,y+1},{x+d,y+1}}
end
-- Dijkstra：友军可穿行不可落（用户确认），敌军阻挡，移耗 0=不可通行；dist["x,y"]=移耗
local function vm_reach(u,cat,budget)
 local dist,queue={},{ {u.x,u.y,0} }
 dist[u.x..","..u.y]=0
 while #queue>0 do
  table.sort(queue,function(a,b) return a[3]<b[3] end)
  local c=table.remove(queue,1)
  if c[3]==dist[c[1]..","..c[2]] then
   for _,n in ipairs(vm_nbrs(c[1],c[2])) do
    local nx,ny=n[1],n[2]
    if nx>=1 and nx<=46 and ny>=1 and ny<=34 then
     local occ=r8(CTX+0x3F60+nx*4+ny*0xC0)
     if occ==0 or occ==1 then
      local tc=vm_cost(terrain_at(nx,ny),cat)
      if tc==0 then tc=99 end
      local nc=c[3]+tc
      if nc<=budget and (dist[nx..","..ny]==nil or nc<dist[nx..","..ny]) then
       dist[nx..","..ny]=nc; queue[#queue+1]={nx,ny,nc}
      end
     end
    end
   end
  end
 end
 return dist
end
-- 落格字段写（复刻 0x12 分支：格表+记录+燃料+乘客联动+镜头重绘，不含置 acted）
local function vm_land(k,u,x,y,costc)
 local ur=U+k*STRIDE-2
 local g1=CTX+0x3F60+u.x*4+u.y*0xC0
 memory.write_u8(g1,0); memory.write_u8(g1+1,0)
 local g2=CTX+0x3F60+x*4+y*0xC0
 memory.write_u8(g2,1); memory.write_u8(g2+1,k+1)
 memory.write_u8(ur+2,x); memory.write_u8(ur+3,y)
 memory.write_u8(ur+4,u.fuel-costc)
 memory.write_u8(CTX+0x637E,x); memory.write_u8(CTX+0x637F,y)
 if bit.band(r8(ur+7),4)~=0 then
  for i=0,5 do
   local pid=r8(ur+12+i)
   if pid~=0 then
    local pr=CTX+pid*0x18-0x18+2
    memory.write_u8(pr,x); memory.write_u8(pr+1,y)
   end
  end
 end
 -- 注意：FUN_080169D4 / FUN_08016BE0 是整屏刷新包装（内含滚屏/淡入重置），
 -- 每移动一个单位调一次会让画面到处跳 → 默认不调，交给游戏自己的每帧渲染。
 if VMLAND_REFRESH then
  native_call(0x080169D4,{x,y})
  native_call(0x08016BE0,{})
 end
end
local function vm(k,x,y)
 local u,cat,budget=vm_ctx(k)
 assert(x>=1 and x<=46 and y>=1 and y<=34,"越界")
 local dist=vm_reach(u,cat,budget)
 local c=dist[x..","..y]
 assert(c, string.format("(%d,%d) 不在移动范围内（预算 %d）",x,y,budget))
 assert(r8(CTX+0x3F60+x*4+y*0xC0)==0,"目标格被占用（可穿不可停）")
 vm_land(k,u,x,y,c)
 native_call(0x0801F130,{U+k*STRIDE-2})
 local u2=unit("MY",k)
 assert(u2 and u2.x==x and u2.y==y,"落点读回失败")
 return string.format("VM 槽%d(id%d) 落点(%d,%d) 移耗%d 燃料%d->%d acted=1",
  k,u.id,x,y,c,u.fuel,u2.fuel)
end
-- ===== 占领（行动分派 0x22 分支 → FUN_08020b20(side, slot)）=====
-- 可占领地形判定 = FUN_080026d8: (terr-0x10) < 0x19 → 0x10..0x28 全部建筑类
local function terr_base() return memory.read_u32_le(CTX + 0x18) end
local function capturable(x,y)
 local t=r8(terr_base()+x*4+y*0xC0)
 return t>=0x10 and t<=0x28
end
local function cap(k)
 local u=unit("MY",k); assert(u,"槽 "..k.." 无单位")
 assert(not u.acted,"已行动")
 assert(u.id==305 or u.id==324,"当前接口仅验证步兵/空降兵占领")
 assert(capturable(u.x,u.y), string.format("(%d,%d) 地形不可占领",u.x,u.y))
 local cb=terr_base()+u.x*4+u.y*0xC0
 local ob,mb=r8(cb+2),memory.read_u32_le(CTX+0x24)
 assert(ob~=1,"已经是我方建筑")
 native_call(0x08020B20,{0,k})          -- 占領：归属翻转 + 收入 + 首都胜利判定
 adv(3)
 local oa,ma=r8(cb+2),memory.read_u32_le(CTX+0x24)
 if r8(CTX)==7 and r8(CTX+1)==1 then native_call(0x0801F130,{U+k*STRIDE-2}) end
 local msg=string.format("CAP 槽%d 占領(%d,%d) 归属%d->%d 资金%d->%d state=%d/%d",
  k,u.x,u.y,ob,oa,mb,ma,r8(CTX),r8(CTX+1))
 log(msg)
 return msg
end
local function commander()
 return string.format("rank=%d points=%d money=%d state=%d",r8(CTX+0x65),memory.read_u32_le(CTX+0x6C),memory.read_u32_le(CTX+0x68),r8(CTX))
end
local function settle_result(previous_points,previous_rank)
 assert(r8(CTX)==8 and r8(CTX+0x2C)==2,"not a victory result")
 local credited_at=nil
 for i=1,12000 do
  adv(1)
  if r8(CTX+0x65)>previous_rank then
   adv(90)
   client.screenshot(BASE.."shots/farm_rank_promotion.png")
   savestate.save(BASE.."states/farm_rank_promotion.State")
   log("PROMOTED "..commander())
   return true
  end
  if memory.read_u32_le(CTX+0x6C)>previous_points then
   credited_at=credited_at or i
   if i-credited_at>=400 then log("CREDITED "..commander()); return false end
  end
 end
 error("native result points have not been credited; "..commander())
end
local function replay_first(speed)
 uninstall(); client.speedmode(tonumber(speed) or 400)
 assert(r8(CTX)==8 and r8(CTX+0x2C)==2,"REPLAYFIRST needs the previous victory")
 local points,rank=memory.read_u32_le(CTX+0x6C),r8(CTX+0x65)
 savestate.save(BASE.."states/farm_before_reentry.State")
 for i=1,16 do
  if r8(CTX)==3 then break end
  tap("A",50); if r8(CTX)==3 then break end
  tap("B",50); if r8(CTX)==3 then break end
  tap("A",100)
 end
 assert(r8(CTX)==3,"could not leave the result page; "..commander())
 local selected=false
 for i=1,48 do
  tap("A",100)
  if r8(CTX)==4 then
   local p=memory.read_u32_le(CTX+0x14); local same=true
   for j=0,15 do if r8(p+j)~=r8(0x08762B10+j) then same=false end end
   if same then selected=true; break end
   tap("B",50); tap("Up",25)
  elseif r8(CTX)==3 then log("FARM SELECT dismissed scenario-list instructions")
  else error("unexpected scenario selection state "..r8(CTX)) end
 end
 assert(selected,"could not select Military Exercise 1")
 tap("A",100); assert(r8(CTX)==6,"not in deployment dialog")
 local wanted={[187]=9,[241]=4,[305]=4,[324]=2,[339]=1}
 local old,counts,empty={},{},{}
 for k=0,98 do
  local a=CTX+0x188+k*4; local id=memory.read_u16_le(a)
  if id==0 then empty[#empty+1]=k
  else
   assert(wanted[id],"unexpected inherited type "..id)
   counts[id]=(counts[id] or 0)+1
   old[#old+1]={slot=k,id=id,exp=r8(a+2)}
  end
 end
 local additions={}; local cost=0
 for _,id in ipairs({187,241,305,324,339}) do
  assert((counts[id] or 0)<=wanted[id],"inherited army exceeds plan")
  for _=1,wanted[id]-(counts[id] or 0) do
   additions[#additions+1]=id
   cost=cost+memory.read_u16_le(0x08798A98+id*0x5C+0x1A)
  end
 end
 local money=memory.read_u32_le(CTX+0x68)
 assert(#old+#additions==20 and #empty>=#additions and money>=cost,"cannot replenish inherited army")
 for i,id in ipairs(additions) do
  local a=CTX+0x188+empty[i]*4
  memory.write_u16_le(a,id); memory.write_u8(a+2,0); memory.write_u8(a+3,0)
 end
 memory.write_u32_le(CTX+0x68,money-cost)
 log(string.format("FARM REPLENISH veterans=%d added=%d cost=%d points=%d rank=%d",#old,#additions,cost,points,rank))
 savestate.save(BASE.."states/farm_stage1_army_ready.State")
 local deployed=false
 for trial=1,2 do
  savestate.load(BASE.."states/farm_stage1_army_ready.State"); adv(15); restore_keyboard()
  tap("A",180)
  if trial==1 then tap("A",40) end
  for i=1,20 do tap("A",35); if i<20 then tap("Down",35) end end
  tap("Start",90); tap("A",120); adv(500)
  if #all_units("MY")==20 then deployed=true; break end
 end
 assert(deployed,"could not deploy all inherited/replenished units")
 for _,v in ipairs(old) do
  local a=CTX+0x188+v.slot*4; local k=r8(a+3)%100-1
  assert(k>=0 and k<64,"missing deployment association")
  local record=U-2+k*STRIDE
  assert(memory.read_u16_le(record)==v.id and r8(record+5)==v.exp,"veteran experience was not preserved")
 end
 tap("Start",90); tap("A",120)
 local ready=false
 for i=1,30 do
  adv(60)
  if r8(CTX)==7 and r8(CTX+1)==1 and r8(CTX+0x21)==3 and r8(CTX+0x22)==0 then ready=true; break end
  tap("A",40)
 end
 assert(ready,"replay did not enter player phase")
 tap("B",40)
 assert(memory.read_u32_le(CTX+0x6C)==points and r8(CTX+0x65)==rank,"commander progress changed during replay setup")
 savestate.save(BASE.."states/farm_stage1_deployed.State")
 log("FARM REPLAY READY "..commander())
 return "OK REPLAYFIRST "..commander()
end
local function autoclear(speed)
 -- ===== 武器表（ROM 实测：DB=0x08798AF4，槽 i = base+(id-1)*0x5C+0x18+i*0x10）=====
 -- 槽+0xD=最大射程, 槽+8+目标类别=攻击力(类别=敌 entry+4)，弹药=单位记录+8+i
 local DB=0x08798AF4
 local function wslot(id,wa) return DB+(id-1)*0x5C+0x18+wa*0x10 end
 local function tcls(id) return r8(DB+(id-1)*0x5C+4) end
 local function uammo(k,wa) return r8(U+k*STRIDE-2+8+wa) end
 -- ===== 战术 =====
 client.speedmode(tonumber(speed) or 800)
 local initial_points,initial_rank=memory.read_u32_le(CTX+0x6C),r8(CTX+0x65)
 local report={}
 local function progress()
  writefile(RUN.."state.txt",build_state()..string.format("CTX state=%d sub=%d result=%d animation=%d\n",r8(CTX),r8(CTX+1),r8(CTX+0x2C),r8(CTX+0xC55)))
  client.screenshot(RUN.."current.png")
 end
 local function finish(reason)
  uninstall()
  for i=1,160 do
   if r8(CTX)==8 then break end
   adv(20)
   if i%5==0 then tap("A",20) end
  end
  adv(600) -- Let the flag intro reach the visible victory title before freezing the bridge.
  if r8(CTX)==8 and r8(CTX+0x2C)==2 then settle_result(initial_points,initial_rank) end
  progress()
  client.speedmode(100)
  if r8(CTX)~=8 or r8(CTX+0x2C)~=2 then
   return string.format("FAIL 结算未确认胜利 state=%d/%d result=%d",r8(CTX),r8(CTX+1),r8(CTX+0x2C))
  end
  savestate.save(BASE.."states/"..SAVE_PREFIX.."_victory.State")
  client.screenshot(BASE.."shots/"..SAVE_PREFIX.."_victory.png")
  local report_prefix=SAVE_PREFIX:match("^farm_") and SAVE_PREFIX or (CAMPAIGN==2 and "stage2" or "stage1")
  writefile(BASE.."logs/"..report_prefix.."_battle_report.txt",table.concat(report,"\n"))
  local msg=string.format("VICTORY %s turn=%d friendly=%d enemies=%d result=2",reason,r8(CTX+0x20),#all_units("MY"),#all_units("EN"))
  msg=msg.." "..commander(); log(msg)
  return msg
 end
 local function markacted(k)
  local u=unit("MY",k)
  if u and not u.acted then native_call(0x0801F130,{U+k*STRIDE-2}) end
 end
 local function best_reach_cell(reach,e,want)
  -- 从可达集中选 dist==want、空置、防御最高的落点
  local bx,by,bs=nil,nil,-1e9
  for key in pairs(reach) do
   local xx,yy=key:match("(-?%d+),(-?%d+)")
   xx,yy=tonumber(xx),tonumber(yy)
   if hexd(xx,yy,e.x,e.y)==want and r8(CTX+0x3F60+xx*4+yy*0xC0)==0 then
     local t=tdef(terrain_at(xx,yy))*100-reach[key]*2-yy*0.01-xx*0.0001
    if t>bs then bs,bx,by=t,xx,yy end
   end
  end
  return bx,by
 end
 local function route_field(e,pref,cat)
  local costs,queue={},{}
  for y=1,34 do for x=1,46 do
   if hexd(x,y,e.x,e.y)==pref and vm_cost(terrain_at(x,y),cat)>0
       and r8(CTX+0x3F60+x*4+y*0xC0)<=1 then
    costs[x..","..y]=0; queue[#queue+1]={x,y,0}
   end
  end end
  local head=1
  while head<=#queue do
   local node=queue[head]; head=head+1
   local key=node[1]..","..node[2]
   if costs[key]==node[3] then
    local step_cost=vm_cost(terrain_at(node[1],node[2]),cat)
    for _,n in ipairs(vm_nbrs(node[1],node[2])) do
     local x,y=n[1],n[2]
     if x>=1 and x<=46 and y>=1 and y<=34 and vm_cost(terrain_at(x,y),cat)>0
         and r8(CTX+0x3F60+x*4+y*0xC0)<=1 then
      local nk=x..","..y; local candidate=node[3]+step_cost
      if not costs[nk] or candidate<costs[nk] then
       costs[nk]=candidate; queue[#queue+1]={x,y,candidate}
      end
     end
    end
   end
  end
  return costs
 end
 local function best_advance_cell(reach,e,pref,cat)
  -- 无攻击方案时：可达集中逼近本兵种最优交战距离、防御最高的推进点
  local bx,by,bs,bd=nil,nil,-1e9,nil
  local routes=(CAMPAIGN==2) and route_field(e,pref,cat) or nil
  for key in pairs(reach) do
   local xx,yy=key:match("(-?%d+),(-?%d+)")
   xx,yy=tonumber(xx),tonumber(yy)
   if r8(CTX+0x3F60+xx*4+yy*0xC0)==0 then
    local dd=hexd(xx,yy,e.x,e.y)
    local remaining=math.abs(dd-pref)
    if routes then remaining=routes[key] end
    local sc=remaining and (-remaining*100+tdef(terrain_at(xx,yy))) or -1e10
    if CAMPAIGN==2 then sc=sc-reach[key]*0.1-yy*0.001-xx*0.00001 end
    if sc>bs then bs,bx,by,bd=sc,xx,yy,dd end
   end
  end
  return bx,by,bd
 end
 local function my_best(u,dist,eid)
  -- 我方对 eid 的最佳可用攻击力（考虑弹药/射程）
  local cls=tcls(eid)
  local best=-1
  for wa=0,3 do
   if uammo(u.idx,wa)>0 then
    local a=r8(wslot(u.id,wa)+8+cls)
    local mr=r8(wslot(u.id,wa)+13)
    if a>0 and dist<=mr and a>best then best=a end
   end
  end
  return best
 end
 local function enemy_counter(e,myid,dist)
  local cls=tcls(myid)
  local best=0
  for wa=0,3 do
   local ammo=r8(U+0x600+e.idx*STRIDE-2+8+wa)
   if ammo>0 then
    local a=r8(wslot(e.id,wa)+8+cls)
    local mr=r8(wslot(e.id,wa)+13)
    if a>best and dist<=mr then best=a end
   end
  end
  return best
 end
 -- Approximate native attack/defence ratio (FUN_08020010/2008C/20220).
 -- Actual HP, ammo and kills are always read back after the real battle.
 local function estimate(att,def,power,x,y)
  if power<=0 then return 0 end
  local ab=DB+(att.id-1)*0x5C
  local bb=DB+(def.id-1)*0x5C
  local ac=math.ceil(att.hp/math.max(1,r8(ab+0x0E)))
  local dc=math.ceil(def.hp/math.max(1,r8(bb+0x0E)))
  local armour=r8(bb+0x14+tcls(att.id))+tdef(terrain_at(x or def.x,y or def.y))
  local weather=(r8(CTX+0x23)==3) and 0.7 or ((r8(CTX+0x23)==1) and 1 or 0.85)
  return math.max(0,math.floor(4*power*ac*weather/math.max(1,armour*dc)))
 end
 local function tb() return memory.read_u32_le(CTX+0x18) end
 local function on_building(x,y)
  local t=r8(tb()+x*4+y*0xC0)
  return t>=0x10 and t<=0x28
 end
 local function enemy_capital()
  local b=tb()
  for y=1,34 do
   for x=1,46 do
    local c=b+x*4+y*0xC0
    if r8(c)==0x10 and r8(c+2)~=1 then return x,y end
   end
  end
 end
 local function is_capturer(id) return id==305 or id==324 end
 local function try_capture_capital(tn)
  local cx,cy=enemy_capital()
  if not cx then return false end
  if r8(CTX+0x3F60+cx*4+cy*0xC0)~=0 then return false end   -- 首都上有守军，先清场
  for k=0,63 do
   local u=unit("MY",k)
   if u and u.hp>0 and not u.acted and is_capturer(u.id) then
    local _,cat,budget=vm_ctx(k)
    local reach=vm_reach(u,cat,budget)
    local c=reach[cx..","..cy]
    if c then
     local okm=pcall(vm_land,k,u,cx,cy,c)
     if okm then
      local okc,msgc=pcall(cap,k)
      report[#report+1]=string.format("T%d 首都占領 %s",tn,tostring(msgc))
      return okc
     end
    end
   end
  end
  return false
 end
 for iteration=1,30 do
  local turn=r8(CTX+0x20)
  log(string.format("TURN %d game_turn=%d friendly=%d enemies=%d",turn,r8(CTX+0x20),#all_units("MY"),#all_units("EN")))
  -- 首都攻略（优先）：能占就占 —— 占领首都即胜利条件
  if try_capture_capital(turn) then
   uninstall(); savestate.save(BASE.."states/"..SAVE_PREFIX.."_capital.State")
   return finish("占領敌方首都")
  end
  for k=0,63 do
   local u=unit("MY",k)
   if u and u.hp>0 and not u.acted then
    local en=all_units("EN")
    if #en==0 then break end
    if u.id>=339 and u.id<=345 then
     markacted(k)
    else
     local _,cat0,budget0=vm_ctx(k)
     local reach=vm_reach(u,cat0,budget0)
     local bestScore,bestPlan=-1,nil
     for _,e in ipairs(en) do
      local plans={}
      local d0=hexd(u.x,u.y,e.x,e.y)
      local h0=my_best(u,d0,e.id)
      if h0>0 then plans[#plans+1]={d=d0,atk=h0} end
      for want=1,3 do
       if want~=d0 and k~=0 then -- U0 guards our capital, blocking a cheap enemy capture.
        local hit=my_best(u,want,e.id)
        if hit>0 then
         local cx,cy=best_reach_cell(reach,e,want)
         if cx then plans[#plans+1]={d=want,atk=hit,cx=cx,cy=cy} end
        end
       end
      end
      for _,p in ipairs(plans) do
       local counter=enemy_counter(e,u.id,p.d)
       local hp=u.hp
       local eff=estimate(u,e,p.atk)
       local loss=estimate(e,u,counter,p.cx or u.x,p.cy or u.y)
       local kill=eff>=e.hp
       -- 比较估计 HP 损失；建筑守军可被同回合集火，不再禁止所有非致命攻击。
       if eff<1 or (loss>=hp and not kill) then
        -- skip
       else
        local threat=hexd(e.x,e.y,21,30)
        local score=math.min(eff,e.hp)*16-loss*20+(kill and 180 or 0)
             +((threat<=6) and (7-threat)*20 or 0)
             +((e.id==224 or e.id==235) and 50 or 0)
             +((CAMPAIGN==2 and e.id==243) and 70 or 0)
             +((CAMPAIGN==2 and e.id==211) and 40 or 0)
             +((e.hp<(db(e.id).dur*4)) and 20 or 0)
             -((p.cx and reach[p.cx..","..p.cy]) or 0)
        if score>bestScore then
         bestScore,bestPlan=score,{e=e,p=p}
        end
       end
      end
     end
     if bestPlan then
      local e,p=bestPlan.e,bestPlan.p
      local ok,amsg=true,""
      if p.cx then
       local okm,amsgm=pcall(vm_land,k,u,p.cx,p.cy,reach[p.cx..","..p.cy] or 1)
       if okm then
        adv(10)
       else
        ok,amsg=false,"落格失败:"..tostring(amsgm)
       end
      end
      if ok then
       local ok2,amsg2=pcall(attack,k,e.idx)
       ok,amsg=ok2,tostring(amsg2)
      end
      report[#report+1]=string.format("T%d U%d(id%d)->E%d(id%d) %s %s",turn,k,u.id,e.idx,e.id,ok and "OK" or "FAIL",amsg)
      log(report[#report]); progress()
      if r8(CTX)==8 or #all_units("EN")==0 then return finish("全歼/战斗结算") end
      if not ok then markacted(k) end
     else
      -- 无攻击方案：占领单位优先占可达的敌/中立建筑（拿钱 + 断敌方补给）；否则推进
      local be,bd=nil,1e9
      for _,e in ipairs(en) do
       local d=hexd(u.x,u.y,e.x,e.y)
       if d<bd then bd,be=d,e end
      end
      local did_cap=false
      if is_capturer(u.id) then
       local bbase=tb()
       local capx2,capy2=0,0
       do
        local cx2,cy2=enemy_capital()
        if cx2 then capx2,capy2=cx2,cy2 end
       end
       local bcx,bcy,bcd=nil,nil,1e9
       for key in pairs(reach) do
        local xx,yy=key:match("(-?%d+),(-?%d+)")
        xx,yy=tonumber(xx),tonumber(yy)
        if r8(CTX+0x3F60+xx*4+yy*0xC0)==0 then
         local c=bbase+xx*4+yy*0xC0
         local t=r8(c)
         if t>=0x10 and t<=0x28 and r8(c+2)~=1 then
          -- 优先占“朝敌首都方向”的建筑；无首都信息则朝最近敌
          local dd=(capx2>0) and hexd(xx,yy,capx2,capy2) or (be and hexd(xx,yy,be.x,be.y) or 0)
          if dd<bcd then bcd,bcx,bcy=dd,xx,yy end
         end
        end
       end
       if bcx then
        local c=reach[bcx..","..bcy]
        local okm=pcall(vm_land,k,u,bcx,bcy,c)
        if okm then
         local okc,msgc=pcall(cap,k)
         report[#report+1]=string.format("T%d U%d 占城 %s",turn,k,tostring(msgc))
         did_cap=true
        end
       end
      end
      if not did_cap and be and k~=0 then
       local pref=1
       for d=3,1,-1 do
        if my_best(u,d,be.id)>0 then pref=d break end
       end
       local ax,ay=best_advance_cell(reach,be,pref,cat0)
       if ax and (ax~=u.x or ay~=u.y) then
        pcall(vm,k,ax,ay)
       end
      end
      markacted(k)
     end
     if #all_units("EN")==0 then
      return finish("全歼敌军")
     end
    end
   end
  end
  -- 本回合清场后：同回合补占首都（胜利条件）
  if try_capture_capital(turn) then
   uninstall(); savestate.save(BASE.."states/"..SAVE_PREFIX.."_capital.State")
   return finish("占領敌方首都")
  end
  if #all_units("EN")>0 then
   local okm,msgm=endturn()
   report[#report+1]=msgm
   if r8(CTX)==8 then return finish("回合结算") end
   if not okm then
    client.speedmode(100)
    return "FAIL ENDTURN: "..msgm
   end
   savestate.save(BASE.."states/"..SAVE_PREFIX.."_t"..turn..".State")
   progress()
  end
 end
 client.speedmode(100)
 return "AUTOCLEAR v2 结束: "..table.concat(report," | ")
end
local function animation_test()
 uninstall()
 local original_state=BASE .. "states/animation_user_before.State"
 savestate.save(original_state)
 savestate.load(BASE .. "states/first_clear_start.State"); adv(30); restore_keyboard()
 local ok,msg=teleport_mem(0,18,29); assert(ok,msg)
 native_call(0x080169D4,{18,29}); native_call(0x08016BE0,{})
 uninstall()
 local baseline=BASE .. "states/animation_ab_base.State"
 savestate.save(baseline)
 local results={}
 for _,mode in ipairs({"OFF","ON"}) do
  savestate.load(baseline); adv(2); restore_keyboard()
  animation(mode)
  recordName=(mode=="ON") and "animation_on" or "animation_off"
  recordFrame=0; recordTick=0
  log("ANIMATION_TEST " .. mode .. " begin")
  local msg=attack(0,0)
  recordName=nil
  local u,e=unit("MY",0),unit("EN",0)
  local frames=native_frames[0x08023188]
  results[#results+1]=string.format('  {"mode":"%s","value":%d,"battle_frames":%d,"my_hp":%d,"enemy_hp":%d,"my_ammo":%d,"acted":%s}',mode,r8(CTX+0xC55),frames,u.hp,e.hp,u.ammo,tostring(u.acted))
  log("ANIMATION_TEST " .. mode .. " frames=" .. frames .. " " .. msg)
  uninstall()
  savestate.save(BASE .. "states/animation_" .. mode:lower() .. "_verified.State")
 end
 writefile(BASE .. "logs/animation_ab.json","[\n" .. table.concat(results,",\n") .. "\n]\n")
 savestate.load(original_state); adv(2); restore_keyboard()
 return "OK ANIMATION_TEST complete; original battle restored; logs/animation_ab.json"
end
-- Read-only full map/army export. VIEWMAP is the game's R shoulder button.
local function mapdata()
 local base=memory.read_u32_le(CTX+0x18)
 assert(base>=0x02000000 and base+48*48*4<=0x02040000,"map is not loaded")
 local cells,roster,units={},{},{}
 for y=0,47 do for x=0,47 do
  local a=base+x*4+y*0xC0
  cells[#cells+1]=string.format('[%d,%d,%d,%d,%d,%d]',x,y,r8(a),r8(a+1),r8(a+2),r8(a+3))
 end end
 for k=0,98 do
  local a=CTX+0x188+k*4
  local id=memory.read_u16_le(a)
  if id~=0 then roster[#roster+1]=string.format('{"slot":%d,"id":%d,"exp":%d,"exp_address":%d,"flag":%d}',k,id,r8(a+2),a+2,r8(a+3)) end
 end
 for side=0,1 do for k=0,63 do
  local u=unit(side==0 and "MY" or "EN",k)
  if u then
   local a=U-2+side*PB+k*STRIDE
   units[#units+1]=string.format('{"side":%d,"slot":%d,"id":%d,"x":%d,"y":%d,"hp":%d,"fuel":%d,"exp":%d,"exp_address":%d}',side,k,u.id,u.x,u.y,u.hp,u.fuel,r8(a+5),a+5)
  end
 end end
 local text=string.format('{"state":%d,"turn":%d,"roster_money":%d,"terrain_base":%d,"cell_format":["x","y","terrain","durability","owner","flags"],"cells":[%s],"roster":[%s],"units":[%s]}\n',
  r8(CTX),r8(CTX+0x20),memory.read_u32_le(CTX+0x68),base,table.concat(cells,","),table.concat(roster,","),table.concat(units,","))
 writefile(RUN.."map.json",text)
 return "OK MAPDATA shots/native_attack/map.json (read-only 48x48 terrain, units, roster and experience)"
end
local function experience(mode)
 local function grade(e) return e>=240 and "A" or e>=150 and "B" or e>=80 and "C" or e>=30 and "D" or "E" end
 local rows={}
 if mode=="" or mode=="ROSTER" then
  for k=0,98 do
   local a=CTX+0x188+k*4; local id=memory.read_u16_le(a)
   if id~=0 then rows[#rows+1]=string.format("ROSTER slot=%d id=%d exp=%d grade=%s address=0x%08X",k,id,r8(a+2),grade(r8(a+2)),a+2) end
  end
 else
  assert(mode=="MY" or mode=="EN","XP ROSTER|MY|EN")
  for _,u in ipairs(all_units(mode)) do
   local a=U-2+(mode=="MY" and 0 or PB)+u.idx*STRIDE+5
   rows[#rows+1]=string.format("%s slot=%d id=%d exp=%d grade=%s address=0x%08X",mode,u.idx,u.id,r8(a),grade(r8(a)),a)
  end
 end
 return "OK XP\n"..table.concat(rows,"\n")
end
local function inspect(seq,result)
 local text=build_state() .. string.format("CTX state=%d sub=%d phase=%d side=%d player=%d animation=%d hook=%s PC=0x%08X\n",
 r8(CTX),r8(CTX+1),r8(CTX+0x21),r8(CTX+0x22),r8(CTX+0x990),r8(CTX+0xC55),tostring(installed),emu.getregister("R15"))
 client.screenshot(RUN .. "current.png")
 client.screenshot(RUN .. string.format("%04d.png",seq))
 writefile(RUN .. "state.txt",text)
 writefile(RUN .. "reply.txt","seq=" .. seq .. "\n" .. result .. "\n")
 log("COMMAND " .. seq .. " " .. result)
end
local function main()
 client.speedmode(100); client.frameskip(0)
 pcall(client.setsoundon,true) -- 桥运行期间保留声音（旧调试脚本习惯静音，会让人以为"模拟器没声音"）
 adv(20); savestate.load(LOAD_STATE); adv(40); restore_keyboard()
 memory.write_u8(CTX+0xC55,0) -- Clean fight: full battle presentation off.
 local seq=0; inspect(0,"READY native attack research; real keyboard active")
 while true do
  local f=io.open(RUN .. "command.txt","r"); local txt=f and f:read("*a") or ""; if f then f:close() end
  local id,line=txt:match("seq=(%d+)\n([^\r\n]+)"); id=tonumber(id)
  if id and id>seq then
   seq=id; step=seq
   local cmd,rest=line:match("^(%S+)%s*(.*)$")
   local result="OK " .. line
   local command_ok,command_error=pcall(function()
   if cmd=="INSTALL" then install()
   elseif cmd=="UNINSTALL" then uninstall()
   elseif cmd=="DIST" then
    local a={}; for n in rest:gmatch("%-?%d+") do a[#a+1]=tonumber(n) end
    assert(#a==4,"DIST x1 y1 x2 y2")
    result="OK DIST " .. native_call(0x08002E74,a)
   elseif cmd=="ATTACK" then
    local i,e=rest:match("(%d+)%s+(%d+)"); result="OK " .. attack(tonumber(i),tonumber(e))
   elseif cmd=="POSITION" then
    local i,x,y=rest:match("(%d+)%s+(%d+)%s+(%d+)")
    local ok,msg=teleport_mem(tonumber(i),tonumber(x),tonumber(y)); result=(ok and "OK " or "FAIL ") .. msg
    if ok then native_call(0x080169D4,{tonumber(x),tonumber(y)}); native_call(0x08016BE0,{}) end
   elseif cmd=="ANIMATION" then result="OK " .. animation(rest)
   elseif cmd=="ENDTURN" then local ok,msg=endturn(); result=(ok and "OK " or "FAIL ")..msg
   elseif cmd=="AUTOCLEAR" then result="OK " .. autoclear(rest)
   elseif cmd=="PROFILE" then result="OK PROFILE "..commander()
   elseif cmd=="PREFIX" then
    assert(rest:match("^[%w_%-]+$") and #rest<70,"invalid save prefix"); SAVE_PREFIX=rest
   elseif cmd=="REPLAYFIRST" then result=replay_first(rest)
   elseif cmd=="SETTLE" then
    local p,r=rest:match("^(%d+)%s+(%d+)$"); assert(p,"SETTLE previous_points previous_rank")
    local promoted=settle_result(tonumber(p),tonumber(r))
    result="OK "..(promoted and "PROMOTED " or "CREDITED ")..commander()
   elseif cmd=="SPEED" then
    local n=tonumber(rest); assert(n and n>=10 and n<=1600,"SPEED 10..1600"); client.speedmode(n)
   elseif cmd=="VM" then
    local k,x,y=rest:match("(%d+)%s+(%d+)%s+(%d+)")
    assert(k and x and y,"VM 槽 x y")
    result="OK " .. vm(tonumber(k),tonumber(x),tonumber(y))
   elseif cmd=="CAP" then
    local k=rest:match("(%d+)")
    assert(k,"CAP 槽号")
    result="OK " .. cap(tonumber(k))
   elseif cmd=="ANIMATIONTEST" then result=animation_test()
   elseif cmd=="KEY" then
    local key,frames,gap=rest:match("(%S+)%s+(%d+)%s+(%d+)"); hold(key,tonumber(frames)); adv(tonumber(gap))
   elseif cmd=="ADV" then adv(tonumber(rest) or 1)
   elseif cmd=="MAP" then to_map()
   elseif cmd=="VIEWMAP" then
    assert(r8(CTX)==6,"VIEWMAP is verified for the deployment screen (state=6)")
    tap("R",100); client.screenshot(RUN.."map_preview.png")
    result="OK VIEWMAP R shoulder pressed; use B to return from preview"
   elseif cmd=="MAPSCROLL" then
    assert(r8(CTX)==6,"MAPSCROLL requires deployment preview")
    local direction,count=rest:match("^(%a+)%s+(%d+)$"); count=tonumber(count)
    assert(direction=="Up" or direction=="Down" or direction=="Left" or direction=="Right","MAPSCROLL Up|Down|Left|Right steps")
    assert(count and count>=1 and count<=40,"steps must be 1..40")
    for _=1,count do hold(direction,14); adv(8) end
    client.screenshot(RUN.."map_preview.png")
   elseif cmd=="MAPDATA" then result=mapdata()
   elseif cmd=="XP" then result=experience(rest)
   elseif cmd=="READ" then
    local addr,n=rest:match("(%S+)%s+(%d+)"); addr=tonumber(addr); n=tonumber(n)
    local b={}; for i=0,n-1 do b[#b+1]=string.format("%02X",r8(addr+i)) end; result="OK READ " .. table.concat(b," ")
   elseif cmd=="RECORD" then
    if rest=="OFF" then recordName=nil else assert(rest:match("^[%w_%-]+$")); recordName=rest; recordFrame=0; recordTick=0 end
   elseif cmd=="SAVE" then
    assert(rest:match("^[%w_%-]+$")); uninstall(); savestate.save(BASE .. "states/" .. rest .. ".State")
   elseif cmd=="LOAD" then
    assert(rest:match("^[%w_%-]+$")); uninstall(); savestate.load(BASE .. "states/" .. rest .. ".State"); adv(30); restore_keyboard()
   elseif cmd=="EXIT" then uninstall(); inspect(seq,result); logf:close(); client.exit(); return
   elseif cmd~="SNAP" then error("unknown command " .. cmd) end
   end)
   if not command_ok then
    if installed and memory.read_u32_le(MAILBOX)==2 then error(command_error) end
    if installed and memory.read_u32_le(MAILBOX)==1 then memory.write_u32_le(MAILBOX,0) end
    result="FAIL " .. tostring(command_error)
   end
   inspect(seq,result)
  else client.sleep(10); emu.yield() end
 end
end
local ok,err=xpcall(main,debug.traceback)
if not ok then
 log("FATAL " .. tostring(err)); client.screenshot(RUN .. "error.png")
 writefile(RUN .. "error.txt",tostring(err)); pcall(client.pause)
end
'''


def build(load, stage=1, current=False, variant=1):
    RUN.mkdir(parents=True, exist_ok=True)
    (RUN / "frames").mkdir(exist_ok=True)
    data, listing = make_stub()
    (ROOT / "lua/native_attack_stub.bin").write_bytes(data)
    (ROOT / "logs/native_attack_stub.txt").write_text("\n".join(
        f"{CAVE+at:08X}  {data[at:at+2].hex()}  {text}" for at, text in listing), encoding="utf-8")
    prefix = (ROOT / "lua/usa_ai_state.lua").read_text(encoding="utf-8").split("-- ============ 启动 ============")[0]
    log_name = "stage2_native_attack" if stage == 2 else "native_attack"
    prefix = prefix.replace('BASE .. "logs/usa_ai_state.txt"', f'BASE .. "logs/{log_name}.txt"')
    prefix = prefix.replace('BASE .. "states/battle_usa_ready.State"', f'BASE .. "states/{load}.State"')
    prefix = prefix.replace("emu.frameadvance()", "controlled_frame()")
    recorder = '''local recordName,recordTick,recordFrame=nil,0,0
local function controlled_frame()
 emu.frameadvance()
 if recordName then
  recordTick=recordTick+1
  if recordTick%6==0 then
   recordFrame=recordFrame+1
   client.screenshot(string.format("D:/prog/gba-ai/shots/native_attack/frames/%s_%05d.png",recordName,recordFrame))
  end
 end
end
'''
    tail = LUA
    if stage == 2:
        tail = tail.replace('local CAMPAIGN=1', 'local CAMPAIGN=2').replace('local SAVE_PREFIX="stage1_v2"', 'local SAVE_PREFIX="stage2"')
    output = ROOT / "lua/native_attack.lua"
    target_run = RUN
    if current:
        # Keep the established reproduction/farming bridge untouched.
        v2 = (variant == 2)
        output = ROOT / ("lua/current_battle2.lua" if v2 else "lua/current_battle.lua")
        target_run = ROOT / ("shots/current_battle2" if v2 else "shots/current_battle")
        run_dir = "shots/current_battle2/" if v2 else "shots/current_battle/"
        log_file = "logs/current_battle2.txt" if v2 else "logs/current_battle.txt"
        target_run.mkdir(parents=True, exist_ok=True)
        prefix = prefix.replace(f'logs/{log_name}.txt', log_file)
        tail = tail.replace('local RUN=BASE .. "shots/native_attack/"',
                            f'local RUN=BASE .. "{run_dir}"')
        tail = tail.replace('adv(20); savestate.load(LOAD_STATE); adv(40); restore_keyboard()',
                            'for i=1,8 do assert(r8(HOOK+i-1)==original[i],"Previous combat hook is active; finish the old controller or load a safe checkpoint") end\n restore_keyboard() -- attach: never load a fixed state')
        tail = tail.replace('SAVE_PREFIX:match("^farm_") and SAVE_PREFIX',
                            '(SAVE_PREFIX:match("^farm_") or SAVE_PREFIX:match("^current_")) and SAVE_PREFIX')
        # Current-game mode reuses terrain routing for stage 3 and later maps.
        tail = tail.replace('(CAMPAIGN==2) and route_field', '(CAMPAIGN~=1) and route_field')
        tail = tail.replace('if CAMPAIGN==2 then sc=sc-reach[key]',
                            'if CAMPAIGN~=1 then sc=sc-reach[key]')
        if v2:
            from tools.current_tactics2 import apply_current_tactics2
            prefix, tail = apply_current_tactics2(prefix, tail, ROOT)
            flow_name = "lua/current_battle_flow2.lua"
            tactics_note = "multi-faction + city resupply"
        else:
            from tools.current_tactics import apply_current_tactics
            tail = apply_current_tactics(tail, ROOT)
            flow_name = "lua/current_battle_flow.lua"
            tactics_note = "single-enemy (v1)"
        # mobile() moves the cursor as its readiness probe. Let its animation
        # and any input overlay finish before installing the native hook.
        tail = tail.replace('if not back then return false,"结束回合后未回到新回合可操作态" end',
                            'if not back then return false,"结束回合后未回到新回合可操作态" end\n to_map(); adv(60)')
        flow = (ROOT / flow_name).read_text(encoding="utf-8")
        tail = tail.replace('local function main()', flow + '\nlocal function main()')
        tail = tail.replace('if cmd=="INSTALL" then install()',
                            'if cmd=="CURRENT" then result=play_current(rest)\n   elseif cmd=="INSTALL" then install()')
        tail = tail.replace('result="FAIL " .. tostring(command_error)',
                            'if cmd=="CURRENT" then uninstall(); client.speedmode(100) end\n    result="FAIL " .. tostring(command_error)')
        print(f"Current-game bridge variant: {tactics_note}")
    output.write_text(recorder + prefix + tail, encoding="utf-8")
    (target_run / "command.txt").write_text("", encoding="utf-8")
    (target_run / "error.txt").unlink(missing_ok=True)
    print(f"Built {output.name}; Thumb trampoline {len(data)} bytes")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", nargs="*")
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--current", action="store_true", help="构建接管当前现场的独立脚本，不加载固定存档")
    ap.add_argument("--current2", action="store_true", help="构建 v2 接管脚本（多阵营 + 城市补给战术）")
    ap.add_argument("--stage", type=int, choices=[1, 2], default=1)
    ap.add_argument("--load", default="first_clear_start")
    ap.add_argument("--timeout", type=float, default=90)
    ap.add_argument("--full", action="store_true")
    args = ap.parse_args()
    if args.build:
        if not args.load.replace("_", "").replace("-", "").isalnum():
            ap.error("--load must be a savestate basename")
        build(args.load, args.stage, args.current or args.current2, 2 if args.current2 else 1)
    else:
        bridge.DIR = RUN
        bridge.command(" ".join(args.command), args.timeout, args.full)
