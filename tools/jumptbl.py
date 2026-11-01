import struct

rom = open('D:/prog/gba-ai/roms/0219 - Daisenryaku.gba', 'rb').read()

print('=== state2 跳转表 @0x080051A0 (5 项) ===')
for i in range(5):
    v = struct.unpack_from('<I', rom, 0x080051A0 - 0x08000000 + i * 4)[0]
    t = 'Thumb' if v & 1 else 'ARM'
    print(f'  substep {i}: 0x{v:08X} ({t})')

# 主跳转表 0x08000480 15 项的 thunk 目标
print('\n=== 主跳转表 15 项 (thunk 目标) ===')
thunks = {0x080004BC, 0x080004C4, 0x080004CC, 0x080004D4, 0x080004DC,
          0x080004E4, 0x080004EC, 0x080004F4, 0x080004FC, 0x08000504,
          0x0800050C, 0x08000514, 0x08000518}
for i in range(15):
    v = struct.unpack_from('<I', rom, 0x08000480 - 0x08000000 + i * 4)[0]
    print(f'  state {i:2d}: thunk 0x{v:08X}')
