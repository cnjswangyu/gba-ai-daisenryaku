// DumpMain17.java —— 解析 state5 相关字面量 + dump 各国商品目录
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import java.io.PrintWriter;

public class DumpMain17 extends GhidraScript {
    private int rd8(long a) throws Exception { return currentProgram.getMemory().getByte(toAddr(a)) & 0xff; }
    private int rd16(long a) throws Exception { return currentProgram.getMemory().getShort(toAddr(a)) & 0xffff; }
    private long rd32(long a) throws Exception { return currentProgram.getMemory().getInt(toAddr(a)) & 0xffffffffL; }

    private void litWalk(PrintWriter out, long from, String tag) throws Exception {
        out.println("\n== refs in " + tag + " @0x" + Long.toHexString(from).toUpperCase() + " ==");
        Function f = getFunctionAt(toAddr(from));
        if (f == null) { out.println("  (no function)"); return; }
        java.util.Set<Long> seen = new java.util.HashSet<Long>();
        for (Address insAddr : f.getBody().getAddresses(true)) {
            Instruction ins = currentProgram.getListing().getInstructionAt(insAddr);
            if (ins == null) continue;
            for (Object refObj : ins.getReferenceIteratorTo()) {
                // skip
            }
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
                    val = "u32=0x" + Long.toHexString(v).toUpperCase() +
                          " u16lo=0x" + Integer.toHexString((int)(v & 0xffff)).toUpperCase();
                } catch (Exception e) { val = "?"; }
                out.println("  " + hex + "  " + val);
            }
        }
    }

    @Override
    public void run() throws Exception {
        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/main17.txt", "UTF-8");
        litWalk(out, 0x080078A0, "buy core func_080078a0");
        litWalk(out, 0x08007758, "list builder func_08007758");
        litWalk(out, 0x0800786C, "pool counter func_0800786c");
        litWalk(out, 0x08007BB8, "buy wrapper func_08007bb8");
        out.close();
        println("DONE");
    }
}
