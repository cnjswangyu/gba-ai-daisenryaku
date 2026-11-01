#!/usr/bin/env python3
"""1. 解出 15 个界面 handler 桩的 bl 目标
2. 从 95 个快照抽 ctx(0x03000480) 的 state/substate 字节序列 → 界面映射
"""
import struct, os

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()

def hw(a):
    off = a - 0x08000000
    return ROM[off] | (ROM[off+1] << 8)

def bl_target(addr):
    """解 Thumb bl (F0xx Fxxx) at addr"""
    h1, h2 = hw(addr), hw(addr + 2)
    if (h1 & 0xF800) != 0xF000 or (h2 & 0xF800) != 0xF800:
        return None
    S = (h1 >> 10) & 1
    imm10 = h1 & 0x3FF
    J1 = (h2 >> 13) & 1
    J2 = (h2 >> 11) & 1
    imm11 = h2 & 0x7FF
    I1 = 1 - J1
    I2 = 1 - J2
    off = (S << 24) | (I1 << 23) | (I2 << 22) | (imm10 << 12) | (imm11 << 1)
    if S: off -= (1 << 25)
    return (addr + 4) + off

# 桩表: state -> 桩地址 (来自跳转表 0x08000480)
tbl = 0x08000480
print("=== 15 个界面 handler 桩解码 ===")
stub_map = {}
for i in range(15):
    stub = struct.unpack_from("<I", ROM, tbl + i*4 - 0x08000000)[0]
    stub_map[i] = stub
    # 桩: [bl h1][(bl h2)][b tail]
    t1 = bl_target(stub)
    if t1 is None:
        # 桩可能先有 movs 指令（如 state6: 2000 2100），在 10 字节内找第一个 bl
        for k in range(0, 10, 2):
            t1 = bl_target(stub + k)
            if t1: break
    extra = ""
    hw3, hw4 = hw(stub+4), hw(stub+6)
    t2 = bl_target(stub + 4) if (hw3 & 0xF800) == 0xF000 else None
    print(f"  state {i:2d}: stub@0x{stub:08X} -> bl 0x{t1:08X}" + (f" ; bl 0x{t2:08X}" if t2 else ""))

# ctx 状态序列
SNAP = r"D:\prog\gba-ai\logs\boot_snaps"
tags = sorted((f.split("_")[0] for f in os.listdir(SNAP) if f.endswith("_iwram.bin")), key=lambda t: int(t[1:]))
print("\n=== ctx(0x03000480) 状态序列: tag | +0(u32) | +0u8 +1u8 +2u8 +3u8 | +8(u32) | +0xC | +0xE | +0x1C ===")
for t in tags:
    d = open(os.path.join(SNAP, f"{t}_iwram.bin"), "rb").read()
    o = 0x480
    if len(d) < o + 0x20:
        print(f"  {t}: (快照过短 {len(d)}B, 跳过)")
        continue
    s0 = int.from_bytes(d[o:o+4], "little")
    b = d[o:o+4]
    s8 = int.from_bytes(d[o+8:o+12], "little")
    kc = int.from_bytes(d[o+0xC:o+0xE], "little")
    ke = int.from_bytes(d[o+0xE:o+0x10], "little")
    p1c = int.from_bytes(d[o+0x1C:o+0x20], "little")
    print(f"  {t}: +0=0x{s0:08X} [{b[0]:02X} {b[1]:02X} {b[2]:02X} {b[3]:02X}] +8=0x{s8:08X} keys=0x{kc:04X}/0x{ke:04X} +1C=0x{p1c:08X}")
