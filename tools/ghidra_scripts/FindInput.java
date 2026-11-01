// 按"常量/偏移特征"定位关键函数：如读输入状态 +0xC/+0xE、按 0x5C 索引单位表
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.scalar.Scalar;
import java.io.PrintWriter;
import java.util.*;

public class FindInput extends GhidraScript {
    @Override
    public void run() throws Exception {
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);

        List<Function> hits = new ArrayList<Function>();
        Set<Long> seen = new HashSet<Long>();
        int scanned = 0;

        for (Instruction ins : currentProgram.getListing().getInstructions(true)) {
            scanned++;
            String mn = ins.getMnemonicString().toLowerCase();
            if (!(mn.startsWith("ldr") || mn.startsWith("str"))) continue;
            for (int i = 0; i < ins.getNumOperands(); i++) {
                for (Object o : ins.getOpObjects(i)) {
                    if (!(o instanceof Scalar)) continue;
                    long v = ((Scalar) o).getUnsignedValue();
                    // 输入状态 +0xC / +0xE；单位表步长 0x18
                    if (v == 0xc || v == 0xe || v == 0x18) {
                        Function f = getFunctionContaining(ins.getAddress());
                        if (f != null && seen.add(f.getEntryPoint().getOffset())) hits.add(f);
                    }
                }
            }
        }
        println("指令扫描 " + scanned + "，命中函数 " + hits.size());

        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/inputfuncs.c", "UTF-8");
        int n = 0;
        for (Function f : hits) {
            if (n++ > 120) break;
            DecompileResults res = dec.decompileFunction(f, 60, monitor);
            if (res == null || !res.decompileCompleted()) continue;
            String c = res.getDecompiledFunction().getC();
            // 只要读输入状态（+0xc 与 +0xe 同时出现）的函数
            boolean hasC = c.contains("+ 0xc)") || c.contains("+ 0xc");
            boolean hasE = c.contains("+ 0xe)") || c.contains("+ 0xe");
            if (hasC && hasE) {
                out.println("/* ===== INPUT? " + f.getName() + " @ " + f.getEntryPoint() + " ===== */");
                out.println(c);
                out.println();
            }
        }
        out.close();
        println("已写出 inputfuncs.c");
    }
}
