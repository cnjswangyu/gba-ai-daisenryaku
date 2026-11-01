// DumpMain18.java —— 解析 state6 handler FUN_080099b8 的 _DAT_08009bxx 字面量
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import java.io.PrintWriter;

public class DumpMain18 extends GhidraScript {
    private int rd8(long a) throws Exception { return currentProgram.getMemory().getByte(toAddr(a)) & 0xff; }
    private long rd32(long a) throws Exception { return currentProgram.getMemory().getInt(toAddr(a)) & 0xffffffffL; }

    private void litWalk(PrintWriter out, long from, String tag) throws Exception {
        out.println("\n== refs in " + tag + " @0x" + Long.toHexString(from).toUpperCase() + " ==");
        Function f = getFunctionAt(toAddr(from));
        if (f == null) { out.println("  (no function)"); return; }
        java.util.Set<Long> seen = new java.util.HashSet<Long>();
        for (Address insAddr : f.getBody().getAddresses(true)) {
            Instruction ins = currentProgram.getListing().getInstructionAt(insAddr);
            if (ins == null) continue;
            for (ghidra.program.model.symbol.Reference r : ins.getReferencesFrom()) {
                Address to = r.getToAddress();
                long ta = to.getOffset();
                if (ta < 0x08000000L || ta >= 0x0A000000L) continue;
                if (seen.contains(ta)) continue;
                seen.add(ta);
                String hex = "0x" + Long.toHexString(ta).toUpperCase();
                String val;
                try {
                    long v = rd32(ta);
                    val = "u32=0x" + Long.toHexString(v).toUpperCase();
                } catch (Exception e) { val = "?"; }
                out.println("  " + hex + "  " + val + "   (ins: " + ins.getMinAddress().toString() + " " + ins.toString() + ")");
            }
        }
    }

    @Override
    public void run() throws Exception {
        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/main18.txt", "UTF-8");
        litWalk(out, 0x080099B8, "state6 handler FUN_080099b8");
        litWalk(out, 0x08009348, "list builder FUN_08009348");
        out.close();
        println("DONE");
    }
}
