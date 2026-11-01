local BASE = "D:/prog/gba-ai/"
local fh = io.open(BASE .. "logs/probe_tmap.txt", "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function r8(a) return memory.read_u8(a) end
adv(30)
savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
local tmap = memory.read_u32_le(0x080026d4)
w(string.format("tmap 指针值 = 0x%08X", tmap))
-- 采样映射表 tmap[0..255]
local row = {}
for i = 0, 63 do row[#row+1] = string.format("%02X", r8(tmap + i)) end
w("tmap[0..63]: " .. table.concat(row, " "))
-- 移耗采样：草地(1) 森林(0x8B) 道路(0x83) 首都(0x10) 市街(0x11) 对 cat 2 和 4
local tblA = 0x08046F26
local tblB = 0x08046FC6
for _, terr in ipairs({0x01, 0x02, 0x83, 0x8B, 0x10, 0x11, 0x0C}) do
  local idx = r8(tmap + terr)
  local c2 = r8(tblA + idx + 2*0x10)
  local c4 = r8(tblA + idx + 4*0x10)
  w(string.format("地形 %02X → 索引 %d → cat2=%d cat4=%d", terr, idx, c2, c4))
end
if fh then fh:close() end
pcall(client.exit)
