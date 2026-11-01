-- Scenario 2: preserve inherited roster/EXP, append missing units and use native deployment.
local BASE="D:/prog/gba-ai/"
local CTX,U=0x03000480,0x03002BE0
local fh=assert(io.open(BASE.."logs/stage2_deploy.txt","w"))
local function log(s) fh:write(string.format("[%d] %s\n",emu.framecount(),s)); fh:flush() end
local function r8(a) return memory.read_u8(a) end
local function adv(n) for _=1,n do emu.frameadvance() end end
local function press(k,n,gap)
 for _=1,(n or 6) do joypad.set({[k]=true}); adv(1) end
 joypad.set({}); adv(gap or 60)
end
local function units()
 local n=0
 for k=0,63 do if memory.read_u16_le(U+k*24)~=0 then n=n+1 end end
 return n
end
local function screenshot(tag) client.screenshot(BASE.."shots/stage2_deploy_"..tag..".png") end
local function snapshot(tag)
 log(string.format("%s state=%d/%d phase=%d side=%d deployed=%d roster_money=%d",tag,
  r8(CTX),r8(CTX+1),r8(CTX+0x21),r8(CTX+0x22),units(),memory.read_u32_le(CTX+0x68)))
 screenshot(tag)
end
local ok,err=xpcall(function()
 client.speedmode(400); client.frameskip(0)
 adv(20); savestate.load(BASE.."states/stage2_pre_battle.State"); adv(40)
 assert(r8(CTX)==6 and units()==0,"expected scenario 2 predeployment dialog")
 local wanted={[187]=9,[241]=5,[305]=2,[324]=2,[339]=2}
 local counts,old,empty={},{},{}
 for k=0,98 do
  local a=CTX+0x188+k*4; local id=memory.read_u16_le(a)
  if id==0 then empty[#empty+1]=k
  else
   assert(wanted[id],"unexpected inherited unit "..id)
   counts[id]=(counts[id] or 0)+1
   old[#old+1]={slot=k,id=id,exp=r8(a+2)}
   log(string.format("VETERAN slot=%d id=%d exp=%d",k,id,r8(a+2)))
  end
 end
 assert(#old==16,"expected the saved 16 veterans, got "..#old)
 local additions={}
 for _,id in ipairs({187,241,305,324,339}) do
  assert((counts[id] or 0)<=wanted[id],"inherited count exceeds 20-slot plan")
  for _=1,wanted[id]-(counts[id] or 0) do additions[#additions+1]=id end
 end
 local cost=0
 for _,id in ipairs(additions) do cost=cost+memory.read_u16_le(0x08798A98+id*0x5C+0x1A) end
 local before=memory.read_u32_le(CTX+0x68)
 assert(#additions==4 and #empty>=4 and before>=cost,"invalid reinforcements or insufficient funds")
 for i,id in ipairs(additions) do
  local a=CTX+0x188+empty[i]*4
  memory.write_u16_le(a,id); memory.write_u8(a+2,0); memory.write_u8(a+3,0)
 end
 memory.write_u32_le(CTX+0x68,before-cost)
 for _,v in ipairs(old) do
  local a=CTX+0x188+v.slot*4
  assert(memory.read_u16_le(a)==v.id and r8(a+2)==v.exp,"veteran changed")
 end
 log(string.format("REINFORCEMENTS added=4 cost=%d funds=%d->%d inherited_exp_unchanged=true",cost,before,before-cost))
 savestate.save(BASE.."states/stage2_army_ready.State")
 local deployed=false
 for trial=1,2 do
  savestate.load(BASE.."states/stage2_army_ready.State"); adv(15)
  press("A",6,180) -- accept automatic deployment dialog, open checklist
  if trial==1 then press("A",6,40) end -- this saved dialog swallows the first checklist confirmation
  for i=1,20 do
   press("A",6,35)
   if i<20 then press("Down",6,35) end
  end
  snapshot("checked_"..trial)
  press("Start",6,90); screenshot("confirm_"..trial)
  press("A",6,120); adv(500)
  snapshot("placed_"..trial)
  if units()==20 then deployed=true; break end
 end
 assert(deployed,"native deployment did not place all 20 units; inspect screenshots")
 for _,v in ipairs(old) do
  local a=CTX+0x188+v.slot*4
  local warSlot=r8(a+3)%100-1
  assert(warSlot>=0 and warSlot<64,"missing deployment association")
  local b=U+warSlot*24
  assert(memory.read_u16_le(b)==v.id and r8(b+5)==v.exp,"deployed veteran EXP mismatch")
  log(string.format("EXP_OK roster=%d war=%d id=%d exp=%d",v.slot,warSlot,v.id,v.exp))
 end
 press("Start",6,90); press("A",6,120)
 local ready=false
 for i=1,30 do
  adv(60)
  if r8(CTX)==7 and r8(CTX+1)==1 and r8(CTX+0x21)==3 and r8(CTX+0x22)==0 then ready=true; break end
  press("A",6,40)
 end
 assert(ready,"battle did not enter player phase")
 press("B",6,40); memory.write_u8(CTX+0xC55,0)
 snapshot("battle_ready")
 savestate.save(BASE.."states/stage2_deployed.State")
 log("SUCCESS 20 deployed; all 16 veteran EXP preserved; states/stage2_deployed.State")
end,debug.traceback)
if not ok then
 log("FAIL "..tostring(err)); screenshot("error")
 local e=assert(io.open(BASE.."logs/stage2_deploy_error.txt","w")); e:write(tostring(err)); e:close()
end
fh:close()
if ok then client.exit() else client.pause() end
