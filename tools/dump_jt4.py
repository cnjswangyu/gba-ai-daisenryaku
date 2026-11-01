import struct
rom = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba","rb").read()
def off(a): return a - 0x08000000
def rd16(a): return struct.unpack_from("<H", rom, off(a))[0]
def bl_target(h1_addr):
    h1 = rd16(h1_addr); h2 = rd16(h1_addr + 2)
    if (h1 & 0xF800) != 0xF000 or (h2 & 0xF800) != 0xF800:
        return None
    imm10 = h1 & 0x3FF
    j1 = (h2 >> 11) & 1; j2 = (h2 >> 12) & 1
    imm11 = h2 & 0x7FF
    i1 = 1 - j1; i2 = 1 - j2
    off25 = (i1 << 24) | (i2 << 23) | (imm10 << 12) | (imm11 << 1)
    if off25 & (1 << 24):
        off25 -= (1 << 25)
    return (h1_addr + 4 + off25) & ~1
base = 0x08000480
print("== state -> handler ==")
res = {}
for i in range(15):
    t = (struct.unpack_from("<I", rom, off(base + i*4))[0]) & ~1
    # thunk body: find first BL
    h = None
    for k in range(4):
        h = bl_target(t + k*2)
        if h: break
    res[i] = h
    print("state%-2d @0x%08X -> 0x%08X" % (i, t, h))
import json
json.dump(res, open(r"D:\prog\gba-ai\logs\handlers.json","w"))
