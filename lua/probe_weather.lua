-- 探路：看「地图资料」/「全体部队」界面里有没有天气显示；并抓剧本数据里的每回合数组
local B="D:/prog/gba-ai/"
local CTX=0x03000480
local f=io.open(B.."logs/probe_weather.txt","w")
local function w(s) f:write(s.."\n"); f:flush() end
local function adv(n) for _=1,(n or 1) do emu.frameadvance() end end
local function cur() return memory.read_u8(CTX+0x637E),memory.read_u8(CTX+0x637F) end
local function shot(n) pcall(client.screenshot,B.."shots/wt_"..n..".png") end
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

w(">>> START -> 地图资料（左列第4项）")
hold("Start",4,55)
hold("Down",5,14); hold("Down",5,14); hold("Down",5,18)
shot("00_mapinfo_sel")
hold("A",4,80); shot("01_mapinfo")
adv(60); shot("02_mapinfo2")
hold("B",4,40)
w(">>> 全体部队（左列第3项）")
hold("Start",4,55)
hold("Down",5,14); hold("Down",5,18)
hold("A",4,80); shot("03_allunits")
adv(60); shot("04_allunits2")
f:close()
pcall(client.exit)
