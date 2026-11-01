-- Recover only this project's exact idle mailbox after its Lua session stopped.
local function air_recover_idle_bridge()
 local clean=true
 for i=1,8 do if r8(HOOK+i-1)~=original[i] then clean=false end end
 if clean then return end
 -- Detaching an identified idle hook does not require the battlefield screen.
 -- Selection/deployment/save reload may leave its ROM patch behind as well.
 assert(memory.read_u16_le(HOOK)==0x4B00 and memory.read_u16_le(HOOK+2)==0x4718
  and memory.read_u32_le(HOOK+4)==CAVE+1,"unknown hook; retained unchanged")
 local status=memory.read_u32_le(MAILBOX)
 assert(status==0 or status==1 or status==3,"native call is running; idle recovery refused")
 local f=assert(io.open(BASE.."lua/air_supply_stub.bin","rb"))
 local expected=f:read("*a");f:close()
 assert(#expected>0 and #expected<0x1C0,"invalid local bridge stub")
 local matches,blank=true,true
 for i=1,#expected do if r8(CAVE+i-1)~=expected:byte(i) then matches=false end end
 for i=0,0x23F do if r8(CAVE+i)~=0 then blank=false;break end end
 assert(matches or blank,"unknown stub; retained unchanged")
 -- New Session stopped the previous Lua owner. No command is executing here.
 if not blank then memory.write_u32_le(MAILBOX,0) end
 for i=1,8 do memory.write_u8(HOOK+i-1,original[i]) end
 if not blank then for i=0,0x23F do memory.write_u8(CAVE+i,0) end end
 log("AIR_BRIDGE_RECLAIM previous idle controller detached; game units retained")
end
