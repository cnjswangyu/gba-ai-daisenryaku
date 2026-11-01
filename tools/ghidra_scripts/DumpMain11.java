// DumpMain11.java —— 批量反编译: state6 子函数 + 其余界面 handler
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import java.io.PrintWriter;
import java.math.BigInteger;

public class DumpMain11 extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;
    private Register tmodeReg;

    private Function ensureFunction(long from, String tag) throws Exception {
        Function f = getFunctionAt(toAddr(from));
        if (f != null) return f;
        Address a = toAddr(from);
        currentProgram.getListing().clearCodeUnits(a, a.add(0x2000), false);
        if (tmodeReg != null) {
            currentProgram.getProgramContext().setValue(tmodeReg, a, a, BigInteger.ONE);
        }
        DisassembleCommand dc = new DisassembleCommand(a, null, true);
        dc.applyTo(currentProgram, monitor);
        CreateFunctionCmd cc = new CreateFunctionCmd(a);
        cc.applyTo(currentProgram, monitor);
        return getFunctionAt(a);
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
        out = new PrintWriter("D:/prog/gba-ai/logs/main11.c", "UTF-8");

        for (Register r : currentProgram.getProgramContext().getRegisters()) {
            if (r.getName().equals("TMode")) { tmodeReg = r; break; }
        }

        // state6 子函数
        decompile(0x08009348, "s6: 单位清单生成 FUN_08009348", 60);
        decompile(0x08009554, "s6: 单位条目渲染 FUN_08009554", 60);
        decompile(0x08009854, "s6: 交互循环A FUN_08009854", 60);
        decompile(0x080098f4, "s6: 交互循环B FUN_080098f4", 60);
        decompile(0x08002c9c, "s6: 单位表项处理 FUN_08002c9c", 60);
        // 其余界面 handler
        decompile(0x08005180, "state2: 姓名/国家/国歌/确认向导", 60);
        decompile(0x08006ED8, "state3: 剧本选择", 60);
        decompile(0x08004D80, "state1: 主菜单", 60);
        decompile(0x08004C98, "state0A: 标题 init", 60);
        decompile(0x080143A0, "state0B: 标题帧", 60);
        decompile(0x08007CE0, "state5 handler", 60);
        decompile(0x0804024c, "FUN_0804024c: DMA拷贝?", 60);
        out.close();
        println("完成 main11.c");
    }
}
