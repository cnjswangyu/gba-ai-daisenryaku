import struct, sys
rom = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba","rb").read()
def off(a): return a - 0x08000000
base = 0x08000480
print("== main jump table @0x%08X ==" % base)
for i in range(15):
    a = base + i*4
    v = struct.unpack_from("<I", rom, off(a))[0]
    tgt = v & ~1
    print("state%-2d -> 0x%08X   (raw 0x%08X)" % (i, tgt, v))
