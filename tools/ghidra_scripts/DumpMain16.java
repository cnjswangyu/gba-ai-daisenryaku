// DumpMain16.java —— 购买核心 func_080078a0 + 相关小函数
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import java.io.PrintWriter;
import java.math.BigInteger;

public class DumpMain16 extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;
    private Register tmodeReg;

    private Function ensureFunction(long from, String tag) throws Exception {
        Function f = getFunctionAt(toAddr(from));
        if (f != null) return f;
        Address a = toAddr(from);
        currentProgram.getListing().clearCodeUnits(a, a.add(0x4000), false);
        if (tmodeReg != null) {
            currentProgram.getProgramContext().setValue(tmodeReg, a, a, BigInteger.ONE);
        }
        DisassembleCommand dc = new DisassembleCommand(a, null, true);
        boolean ok = dc.applyTo(currentProgram, monitor);
        println(tag + " disasm=" + ok);
        CreateFunctionCmd cc = new CreateFunctionCmd(a);
        cc.applyTo(currentProgram, monitor);
        Function nf = getFunctionAt(a);
        println(tag + " func=" + (nf != null ? nf.getBody().getNumAddresses() + " bytes" : "FAIL"));
        return nf;
    }

    private void decompile(long from, String title, int secs) throws Exception {
        String hex = "0x" + Long.toHexString(from).toUpperCase();
        out.println("\n/* ===== " + title + " @" + hex + " ==== */");
        Function f = ensureFunction(from, hex);
        if (f == null) { out.println("  (建函数失败)"); return; }
        out.println("  函数: " + f.getName() + " size=" + f.getBody().getNumAddresses() + "B");
        out.flush();
        DecompileResults res = dec.decompileFunction(f, secs, monitor);
        if (res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
        else out.println("  (反编译失败: " + res.getErrorMessage() + ")");
        out.flush();
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/main16.c", "UTF-8");

        for (Register r : currentProgram.getProgramContext().getRegisters()) {
            if (r.getName().equals("TMode")) { tmodeReg = r; break; }
        }
        println("TMode=" + tmodeReg + " program=" + currentProgram.getName());

        decompile(0x080078A0, "s5: 购买核心 func_080078a0", 150);
        decompile(0x080031B90, "s5: 检查 func_08031b90", 90);
        decompile(0x08002D84, "unit: func_08002d84", 60);
        decompile(0x08002DAC, "unit: func_08002dac", 60);
        decompile(0x08002D4C, "unit: func_08002d4c", 60);
        decompile(0x0800237C, "unit: func_0800237c", 60);

        out.close();
        println("DONE");
    }
}
