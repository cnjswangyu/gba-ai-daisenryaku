// DumpMain12.java —— 国家选择(state2 step1) + 出击编成表输入处理函数群
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import java.io.PrintWriter;
import java.math.BigInteger;

public class DumpMain12 extends GhidraScript {
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
        out = new PrintWriter("D:/prog/gba-ai/logs/main12.c", "UTF-8");

        for (Register r : currentProgram.getProgramContext().getRegisters()) {
            if (r.getName().equals("TMode")) { tmodeReg = r; break; }
        }
        println("TMode=" + tmodeReg + " program=" + currentProgram.getName());

        // ===== 需求①: 国家选择 =====
        decompile(0x080051CC, "state2 step1: 国家选择", 90);

        // ===== state2 其余向导步骤(备用) =====
        decompile(0x080051B4, "state2 step0: 姓名输入", 60);
        decompile(0x08005224, "state2 step2: 国歌选择", 60);
        decompile(0x0800522A, "state2 step3: 确认设置", 60);
        decompile(0x0800523C, "state2 step4: 存档", 60);

        // ===== 需求②: 出击编成表输入处理 =====
        decompile(0x08009F08, "s6: 每帧输入处理A func_08009f08", 90);
        decompile(0x08009F04, "s6: 每帧输入处理B func_08009f04", 60);
        decompile(0x08008684, "s6: 单位清单渲染 func_0808684", 90);
        decompile(0x08009830, "s6: func_0809830", 60);
        decompile(0x08009520, "s6: 光标/条漫渲染 func_0809520", 60);
        decompile(0x080097AC, "s6: func_08097ac", 60);
        decompile(0x080094A4, "s6: 初始化渲染 func_08094a4", 60);
        decompile(0x080092C0, "s6: func_08092c0", 60);
        decompile(0x080097C4, "s6: func_08097c4", 60);
        decompile(0x08003C94, "s6: 条件检查 func_0803c94", 60);
        decompile(0x0800AEB4, "s6: 购买/部署动作 func_080aeb4", 90);

        out.close();
        println("完成 main12.c");
    }
}
