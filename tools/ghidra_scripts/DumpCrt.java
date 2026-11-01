// DumpCrt.java —— 反汇编 crt0 找 main；解出 vblank 标志地址找 IRQ 处理者
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;
import java.util.*;

public class DumpCrt extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;

    private int rd32(long a) throws Exception {
        byte[] b = new byte[4];
        currentProgram.getMemory().getBytes(toAddr(a), b);
        return (b[0] & 0xFF) | ((b[1] & 0xFF) << 8) | ((b[2] & 0xFF) << 16) | ((b[3] & 0xFF) << 24);
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/crt.c", "UTF-8");

        // 1) 反汇编 crt0 入口 0x08000000 和 0x080000C0
        out.println("/* ===== 入口 0x08000000 ===== */");
        for (int i = 0; i < 6; i++) {
            Instruction ins = getInstructionAt(toAddr(0x08000000 + i * (i == 0 ? 2 : 2)));
            if (ins != null) out.println("  " + ins.getAddress() + ": " + ins);
        }
        out.println("\n/* ===== crt0 0x080000C0 起 60 条 ===== */");
        Address a = toAddr(0x080000C0);
        for (int i = 0; i < 60; i++) {
            Instruction ins = getInstructionAt(a);
            if (ins == null) ins = getInstructionAfter(a);
            if (ins == null) break;
            out.println("  " + ins.getAddress() + ": " + ins);
            a = ins.getNext().getAddress();
        }

        // 2) 解出 FUN_080006ac 等待的 vblank 标志地址（DAT_08000768）
        long lit = rd32(0x08000768);
        out.println("\n/* DAT_08000768 字面量 = 0x" + Long.toHexString(lit) + " (vblank 标志地址) */");
        long lit70 = rd32(0x08000770);
        long lit74 = rd32(0x08000774);
        long lit78 = rd32(0x08000778);
        out.println("DAT_08000770 = 0x" + Long.toHexString(lit70) + ", DAT_08000774 = 0x" + Long.toHexString(lit74)
                    + ", DAT_08000778 = 0x" + Long.toHexString(lit78));

        // 3) 找谁写这个标志（IRQ 处理者）—— 用引用管理器
        out.println("\n/* ===== 引用 vblank 标志 " + Long.toHexString(lit) + " 的指令 ===== */");
        for (Reference ref : currentProgram.getReferenceManager().getReferencesTo(toAddr(lit))) {
            Function f = getFunctionContaining(ref.getFromAddress());
            out.println("  " + ref.getFromAddress() + "  in " + (f != null ? f.getName() + "@" + f.getEntryPoint() : "?"));
        }
        out.close();
        println("完成 crt.c");
    }
}
