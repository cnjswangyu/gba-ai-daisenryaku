#!/usr/bin/env python3
"""解 Thumb 函数体内所有 ldr rX,[pc,#imm] 字面量 -> 常量表
用于把反编译里的 _DAT_0800xxxx 坐成真实地址"""
import struct, sys

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()

def hw(a):
    off = a - 0x08000000
    return ROM[off] | (ROM[off+1] << 8)

def word(a):
    off = a - 0x08000000
    return struct.unpack_from("<I", ROM, off)[0]

def resolve(lo, hi, label):
    print(f"=== {label}: 0x{lo:08X}-0x{hi:08X} 字面量解析 ===")
    a = lo
    seen = {}
    while a < hi:
        h1 = hw(a)
        # ldr rT,[pc,#imm8]: 0100 1ttt imm8  (16-bit)
        if (h1 & 0xF800) == 0x4800:
            rt = (h1 >> 8) & 7
            imm8 = (h1 & 0xFF) * 4
            base = (a + 4) & ~3
            val = word(base + imm8)
            key = (a, rt)
            if key not in seen:
                seen[key] = val
                print(f"  0x{a:08X}: ldr r{rt},[pc,#0x{imm8:X}] -> 0x{val:08X}")
            a += 2
            continue
        a += 2
    print()

if __name__ == "__main__":
    ranges = [
        (0x080099B8, 0x0800A1A0, "state6 handler FUN_080099B8"),
        (0x08007364, 0x080075C0, "state4 handler FUN_08007364"),
    ]
    for lo, hi, lab in ranges:
        resolve(lo, hi, lab)
