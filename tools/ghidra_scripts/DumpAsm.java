// DumpAsm.java —— 反汇编指定范围并输出 listing
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import java.io.PrintWriter;
import java.math.BigInteger;

public class DumpAsm extends GhidraScript {
    private Register tmodeReg;

    @Override
    public void run() throws Exception {
        for (Register r : currentProgram.getProgramContext().getRegisters()) {
            if (r.getName().equals("TMode")) { tmodeReg = r; break; }
        }
        String[] argsS = getScriptArgs();
        long from = Long.decode(argsS[0]);
        long to = Long.decode(argsS[1]);
        String outPath = argsS.length > 2 ? argsS[2] : "D:/prog/gba-ai/logs/asm.txt";

        Address a = toAddr(from);
        Address b = toAddr(to);
        currentProgram.getListing().clearCodeUnits(a, b, false);
        if (tmodeReg != null) {
            currentProgram.getProgramContext().setValue(tmodeReg, a, b, BigInteger.ONE);
        }
        DisassembleCommand dc = new DisassembleCommand(a, null, true);
        boolean ok = dc.applyTo(currentProgram, monitor);
        println("disasm=" + ok);

        PrintWriter out = new PrintWriter(outPath, "UTF-8");
        out.println("== listing 0x" + Long.toHexString(from).toUpperCase() + " - 0x" + Long.toHexString(to).toUpperCase() + " ==");
        for (Address addr = a; addr.compareTo(b) < 0; ) {
            Instruction ins = currentProgram.getListing().getInstructionAt(addr);
            if (ins == null) { addr = addr.add(2); continue; }
            StringBuilder sb = new StringBuilder();
            sb.append(addr.toString()).append("  ");
            for (byte by : ins.getBytes()) sb.append(String.format("%02X", by & 0xff));
            while (sb.length() < 24) sb.append(' ');
            sb.append(ins.toString());
            out.println(sb.toString());
            addr = addr.add(ins.getLength());
        }
        out.close();
        println("listing -> " + outPath);
    }
}
