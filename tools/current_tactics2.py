"""current_tactics2.py — 把 v2 战术（多阵营 + 城市补给）装配进桥脚本。

和 v1 的 tools/current_tactics.py 的区别：
  1. 前缀单位读取改成多阵营（`unit`/`all_units` 支持 0..3 号阵营，"EN" = 所有敌对阵营的并集）；
  2. 原生战斗调用 `FUN_08023188` 的目标阵营不再是写死的 1，随目标单位传入；
  3. 反击武器/敌方弹药、敌首都、占领接口全部按目标阵营参数化；
  4. 战术模块换成 lua/current_tactics2.lua：考虑全部敌方阵营 + 利用城市补给
     （回合开始站在自家 0x10 首都 / 0x11 市街 / 0x14 村落 上会补满 HP/燃料/弹药）。

逆向依据见 docs/MULTIFACTION_REVERSE.md 与 .workbuddy/memory/2026-10-18.md。
"""
from pathlib import Path

MAX_SIDES = 4


def _multi_side_block() -> str:
    return f'''local MAX_SIDES = {MAX_SIDES}
-- ============ 多阵营（v2）============
-- 势力上限 {MAX_SIDES}：FUN_08018ca0 里 `uVar5 < 4`。
-- 单位表 ctx+0x2760+side*0x600；阵营记录 ctx+0x24+side*0xC +4 = 状态(1..3 参战, FUN_080023c4)；
-- 玩家阵营 ctx+0x990；格表 +0 = 阵营+1。
local function side_alive(s)
  local v = memory.read_u8(CTX + 0x24 + s * 0xC + 4)
  return v >= 1 and v <= 3
end
local function player_side() return memory.read_u8(CTX + 0x990) end
local function foe_sides()
  local p, t = player_side(), {{}}
  for s = 0, MAX_SIDES - 1 do
    if s ~= p and side_alive(s) then t[#t + 1] = s end
  end
  return t
end
local function unit_side(side, k)
  local base = U + side * PB + k * STRIDE
  local id = memory.read_u16_le(base - 2)
  if id == 0 then return nil end
  local x, y = r8(base), r8(base + 1)
  if not (x > 0 and x < 64 and y > 0 and y < 64) then return nil end
  local d = db(id)
  return {{
    side = side, idx = k, key = side * SLOTS + k, id = id,
    name = d and d.name or ("ID" .. id),
    x = x, y = y,
    fuel = r8(base + 2),
    exp = r8(base + 3),
    hp = r8(base + 4),
    maxhp = d and (d.dur * 4) or 0,
    ammo = r8(base + 6),
    st = r8(base + 5),
    acted = (r8(base + 5) % 2 == 1),
  }}
end
local function all_units_side(side)
  local t = {{}}
  for k = 0, SLOTS - 1 do
    local u = unit_side(side, k)
    if u then t[#t + 1] = u end
  end
  return t
end
-- 旧接口：unit("MY",k)/all_units("MY") = 玩家阵营；"EN" = 全部敌对阵营（并集）
local function unit(side, k)
  if side == "MY" then return unit_side(player_side(), k) end
  if side == "EN" then
    local f = foe_sides()
    if not f[1] then return nil end
    return unit_side(f[1], k)
  end
  return unit_side(side, k)
end
local function all_units(side)
  if side == "EN" then
    local t = {{}}
    for _, s in ipairs(foe_sides()) do
      for k = 0, SLOTS - 1 do
        local u = unit_side(s, k)
        if u then t[#t + 1] = u end
      end
    end
    return t
  end
  local s = (side == "MY") and player_side() or side
  return all_units_side(s)
end'''


def patch_prefix(prefix: str) -> str:
    def replace(old: str, new: str) -> None:
        nonlocal prefix
        if old not in prefix:
            raise ValueError(f'v2 prefix insertion point missing: {old[:70]}')
        prefix = prefix.replace(old, new)

    replace('local function unit(side, k)\n'
            '  local base = (side == "MY") and (U + k * STRIDE) or (U + PB + k * STRIDE)',
            'local function unit_side(side, k)\n'
            '  local base = U + side * PB + k * STRIDE')
    replace('    side = side, idx = k, id = id,',
            '    side = side, idx = k, key = side * SLOTS + k, id = id,')
    replace('local function all_units(side)\n'
            '  local t = {}\n'
            '  for k = 0, SLOTS - 1 do\n'
            '    local u = unit(side, k)\n'
            '    if u then t[#t + 1] = u end\n'
            '  end\n'
            '  return t\n'
            'end',
            _multi_side_block())
    # 状态导出给敌方行补一个 side 字段（追加在行尾，旧解析器不受影响）
    replace('    L[#L + 1] = string.format("E%d id%d %s x%d y%d hp%d/%d f%d st%d act%d ammo%d",\n'
            '      u.idx, u.id, u.name, u.x, u.y, u.hp, u.maxhp, u.fuel, u.st, u.acted and 1 or 0, u.ammo)',
            '    L[#L + 1] = string.format("E%d id%d %s x%d y%d hp%d/%d f%d st%d act%d ammo%d side%d",\n'
            '      u.idx, u.id, u.name, u.x, u.y, u.hp, u.maxhp, u.fuel, u.st, u.acted and 1 or 0, u.ammo, u.side or 1)')
    return prefix


def apply_current_tactics2(prefix: str, tail: str, root: Path) -> tuple[str, str]:
    def replace(old: str, new: str) -> None:
        nonlocal tail
        if old not in tail:
            raise ValueError(f'v2 tactics insertion point missing: {old[:70]}')
        tail = tail.replace(old, new)

    prefix = patch_prefix(prefix)

    # ---------- 1. 原生战斗调用：目标阵营参数化 ----------
    replace('local function attack(idx,eidx)\n'
            ' assert(idx and eidx and idx>=0 and idx<64 and eidx>=0 and eidx<64,"slot out of bounds")\n'
            ' local u,e=unit("MY",idx),unit("EN",eidx)',
            ' local function attack(idx,foe)\n'
            ' -- foe: 目标单位表（带 side/idx）；也接受槽号（旧调用，默认第一个敌对阵营）\n'
            ' if type(foe)~="table" then foe=unit("EN",foe) end\n'
            ' assert(foe,"invalid target")\n'
            ' local eidx,eside=foe.idx,foe.side\n'
            ' assert(idx and idx>=0 and idx<64 and eidx>=0 and eidx<64,"slot out of bounds")\n'
            ' local u,e=unit("MY",idx),unit(eside,eidx)')
    replace(' local ur,er=U+idx*STRIDE-2,U+PB+eidx*STRIDE-2',
            ' local ur,er=U+idx*STRIDE-2,U+(eside or 1)*PB+eidx*STRIDE-2')
    replace(' native_call(0x08023188,{0,idx,wa,1,eidx,wb},1800)',
            ' -- 灭国会放很长的演出（多阵营地图上常见）：预算放到 6000 帧再判超时\n'
            ' native_call(0x08023188,{player_side(),idx,wa,eside,eidx,wb},6000)')
    wait_start=tail.index(' for i=1,(maxframes or 1200) do')
    wait_end=tail.index(' assert(done,string.format("native call',wait_start)
    tail=tail[:wait_start]+''' local i,manual=0,false
 while true do
  i=i+1; adv(1)
  local status=memory.read_u32_le(MAILBOX)
  if status==3 then done=true;break end
  if addr==0x08023188 and status==2 and i>=1200 then
   if not manual then
    manual=true;client.speedmode(100)
    writefile(RUN.."manual_wait.txt","Confirm the game's elimination dialog manually; automatic orders are waiting.")
    log("MANUAL_WAIT 原生战斗/灭国提示等待中，请在模拟器手动确认；不会自动按A或清除调用栈")
   end
  elseif i>=(maxframes or 1200) then break end
 end
 if manual then
  writefile(RUN.."manual_wait.txt","")
  log(done and "MANUAL_RESUMED 原生调用已返回，继续自动决策" or "MANUAL_STOPPED 原生调用未正常返回，保留现场")
  client.speedmode(done and (CURRENT_SPEED or 100) or 100)
 end
'''+tail[wait_end:]
    replace(' local a,b=unit("MY",idx),unit("EN",eidx)',
            ' local a,b=unit("MY",idx),unit(eside,eidx)')
    replace('  local ammo=r8(U+0x600+e.idx*STRIDE-2+8+wa)',
            '  local ammo=r8(U+(e.side or 1)*PB+e.idx*STRIDE-2+8+wa)')
    # 攻击日志带上目标阵营，便于核对"确实打了两个敌人阵营"
    replace(' log(string.format("DIRECT U%d -> E%d distance=%d weapons=%d/%d HP=%d/%d",idx,eidx,d,wa,wb,u.hp,e.hp))',
            ' log(string.format("DIRECT U%d -> E%d(side%d) distance=%d weapons=%d/%d HP=%d/%d",idx,eidx,eside,d,wa,wb,u.hp,e.hp))')
    replace(' return string.format("DIRECT U%d E%d | my HP %d->%d enemy HP %d->%d ammo %d->%d counter %d->%d acted=%s",\n'
            '  idx,eidx,u.hp,a and a.hp or 0,e.hp,b and b.hp or 0,ammoA,r8(ur+8+wa),ammoB,',
            ' return string.format("DIRECT U%d E%d(side%d) | my HP %d->%d enemy HP %d->%d ammo %d->%d counter %d->%d acted=%s",\n'
            '  idx,eidx,eside,u.hp,a and a.hp or 0,e.hp,b and b.hp or 0,ammoA,r8(ur+8+wa),ammoB,')
    replace('      report[#report+1]=string.format("T%d U%d(id%d)->E%d(id%d) %s %s",turn,k,u.id,e.idx,e.id,ok and "OK" or "FAIL",amsg)',
            '      report[#report+1]=string.format("T%d U%d(id%d)->E%d(side%d,id%d) %s %s",turn,k,u.id,e.idx,e.side,e.id,ok and "OK" or "FAIL",amsg)')

    # ---------- 2. 占领：按玩家阵营 ----------
    replace(' assert(ob~=1,"已经是我方建筑")\n'
            ' native_call(0x08020B20,{0,k})          -- 占領：归属翻转 + 收入 + 首都胜利判定',
            ' assert(ob~=player_side()+1,"已经是我方建筑")\n'
            ' native_call(0x08020B20,{player_side(),k})  -- 占領：归属翻转 + 收入 + 首都胜利判定')

    # ---------- 3. 敌首都：多阵营下收集全部 ----------
    replace(' local function enemy_capital()\n'
            '  local b=tb()\n'
            '  for y=1,34 do\n'
            '   for x=1,46 do\n'
            '    local c=b+x*4+y*0xC0\n'
            '    if r8(c)==0x10 and r8(c+2)~=1 then return x,y end\n'
            '   end\n'
            '  end\n'
            ' end',
            ' local function enemy_capitals()\n'
            '  -- 敌方各阵营的首都（归属 != 我方），多阵营下一个都不漏\n'
            '  local b,out=tb(),{}\n'
            '  for y=1,46 do\n'
            '   for x=1,46 do\n'
            '    local c=b+x*4+y*0xC0\n'
            '    if r8(c)==0x10 then\n'
            '     local o=r8(c+2)\n'
            '     if o>=1 and o~=player_side()+1 then out[#out+1]={x=x,y=y,owner=o} end\n'
            '    end\n'
            '   end\n'
            '  end\n'
            '  return out\n'
            ' end\n'
            ' local function enemy_capital()\n'
            '  local caps=enemy_capitals()\n'
            '  if caps[1] then return caps[1].x,caps[1].y end\n'
            ' end')

    # ---------- 4. 战术模块 ----------
    policy = (root / 'lua/current_deadline2.lua').read_text(encoding='utf-8')+'\n'+(root / 'lua/current_tactics2.lua').read_text(encoding='utf-8')
    policy += '\n'+(root/'lua/current_fireplan2.lua').read_text(encoding='utf-8')
    policy += '\n'+(root/'lua/current_mobility2.lua').read_text(encoding='utf-8')
    replace(' local function markacted(k)', ' local cs_before_wait=nil\n local function markacted(k)')
    replace('  if u and not u.acted then native_call(0x0801F130,{U+k*STRIDE-2}) end',
            '  if u and not u.acted and cs_before_wait then cs_before_wait(k);u=unit("MY",k) end\n  if u and not u.acted and r8(CTX)==7 then native_call(0x0801F130,{U+k*STRIDE-2}) end')
    replace(' local function try_capture_capital(tn)', policy + '\n local function try_capture_capital(tn)')

    # ---------- 5. 主循环：回合骨架 ----------
    replace('for iteration=1,30 do', '''for iteration=1,80 do
  current_begin_round()
  cs_update_clock()
  current_trace_round("before_fire")
  if try_capture_capital(r8(CTX+0x20)) then return finish("立即占领敌首都") end
  local handoff_error=cs_capture_handoff()
  if handoff_error then return handoff_error end
  if r8(CTX)==8 or #all_units("EN")==0 then return finish("占领让位结算") end
  cs_supply_handoff()
  if r8(CTX)==8 or #all_units("EN")==0 then return finish("补给让位战斗结算") end
  local fire_error=cs_fire_phase()
  if fire_error then return fire_error end
  if r8(CTX)==8 or #all_units("EN")==0 then return finish("全军原地火力结算") end
  current_trace_round("before_defense")
  current_defend_capitals()
  if r8(CTX)==8 or #all_units("EN")==0 then return finish("城市防守结算") end
  current_plan_round()
  cs_deadline_orders()
  cs_offensive_orders()
  cs_log_roles()
  current_trace_round("planned")''')

    # ---------- 6. 每个单位的行动：先守城（含补给），再占城，再攻击 ----------
    replace('if u.id>=339 and u.id<=345 then', '''cs_refresh_order(k,en)
    local hold,reason=cs_hold(u,en)
    if hold then
     cs_hold_action(k,u,en,reason)
     if r8(CTX)==8 or #all_units("EN")==0 then return finish("城市驻守结算") end
    elseif current_capture_action(k,u,en) then
     if r8(CTX)==8 or #all_units("EN")==0 then return finish("步兵占领结算") end
    elseif u.id>=339 and u.id<=345 then''')

    # 目标列表（多阵营下按 intercept 任务过滤）
    replace('for _,e in ipairs(en) do\n      local plans={}',
            'for _,e in ipairs(current_attack_targets(u,en)) do\n      local plans={}')

    # 首都守卫不再写死槽 0
    replace('if want~=d0 and k~=0 then', 'if want~=d0 and not cs_guard(u,en) then')

    # 威胁距离：从写死的 (21,30) 改成「最近的自家补给城市」
    replace('local threat=hexd(e.x,e.y,21,30)', 'local threat=current_home_threat(e)')
    replace('local score=math.min(eff,e.hp)*16-loss*20+(kill and 180 or 0)',
            'local score=math.min(eff,e.hp)*16-loss*20+(kill and 180 or 0)+cs_attack_priority(e)+cs_clock.urgency*((kill and 180 or 0)+math.min(eff,e.hp)*8)')

    # 打分：加入被反击暴露度与「结束在自家补给点」的加成
    replace('if eff<1 or (loss>=hp and not kill) then', '''local exposure=cs_danger(u,p.cx or u.x,p.cy or u.y,en)
       if eff<1 or (loss>=hp and not kill) or (p.cx and exposure>=hp*0.9) then''')
    replace('-((p.cx and reach[p.cx..","..p.cy]) or 0)', '''-((p.cx and reach[p.cx..","..p.cy]) or 0)-exposure*8
             +((p.cx and cs_supply_cell(p.cx,p.cy)) and 70 or 0)
             +((not p.cx and cs_supply_cell(u.x,u.y)) and (cs_needs_supply(u) and 180 or 40) or 0)''')

    # 无攻击方案：交给 v2 的推进/补给/占领决策
    start = tail.index('      -- 无攻击方案：占领单位优先占可达的敌/中立建筑')
    end = tail.index('      markacted(k)', start)
    tail = tail[:start] + '''      current_advance(k,u,reach,cat0,en)
      if r8(CTX)==8 or #all_units("EN")==0 then return finish("推进/占领/补给结算") end
''' + tail[end:]

    # 补给车等后勤单位：跟着战线走而不是原地发呆
    replace('elseif u.id>=339 and u.id<=345 then\n     markacted(k)', '''elseif u.id>=339 and u.id<=345 then
     local _,support_cat,support_budget=vm_ctx(k)
     current_advance(k,u,vm_reach(u,support_cat,support_budget),support_cat,en)
     markacted(k)''')

    # 回合收尾
    replace('local okm,msgm=endturn()', 'current_trace_round("completed")\n   local okm,msgm=endturn()')
    # 攻击调用卡住（多阵营下灭掉某一方会触发灭国演出）时的自救
    replace('       local ok2,amsg2=pcall(attack,k,e.idx)',
            '       local ok2,amsg2=pcall(attack,k,e)')
    replace('      if r8(CTX)==8 or #all_units("EN")==0 then return finish("全歼/战斗结算") end\n'
            '      if not ok then markacted(k) end',
            '      if r8(CTX)==8 or #all_units("EN")==0 then return finish("全歼/战斗结算") end\n'
            '      if not ok then\n'
            '       local why=tostring(amsg)\n'
            '       if why:find("did not return") or why:find("mailbox busy") then\n'
            '        cs_recover_stuck(k)\n'
            '        if cs_stuck_aborted then return "FAIL STUCK 灭国演出打断，战场已保留；重新运行 Play-Current2 可继续" end\n'
            '        if r8(CTX)==8 or #all_units("EN")==0 then return finish("战斗结算/敌军全灭") end\n'
            '       end\n'
            '       markacted(k)\n'
            '      end')
    # Apply only after literal patches above: several source anchors include row 34.
    tail=tail.replace('ny<=34','ny<=46').replace('y<=34','y<=46')
    tail=tail.replace('for y=1,34 do','for y=1,46 do').replace('for yy=1,34 do','for yy=1,46 do')
    return prefix, tail
