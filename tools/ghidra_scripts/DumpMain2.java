// DumpMain2.java —— 精准版：只反编译锚点函数 + 用引用 API 找调用关系（不做全 ROM 扫描）
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;
import java.util.*;

public class DumpMain2 extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;

    private void dumpFun(String label, long addr) {
        Function f = getFunctionContaining(toAddr(addr));
        out.println("/* ===== " + label + " @ " + Long.toHexString(addr) +
                    (f != null ? " (func " + f.getName() + " " + f.getEntryPoint() + ")" : "") + " ===== */");
        if (f == null) { out.println("/* 无函数 */"); out.println(); return; }
        DecompileResults r = dec.decompileFunction(f, 120, monitor);
        if (r != null && r.decompileCompleted()) out.println(r.getDecompiledFunction().getC());
        else out.println("/* decompile failed */");
        out.println();
        // 输出 callees（直接扫函数体内 bl）
        Set<String> called = new TreeSet<String>();
        for (Instruction ins : currentProgram.getListing().getInstructions(f.getBody(), true)) {
            String m = ins.getMnemonicString().toLowerCase();
            if (m.startsWith("bl")) {
                for (Object o : ins.getOpObjects(0)) {
                    if (o instanceof Address) {
                        Function t = getFunctionContaining((Address) o);
                        if (t != null) called.add(t.getName() + "@" + t.getEntryPoint());
                    }
                }
            }
        }
        for (String c : called) out.println("   bl -> " + c);
        out.println();
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/mainfuncs2.c", "UTF-8");

        dumpFun("主循环(trace冠军)", 0x080006C2L);
        dumpFun("crt0入口", 0x080000C0L);
        dumpFun("读键函数", 0x080015D4L);
        dumpFun("IRQ回调槽0x03007F9C常驻值附近", 0x080006C4L);

        // 找所有 bl 到 0x080006C0 的调用者（谁调用主循环函数）
        out.println("/* ===== 引用主循环函数的代码 ===== */");
        Function main = getFunctionContaining(toAddr(0x080006C2L));
        if (main != null) {
            for (Reference ref : currentProgram.getReferenceManager().getReferencesTo(main.getEntryPoint())) {
                Function from = getFunctionContaining(ref.getFromAddress());
                out.println("   " + ref.getFromAddress() + " in " + (from != null ? from.getName() + "@" + from.getEntryPoint() : "?"));
            }
        }
        out.close();
        println("完成 mainfuncs2.c");
    }
}
