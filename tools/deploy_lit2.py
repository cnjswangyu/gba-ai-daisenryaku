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
        elif 0x08000000 <= v < 0x0D000000:
            tag = ' [ROM]'
        sv = v if v < 0x80000000 else v - 0x100000000
        if 0 < sv < 0x10000:
            tag = f' [ctx+0x{sv:X}]'
        print(f'  0x{a:08X}: {v:08X}{tag}')

# func_08009f08 尾部池 (auto-deploy 相关: 0x0800A760-0x0800A9A0)
dump(0x0800A760, 0x0800A7A0, 'a77c/a780/a784 区')
print()
dump(0x0800A960, 0x0800A9A0, 'a964/a970/a974 区')
print()
dump(0x0800A9E0, 0x0800AA00, 'a9ec/a9f0 区')
