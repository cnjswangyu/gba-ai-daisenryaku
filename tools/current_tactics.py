"""Compose current-game strategy without altering legacy replay tactics."""
from pathlib import Path

def apply_current_tactics(source: str, root: Path) -> str:
    def replace(old: str, new: str) -> None:
        nonlocal source
        if old not in source:
            raise ValueError(f'Current tactics insertion point missing: {old[:70]}')
        source = source.replace(old, new)

    # All maps occupy a 48x48 buffer, with the playable interior bounded by 1..46.
    # The previous 34-row restriction stranded scenario-3 troops at rows 35..37.
    replace('ny<=34', 'ny<=46')
    replace('y<=34', 'y<=46')
    replace('for y=1,34 do', 'for y=1,46 do')
    replace('for yy=1,34 do', 'for yy=1,46 do')
    replace('local function vm_land(k,u,x,y,costc)', '''local function vm_land(k,u,x,y,costc)
 if x~=u.x or y~=u.y then
  local source=memory.read_u32_le(CTX+0x18)+u.x*4+u.y*0xC0
  assert(not (terrain_at(u.x,u.y)==0x10 and r8(source+2)==1),
   "Capital garrison cannot leave its post")
 end''')
    policy = (root / 'lua/current_tactics.lua').read_text(encoding='utf-8')
    policy += '\n' + (root / 'lua/current_endgame.lua').read_text(encoding='utf-8')
    replace(' local function try_capture_capital(tn)', policy + '\n local function try_capture_capital(tn)')
    replace('for iteration=1,30 do', '''for iteration=1,80 do
  current_begin_round()
  current_assess()
  current_trace_round("before_defense")
  current_defend_capitals()
  if r8(CTX)==8 or #all_units("EN")==0 then return finish("首都防守结算") end
  current_plan_round()
  local blocked=current_finish_plan()
  if blocked then client.speedmode(100); return "FAIL "..blocked end
  current_trace_round("planned")''')
    replace('for want=1,3 do', 'for _,want in ipairs(current_ranges(u,e)) do')
    replace('and not u.acted and is_capturer(u.id) then',
            'and not u.acted and is_capturer(u.id) and not current_guard(u,all_units("EN")) then')
    replace('if u.id>=339 and u.id<=345 then', '''local hold,reason=current_hold(u,en)
    if current_quick_attack(u,en) then
     if r8(CTX)==8 or #all_units("EN")==0 then return finish("近身歼敌结算") end
    elseif hold then
     current_hold_action(k,u,en,reason)
     if r8(CTX)==8 or #all_units("EN")==0 then return finish("驻城战斗结算") end
    elseif current_capture_action(k,u,en) then
     if r8(CTX)==8 or #all_units("EN")==0 then return finish("步兵占领结算") end
    elseif u.id>=339 and u.id<=345 then''')
    replace('for _,e in ipairs(en) do\n      local plans={}',
            'for _,e in ipairs(current_attack_targets(u,en)) do\n      local plans={}')
    replace('local okm,msgm=endturn()', 'current_trace_round("completed")\n   local okm,msgm=endturn()')
    replace('elseif u.id>=339 and u.id<=345 then\n     markacted(k)', '''elseif u.id>=339 and u.id<=345 then
     local _,support_cat,support_budget=vm_ctx(k)
     current_advance(k,u,vm_reach(u,support_cat,support_budget),support_cat,en)
     markacted(k)''')
    # Guard the actual capital while threatened, rather than always pinning slot 0.
    replace('if want~=d0 and k~=0 then', 'if want~=d0 and not current_guard(u,en) then')
    replace('local threat=hexd(e.x,e.y,21,30)', '''local threat=99
        for _,capital in ipairs(current_capitals) do
         threat=math.min(threat,hexd(e.x,e.y,capital.x,capital.y))
        end''')
    replace('if eff<1 or (loss>=hp and not kill) then', '''local exposure=current_danger(u,p.cx or u.x,p.cy or u.y,en)
       if eff<1 or (loss>=hp and not kill) or (p.cx and exposure>=hp*0.9) then''')
    replace('-((p.cx and reach[p.cx..","..p.cy]) or 0)', '''-((p.cx and reach[p.cx..","..p.cy]) or 0)-exposure*8
             -((p.cx and current_friendly_city(u.x,u.y)) and 50 or 0)''')
    start=source.index('      -- 无攻击方案：占领单位优先占可达的敌/中立建筑')
    end=source.index('      markacted(k)', start)
    source=source[:start]+'''      current_advance(k,u,reach,cat0,en)
      if r8(CTX)==8 or #all_units("EN")==0 then return finish("推进/占领结算") end
'''+source[end:]
    return source
