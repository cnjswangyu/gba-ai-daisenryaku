// DumpMain3.java —— 反编译 vblank 同步函数的调用者簇（任务调度器候选）+ crt0 之后的 main
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;
import java.util.*;

public class DumpMain3 extends GhidraScript {
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
        Set<String> called = new TreeSet<String>();
        for (Instruction ins : currentProgram.getListing().getInstructions(f.getBody(), true)) {
            if (ins.getMnemonicString().toLowerCase().startsWith("bl")) {
                for (Object o : ins.getOpObjects(0)) {
                    if (o instanceof Address) {
                        Function t = getFunctionContaining((Address) o);
                        if (t != null) called.add(t.getName() + "@" + t.getEntryPoint());
                    }
                }
            }
        }
        out.println("/* bl -> " + String.join(" , ", called) + " */");
        out.println();
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/mainfuncs3.c", "UTF-8");

        dumpFun("调度器候选A", 0x08003a08L);
        dumpFun("调度器候选B", 0x08003a94L);
        dumpFun("调度器候选C", 0x08003b84L);
        dumpFun("调度器候选D", 0x08004020L);
        dumpFun("调度器候选E", 0x08003d6cL);
        dumpFun("main?", 0x0800099cL);
        dumpFun("IRQ/回调注册", 0x08001198L);
        dumpFun("IRQ/回调注册2", 0x0800128cL);
        out.close();
        println("完成 mainfuncs3.c");
    }
}
