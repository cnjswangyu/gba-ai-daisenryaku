--[[
  把 BG 层还原成「文本」而不是「图像」：
  - 读 BGxCNT 得到 char base / map base / 色深
  - 读 tilemap 得到屏幕网格
  - 把每个唯一 tile 渲染成 8x8 的 #/. 字符画
  输出到 logs/tiles.txt，纯文本，模型可以直接"读"字。
]]

local BASE = "D:/prog/gba-ai/"
local OUT  = BASE .. "logs/tiles.txt"

local lines = {}
local function w(s) lines[#lines + 1] = s end
local function hex(v, n) return string.format("%0" .. (n or 2) .. "X", v or 0) end

client.speedmode(0)
pcall(client.setsoundon, false)

-- 停在标题画面（此时画面稳定、内容最丰富），方便对照
for _ = 1, 120 do emu.frameadvance() end
pcall(client.screenshot, BASE .. "shots/title.png")

local function bit(v, i) return math.floor(v / 2 ^ i) % 2 end

-- ---------- 解析 BGxCNT ----------
local BGCNT = { [0] = 0x04000008, [1] = 0x0400000A, [2] = 0x0400000C, [3] = 0x0400000E }
local DISPCNT = memory.read_u16_le(0x04000000)
w(string.format("DISPCNT=0x%04X  frame=%d", DISPCNT, emu.framecount()))
local bg = {}
for i = 0, 3 do
  local cnt = memory.read_u16_le(BGCNT[i])
  bg[i] = {
    prio      = cnt % 4,
    charBase  = 0x06000000 + (math.floor(cnt / 4) % 4) * 0x4000,
    colors8   = bit(cnt, 7) == 1,
    mapBase   = 0x06000000 + (math.floor(cnt / 256) % 32) * 0x800,
    enabled   = bit(DISPCNT, 8 + i) == 1,
  }
  w(string.format("BG%d  en=%s  char=0x%08X  map=0x%08X  %s  cnt=0x%04X",
    i, tostring(bg[i].enabled), bg[i].charBase, bg[i].mapBase,
    bg[i].colors8 and "8bpp" or "4bpp", cnt))
end

-- ---------- 把某个 BG 的屏幕内容写成 tile 网格 + 唯一图案字典 ----------
local function dump_bg(idx)
  local b = bg[idx]
  if not b.enabled then return end

  w("")
  w(string.format("===== BG%d  tilemap（30x20，值=tile编号）=====", idx))
  local mapSeen, uniq = {}, {}
  local grid = {}
  for ty = 0, 19 do
    local row = {}
    for tx = 0, 29 do
      local e = memory.read_u16_le(b.mapBase + (ty * 32 + tx) * 2)
      local tile = e % 1024            -- 8bpp 用全 10 位；4bpp 也是 10 位
      row[#row + 1] = string.format("%4d", tile)
      if not mapSeen[tile] then
        mapSeen[tile] = true
        uniq[#uniq + 1] = tile
      end
    end
    grid[#grid + 1] = "  " .. table.concat(row, "")
  end
  for _, g in ipairs(grid) do w(g) end

  w("")
  w(string.format("===== BG%d 唯一 tile 图案：%d 种 =====", idx, #uniq))
  table.sort(uniq)

  local bpp = b.colors8 and 8 or 4
  local bytesPerTile = b.colors8 and 64 or 32   -- 8x8 像素：8bpp=64B，4bpp=32B
  for _, t in ipairs(uniq) do
    local addr = b.charBase + t * bytesPerTile
    local ok, data = pcall(memory.readbyterange, addr, bytesPerTile)
    if ok and data then
      w(string.format("tile %d:", t))
      for y = 0, 7 do
        local s = {}
        for x = 0, 7 do
          local px
          if bpp == 8 then
            px = data[y * 8 + x] or 0
          else
            local byte = data[y * 4 + math.floor(x / 2)] or 0
            px = (x % 2 == 0) and (byte % 16) or math.floor(byte / 16)
          end
          s[#s + 1] = (px ~= 0) and "#" or "."
        end
        w("  " .. table.concat(s))
      end
    end
  end
end

for i = 0, 3 do dump_bg(i) end

local text = table.concat(lines, "\n") .. "\n"
local okw = pcall(function()
  local f = io.open(OUT, "w")
  if not f then error("io.open failed") end
  f:write(text)
  f:close()
end)
if not okw then pcall(comm.mmfWrite, "tiles.txt", text) end

client.pause()
