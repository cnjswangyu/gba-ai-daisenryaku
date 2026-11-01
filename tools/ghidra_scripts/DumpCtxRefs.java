// DumpCtxRefs.java —— 找"用 ctx 偏移访问单位表/光标"的指令并反编译所属函数
// 背景：这游戏代码走 ctx(0x03000480) + 偏移，绝对地址 0x03002BE2 在代码里不存在，
//       所以 xref 查不到。单位表 = ctx+0x2762，光标 = ctx+0x637C。
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.scalar.Scalar;
import java.io.PrintWriter;
import java.util.*;

public class DumpCtxRefs extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String outPath = (args.length > 0) ? args[0] : "D:/prog/gba-ai/logs/ctxrefs.c";
        long[] targets = { 0x2762L, 0x637CL, 0x6380L, 0x638EL };

        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);

        PrintWriter out = new PrintWriter(outPath, "UTF-8");
        Set<Long> seen = new HashSet<Long>();
        int insHits = 0;

        for (Instruction ins : currentProgram.getListing().getInstructions(true)) {
            boolean hit = false;
            long hitVal = 0;
            for (int i = 0; i < ins.getNumOperands(); i++) {
                for (Object o : ins.getOpObjects(i)) {
                    if (!(o instanceof Scalar)) continue;
                    long v = ((Scalar) o).getUnsignedValue();
                    for (long t : targets) {
                        if (v == t) { hit = true; hitVal = v; }
                    }
                }
            }
            if (!hit) continue;
            insHits++;
            Function f = getFunctionContaining(ins.getAddress());
            long key = (f != null) ? f.getEntryPoint().getOffset() : ins.getAddress().getOffset();
            if (!seen.add(key)) continue;

            out.println("// ===== 0x" + Long.toHexString(hitVal).toUpperCase() +
                "  @ " + ins.getAddress() + "   " + ins);
            if (f != null) {
                out.println("// func " + f.getName() + " @ " + f.getEntryPoint());
                DecompileResults res = dec.decompileFunction(f, 60, monitor);
                if (res != null && res.decompileCompleted()) {
                    out.println(res.getDecompiledFunction().getC());
                }
            } else {
                out.println("// (无函数)");
            }
            out.println();
        }
        out.close();
        println("DumpCtxRefs: 命中指令 " + insHits + "，函数 " + seen.size() + " -> " + outPath);
    }
}
