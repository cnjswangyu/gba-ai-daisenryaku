// DumpMain7.java —— main(Thumb@0x08000228) + 输入读取函数 FUN_08032E54
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.*;
import java.io.PrintWriter;
import java.math.BigInteger;

public class DumpMain7 extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;

    private void disasmThumb(long from, int n, String title) throws Exception {
        out.println("\n/* ===== " + title + " @0x" + Long.toHexString(from) + " (Thumb) ==== */");
        // 先清掉该区域可能存在的 ARM 坏指令，再强制 Thumb 模式
        try {
            clearListing(toAddr(from), toAddr(from + n * 4 + 64));
        } catch (Exception e) {
            out.println("  (clearListing 失败: " + e.getMessage() + ")");
        }
        try {
            Register tmode = currentProgram.getRegister("TMode");
            if (tmode != null) {
                currentProgram.getProgramContext().setValue(tmode, toAddr(from), toAddr(from + n * 4 + 64), BigInteger.ONE);
                println("TMode set at 0x" + Long.toHexString(from));
            } else println("WARN: no TMode register");
        } catch (Exception e) {
            out.println("  (TMode 设置失败: " + e.getMessage() + ")");
        }
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
        DecompileResults res = dec.decompileFunction(f, 250, monitor);
        if (res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
        else out.println("  (反编译失败)");
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/main7.c", "UTF-8");

        disasmThumb(0x08000228, 400, "main");
        decompile(0x08000228, "main");
        disasmThumb(0x08032E54, 120, "输入读取 FUN_08032E54");
        decompile(0x08032E54, "输入读取 FUN_08032E54");
        out.close();
        println("完成 main7.c");
    }
}
