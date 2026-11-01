// DumpMain8.java —— 反编译输入读取 + 全部界面 handler + 主循环公共处理
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import java.io.PrintWriter;

public class DumpMain8 extends GhidraScript {
    private DecompInterface dec;
    private PrintWriter out;

    private void decompile(long from, String title) throws Exception {
        out.println("\n/* ===== 反编译 " + title + " @0x" + Long.toHexString(from) + " ==== */");
        Function f = getFunctionAt(toAddr(from));
        if (f == null) { out.println("  (无函数)"); return; }
        out.println("  函数: " + f.getName() + " @" + f.getEntryPoint() + " size=" + f.getBody().getNumAddresses());
        DecompileResults res = dec.decompileFunction(f, 300, monitor);
        if (res.decompileCompleted()) out.println(res.getDecompiledFunction().getC());
        else out.println("  (反编译失败)");
    }

    @Override
    public void run() throws Exception {
        dec = new DecompInterface();
        dec.openProgram(currentProgram);
        out = new PrintWriter("D:/prog/gba-ai/logs/main8.c", "UTF-8");

        decompile(0x080321B0, "输入读取 FUN_080321B0 (FUN_08032E54 的实体)");
        decompile(0x080015D4, "主循环公共帧处理 FUN_080015D4");
        decompile(0x08004C98, "state0 handler A: 标题 init");
        decompile(0x080143A0, "state0 handler B: 标题帧");
        decompile(0x08004D80, "state1 handler: 主菜单");
        decompile(0x08005180, "state2 handler: 姓名/国家/国歌/确认向导");
        decompile(0x08006ED8, "state3 handler: 剧本选择");
        decompile(0x08007364, "state4 handler: 剧本详情");
        decompile(0x080099B8, "state6 handler: 出击编成表 + 战场");
        decompile(0x08007CE0, "state5 handler");
        decompile(0x0800D5C0, "state7 handler");
        decompile(0x0800EED8, "state8 handler");
        decompile(0x080104C0, "state9 handler");
        decompile(0x080105D8, "state10 handler");
        decompile(0x0800F7D8, "state11 handler");
        decompile(0x08007084, "state12 handler");
        decompile(0x08010A90, "state13 handler");
        decompile(0x0802EEE0, "state14 handler");
        out.close();
        println("完成 main8.c");
    }
}
