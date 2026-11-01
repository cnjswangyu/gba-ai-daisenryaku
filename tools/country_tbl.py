import struct
rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()

def txt(a):
    off = a - 0x08000000
    if not (0x08000000 <= a < 0x0A000000):
        return None
    end = rom.find(b'\x00', off)
    s = rom[off:end].decode('shift_jis', 'replace')
    return s if len(s) < 40 else s[:37] + '...'

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
        print(f'  0x{a:08X}: {v:08X}{tag}')

# func_08030a14 的字面量池尾部 (0x08030F30-0x08030F68)
dump(0x08030F30, 0x08030F68, '国家选择池')

# _DAT_08030f58 应该是 6 国指针表地址
pool = 0x08030F58
tbl = struct.unpack_from('<I', rom, pool - 0x08000000)[0]
print(f'\n_DAT_08030f58 -> 国家表 @ 0x{tbl:08X}')
if 0x08000000 <= tbl < 0x0A000000:
    print('=== 6 国指针表内容 ===')
    for i in range(6):
        p = struct.unpack_from('<I', rom, tbl - 0x08000000 + i * 4)[0]
        print(f'  国[{i}]: ptr=0x{p:08X} -> {txt(p)!r}')
        # 打印指针目标的前 32 字节，可能是结构体
        if 0x08000000 <= p < 0x0A000000:
            raw = rom[p - 0x08000000:p - 0x08000000 + 32]
            print(f'        数据: ' + ' '.join(f'{b:02X}' for b in raw))
