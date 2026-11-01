import struct
rom = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba","rb").read()
def off(a): return a - 0x08000000
def rd32(a): return struct.unpack_from("<I", rom, off(a))[0]
base = 0x08000480
print("== state -> handler ==")
handlers = {}
for i in range(15):
    t = (rd32(base + i*4)) & ~1
    # thunk: ldr rX,[pc+..] typically; read 16 bytes and find pc-relative load
    words = struct.unpack_from("<HHHHHHHH", rom, off(t))
    h = None
    # find pattern: ldr rX, [pc, #imm] => bytes 48 xx .. then target = (t+4)&~2 + imm
    for k in range(4):
        w = words[k]
        if (w & 0xF800) == 0x4800:  # ldr rd,[pc,#imm8*4]
            imm = (w & 0xFF) * 4
            pc = (t + 4 + k*2) & ~2
            val = rd32(pc + imm)
            if 0x08000000 <= val < 0x09000000:
                h = val & ~1
                break
    handlers[i] = h
    print("state%-2d thunk 0x%08X -> handler 0x%08X" % (i, t, h if h else 0))
import json
json.dump({str(k): v for k, v in handlers.items()}, open(r"D:\prog\gba-ai\logs\handlers.json","w"))
