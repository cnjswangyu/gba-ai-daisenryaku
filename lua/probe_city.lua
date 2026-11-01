-- probe_city.lua —— 扫全图建筑格 + 4 字节布局（找归属/耐久/占领进度字段）
local BASE = "D:/prog/gba-ai/"
local fh = io.open(BASE .. "logs/probe_city.txt", "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function r8(a) return memory.read_u8(a) end
local CTX = 0x03000480
adv(30)
savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
local terrbase = memory.read_u32_le(CTX + 0x18)
w(string.format("地形表基址=0x%08X", terrbase))
local counts, list = {}, {}
for y = 1, 34 do
  for x = 1, 46 do
    local cell = terrbase + x*4 + y*0xC0
    local t = r8(cell)
    if t >= 0x10 and t <= 0x28 then
      counts[t] = (counts[t] or 0) + 1
      list[#list+1] = string.format("(%2d,%2d) t=%02X bytes=%02X %02X %02X %02X",
        x, y, t, r8(cell), r8(cell+1), r8(cell+2), r8(cell+3))
    end
  end
end
for t, n in pairs(counts) do w(string.format("地形 %02X: %d 格", t, n)) end
w("--- 建筑格明细 ---")
for _, l in ipairs(list) do w(l) end
if fh then fh:close() end
pcall(client.exit)
