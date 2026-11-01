// DumpMain5.java —— 反汇编 main(0x08000229) + IRQ入口(0x080000FC) + vblank标志设置函数(0x08000674)
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import java.io.PrintWriter;

public class DumpMain5 extends GhidraScript {
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
            // 尝试创建函数
            DisassembleCommand cmd = new DisassembleCommand(toAddr(from), null, true);
            cmd.applyTo(currentProgram, monitor);
            f = createFunction(toAddr(from), "FUN_" + Long.toHexString(from));
        }
        if (f == null) { out.println("  (无法定位函数)"); return; }
        out.println("  函数: " + f.getName() + " @" + f.getEntryPoint() + " size=" + f.getBody().getNumAddresses());
        DecompileResults res = dec.decompileFunction(f, 180, monitor);
        if (res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
        else out.println("  (反编译失败)");
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/main5.c", "UTF-8");

        disasm(0x080000FC, 40, "IRQ入口 (BIOS跳到这)");
        disasm(0x08000229, 250, "main");
        disasm(0x08000674, 30, "vblank标志设置函数");
        decompile(0x08000229, "main");
        decompile(0x08000674, "vblank标志设置函数");
        out.close();
        println("完成 main5.c");
    }
}
