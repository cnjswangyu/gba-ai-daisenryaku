-- probe_keyframe.lua —— 帧级输入观察
local BASE = "D:/prog/gba-ai/"
local fh = io.open(BASE .. "logs/probe_keyframe.txt", "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end
local CTX = 0x03000480
local function r8(a) return memory.read_u8(a) end
local function cur() return r8(0x030067FE), r8(0x030067FF) end
local ok, err = xpcall(function()
  pcall(client.speedmode, 100)
  adv(30)
  savestate.load(BASE .. "states/stage1_v2_deployed.State"); adv(60)
  local c0x, c0y = cur()
  w(string.format("载入 cur=(%d,%d) state=%d ph=%d", c0x, c0y, r8(CTX), r8(CTX+0x21)))
  -- 按住 Right 25 帧，逐帧记录
  for i = 1, 25 do
    joypad.set({ Right = true })
    adv(1)
    local kx, ky = cur()
    w(string.format("f%d KEYINPUT=%03X ctx新键=%03X 按住=%03X cur=(%d,%d)",
      i, memory.read_u16_le(0x04000130), memory.read_u16_le(CTX+0x0C),
      memory.read_u16_le(CTX+0x0E), kx, ky))
  end
  joypad.set({})
  adv(10)
  -- 对照：A 键 10 帧
  for i = 1, 10 do
    joypad.set({ A = true })
    adv(1)
    w(string.format("A%d KEYINPUT=%03X ctx新键=%03X 按住=%03X",
      i, memory.read_u16_le(0x04000130), memory.read_u16_le(CTX+0x0C), memory.read_u16_le(CTX+0x0E)))
  end
  joypad.set({})
  adv(30)
  local c1x, c1y = cur()
  w(string.format("A 后 cur=(%d,%d) state=%d", c1x, c1y, r8(CTX)))
end, function(e) w("ERROR: " .. tostring(e)) end)
w("done ok=" .. tostring(ok) .. " " .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
