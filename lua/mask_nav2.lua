-- 用掩码挑"最东侧可走格"→ 导航光标 → 确认移动 → 内存校验
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local OUT   = BASE .. "logs/masknav2.txt"
local MASK, STRIDE, ROWS, COLS = 0x030010DD, 48, 144, 48

local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/mv2_"..n..".png"); say("shot "..n) end
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
for _ = 1, 20 do
  local cx, cy = cur()
  if math.abs(cx - ux) <= 1 and math.abs(cy - uy) <= 1 then break end
  if cx < ux then hold("Right", 14) elseif cx > ux then hold("Left", 14)
  elseif cy < uy then hold("Down", 14) else hold("Up", 14) end
end

tap("A", 50); tap("A", 50); adv(40)   -- 选中 → 移動
shot("01_range")

-- bbox → 偏移
local minc, maxc, minr, maxr = 999, -1, 999, -1
for r = 0, ROWS - 1 do
  for c = 0, COLS - 1 do
    if mark(c, r) then
      if c < minc then minc = c end; if c > maxc then maxc = c end
      if r < minr then minr = r end; if r > maxr then maxr = r end
    end
  end
end
local offc = ux - (minc + maxc) / 2
local offr = uy - (minr + maxr) / 2
say(string.format("bbox col %d..%d row %d..%d offset (%.1f,%.1f)", minc, maxc, minr, maxr, offc, offr))

-- 选最东侧（col 最大）的可走格
local bestc, bestr = nil, nil
for r = minr, maxr do
  for c = maxc, minc, -1 do
    if mark(c, r) then bestc, bestr = c, r; break end
  end
  if bestc then break end
end
local tx, ty = math.floor(bestc + offc + 0.5), math.floor(bestr + offr + 0.5)
say(string.format("目标格 mask(%d,%d) -> hex(%d,%d)", bestc, bestr, tx, ty))

-- 导航光标到目标
local ok = false
for _ = 1, 20 do
  local cx, cy = cur()
  if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then ok = true; break end
  if cx < tx then hold("Right", 14) elseif cx > tx then hold("Left", 14)
  elseif cy < ty then hold("Down", 14) else hold("Up", 14) end
end
say(string.format("导航%s cursor=%s", ok and "成功" or "失败", string.format("(%d,%d)", cur())))
shot("02_at_target")

tap("A", 90)     -- 确认移动
adv(90)
local nx, ny, nhp = unit0()
say(string.format("unit0 (%d,%d) -> (%d,%d) hp=%d", ux, uy, nx, ny, nhp))
shot("03_moved")
say("done")
pcall(client.exit)
