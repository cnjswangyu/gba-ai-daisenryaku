// 扫描所有"按 0x5C(92) 索引"的函数（兵种/武器表访问），并反编译导出
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.scalar.Scalar;
import java.io.PrintWriter;
import java.util.*;

public class FindStride extends GhidraScript {
    @Override
    public void run() throws Exception {
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        List<Function> hits = new ArrayList<Function>();
        Set<Long> seen = new HashSet<Long>();

        for (Instruction ins : currentProgram.getListing().getInstructions(true)) {
            String mn = ins.getMnemonicString().toLowerCase();
            if (!mn.startsWith("mul") && !mn.startsWith("lsl") && !mn.startsWith("add") && !mn.startsWith("mov")) continue;
            for (int i = 0; i < ins.getNumOperands(); i++) {
                for (Object o : ins.getOpObjects(i)) {
                    if (!(o instanceof Scalar)) continue;
                    long v = ((Scalar) o).getUnsignedValue();
                    if (v == 0x3f60 || v == 0x6380 || v == 0x6385) {
                        Function f = getFunctionContaining(ins.getAddress());
                        if (f != null && seen.add(f.getEntryPoint().getOffset())) hits.add(f);
                    }
                }
            }
        }
        println("命中函数 " + hits.size());

        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/mapfuncs.c", "UTF-8");
        int n = 0;
        for (Function f : hits) {
            if (n++ > 150) break;
            DecompileResults res = dec.decompileFunction(f, 60, monitor);
            if (res == null || !res.decompileCompleted()) continue;
            String c = res.getDecompiledFunction().getC();
            // 只保留真正做表索引的（同时出现 0x5c 和 0x20 附近的攻击字段）
            if (!(c.contains("0x3f60") || c.contains("0x6380") || c.contains("0xc0"))) continue;
            out.println("/* ===== " + f.getName() + " @ " + f.getEntryPoint() + " ===== */");
            out.println(c);
            out.println();
        }
        out.close();
        println("已写出 stridefuncs.c");
    }
}
