-- 三态快照：未选中 → 选中(菜单) → 移动模式(显示范围) → 取消
-- 用来定位"移动范围"标志位与地形数组
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle.State"
local DIR   = BASE .. "states/ram4/"
local LOG   = BASE .. "logs/ramdump4.txt"
local unpack = table.unpack or unpack
local function say(s) local f=io.open(LOG,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/r4_"..n..".png") end
local function tap(k, g)
  for _ = 1, 5 do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(g or 40)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(16)
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
  dump_bin(0x02000000, 0x40000, DIR .. tag .. "_ewram.bin")
  dump_bin(0x03000000, 0x8000,  DIR .. tag .. "_iwram.bin")
  shot(tag); say("snap " .. tag)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

-- 清横幅
for _ = 1, 6 do
  local x0 = cur(); hold("Right", 12); local x1 = cur(); hold("Left", 12)
  if x0 ~= x1 then break end
  tap("A", 100)
end
say(string.format("cursor=(%d,%d)", cur()))
snap("00_idle")

-- 选中一个单位（光标已在其上）
tap("A", 60);  snap("01_menu")     -- 单位菜单
tap("A", 60);  snap("02_range")    -- 移動：显示移动范围
tap("B", 60);  snap("03_cancel")   -- 取消
tap("B", 60);  snap("04_idle2")
say("done")
pcall(client.exit)
