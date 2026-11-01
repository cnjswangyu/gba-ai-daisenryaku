-- 真正的光标差分：按住多帧让光标走，每步导 RAM
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/pre_battle.State"
local DIR   = BASE .. "states/ram3/"
local LOG   = BASE .. "logs/ramdump3.txt"
local unpack = table.unpack or unpack
local function say(s) local f=io.open(LOG,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/r3_"..n..".png") end
local function tap(k)
  joypad.set({ [k] = true }); emu.frameadvance(); joypad.set({}); adv(8)
end
local function hold(k, f)
  for _ = 1, (f or 14) do joypad.set({ [k] = true }); emu.frameadvance() end
  joypad.set({}); adv(20)
end

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
  shot(tag)
  say("snap " .. tag)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)

tap("Start"); adv(40)
tap("A"); adv(80)
tap("A"); adv(80)
snap("00_clean")

hold("Right", 14); snap("01_r1")
hold("Right", 14); snap("02_r2")
hold("Down", 14);  snap("03_d1")
hold("Left", 14);  snap("04_l1")
say("done")
pcall(client.exit)
