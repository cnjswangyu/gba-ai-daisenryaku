--[[
  诊断版探测：怀疑 ROM 卡在开机画面。
  1) 每 20 帧采样 PC / CPSR，看 PC 是否在 ROM 里死循环
  2) 采样 KEYINPUT / IME / IF / VCOUNT，看 CPU 是否还在跑、是否在等按键
  3) 逐键尝试 A / START / SELECT / B，每按一次存图并记录画面指纹
  输出：logs/probe2.txt + shots/p2_*.png
]]

local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/probe2.txt"
local SHOT = BASE .. "shots/"

local lines = {}
local function w(s) lines[#lines + 1] = s end
local function hex(v, n) return string.format("%0" .. (n or 2) .. "X", (v or 0) % 2 ^ (4 * (n or 2))) end

local function memfp()
  local acc = 5381
  local function mix(v) acc = (acc * 33 + v) % 1000003 end
  for _, a in ipairs({ 0x05000000, 0x06000000, 0x07000000 }) do
    for off = 0, 0x1000 - 1, 32 do
      local ok, v = pcall(memory.read_u16_le, a + off)
      if ok then mix(v or 0) end
    end
  end
  return acc
end

local function reg(name)
  local ok, v = pcall(emu.getregister, name)
  if ok and v then return v end
  return -1
end

local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

local function sample(tag)
  w(string.format("%-12s f=%-5d PC=0x%08X CPSR=0x%08X LR=0x%08X R0=0x%08X KEYINPUT=0x%03X IF=0x%04X IME=%d VCOUNT=%-3d fp=%d",
    tag, emu.framecount(), reg("PC"), reg("CPSR"), reg("R14"), reg("R0"),
    memory.read_u16_le(0x04000130) % 1024,
    memory.read_u16_le(0x04000202), memory.read_u16_le(0x04000208),
    memory.read_u16_le(0x04000006), memfp()))
end

local function snap(tag)
  pcall(client.screenshot, SHOT .. "p2_" .. tag .. ".png")
end

local function press(key, hold, gap)
  pcall(joypad.set, { [key] = true }, 1)
  adv(hold or 4)
  pcall(joypad.set, {}, 1)
  adv(gap or 40)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)

w("=== 诊断开始 ===")

-- 阶段 1：不按任何键，看 PC 轨迹（判断是否死循环）
adv(40)
sample("idle_0")
for i = 1, 12 do
  adv(20)
  sample("idle_" .. i)
end
snap("idle")

-- 阶段 2：按键尝试
w("")
w("=== 按键尝试 ===")
local keys = { "A", "B", "Start", "Select", "Right", "A", "Start", "A" }
for i, k in ipairs(keys) do
  local before = memfp()
  press(k, 5, 45)
  adv(30)
  local after = memfp()
  snap(string.format("key%d_%s", i, k))
  w(string.format("  按 %-7s -> fp %d -> %d  %s  PC=0x%08X",
    k, before, after, before == after and "画面未变" or "画面变化", reg("PC")))
end

-- 阶段 3：长等待（模拟"过场需要时间"）
w("")
w("=== 长时间空转 600 帧 ===")
adv(600)
sample("after600")
w("  PC=0x" .. hex(reg("PC"), 8))

-- 阶段 4：看 ROM 里的入口是否被执行过（IWRAM/EWRAM 是否被用过）
w("")
w("=== RAM 使用情况 ===")
for _, r in ipairs({ { "EWRAM", 0x02000000, 64 }, { "IWRAM", 0x03000000, 8 } }) do
  local tag, base, nblk = r[1], r[2], r[3]
  local used = 0
  for b = 0, nblk - 1 do
    local ok, bytes = pcall(memory.readbyterange, base + b * 4096, 4096)
    local nz = 0
    if ok and bytes then
      for j = 0, 4095, 16 do if (bytes[j] or 0) ~= 0 then nz = nz + 1 end end
    end
    if nz > 0 then used = used + 1 end
  end
  w(string.format("  %s 有数据的 4KB 块: %d/%d", tag, used, nblk))
end

local text = table.concat(lines, "\n") .. "\n"
local okw = pcall(function()
  local f = io.open(OUT, "w")
  if not f then error("io.open failed") end
  f:write(text)
  f:close()
end)
if not okw then pcall(comm.mmfWrite, "probe2.txt", text) end

pcall(client.exit)
