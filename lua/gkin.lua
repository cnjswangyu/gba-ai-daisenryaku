-- gkin：直接注入按键（把输入函数的 KEYINPUT 换成 RAM 邮箱），不走 joypad
-- 用法：GK.patch()  GK.key(0x0010, 5)  GK.tap(0x0001)  GK.release()
GK = {}
GK.MAIL  = 0x03007F00
GK.LITS  = { 0x03007560, 0x0300758C, 0x030075A8, 0x030075B8, 0x03007F94 }
GK.ROM   = 0x080015F4
GK.A, GK.B, GK.SEL, GK.START = 0x1, 0x2, 0x4, 0x8
GK.RIGHT, GK.LEFT, GK.UP, GK.DOWN = 0x10, 0x20, 0x40, 0x80
GK.R, GK.L = 0x100, 0x200

function GK.patch()
  memory.write_u16_le(GK.MAIL, 0x3FF)
  for _, a in ipairs(GK.LITS) do memory.write_u32_le(a, GK.MAIL) end
  memory.write_u32_le(GK.ROM, GK.MAIL)
end

function GK.restore()
  for _, a in ipairs(GK.LITS) do memory.write_u32_le(a, 0x04000130) end
  memory.write_u32_le(GK.ROM, 0x04000130)
end

function GK.down(bits) memory.write_u16_le(GK.MAIL, 0x3FF - bits) end
function GK.release() memory.write_u16_le(GK.MAIL, 0x3FF) end

-- 按住 bits 共 frames 帧（游戏看到的都是"按住"）
function GK.key(bits, frames)
  GK.down(bits)
  for _ = 1, (frames or 1) do emu.frameadvance() end
  GK.release()
  for _ = 1, 3 do emu.frameadvance() end
end

-- 点一下（新按下边沿）：1 帧按下 + 释放
function GK.tap(bits, wait)
  GK.key(bits, 1)
  for _ = 1, (wait or 6) do emu.frameadvance() end
end

-- 按住直到条件成立（用于方向键：走 N 格）
function GK.until(bits, cond, maxframes)
  GK.down(bits)
  for _ = 1, (maxframes or 60) do
    emu.frameadvance()
    if cond() then GK.release(); return true end
  end
  GK.release()
  for _ = 1, 3 do emu.frameadvance() end
  return false
end
