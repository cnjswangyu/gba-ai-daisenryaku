local B="D:/prog/gba-ai/"
local CTX,U,STRIDE=0x03000480,0x03002BE2,24
local f=io.open(B.."logs/test_noreplay.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
local MAIL,ROML=0x03007F00,0x080015F4
local KEYBIT={A=0x1,B=0x2,Select=0x4,Start=0x8,Right=0x10,Left=0x20,Up=0x40,Down=0x80}
local mailOK=false
local function hold(k,fr,g)
  if mailOK then
    memory.write_u16_le(MAIL,0x3FF-(KEYBIT[k] or 0))
    for _=1,(fr or 5) do emu.frameadvance() end
    memory.write_u16_le(MAIL,0x3FF)
  else
    for _=1,(fr or 13) do joypad.set({[k]=true}); emu.frameadvance() end
    joypad.set({})
  end
  for _=1,(g or 8) do emu.frameadvance() end
end
local function patch_mail()
  local hits={}
  for a=0x03000000,0x03007FFC,4 do if memory.read_u32_le(a)==0x04000130 then hits[#hits+1]=a end end
  local rv=memory.read_u32_le(ROML)
  for _,a in ipairs(hits) do memory.write_u32_le(a,MAIL) end
  if rv==0x04000130 then memory.write_u32_le(ROML,MAIL) end
  memory.write_u16_le(MAIL,0x3FF); mailOK=true
end
local function cur() return memory.read_u8(CTX+0x637E),memory.read_u8(CTX+0x637F) end
local function shot(n) pcall(client.screenshot,B.."shots/nr_"..n..".png") end
local function ga(x,y) return CTX+0x3F60+x*4+y*0xC0 end
local function uxy(k) return memory.read_u8(U+k*STRIDE),memory.read_u8(U+k*STRIDE+1) end
local function ehp(k) return memory.read_u8(0x03002BE0+0x600+k*24+6) end
local function tp(k,tx,ty)
  local ox,oy=uxy(k)
  local g1=ga(ox,oy); memory.write_u8(g1,0); memory.write_u8(g1+1,0)
  local g2=ga(tx,ty); memory.write_u8(g2,1); memory.write_u8(g2+1,k+1)
  memory.write_u8(U+k*STRIDE,tx); memory.write_u8(U+k*STRIDE+1,ty)
  memory.write_u8(CTX+0x637E,tx); memory.write_u8(CTX+0x637F,ty)
  memory.write_u8(CTX+0x990,k)
  for _=1,4 do emu.frameadvance() end
end

pcall(client.speedmode,0)
for _=1,20 do emu.frameadvance() end
pcall(savestate.load, B.."states/battle_usa_ready.State")
for _=1,60 do emu.frameadvance() end
for i=1,10 do
  local x0,y0=cur(); hold("Right",13,8)
  local x1,y1=cur()
  if x0~=x1 or y0~=y1 then hold("Left",13,8); break end
  hold("A",4,35)
end
patch_mail()

-- ★ 关闭演出
memory.write_u8(0x0300756F, 0)
w(string.format("已写 0x0300756F=0（关闭リプレイ），读回=%d", memory.read_u8(0x0300756F)))

w(string.format("E0 HP 初始=%d", ehp(0)))
local f0=emu.framecount()
tp(0,18,29)
w(string.format("瞬移后 cursor=(%d,%d) 帧=%d", memory.read_u8(CTX+0x637E), memory.read_u8(CTX+0x637F), emu.framecount()))
shot("00_ready")

hold("A",4,38); shot("01_menu")
hold("Down",5,28); shot("02_sel")
hold("A",4,38); shot("03_aim")
hold("Left",5,25); shot("04_target")
hold("A",4,42); shot("05_conf")
local f1=emu.framecount()
hold("A",4,48); shot("06_confirm")
for _=1,120 do emu.frameadvance() end
local f2=emu.framecount()
w(string.format("确认后 120 帧: E0 HP=%d  耗时=%d 帧", ehp(0), f2-f0))
shot("07_after")
f:close()
pcall(client.exit)
