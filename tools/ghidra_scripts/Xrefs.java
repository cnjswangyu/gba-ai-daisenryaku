// Xrefs.java —— 查找指定地址的所有调用来源 + 函数边界
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.*;
import java.io.PrintWriter;

public class Xrefs extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] argsS = getScriptArgs();
        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/xrefs.txt", "UTF-8");
        long[] targets = { 0x08009F04L, 0x08009F08L, 0x0800A72AL, 0x0800AEB4L, 0x08003C94L, 0x0800A5D4L, 0x080099B8L, 0x08008E2CL, 0x08001198L, 0x0800128CL, 0x08000B20L, 0x08000B3CL };
        for (long t : targets) {
            Address a = toAddr(t);
            out.println("== xrefs to 0x" + Long.toHexString(t).toUpperCase() + " ==");
            ReferenceIterator it = currentProgram.getReferenceManager().getReferencesTo(a);
            int n = 0;
            while (it.hasNext()) {
                Reference r = it.next();
                Address from = r.getFromAddress();
                Function f = currentProgram.getFunctionManager().getFunctionContaining(from);
                out.println("   from " + from + "  type=" + r.getReferenceType() +
                    "  inFunc=" + (f != null ? f.getName() + "@" + f.getEntryPoint() : "?"));
                n++;
            }
            if (n == 0) out.println("   (none)");
        }
        // 函数边界
        out.println("\n== functions in 0x08009d00-0x0800ab00 ==");
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            Address e = f.getEntryPoint();
            long o = e.getOffset();
            if (o >= 0x08009d00L && o < 0x0800ab00L) {
                out.println("   " + f.getName() + " @" + e + " size=" + f.getBody().getNumAddresses() +
                    " end=" + f.getBody().getMaxAddress());
            }
        }
        out.close();
        println("xrefs.txt done");
    }
}
