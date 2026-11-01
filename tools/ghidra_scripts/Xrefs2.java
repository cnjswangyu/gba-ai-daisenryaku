// Xrefs2.java —— 查找指定地址(可多个)的所有引用来源
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.*;
import java.io.PrintWriter;

public class Xrefs2 extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] argsS = getScriptArgs();
        PrintWriter out = new PrintWriter(argsS[argsS.length - 1], "UTF-8");
        for (int i = 0; i < argsS.length - 1; i++) {
            long t = Long.decode(argsS[i]);
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
        out.close();
        println("xrefs2 done");
    }
}
