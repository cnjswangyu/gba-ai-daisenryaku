import struct

rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()

def dump(lo, hi, label=''):
    print(f'=== ROM 0x{lo:08X}-0x{hi:08X} {label} ===')
    for a in range(lo, hi, 4):
        v = struct.unpack_from('<I', rom, a - 0x08000000)[0]
        tag = ''
        if 0x02000000 <= v < 0x02040000:
            tag = ' [EWRAM]'
        elif 0x03000000 <= v < 0x03008000:
            tag = ' [IWRAM]'
        elif 0x08000000 <= v < 0x0A000000:
            tag = ' [ROM]'
        sv = v if v < 0x80000000 else v - 0x100000000
        if -0x10000 < sv < 0:
            tag = f' [ctx{sv:+d}]'
        print(f'  0x{a:08X}: {v:08X}{tag}')

# func_08009f08 头部字面量池 (0x08009F3C-0x08009FA0)
dump(0x08009F3C, 0x08009FA0, 'func_08009f08 头池')
print()
# A 键分支附近池 (0x0800A140-0x0800A210)
dump(0x0800A140, 0x0800A210, 'A键分支池')
print()
# B 键分支池 (0x0800A4F0-0x0800A5C0)
dump(0x0800A4F0, 0x0800A5C0, 'B键分支池')
