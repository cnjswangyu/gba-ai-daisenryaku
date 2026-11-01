// DumpMain15.java —— state5 购买/编成界面的核心函数群
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import java.io.PrintWriter;
import java.math.BigInteger;

public class DumpMain15 extends GhidraScript {
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
        out = new PrintWriter("D:/prog/gba-ai/logs/main15.c", "UTF-8");

        for (Register r : currentProgram.getProgramContext().getRegisters()) {
            if (r.getName().equals("TMode")) { tmodeReg = r; break; }
        }
        println("TMode=" + tmodeReg + " program=" + currentProgram.getName());

        decompile(0x08007BB8, "s5: 购买动作 func_08007bb8", 120);
        decompile(0x0800786C, "s5: 分类清单构建 func_0800786c", 120);
        decompile(0x08007618, "s5: 取消购买? func_08007618", 90);
        decompile(0x08007928, "s5: func_08007928", 90);
        decompile(0x08007CBC, "s5: 光标闪烁 func_08007cbc", 60);
        decompile(0x08007758, "s5: 列表渲染 func_08007758", 90);
        decompile(0x080079D4, "s5: 信息面板 func_080079d4", 90);
        decompile(0x08007A40, "s5: 信息面板2 func_08007a40", 90);
        decompile(0x08007B90, "s5: func_08007b90", 60);

        out.close();
        println("DONE");
    }
}
