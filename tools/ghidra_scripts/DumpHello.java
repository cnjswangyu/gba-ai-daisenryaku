// 最小可用性检查：确认 headless 脚本管线能跑、能写文件
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import java.io.PrintWriter;

public class DumpHello extends GhidraScript {
    @Override
    public void run() throws Exception {
        PrintWriter out = new PrintWriter("D:/prog/gba-ai/logs/gh_hello.txt", "UTF-8");
        out.println("program=" + currentProgram.getName());
        out.println("language=" + currentProgram.getLanguageID());
        out.println("imageBase=" + currentProgram.getImageBase());
        int n = 0;
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext()) { Function f = it.next(); n++; if (n <= 5) out.println("  fn " + f.getEntryPoint()); }
        out.println("functionCount=" + n);
        out.close();
        println("hello done, functions=" + n);
    }
}
