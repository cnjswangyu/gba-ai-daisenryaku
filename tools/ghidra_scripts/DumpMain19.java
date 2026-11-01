// DumpMain19.java —— 自动部署链路: state6 init + FUN_08001198/128c + 00b20/00b3c + 放置小模式 + 标记函数
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import java.io.PrintWriter;
import java.math.BigInteger;

public class DumpMain19 extends GhidraScript {
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
        out = new PrintWriter("D:/prog/gba-ai/logs/main19.c", "UTF-8");

        for (Register r : currentProgram.getProgramContext().getRegisters()) {
            if (r.getName().equals("TMode")) { tmodeReg = r; break; }
        }
        println("TMode=" + tmodeReg + " program=" + currentProgram.getName());

        decompile(0x080099B8, "state6: init/主循环 handler FUN_080099b8", 120);
        decompile(0x08001198, "自动部署A FUN_08001198", 90);
        decompile(0x0800128C, "自动部署B FUN_0800128c", 90);
        decompile(0x08000B20, "func_08000b20", 60);
        decompile(0x08000B3C, "func_08000b3c", 60);
        decompile(0x08008E2C, "放置小模式 func_08008e2c", 120);
        decompile(0x080135C0, "标记函数 func_080135c0", 60);
        decompile(0x080039FC, "显示函数 FUN_080039fc", 60);
        decompile(0x08003C94, "B确认框 func_0803c94", 60);
        decompile(0x080105D8, "state10 handler FUN_080105d8", 90);

        out.close();
        println("完成 main19.c");
    }
}
