import struct
rom = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba","rb").read()
def off(a): return a - 0x08000000
def rd16(a): return struct.unpack_from("<H", rom, off(a))[0]
def rd32(a): return struct.unpack_from("<I", rom, off(a))[0]

CAT_BASE = 0x087985DC
CAT_N    = 93
STRIDE   = 0xBA
UNIT_DB  = 0x08798A98
ES       = 0x5C
COUNTRIES = ["美国","俄罗斯","日本","德国","法国","英国","中国"]

def name(uid):
    ptr = rd32(UNIT_DB + uid*ES)
    if not (0x08000000 <= ptr < 0x0A000000): return "?ptr"
    b = bytearray(); a = off(ptr)
    while len(b) < 24:
        c = rom[a]
        if c == 0: break
        b.append(c); a += 1
    return b.decode("gbk", "replace")

def cls_of(kind_lo):
    if kind_lo < 8: return 2
    if kind_lo < 0x13: return 1
    return 3

out = []
for ci, cname in enumerate(COUNTRIES):
    base = CAT_BASE + ci*STRIDE
    ids = [rd16(base + i*2) for i in range(CAT_N)]
    out.append("\n===== %s (idx=%d) =====" % (cname, ci))
    for i, uid in enumerate(ids):
        if uid == 0: continue
        e = UNIT_DB + uid*ES
        klo = rom[off(e)+6]
        c = cls_of(klo)
        out.append(" [%2d] id=0x%03X klo=%-3d cls=%d 价%-5d %s" % (i, uid, klo, c, rd16(e+0x1A), name(uid)))
txt = "\n".join(out)
open(r"D:\prog/gba-ai/logs/catalog2.txt","w",encoding="utf-8").write(txt)
print(txt)
