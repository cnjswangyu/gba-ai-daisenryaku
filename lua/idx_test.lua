-- 校准 readbyterange 的索引基准：ROM 头 0x080000A0 起是 "DAISENRYAKU"
local BASE = "D:/prog/gba-ai/"
local OUT = BASE .. "logs/idx_test.txt"
local lines = {}
local function w(s) lines[#lines + 1] = s end

local ok, b = pcall(memory.readbyterange, 0x080000A0, 16)
w("readbyterange ok=" .. tostring(ok) .. " type=" .. type(b))
if ok and b then
  for i = 0, 17 do
    w(string.format("  [%d] = %s", i, tostring(b[i])))
  end
  -- 猜测：若 [0]=0x44(D) 则 0 基；若 [1]=0x44 则 1 基
  local ascii = {}
  for i = 0, 11 do
    local v = b[i]
    if type(v) == "number" then ascii[#ascii + 1] = string.char(v) end
  end
  w("0-based 拼出来: " .. table.concat(ascii))
  ascii = {}
  for i = 1, 12 do
    local v = b[i]
    if type(v) == "number" then ascii[#ascii + 1] = string.char(v) end
  end
  w("1-based 拼出来: " .. table.concat(ascii))
end

local f = io.open(OUT, "w"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
pcall(client.exit)
