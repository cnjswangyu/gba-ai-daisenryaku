local B="D:/prog/gba-ai/"
local CTX=0x03000480
local f=io.open(B.."logs/verify_replay.txt","w")
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
local function v(tag) w(string.format("%-14s 0x0300756F=%d  0x0300756E=%d  0x03007570=%d", tag,
  memory.read_u8(0x0300756F), memory.read_u8(0x0300756E), memory.read_u8(0x03007570))) end

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
v("战场初始")
hold("Start",4,55); hold("Right",5,22); hold("Down",5,22); hold("A",4,80)
for _=1,40 do emu.frameadvance() end
v("进设置")
hold("Down",5,18); hold("Down",5,20)
v("选中リプレイ")
hold("Left",5,30); v("LEFT(->OFF)")
hold("Right",5,30); v("RIGHT(->ON)")
hold("Left",5,30); v("LEFT(->OFF)")
f:close()
pcall(client.exit)
