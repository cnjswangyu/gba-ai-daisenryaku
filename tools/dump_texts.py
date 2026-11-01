import struct
rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()
def txt(a, maxlen=64):
    off = a - 0x08000000
    if not (0 <= off < len(rom)):
        return None
    end = rom.find(b'\x00', off)
    s = rom[off:end]
    try:
        return s[:maxlen].decode('shift_jis', 'replace')
    except Exception:
        return repr(s[:maxlen])
for a in [0x08046308, 0x08046320, 0x08046328, 0x08046334, 0x08046364, 0x08046384,
          0x08046398, 0x080463B0, 0x080463D0, 0x080463E4, 0x080463F8,
          0x0804640C, 0x08046424, 0x0804643C, 0x08046454, 0x08046478, 0x08046488,
          0x08046494, 0x080464B0, 0x0804655C, 0x0804657C, 0x08046584, 0x080465A4,
          0x080465C8, 0x080465F0, 0x08046604]:
    t = txt(a)
    print(f'0x{a:08X}: {t!r}')
