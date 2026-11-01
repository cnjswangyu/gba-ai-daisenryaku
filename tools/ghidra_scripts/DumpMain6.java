// DumpMain6.java —— main(0x08000228) / vblank等待(0x080006AC) / 按键采集候选(0x0802F03C) / (0x08032790)
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import java.io.PrintWriter;

public class DumpMain6 extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;

    private void disasm(long from, int n, String title) throws Exception {
        out.println("\n/* ===== " + title + " @0x" + Long.toHexString(from) + " ==== */");
        DisassembleCommand cmd = new DisassembleCommand(toAddr(from), null, true);
        if (!cmd.applyTo(currentProgram, monitor)) {
            out.println("  (反汇编失败: " + cmd.getStatusMsg() + ")");
            return;
        }
        Address a = toAddr(from);
        Listing lst = currentProgram.getListing();
        for (int i = 0; i < n; i++) {
            Instruction ins = lst.getInstructionAt(a);
            if (ins == null) { out.println("  -- stop --"); break; }
            out.println("  " + ins.getAddress() + ": " + ins);
            a = ins.getNext().getAddress();
        }
    }

    private void decompile(long from, String title) throws Exception {
        out.println("\n/* ===== 反编译 " + title + " @0x" + Long.toHexString(from) + " ==== */");
        Function f = getFunctionAt(toAddr(from));
        if (f == null) {
            DisassembleCommand cmd = new DisassembleCommand(toAddr(from), null, true);
            cmd.applyTo(currentProgram, monitor);
            f = getFunctionAt(toAddr(from));
            if (f == null) f = createFunction(toAddr(from), "FUN_" + Long.toHexString(from));
        }
        if (f == null) { out.println("  (无法定位函数)"); return; }
        out.println("  函数: " + f.getName() + " @" + f.getEntryPoint() + " size=" + f.getBody().getNumAddresses());
        DecompileResults res = dec.decompileFunction(f, 200, monitor);
        if (res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
        else out.println("  (反编译失败)");
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/main6.c", "UTF-8");

        disasm(0x08000228, 300, "main (0x08000229 Thumb)");
        decompile(0x08000228, "main");
        disasm(0x080006AC, 80, "vblank等待 FUN_080006AC");
        decompile(0x080006AC, "vblank等待 FUN_080006AC");
        disasm(0x0802F03C, 60, "按键采集候选 FUN_0802F03C");
        decompile(0x0802F03C, "按键采集候选 FUN_0802F03C");
        disasm(0x08032790, 40, "FUN_08032790 (vblank里第一个调用)");
        decompile(0x08032790, "FUN_08032790");
        out.close();
        println("完成 main6.c");
    }
}
