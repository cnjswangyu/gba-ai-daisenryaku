-- RAM 差分扫描：在几个关键操作前后各导一份 EWRAM+IWRAM，供 Python 对比
local BASE  = "D:/prog/gba-ai/"
local STATE = BASE .. "states/battle_start.State"
local DIR   = BASE .. "states/ram/"
local LOG   = BASE .. "logs/ramdump.txt"
local unpack = table.unpack or unpack   -- Lua 5.4 没有全局 unpack
local lines = {}
local function w(s) lines[#lines + 1] = s end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE .. "shots/d_" .. n .. ".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true })
  adv(hold or 4)
  joypad.set({})
  adv(gap or 26)
end
local function key(k, n) for _ = 1, n do press(k, 4, 20) end end

local function dump_bin(addr, len, path)
  local parts = {}
  local CH = 1024
  for off = 0, len - 1, CH do
    local n = math.min(CH, len - off)
    local ok, b = pcall(memory.readbyterange, addr + off, n)
    if ok and b then
      local acc = {}
      for i = 0, n - 1, 256 do
        local chunk = {}
        for j = i, math.min(i + 255, n - 1) do
          chunk[#chunk + 1] = b[j] or 0
        end
        acc[#acc + 1] = string.char(unpack(chunk))
      end
      parts[#parts + 1] = table.concat(acc)
    end
  end
  local f = io.open(path, "wb")
  if f then f:write(table.concat(parts)); f:close(); return true end
  return false
end

local function snap(tag)
  local ok1 = dump_bin(0x02000000, 0x40000, DIR .. tag .. "_ewram.bin")
  local ok2 = dump_bin(0x03000000, 0x8000,  DIR .. tag .. "_iwram.bin")
  shot(tag)
  w(string.format("%-14s ewram=%s iwram=%s", tag, tostring(ok1), tostring(ok2)))
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(30)
local ok = pcall(savestate.load, STATE)
w("load state: " .. tostring(ok))
adv(60)

snap("00_init")

key("Right", 3); snap("01_right3")
key("Left", 3);  snap("02_left3")
key("Down", 2);  snap("03_down2")
press("A", 5, 40); snap("04_select")
press("A", 5, 40); snap("05_menu")
press("B", 5, 40); snap("06_cancel")
press("B", 5, 40); adv(20); snap("07_back")

local f = io.open(LOG, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
