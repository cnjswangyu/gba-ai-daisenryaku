// 找出所有读 KEYINPUT(0x04000130) 的函数，并把反编译结果导出
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Data;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;
import java.util.LinkedHashSet;
import java.util.Set;

public class DumpKey extends GhidraScript {

    @Override
    public void run() throws Exception {
        long target = 0x04000130L;
        Set<Function> funcs = new LinkedHashSet<Function>();

        // 1) 指令里直接出现常量
        for (Instruction ins : currentProgram.getListing().getInstructions(true)) {
            int n = ins.getNumOperands();
            for (int i = 0; i < n; i++) {
                for (Object o : ins.getOpObjects(i)) {
                    if (o instanceof Scalar) {
                        Scalar s = (Scalar) o;
                        if (s.getUnsignedValue() == target) {
                            Function f = getFunctionContaining(ins.getAddress());
                            if (f != null) funcs.add(f);
                        }
                    }
                }
            }
        }
        println("直接常量引用函数数: " + funcs.size());

        // 2) 字面量池：内存里出现 0x04000130 的地方，被谁引用
        int foundLits = 0;
        for (Data d : currentProgram.getListing().getDefinedData(true)) {
            if (d.getLength() == 4 && d.getValue() != null) {
                Object v = d.getValue();
                if (v instanceof Scalar && ((Scalar) v).getUnsignedValue() == target) {
                    foundLits++;
                    for (Reference r : getReferencesTo(d.getAddress())) {
                        Function f = getFunctionContaining(r.getFromAddress());
                        if (f != null) funcs.add(f);
                    }
                }
            }
        }
        println("字面量池命中: " + foundLits + "  合计函数: " + funcs.size());

        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);

        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/keyfuncs.c", "UTF-8");
        for (Function f : funcs) {
            out.println("/* ===== " + f.getName() + " @ " + f.getEntryPoint() + " ===== */");
            try {
                DecompileResults res = dec.decompileFunction(f, 60, monitor);
                if (res != null && res.decompileCompleted()) {
                    out.println(res.getDecompiledFunction().getC());
                } else {
                    out.println("// decompile failed");
                }
            } catch (Exception e) {
                out.println("// error: " + e);
            }
            out.println();
        }
        out.close();
        println("已写出 D:/prog/gba-ai/logs/keyfuncs.c");
    }
}
