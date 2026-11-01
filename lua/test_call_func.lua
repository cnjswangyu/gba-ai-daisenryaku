-- 验证：能不能直接调用游戏内部函数（寄存器注入 + 陷阱返回）
-- 先拿纯函数 FUN_08002e74(x1,y1,x2,y2)->距离 试，无副作用
-- 关键点：Thumb 函数入口要 +1（bit0=1），否则按 ARM 解码直接崩（之前踩的坑）
local B = "D:/prog/gba-ai/"
local OUT = B .. "logs/call_func.txt"
local TRAP = 0x0203FF00          -- 陷阱：EWRAM 尾部（不要放 IWRAM 0x7F80，那是 IRQ 栈）
local fh = io.open(OUT, "w")
local function w(s) if fh then fh:write(s .. "\n"); fh:flush() end end
local function adv(n) for _ = 1, (n or 1) do emu.frameadvance() end end

local function save_regs()
  local r = {}
  for i = 0, 15 do r[i] = emu.getregister("R" .. i) end
  r.cpsr = emu.getregister("CPSR")
  return r
end
local function restore(r)
  for i = 0, 15 do emu.setregister("R" .. i, r[i]) end
  emu.setregister("CPSR", r.cpsr)
end

-- 调用一个 Thumb 函数，返回 R0
local function call_thumb(addr, args, maxframes)
  -- 陷阱：b .
  memory.write_u16_le(TRAP, 0xE7FE)
  local saved = save_regs()
  local ok, res = pcall(function()
    for i = 1, #args do emu.setregister("R" .. (i - 1), args[i]) end
    emu.setregister("R14", TRAP + 1)      -- LR = 陷阱(Thumb)
    emu.setregister("R15", addr + 1)      -- PC = 函数入口(Thumb)
    local ret = -1
    for f = 1, (maxframes or 30) do
      emu.frameadvance()
      local pc = emu.getregister("R15")
      if pc == TRAP or pc == TRAP + 1 then
        ret = emu.getregister("R0")
        break
      end
    end
    return ret
  end)
  restore(saved)
  return ok and res or -999, ok
end

local ok, err = xpcall(function()
  pcall(client.speedmode, 0)
  pcall(client.setsoundon, false)
  adv(20)
  w("load=" .. tostring(pcall(savestate.load, B .. "states/battle_usa_ready.State")))
  adv(80)

  -- 基线
  local x, y = memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)
  w(string.format("基线 cursor=(%d,%d) R15=0x%08X", x, y, emu.getregister("R15")))

  -- 调 FUN_08002e74(19,29,24,26) —— 求两点距离
  local r, okc = call_thumb(0x08002E74, { 19, 29, 24, 26 }, 40)
  w(string.format("调 FUN_08002E74(19,29,24,26) -> R0=%d  pcall=%s", r, tostring(okc)))

  -- 对照：同点距离应为 0
  local r2 = call_thumb(0x08002E74, { 19, 29, 19, 29 }, 40)
  w(string.format("调 FUN_08002E74(19,29,19,29) -> R0=%d", r2))

  -- 再对照：垂直距离
  local r3 = call_thumb(0x08002E74, { 19, 29, 19, 35 }, 40)
  w(string.format("调 FUN_08002E74(19,29,19,35) -> R0=%d", r3))

  -- 调完检查游戏还活着
  adv(10)
  w(string.format("调用后 R15=0x%08X CPSR=0x%08X 光标=(%d,%d)",
    emu.getregister("R15"), emu.getregister("CPSR"),
    memory.read_u8(0x030067FE), memory.read_u8(0x030067FF)))
  pcall(client.screenshot, B .. "shots/call_after.png")
end, function(e) w("ERROR: " .. tostring(e)) end)

w("ok=" .. tostring(ok) .. " err=" .. tostring(err))
if fh then fh:close() end
pcall(client.exit)
