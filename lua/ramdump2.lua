-- 干净战斗状态下的 RAM 差分：确认光标字段
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/battle_start.State"
local DIR   = BASE .. "states/ram2/"
local LOG   = BASE .. "logs/ramdump2.txt"
local unpack = table.unpack or unpack
local function say(s) local f=io.open(LOG,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/r2_"..n..".png") end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 50)
end
local function key(k, n) for _ = 1, n do press(k, 8, 40) end end

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

press("A", 8, 120)    -- 确认自动部署
adv(120)
press("A", 8, 120)    -- 回合相关提示
adv(120)

snap("00_clean")
key("Right", 3); snap("01_right3")
key("Left", 3);  snap("02_left3")
key("Down", 2);  snap("03_down2")
press("A", 8, 80); snap("04_selectA")
say("done")
pcall(client.exit)
