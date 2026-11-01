// 反编译指定地址所在函数（含被调用者一层），导出到文件
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;
import java.util.*;

public class DumpAt extends GhidraScript {
    long[] TARGETS = { 0x08020010L, 0x0802008cL, 0x08002e74L, 0x08022be8L };

    @Override
    public void run() throws Exception {
        FunctionManager fm = currentProgram.getFunctionManager();
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/damage.c", "UTF-8");
        Set<Long> seen = new HashSet<Long>();

        for (long t : TARGETS) {
            Address a = toAddr(t);
            Function f = fm.getFunctionContaining(a);
            out.println("// ===== target 0x" + Long.toHexString(t) + " -> " +
                (f == null ? "NO FUNCTION" : f.getName() + " @ " + f.getEntryPoint()) + " =====");
            if (f == null) {
                // 用包含该地址的函数集合兜底
                Iterator<Function> it2 = fm.getFunctions(a, true);
                if (it2.hasNext()) {
                    f = it2.next();
                    out.println("// 用包含该地址的函数: " + f.getName());
                }
            }
            if (f == null) { out.println("// skip"); continue; }
            dump(f, dec, out, 2, seen);
        }
        out.close();
        println("done");
    }

    void dump(Function f, DecompInterface dec, PrintWriter out, int depth, Set<Long> seen) throws Exception {
        long key = f.getEntryPoint().getOffset();
        if (seen.contains(key)) return;
        seen.add(key);
        out.println("/* ===== " + f.getName() + " @ " + f.getEntryPoint() + " ===== */");
        DecompileResults res = dec.decompileFunction(f, 90, monitor);
        if (res != null && res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
        else out.println("// decompile failed");
        out.println();
        if (depth > 0) {
            for (Function callee : f.getCalledFunctions(monitor)) {
                dump(callee, dec, out, depth - 1, seen);
            }
        }
    }
}
