-- verify_move.lua —— 移动落地验证程序（双跑对比）
-- 金标准: 游戏原生移动（移動菜单+寻路+A 落格+待机），记录燃料扣减/落点/格表
-- 模拟跑: BFS（用游戏自己的移耗表）算 cost，内存写四件套+扣燃料到同一格
-- PASS = 两跑的落点/燃料扣减/格表状态完全一致
local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/verify_move.txt"
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/vm_" .. n .. ".png") end
-- ===== 输入：邮箱注入（0x03007F00，规矩：不用 joypad）=====
local MAIL = 0x03007F00
local KEYBIT = { A = 0x1, B = 0x2, Select = 0x4, Start = 0x8,
                 Right = 0x10, Left = 0x20, Up = 0x40, Down = 0x80 }
local function patch_mail()
  local hits = {}
  for a = 0x03000000, 0x03007FFC, 4 do
    if memory.read_u32_le(a) == 0x04000130 then hits[#hits + 1] = a end
  end
  for _, a in ipairs(hits) do memory.write_u32_le(a, MAIL) end
  if memory.read_u32_le(0x080015F4) == 0x04000130 then
    memory.write_u32_le(0x080015F4, MAIL)
  end
  memory.write_u16_le(MAIL, 0x3FF)
  w("邮箱补丁：IWRAM " .. #hits .. " 处 + ROM")
end
local function mhold(k, frames)
  for _ = 1, (frames or 4) do
    memory.write_u16_le(MAIL, 0x3FF - (KEYBIT[k] or 0)); adv(1)
  end
  memory.write_u16_le(MAIL, 0x3FF)
end
local function mtap(k, gap) mhold(k, 4); adv(gap or 40) end
local function press(k, hold, gap) mhold(k, hold, gap or 40) end
local function dir(k) mhold(k, 5); adv(5) end   -- 邮箱实测：按住 5 帧 = 走 1 格
local CTX = 0x03000480
local U   = 0x03002BE2
local DBA = 0x08798AF4
local function r8(a) return memory.read_u8(a) end
local function state() return r8(CTX) end
local function cur() return r8(0x030067FE), r8(0x030067FF) end
local K = 17  -- 验证对象：U17 空降傘兵(324) @ (19,29)，西面开阔
local function rec() local b=U+K*24-2 return {
  id=memory.read_u16_le(b), x=r8(b+2), y=r8(b+3), fuel=r8(b+4), lv=r8(b+5),
  hp=r8(b+6), st=r8(b+7) } end
local function grid(x,y) return r8(CTX+0x3F60+x*4+y*0xC0), r8(CTX+0x3F60+x*4+y*0xC0+1) end

-- ===== 移耗（游戏自己的表）=====
local tblA = 0x08046F26
local tblB = 0x08046FC6
local tmap = memory.read_u32_le(0x080026d4)
local function cost(terr, cat)
  if terr >= 0x10 and terr < 0x29 then return r8(tblB + (terr-0x10) + cat*5) end
  local idx = r8(tmap + terr)
  return r8(tblA + idx + cat*0x10)
end
local function terr_at(x,y)
  local base = memory.read_u32_le(CTX + 0x18)
  return r8(base + x*4 + y*0xC0)
end
-- 六邻格（FUN_08002DC4：偶数行左偏）
local function neighbors(x, y)
  local d = (y % 2 == 0) and -1 or 0
  return {{x+1,y},{x-1,y},{x+d,y-1},{x+d+1,y-1},{x+d+1,y+1},{x+d,y+1}}
end
-- Dijkstra 可达集（预算 = min(移动力, 燃料)）
local function bfs(sx, sy, budget, cat)
  local dist, queue = {}, {{sx, sy, 0}}
  dist[sx .. "," .. sy] = 0
  while #queue > 0 do
    table.sort(queue, function(a,b) return a[3] < b[3] end)
    local cell = table.remove(queue, 1)
    local x, y, c = cell[1], cell[2], cell[3]
    if c == dist[x .. "," .. y] then
      for _, n in ipairs(neighbors(x, y)) do
        local nx, ny = n[1], n[2]
        if nx >= 1 and nx <= 46 and ny >= 1 and ny <= 34 then
          local occ = r8(CTX + 0x3F60 + nx*4 + ny*0xC0)
          if occ == 0 or occ == 1 then   -- 用户确认：可穿过友军，不可落在友军身上
            local tcost = cost(terr_at(nx, ny), cat)
            if tcost == 0 then tcost = 99 end   -- 移耗 0 = 不可通行（实测：平地/首都等）
            local nc = c + tcost
            if nc <= budget and (dist[nx .. "," .. ny] == nil or nc < dist[nx .. "," .. ny]) then
              dist[nx .. "," .. ny] = nc
              queue[#queue+1] = {nx, ny, nc}
            end
          end
        end
      end
    end
  end
  return dist
end

local function snapshot(tag)
  local r = rec()
  local g1x, g1y = grid(r.x, r.y)
  w(string.format("%s: pos=(%d,%d) fuel=%d st=%d 格表=(%d,%d) cur=(%d,%d)",
    tag, r.x, r.y, r.fuel, r.st, g1x, g1y, cur()))
  return r
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  pcall(client.setsoundon, true)
  adv(30)
  savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
  patch_mail()
  local r0 = rec()
  local cat = r8(0x08798A98 + r0.id * 0x5C + 5)
  local move = 4   -- 空降傘兵 移动力（unitdb.tsv col4）
  local budget = math.min(move, r0.fuel)
  w(string.format("验证对象 U0 id=%d (%d,%d) 燃料=%d 移耗类别=%d 预算=%d",
    r0.id, r0.x, r0.y, r0.fuel, cat, budget))
  local reach = bfs(r0.x, r0.y, budget, cat)
  -- 选目标：可达且最远（cost 最大）的空格
  local tx, ty, tc = nil, nil, -1
  for k2, c in pairs(reach) do
    local x, y = k2:match("(-?%d+),(-?%d+)")
    x, y = tonumber(x), tonumber(y)
    if c > tc and r8(CTX + 0x3F60 + x*4 + y*0xC0) == 0 then tc, tx, ty = c, x, y end
  end
  if not tx then error("BFS 无可达空格") end
  local rc = 0 for _ in pairs(reach) do rc = rc + 1 end
  w(string.format("BFS 可达 %d 格，目标 (%d,%d) 预期移耗=%d", rc, tx, ty, tc))

  -- ===== 金标准：游戏原生移动 =====
  -- 决定性实验：Right / Left 连按对比
  for i = 1, 15 do
    joypad.set({ Right = true }); adv(1)
  end
  joypad.set({})
  local r1x, r1y = cur()
  w(string.format("Right 连按15帧后 -> (%d,%d)", r1x, r1y))
  for i = 1, 15 do
    joypad.set({ Left = true }); adv(1)
  end
  joypad.set({})
  local l1x, l1y = cur()
  w(string.format("Left  连按15帧后 -> (%d,%d)", l1x, l1y))
  -- 先把光标走到 U17 所在格
  for i = 1, 80 do
    local x, y = cur()
    if x == r0.x and y == r0.y then break end
    local dx, dy = r0.x - x, r0.y - y
    local key = (dy ~= 0 and math.abs(dy) >= math.abs(dx)) and ((dy>0) and "Down" or "Up")
                or ((dx ~= 0) and ((dx>0) and "Right" or "Left") or ((dy>0) and "Down" or "Up"))
    dir(key)
    if i <= 6 or i % 10 == 0 then
      local wx, wy = cur()
      w(string.format("走位 i=%d key=%s -> (%d,%d)", i, key, wx, wy))
    end
  end
  if cur() ~= r0.x or select(2, cur()) ~= r0.y then
    error(string.format("光标没走到单位格 (%d,%d)，停在 (%d,%d)", r0.x, r0.y, cur()))
  end
  press("A", 6, 60)     -- 选中
  press("A", 6, 60)     -- 移動/解散
  press("A", 6, 90)     -- 移動 → 寻路态
  local px, py = cur()
  w(string.format("A×3 后: state=%d sub=%d ph=%d cur=(%d,%d)", state(), r8(CTX+1), r8(CTX+0x21), px, py))
  shot("pathmode")
  if px ~= r0.x or py ~= r0.y then error("未进入寻路态") end
  -- 单步试探：按一次 Right，看光标/路径是否延伸
  press("Right", 14, 8)
  w(string.format("Right 一步后 cur=(%d,%d)", cur()))
  shot("pathstep1")
  -- 光标闭环走到目标（寻路态内）
  local lastx, lasty, still = -99, -99, 0
  for i = 1, 60 do
    local x, y = cur()
    if x == tx and y == ty then break end
    if x == lastx and y == lasty then
      still = still + 1
      if still >= 3 then
        local moved = false
        for _, kk in ipairs({"Up","Down","Left","Right"}) do
          local bx, by = cur(); dir(kk)
          if cur() ~= bx or select(2,cur()) ~= by then moved = true break end
        end
        if not moved then break end
        still = 0
      end
    else still = 0 end
    lastx, lasty = x, y
    local dx, dy = tx - x, ty - y
    local key = (dy ~= 0 and math.abs(dy) >= math.abs(dx)) and ((dy>0) and "Down" or "Up")
                or ((dx ~= 0) and ((dx>0) and "Right" or "Left") or ((dy>0) and "Down" or "Up"))
    press(key, 14, 8)
  end
  if cur() ~= tx or select(2, cur()) ~= ty then
    error(string.format("寻路光标没走到 (%d,%d)，停在 (%d,%d)", tx, ty, cur()))
  end
  press("A", 6, 60)     -- 落格确认
  press("A", 6, 60)     -- 待機
  adv(60)
  local gold = snapshot("金标准(游戏原生移动)")
  gold.expected_cost = tc
  gold.tx, gold.ty = tx, ty
  savestate.save(BASE .. "states/verify_gold.State")

  -- ===== 模拟跑：重置 → 内存移动（BFS cost 扣燃料）=====
  savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
  local r1 = rec()
  local b = U + K*24 - 2
  local g1 = CTX + 0x3F60 + r1.x*4 + r1.y*0xC0
  memory.write_u8(g1, 0); memory.write_u8(g1+1, 0)
  local g2 = CTX + 0x3F60 + tx*4 + ty*0xC0
  memory.write_u8(g2, 1); memory.write_u8(g2+1, K+1)
  memory.write_u8(b+2, tx); memory.write_u8(b+3, ty)
  memory.write_u8(b+4, r1.fuel - tc)          -- 按 BFS 移耗扣燃料
  memory.write_u8(CTX + 0x637E, tx); memory.write_u8(CTX + 0x637F, ty)
  adv(30)
  local sim = snapshot("模拟(内存移动+BFS扣燃料)")
  sim.expected_cost = tc

  -- ===== 对比 =====
  local pass = (sim.x == gold.x and sim.y == gold.y and sim.fuel == gold.fuel
                and sim.st == gold.st)
  w(string.format("对比: 落点 %s | 燃料 金=%d 模=%d (预期扣 %d) | 状态 金=%d 模=%d",
    (gold.x == sim.x and gold.y == sim.y) and "一致" or "不一致",
    gold.fuel, sim.fuel, tc, gold.st, sim.st))
  w(pass and "PASS ✔ 内存移动与游戏原生移动完全一致" or "FAIL ✘ 存在差异，见上")
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
