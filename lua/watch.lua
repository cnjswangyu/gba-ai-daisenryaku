-- 操作驱动逆向：逐步动作 + 每步快照，用于定位"状态机标志位"
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local DIR   = BASE .. "states/watch/"
local LOG   = BASE .. "logs/watch.txt"
local unpack = table.unpack or unpack
local function say(s) local f=io.open(LOG,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/w_"..n..".png") end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 20)
end
local function step1(dir)
  for _ = 1, 14 do joypad.set({ [dir] = true }); emu.frameadvance() end
  joypad.set({}); adv(6)
end
local function cur() return memory.read_u8(0x030067FE), memory.read_u8(0x030067FF) end

local function dump_bin(addr, len, path)
  local parts, CH = {}, 1024
  for off = 0, len - 1, CH do
    local n = math.min(CH, len - off)
    local ok, b = pcall(memory.readbyterange, addr + off, n)
    if ok and b then
      local acc = {}
      for i = 0, n - 1, 256 do
        local chunk = {}
        for j = i, math.min(i + 255, n - 1) do chunk[#chunk + 1] = b[j] or 0 end
        acc[#acc + 1] = string.char(unpack(chunk))
      end
      parts[#parts + 1] = table.concat(acc)
    end
  end
  local f = io.open(path, "wb"); if f then f:write(table.concat(parts)); f:close() end
end
local function snap(tag)
  dump_bin(0x02000000, 0x40000, DIR .. tag .. "_e.bin")
  dump_bin(0x03000000, 0x8000,  DIR .. tag .. "_i.bin")
  shot(tag)
  say(string.format("snap %-10s cursor=(%d,%d)", tag, cur()))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(40)
-- 清横幅到空闲
for _ = 1, 4 do
  local x0 = cur(); step1("Right"); local x1 = cur(); step1("Left")
  if x0 ~= x1 then break end
  tap("A", 60)
end

snap("s0_idle")
tap("A", 25);  snap("s1_menu")       -- 单位菜单
tap("A", 25);  snap("s2_move")       -- 移動（范围显示）
step1("Right"); snap("s3_cursor")    -- 光标走一格
tap("A", 25);  snap("s4_commit")     -- 确认落点
adv(45);       snap("s5_after")      -- 动画结束
tap("B", 25);  snap("s6_b")          -- 取消
tap("A", 25);  snap("s7_a")
say("done")
pcall(client.exit)
