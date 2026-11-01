#!/usr/bin/env python3
"""扫 ROM 里的关键地址字面量，定位：
1. 0x02007060 (指向界面上下文 0x03000480 的全局指针) —— 状态机代码
2. 0x03000480 / 0x03000488 —— 状态变量直接引用
3. 0x03007F00 —— 邮箱输入源(我们patch过的)
输出 ROM 偏移 + 对应地址，供 Ghidra 反编译
"""
import struct

ROM = open(r"D:\prog\gba-ai\roms\0219 - Daisenryaku.gba", "rb").read()
BASE = 0x08000000

def find_all(needle: int, label: str):
    b = struct.pack("<I", needle)
    hits = []
    off = 0
    while True:
        i = ROM.find(b, off)
        if i < 0: break
        # 过滤明显是数据的(文件头/压缩区) 后面统一看
        hits.append(BASE + i)
        off = i + 1
    print(f"{label} 0x{needle:08X}: {len(hits)} 处")
    for a in hits:
        print(f"   0x{a:08X} (file 0x{a-BASE:06X})")
    return hits

find_all(0x02007060, "上下文指针槽")
find_all(0x03000480, "上下文基址")
find_all(0x03000488, "子状态")
find_all(0x0300048C, "新按键")
find_all(0x03007F00, "邮箱输入源")
find_all(0x02007074, "vblank标志")
