import struct
rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()
BASE = 0x08000000
TBL = 0x08798A98
ST = 0x5C

def txt(a):
    off = a - BASE
    if not (BASE <= a < 0x0D000000):
        return None
    end = rom.find(b'\x00', off)
    return rom[off:end].decode('shift_jis', 'replace')

# 战场记录原始字节（来自 logs/cmp_battle.txt，基址 0x03002BE0 + i*24）
BATTLE = {
    187: "BB 00 15 1E 32 00 10 00 04 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    241: "F1 00 14 1C 28 00 08 00 04 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    208: "D0 00 14 20 2D 00 08 00 02 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    339: "53 01 16 20 32 00 04 00 28 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    290: "22 01 13 1D 37 00 08 00 01 04 01 00 00 00 00 00 00 00 00 00 00 00 00 00",
    200: "C8 00 15 1E 2D 00 08 00 05 05 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    239: "EF 00 16 1D 28 00 04 00 06 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    305: "31 01 15 1F 28 00 18 00 04 02 02 00 00 00 00 00 00 00 00 00 00 00 00 00",
    344: "58 01 14 1C 32 00 04 00 28 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
}

print("ROM 兵种记录（0x08798A98 + id*0x5C） vs 战场记录（0x03002BE0 + i*24）")
print("=" * 100)
for uid in sorted(BATTLE):
    off = TBL + uid * ST - BASE
    r = rom[off:off + ST]
    nm = txt(struct.unpack_from('<I', r, 0)[0])
    b = bytes(int(x, 16) for x in BATTLE[uid].split())
    print(f"ID {uid:3d} {str(nm)[:20]}")
    print(f"   ROM: name@{struct.unpack_from('<I', r, 0)[0]:08X} "
          f"大类={r[4]} 移动={r[5]} 细={r[6]} "
          f"+0xC={r[0xC]:3d} +0xD速度={r[0xD]:3d} +0xE耐久={r[0xE]:3d} "
          f"+0xF={r[0xF]:3d} +0x10={r[0x10]:3d} +0x11={r[0x11]:3d}")
    print(f"        攻击5列 +0x14..18 = {list(r[0x14:0x19])}  "
          f"+0x19..0x24 = {list(r[0x19:0x25])}")
    print(f"        +0x25 = {r[0x25]:3d}  +0x26..27 = {struct.unpack_from('<H', r, 0x26)[0]:5d}  "
          f"+0x28..2B = {struct.unpack_from('<I', r, 0x28)[0]}")
    print(f"   BAT: id={struct.unpack_from('<H', b, 0)[0]:3d} x={b[2]:3d} y={b[3]:3d} "
          f"+4={b[4]:3d} +5={b[5]:3d} +6={b[6]:3d} +7={b[7]:3d} +8={b[8]:3d} +9={b[9]:3d} "
          f"+10={b[10]:3d} +11={b[11]:3d} +12={b[12]:3d} +13={b[13]:3d}")
    print()
