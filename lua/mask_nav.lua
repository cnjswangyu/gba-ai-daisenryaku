-- 用范围掩码做一次"合法落点"判定：选中单位 → 读掩码 → 以单位为锚点标出可走方向
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/masknav.txt"
local MASK  = 0x030010DD     -- 掩码基址（实测）
local STRIDE = 48
local ROWS, COLS = 144, 48

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/mn_"..n..".png"); say("shot "..n) end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(16)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end
local function unit0()
  return memory.read_u8(0x03002BE2), memory.read_u8(0x03002BE3), memory.read_u8(0x03002BE4)
end
local function mark(c, r) return memory.read_u8(MASK + r * STRIDE + c) ~= 0xF1 end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
for _ = 1, 6 do
  local x0 = cur(); hold("Right", 12); local x1 = cur(); hold("Left", 12)
  if x0 ~= x1 then break end
  tap("A", 100)
end

local ux, uy = unit0()
say(string.format("unit0=(%d,%d) cursor=(%d,%d)", ux, uy, cur()))

-- 让光标落在 unit0 上
for _ = 1, 20 do
  local cx, cy = cur()
  if math.abs(cx - ux) <= 1 and math.abs(cy - uy) <= 1 then break end
  if cx < ux then hold("Right", 14) elseif cx > ux then hold("Left", 14)
  elseif cy < uy then hold("Down", 14) else hold("Up", 14) end
end

tap("A", 50)   -- 菜单
tap("A", 50)   -- 移動 → 计算范围
adv(40)
shot("range")

-- 掩码 bbox
local minc, maxc, minr, maxr, n = 999, -1, 999, -1, 0
for r = 0, ROWS - 1 do
  for c = 0, COLS - 1 do
    if mark(c, r) then
      n = n + 1
      if c < minc then minc = c end; if c > maxc then maxc = c end
      if r < minr then minr = r end; if r > maxr then maxr = r end
    end
  end
end
say(string.format("掩码标记 %d 个, col %d..%d, row %d..%d", n, minc, maxc, minr, maxr))
local bc, br = (minc + maxc) / 2, (minr + maxr) / 2
local offc, offr = ux - bc, uy - br
say(string.format("bbox中心(%.1f,%.1f) → 偏移(%.1f,%.1f)", bc, br, offc, offr))

-- 打印以单位为窗的网格
say("网格（U=单位, #=可走, .=不可走）")
for r = math.floor(br) - 5, math.floor(br) + 5 do
  local line = {}
  for c = math.floor(bc) - 6, math.floor(bc) + 6 do
    if r == math.floor(br) and c == math.floor(bc) then line[#line + 1] = "U"
    elseif r >= 0 and r < ROWS and c >= 0 and c < COLS and mark(c, r) then line[#line + 1] = "#"
    else line[#line + 1] = "." end
  end
  say(string.format("  r%3d %s", r, table.concat(line)))
end
say("done")
pcall(client.exit)
