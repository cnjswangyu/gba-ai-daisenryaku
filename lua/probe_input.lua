-- probe_input.lua —— 诊断 v2_deployed 存档点的输入响应
local BASE = "D:/prog/gba-ai/"
local fh = io.open(BASE .. "logs/probe_input.txt", "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local function press(k, hold, gap)
  joypad.set({ [k] = true }); adv(hold or 6); joypad.set({}); adv(gap or 60)
end
local CTX = 0x03000480
local function r8(a) return memory.read_u8(a) end
local function cur() return r8(0x030067FE), r8(0x030067FF) end
local function snap(tag)
  w(string.format("%s f=%d state=%d sub=%d ph=%d side=%d newkey=%03X hold=%03X cur=(%d,%d)",
    tag, emu.framecount(), r8(CTX), r8(CTX+1), r8(CTX+0x21), r8(CTX+0x22),
    memory.read_u16_le(CTX+0x0C), memory.read_u16_le(CTX+0x0E), cur()))
end
local ok, err = xpcall(function()
  pcall(client.speedmode, 400)
  adv(30)
  savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
  snap("载入后")
  press("Right", 14, 8); snap("Right 后")
  press("A", 6, 60);     snap("A 后")
  press("Start", 8, 80); snap("Start 后")
  shot("pi_start")
  press("B", 6, 60);     snap("B 后")
  -- 对照：battle_usa_ready 存在吗？
  local f = io.open(BASE .. "states/battle_usa_ready.State", "rb")
  if f then f:close()
    savestate.load(BASE .. "states/battle_usa_ready.State"); adv(60)
    snap("载入 battle_usa_ready")
    press("Right", 14, 8); snap("对照 Right 后")
  else
    w("无 battle_usa_ready.State")
  end
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
