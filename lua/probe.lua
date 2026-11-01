-- 最小验证：跑 120 帧，截两张图，然后暂停。
-- 用来确认 EmuHawk 能正常加载 ROM、Lua 能写截图文件。

local BASE = "D:/prog/gba-ai/"

console.log("[probe] start, core = " .. emu.getsystemid())

for _ = 1, 120 do
  emu.frameadvance()
end

client.screenshot(BASE .. "shots/probe_a.png")
for _ = 1, 30 do
  emu.frameadvance()
end
client.screenshot(BASE .. "shots/probe_b.png")

console.log("[probe] screenshots written, frame = " .. emu.framecount())
client.pause()
