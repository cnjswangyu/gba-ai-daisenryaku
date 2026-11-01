import struct
rom = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba","rb").read()
def off(a): return a - 0x08000000
def rd16(a): return struct.unpack_from("<H", rom, off(a))[0]
def rd32(a): return struct.unpack_from("<I", rom, off(a))[0]

CAT_BASE = 0x087985DC
CAT_N    = 93
STRIDE   = 0xBA
UNIT_DB  = 0x08798A98   # entry = id*0x5C (id 1-based)
ES       = 0x5C

COUNTRIES = ["美国","俄罗斯","日本","德国","法国","英国","中国"]

def unit_name(uid):
    if uid == 0: return "(空)"
    ptr = rd32(UNIT_DB + uid*ES)
    if not (0x08000000 <= ptr < 0x0A000000): return "?ptr"
    # read shift-jis-ish ascii until 0
    b = bytearray()
    a = off(ptr)
    while len(b) < 24:
        c = rom[a]
        if c == 0: break
        b.append(c); a += 1
    try:
        s = b.decode("gbk", "replace")
    except Exception:
        s = b.decode("gbk", "replace")
    return s

def unit_info(uid):
    e = UNIT_DB + uid*ES
    return dict(name=unit_name(uid), price=rd16(e+0x1A), kind=rd16(e+0x06),
                y1=rd16(e+0x10), y2=rd16(e+0x12), b7=rom[off(e)+7])

def cls(kind):
    if kind < 8: return "陆2"
    if kind < 19: return "陆1"
    return "空3"

# category tab codes at 0x080461AB (3 bytes)
cat_codes = rom[off(0x080461AB):off(0x080461AB)+3]
print("tab category codes @0x080461AB:", list(cat_codes))

out = []
out.append("== 商品目录（catalog @0x%08X, %d entries/country, stride 0x%X）==" % (CAT_BASE, CAT_N, STRIDE))
for ci, cname in enumerate(COUNTRIES):
    base = CAT_BASE + ci*STRIDE
    ids = [rd16(base + i*2) for i in range(CAT_N)]
    nz = sum(1 for x in ids if x != 0)
    out.append("\n-- %s (idx=%d) @0x%08X : %d/%d 非零" % (cname, ci, base, nz, CAT_N))
    for i, uid in enumerate(ids):
        if uid == 0: continue
        info = unit_info(uid)
        out.append("   [%2d] id=0x%03X %-14s 价%-5d %s y=%d/%d b7=%d" % (
            i, uid, info["name"], info["price"], cls(info["kind"]), info["y1"], info["y2"], info["b7"]))

txt = "\n".join(out)
open(r"D:\prog\gba-ai\logs\catalog.txt","w",encoding="utf-8").write(txt)
print(txt[:3000])
