import struct
rom = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba","rb").read()
def off(a): return a - 0x08000000
def rd32(a): return struct.unpack_from("<I", rom, off(a))[0]
base = 0x08000480
print("== thunk raw bytes ==")
for i in range(15):
    t = (rd32(base + i*4)) & ~1
    b = rom[off(t):off(t)+10]
    print("state%-2d @0x%08X: %s" % (i, t, b.hex(" ")))
