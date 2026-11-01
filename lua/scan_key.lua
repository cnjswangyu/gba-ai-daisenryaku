-- 在 RAM 里找运行期的 0x04000130 字面量（游戏可能把输入函数复制到 IWRAM）
local BASE = "D:/prog/gba-ai/"
local SRC  = BASE .. "states/battle.State"
local OUT  = BASE .. "logs/scan_key.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)

for _, reg in ipairs({ { 0x02000000, 0x40000, "EWRAM" }, { 0x03000000, 0x8000, "IWRAM" } }) do
  local base, len, name = reg[1], reg[2], reg[3]
  local hits = 0
  for off = 0, len - 4 do
    if memory.read_u32_le(base + off) == 0x04000130 then
      hits = hits + 1
      say(string.format("%s 命中 0x%08X", name, base + off))
      if hits > 20 then break end
    end
  end
  say(string.format("%s 共 %d 处", name, hits))
end

-- 顺便看 IWRAM 里是否有与 0x080015D4 相同的指令序列（0xC0B5.. = push {r6,r7,lr}）
say("done")
pcall(client.exit)
