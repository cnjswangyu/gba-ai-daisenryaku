-- One-shot native framebuffer capture for release media.
local OUT = "D:/prog/gba-ai/media/victory_native.png"
local saved = false

while true do
  if not saved then
    client.screenshot(OUT)
    print("SHOT " .. OUT)
    saved = true
  end
  emu.frameadvance()
end
