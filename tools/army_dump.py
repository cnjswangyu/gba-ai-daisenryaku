import struct
rom = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba","rb").read()
def off(a): return a - 0x08000000
def rd16(a): return struct.unpack_from("<H", rom, off(a))[0]
def rd32(a): return struct.unpack_from("<I", rom, off(a))[0]
def txt(a):
    if not (0x08000000 <= a < 0x0A000000): return None
    b = bytearray(); o = off(a)
    while len(b) < 40:
        c = rom[o]
        if c == 0: break
        b.append(c); o += 1
    try: return b.decode("gbk")
    except Exception: return b.decode("shift_jis","replace")

def name(uid):
    return txt(0x08798A98 + uid*0x5C)

SCEN = 0x08762B10
print("scenario name:", txt(rd32(SCEN)))
blue = rd32(SCEN + 0x10)
red  = rd32(SCEN + 0x30)
print("BLUE ptr = 0x%08X  RED ptr = 0x%08X" % (blue, red))

def dump_army(tag, base):
    print("\n== %s @0x%08X ==" % (tag, base))
    for i in range(0, 0x60, 4):
        v = rd32(base + i)
        extra = ""
        if 0x08000000 <= v < 0x0A000000:
            t = txt(v)
            if t: extra = " -> %r" % t
        print("  +0x%02X: 0x%08X%s" % (i, v, extra))
    # 尝试按单位表解析: u16 id + coords, stride 24? 或 0x18 记录
    print("  -- as u16 array --")
    vals = [rd16(base + i*2) for i in range(0x40)]
    print("  ", [hex(x) for x in vals[:32]])

dump_army("BLUE", blue)
dump_army("RED", red)
