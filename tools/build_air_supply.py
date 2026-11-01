"""Build a separate current-game air/logistics bridge; never overwrite current2."""
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from tools.native_attack import LUA, make_stub
from tools.current_tactics2 import apply_current_tactics2

def compose():
    prefix=(ROOT/'lua/usa_ai_state.lua').read_text(encoding='utf-8').split('-- ============ 启动 ============')[0]
    prefix=prefix.replace('logs/usa_ai_state.txt','logs/air_supply.txt')
    prefix=prefix.replace('emu.frameadvance()','controlled_frame()')
    prefix,tail=apply_current_tactics2(prefix,LUA,ROOT)
    # mobile() in endturn probes cursor movement and can leave a menu/animation.
    # Match the established current2 attach lifecycle before the next hook install.
    tail=tail.replace('if not back then return false,"结束回合后未回到新回合可操作态" end',
        'if not back then return false,"结束回合后未回到新回合可操作态" end\n to_map(); adv(60)')
    tail=tail.replace('local function native_call(addr,args,maxframes)',
        'local function native_call(addr,args,maxframes,retried)')
    retry=''' if not done and not retried and memory.read_u32_le(MAILBOX)==1 and r8(CTX)==7 and r8(CTX+1)==1 then
  -- Status 1 has not entered native code. Withdraw it before sending any input.
  memory.write_u32_le(MAILBOX,0)
  uninstall()
  log(string.format("AIR_BRIDGE_RETRY 0x%08X unstarted request; restore idle map once",addr))
  to_map();adv(60)
  return native_call(addr,args,maxframes,true)
 end
'''
    tail=tail.replace(' assert(done,string.format("native call',retry+' assert(done,string.format("native call',1)
    # Only the independent branch gains these two audited supply entry points.
    tail=tail.replace('local whitelist={',
        'local whitelist={ [0x08022388]=true,[0x08021F78]=true,',1)
    # Embarked troops are not independent actors. Keep their positions linked to
    # the carrier using the verified unit-table base, not the context header.
    prefix=prefix.replace('  local x, y = r8(base), r8(base + 1)',
        '  if (r8(base+5)&0x80)~=0 then return nil end\n  local x, y = r8(base), r8(base + 1)')
    tail=tail.replace('local pr=CTX+pid*0x18-0x18+2','local pr=U+(pid-1)*STRIDE')
    tail=tail.replace(' local cs_before_wait=nil',' local air_before_acted=nil\n local cs_before_wait=nil')
    tail=tail.replace('  if u and not u.acted and r8(CTX)==7 then native_call(0x0801F130,{U+k*STRIDE-2}) end',
        '  if u and not u.acted and r8(CTX)==7 and air_before_acted then air_before_acted(k,u);u=unit("MY",k) end\n  if u and not u.acted and r8(CTX)==7 then native_call(0x0801F130,{U+k*STRIDE-2}) end')
    tail=tail.replace('shots/native_attack/','shots/air_supply/')
    tail=tail.replace('lua/native_attack_stub.bin','lua/air_supply_stub.bin')
    tail=tail.replace('adv(20); savestate.load(LOAD_STATE); adv(40); restore_keyboard()',
        'air_recover_idle_bridge()\n restore_keyboard()')
    tail=tail.replace('SAVE_PREFIX:match("^farm_") and SAVE_PREFIX',
        '(SAVE_PREFIX:match("^farm_") or SAVE_PREFIX:match("^current_")) and SAVE_PREFIX')
    tail=tail.replace('(CAMPAIGN==2) and route_field','(CAMPAIGN~=1) and route_field')
    # Live run: tanks/artillery picked uncaptured towns (+20 defence) as firing
    # posts and blocked infantry 11 times. Only capturers may stop on them.
    tail=tail.replace('local cx,cy=best_reach_cell(reach,e,want)',
        'local cx,cy=best_reach_cell(air_keep_towns_free(u,reach),e,want)',1)
    block="if not capturer and on_building(x,y) and r8(tb()+x*4+y*0xC0+2)~=cs_owner then score=score-400 end"
    prefix=prefix.replace(block,block.replace('-400','-5000'))
    tail=tail.replace(block,block.replace('-400','-5000'))
    policy=(ROOT/'lua/air_supply_policy.lua').read_text(encoding='utf-8')
    tail=tail.replace(' local function try_capture_capital(tn)',policy+'\n local function try_capture_capital(tn)')
    tail=tail.replace('if u and u.hp>0 and not u.acted then\n    local en=all_units("EN")',
        'if u and u.hp>0 and not u.acted and not air_exhausted[k] then\n    local en=all_units("EN")')
    tail=tail.replace('  cs_update_clock()','  cs_update_clock()\n  local logistics_error=air_logistics_round()\n  if logistics_error then return logistics_error end')
    # Native attack upkeep is charged separately; do not allow a fuel-starved sortie.
    tail=tail.replace('    local hold,reason=cs_hold(u,en)',
        '    u=unit("MY",k)\n    local hold,reason=cs_hold(u,en)')
    tail=tail.replace('if eff<1 or (loss>=hp and not kill) or (p.cx and exposure>=hp*0.9) then',
        'if eff<1 or (loss>=hp and not kill) or (p.cx and exposure>=hp*0.9) or (air_is_air(u) and not air_fuel_safe(u,p.cx or u.x,p.cy or u.y,(p.cx and reach[p.cx..","..p.cy]) or 0)) then')
    flow=(ROOT/'lua/current_battle_flow2.lua').read_text(encoding='utf-8')
    flow=flow.replace('campaign-v10(multi-faction)','air-supply-v9(multi-faction)')
    flow=flow.replace('"current_" .. token','"current_air_" .. token')
    flow=flow.replace('if deployed == 0 then prepare_current_army() else',
        'if deployed == 0 then error("Deploy your air/ground army manually, then run this CMD again") else')
    recover=(ROOT/'lua/air_bridge_recover.lua').read_text(encoding='utf-8')
    tail=tail.replace('local function main()',recover+'\n'+flow+'\nlocal function main()')
    tail=tail.replace('if cmd=="INSTALL" then install()',
        'if cmd=="CURRENT" then result=play_current(rest)\n   elseif cmd=="INSTALL" then install()')
    tail=tail.replace('result="FAIL " .. tostring(command_error)',
        'if cmd=="CURRENT" then uninstall();client.speedmode(100) end\n    result="FAIL " .. tostring(command_error)')
    return 'local function controlled_frame() emu.frameadvance() end\n'+prefix+tail

def build():
    source=compose()
    from tools.check_current_tactics2 import lua_check
    lua_check(source)
    data,_=make_stub()
    run=ROOT/'shots/air_supply'
    run.mkdir(parents=True,exist_ok=True)
    (ROOT/'lua/air_supply_stub.bin').write_bytes(data)
    (ROOT/'lua/air_supply_battle.lua').write_text(source,encoding='utf-8')
    (run/'command.txt').write_text('',encoding='utf-8')
    (run/'error.txt').unlink(missing_ok=True)
    print('Built air_supply_battle.lua (independent air-supply-v9)')

if __name__=='__main__':
    build()
