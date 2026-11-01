// DisasmAll.java —— 对指定区段做 Thumb 反汇编，搜"立即数引用 0x2760/0x637C 等"，
// 再对所属函数重建并反编译。
// 用法: DisasmAll.java <lo> <hi> <out.c> [目标立即数...]
// 关键：项目是 -noanalysis 导入的，必须先自己反汇编，否则 getInstructions 返回空。
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.*;
import ghidra.program.model.scalar.Scalar;
import java.io.PrintWriter;
import java.math.BigInteger;
import java.util.*;

public class DisasmAll extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        long lo = Long.decode(args[0]);
        long hi = Long.decode(args[1]);
        String outPath = args[2];

        List<Long> targets = new ArrayList<Long>();
        for (int i = 3; i < args.length; i++) targets.add(Long.decode(args[i]));

        Register tmode = null;
        for (Register r : currentProgram.getProgramContext().getRegisters()) {
            if (r.getName().equals("TMode")) { tmode = r; break; }
        }
        println("TMode=" + tmode);

        Address aLo = toAddr(lo), aHi = toAddr(hi);
        // 必须先清掉已有指令/context，否则整体设 TMode 会抛 ContextChangeException
        currentProgram.getListing().clearCodeUnits(aLo, aHi, true);
        if (tmode != null) {
            currentProgram.getProgramContext().setValue(tmode, aLo, aHi, BigInteger.ONE);
        }
        DisassembleCommand dc = new DisassembleCommand(aLo, new AddressSet(aLo, aHi), true);
        boolean ok = dc.applyTo(currentProgram, monitor);
        println("disasm=" + ok);

        PrintWriter out = new PrintWriter(outPath, "UTF-8");
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);

        // 搜命中立即数的指令。
        // 注意：Thumb 的 ldr rX,[pc,#imm] 操作数是偏移，字面量里的值要自己算出来再比。
        // 直接看 operand scalar 是找不到的（这就是之前"命中 0"的原因）。
        Map<Long, List<String>> hitsByFunc = new LinkedHashMap<Long, List<String>>();
        int insHits = 0;
        java.util.regex.Pattern pImm = java.util.regex.Pattern.compile("#(0x[0-9a-fA-F]+)");
        for (Instruction ins : currentProgram.getListing().getInstructions(aLo, true)) {
            if (ins.getAddress().compareTo(aHi) > 0) break;
            String txt = ins.toString();
            long hitVal = -1;

            // 情况 1：ldr rX,[pc,#imm] —— 解析字面量池里的值
            if (ins.getMnemonicString().equalsIgnoreCase("ldr") && txt.contains("[pc")) {
                java.util.regex.Matcher m = pImm.matcher(txt);
                if (m.find()) {
                    long imm = Long.decode(m.group(1));
                    long lit = ((ins.getAddress().getOffset() + 4) & ~3L) + imm;
                    try {
                        long val = currentProgram.getMemory().getInt(toAddr(lit)) & 0xFFFFFFFFL;
                        for (long t : targets) if (val == t) hitVal = t;
                    } catch (Exception ex) { /* 越界忽略 */ }
                }
            }
            // 情况 2：操作数本身就是目标立即数（movs/adds 等）
            if (hitVal < 0) {
                for (int i = 0; i < ins.getNumOperands(); i++) {
                    for (Object o : ins.getOpObjects(i)) {
                        if (!(o instanceof Scalar)) continue;
                        long v = ((Scalar) o).getUnsignedValue();
                        for (long t : targets) if (v == t) hitVal = t;
                    }
                }
            }
            if (hitVal < 0) continue;

            insHits++;
            Function f = getFunctionContaining(ins.getAddress());
            long key = (f != null) ? f.getEntryPoint().getOffset() : ins.getAddress().getOffset();
            List<String> lst = hitsByFunc.get(key);
            if (lst == null) { lst = new ArrayList<String>(); hitsByFunc.put(key, lst); }
            lst.add("0x" + Long.toHexString(hitVal).toUpperCase() + " @ " + ins.getAddress() + "  " + txt);
        }
        println("命中指令 " + insHits + " / 函数 " + hitsByFunc.size());

        int n = 0;
        for (Map.Entry<Long, List<String>> e : hitsByFunc.entrySet()) {
            long addr = e.getKey();
            out.println("/* ================ 0x" + Long.toHexString(addr).toUpperCase() + " ================ */");
            for (String s : e.getValue()) out.println("//   " + s);

            Function f = getFunctionContaining(toAddr(addr));
            if (f == null) {
                Address aa = toAddr(addr);
                CreateFunctionCmd cc = new CreateFunctionCmd(aa);
                cc.applyTo(currentProgram, monitor);
                f = getFunctionAt(aa);
            }
            if (f == null) {
                out.println("// (建函数失败)\n");
                continue;
            }
            out.println("// func " + f.getName() + " size=" + f.getBody().getNumAddresses() + "B");
            if (n++ < 40) {
                DecompileResults res = dec.decompileFunction(f, 60, monitor);
                if (res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
                else out.println("// 反编译失败: " + res.getErrorMessage());
            } else {
                out.println("// (超过 40 个，跳过反编译)");
            }
            out.println();
            out.flush();
        }
        out.close();
        println("done -> " + outPath);
    }
}
