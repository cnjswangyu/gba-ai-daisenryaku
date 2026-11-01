// DumpMain.java —— 反编译主循环/crt0/IRQ注册/上下文指针引用，摸清界面状态机骨架
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import java.io.PrintWriter;
import java.util.*;

public class DumpMain extends GhidraScript {
    @Override
    public void run() throws Exception {
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/mainfuncs.c", "UTF-8");

        // 1) 直接反编译一组锚点函数
        long[] anchors = {
            0x080006C0L,  // 主循环（trace 直方图冠军）
            0x080000C0L,  // crt0 入口
            0x080015D4L,  // 读键函数（已知）
        };
        for (long a : anchors) {
            Function f = getFunctionContaining(toAddr(a));
            if (f == null) { out.println("/* no function @ " + Long.toHexString(a) + " */"); continue; }
            DecompileResults r = dec.decompileFunction(f, 90, monitor);
            out.println("/* ===== ANCHOR " + f.getName() + " @ " + f.getEntryPoint() + " ===== */");
            if (r != null && r.decompileCompleted()) out.println(r.getDecompiledFunction().getC());
            else out.println("/* decompile failed */");
            out.println();
        }

        // 2) 找引用关键常量的函数：IRQ 句柄注册 0x03007FFC、上下文指针 0x02007060
        Set<Long> seen = new HashSet<Long>();
        List<Function> hits = new ArrayList<Function>();
        for (Instruction ins : currentProgram.getListing().getInstructions(true)) {
            for (int i = 0; i < ins.getNumOperands(); i++) {
                for (Object o : ins.getOpObjects(i)) {
                    if (!(o instanceof ghidra.program.model.scalar.Scalar)) continue;
                    long v = ((ghidra.program.model.scalar.Scalar) o).getUnsignedValue();
                    if (v == 0x03007FFCL || v == 0x02007060L) {
                        Function f = getFunctionContaining(ins.getAddress());
                        if (f != null && seen.add(f.getEntryPoint().getOffset())) hits.add(f);
                    }
                }
            }
        }
        out.println("/* ===== 引用 0x03007FFC(IRQ注册) 或 0x02007060(上下文指针) 的函数: " + hits.size() + " 个 ===== */");
        for (Function f : hits) {
            DecompileResults r = dec.decompileFunction(f, 60, monitor);
            out.println("/* ---- " + f.getName() + " @ " + f.getEntryPoint() + " ---- */");
            if (r != null && r.decompileCompleted()) out.println(r.getDecompiledFunction().getC());
            else out.println("/* decompile failed */");
            out.println();
        }
        out.close();
        println("已写出 mainfuncs.c");
    }
}
