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
print("scenario @0x%08X" % SCEN)
print("name ptr ->", txt(rd32(SCEN)))
for i in range(0, 0x80, 4):
    v = rd32(SCEN + i)
    note = ""
    if 0x08000000 <= v < 0x0A000000:
        t = txt(v)
        if t: note = " -> %r" % t
    print("  +0x%02X: 0x%08X (%d)%s" % (i, v, v & 0xffff if v < 0x10000 else v, note))

# 找剧本列表: 往前扫描指回 0x08762B10 的指针
print("\n== refs to scenario ==")
for a in range(0x08000000, 0x08800000, 4):
    if rd32(a) == SCEN:
        print("  0x%08X -> scenario" % a)
