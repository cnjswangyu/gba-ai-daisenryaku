-- 指针猜测验证：直接改内存候选地址，看光标/坐标显示是否变化
local BASE  = "D:/prog/gba-ai/"
local SRC   = BASE .. "states/pre_battle.State"
local OUT   = BASE .. "logs/poke.txt"
local function say(s) local f=io.open(OUT,"a"); if f then f:write(s,"\n"); f:close() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function shot(n) pcall(client.screenshot, BASE.."shots/pk_"..n..".png"); say("shot "..n) end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 8); joypad.set({}); adv(gap or 50)
end

pcall(client.speedmode, 0)
pcall(client.setsoundon, false)
adv(20)
say("load=" .. tostring(pcall(savestate.load, SRC)))
adv(60)
press("Start", 8, 80)
press("A", 8, 150)
adv(120)
shot("00_base")

-- 候选 1: 0x030004AB (21,30)
say("poke1 0x030004AB <- 5,10")
memory.write_u8(0x030004AB, 5)
memory.write_u8(0x030004AC, 10)
adv(30); shot("01_poke04AB")

-- 候选 2: 0x030067FE (21,30)
say("poke2 0x030067FE <- 5,10")
memory.write_u8(0x030067FE, 5)
memory.write_u8(0x030067FF, 10)
adv(30); shot("02_poke67FE")

-- 候选 3: 单位表第一条 0x03002BE2
say("poke3 unit0 <- 5,10")
memory.write_u8(0x03002BE2, 5)
memory.write_u8(0x03002BE3, 10)
adv(30); shot("03_poke2BE2")

say("done")
pcall(client.exit)
