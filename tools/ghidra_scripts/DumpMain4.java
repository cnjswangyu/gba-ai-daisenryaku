// DumpMain4.java —— 强制反汇编 crt0/IRQ处理者/上下文初始化，找 main 与调度链
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;

public class DumpMain4 extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;

    private void disasm(long from, int n, String title) throws Exception {
        out.println("\n/* ===== " + title + " @0x" + Long.toHexString(from) + " ==== */");
        Address a = toAddr(from);
        Listing lst = currentProgram.getListing();
        DisassembleCommand cmd = new DisassembleCommand(toAddr(from), null, true);
        if (!cmd.applyTo(currentProgram, monitor)) {
            out.println("  (反汇编失败: " + cmd.getStatusMsg() + ")");
            return;
        }
        a = toAddr(from);
        for (int i = 0; i < n; i++) {
            Instruction ins = lst.getInstructionAt(a);
            if (ins == null) { out.println("  -- stop --"); break; }
            out.println("  " + ins.getAddress() + ": " + ins);
            a = ins.getNext().getAddress();
        }
    }

    private void dumpFuncContaining(long addr, String title) throws Exception {
        Address a = toAddr(addr);
        Function f = null;
        // 找包含该地址的函数（可能未创建）
        f = getFunctionContaining(a);
        if (f == null) {
            // 往前找函数入口
            for (long back = 0; back < 0x200; back += 2) {
                Function g = getFunctionAt(toAddr(addr - back));
                if (g != null) { f = g; break; }
            }
        }
        out.println("\n/* ===== " + title + " (含 0x" + Long.toHexString(addr) + ") ==== */");
        if (f == null) { out.println("  (无函数)"); return; }
        out.println("  函数: " + f.getName() + " @" + f.getEntryPoint() + "  size=" + f.getBody().getNumAddresses());
        DecompileResults res = dec.decompileFunction(f, 120, monitor);
        if (res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
        else out.println("  (反编译失败)");
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/main4.c", "UTF-8");

        disasm(0x080000C0, 120, "crt0 (GBA入口)");
        disasm(0x08000180, 40, "IRQ尾部 trampoline");
        disasm(0x080003C0, 80, "上下文初始化 (含 0x02007060/0x03000480 字面量)");
        disasm(0x08000640, 60, "IRQ处理者 (写 vblank 标志 0x02007074)");
        disasm(0x080006A0, 40, "vblank等待 FUN_080006ac");

        dumpFuncContaining(0x080006A4, "IRQ处理者函数");
        dumpFuncContaining(0x080003D8, "上下文初始化函数");

        // 字面量池：0x08000600-0x08000790 每4字节
        out.println("\n/* ===== 字面量池 0x08000600-0x08000790 ==== */");
        for (long a = 0x08000600; a < 0x08000790; a += 4) {
            byte[] b = new byte[4];
            currentProgram.getMemory().getBytes(toAddr(a), b);
            int v = (b[0] & 0xFF) | ((b[1] & 0xFF) << 8) | ((b[2] & 0xFF) << 16) | ((b[3] & 0xFF) << 24);
            String tag = "";
            if (v == 0x02007060) tag = "  <== 上下文指针槽";
            if (v == 0x02007074) tag = "  <== vblank标志";
            if (v == 0x03000480) tag = "  <== 上下文基址";
            if (v == 0x04000000) tag = "  <== IO基址";
            out.println("  0x" + Long.toHexString(a) + ": 0x" + Integer.toHexString(v) + tag);
        }
        out.close();
        println("完成 main4.c");
    }
}
