import struct

# s95 战场快照: 看 0x03002BE0 附近的真实布局
d = open('D:/prog/gba-ai/logs/boot_snaps/s95_iwram.bin', 'rb').read()

def hd(addr, n, label=''):
    print(f'--- {label} 0x{addr:08X} ---')
    for i in range(0, n, 12):
        row = d[addr - 0x03000000 + i: addr - 0x03000000 + i + 12]
        print(f'  0x{addr + i:08X}: ' + ' '.join(f'{b:02X}' for b in row))

hd(0x03002BD0, 120, '单位表区(疑 stride12/24)')
print()
# ctx+0x2760 = 0x03002BE0; player1 区 = +0x600
hd(0x030031D0, 60, 'player1 部署数组? (ctx+0x2760+0x600)')
print()
# ctx+0x2D60 = 0x030031E0 (另一个数组)
hd(0x030031E0, 48, 'ctx+0x2D60 区')
