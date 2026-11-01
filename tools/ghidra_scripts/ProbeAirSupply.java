// Execute the ROM transfer routine in Ghidra's isolated ARM emulator.
// No live emulator, save state, or gameplay input is touched.
import ghidra.app.script.GhidraScript;
import ghidra.app.emulator.EmulatorHelper;
import java.io.PrintWriter;
import java.math.BigInteger;
public class ProbeAirSupply extends GhidraScript {
 long ctx=0x03000480L, units=ctx+0x2760;
 void write(EmulatorHelper e,long a,int size,long v){e.writeMemoryValue(toAddr(a),size,v);}
 int read(EmulatorHelper e,long a){return e.readMemoryByte(toAddr(a))&255;}
 void check(boolean ok,String msg){if(!ok)throw new RuntimeException(msg);}
 void probe(PrintWriter out,int recipient,int fuel,int stock,boolean acted) throws Exception {
  currentProgram.getListing().clearCodeUnits(toAddr(0x08010000L),toAddr(0x08050000L),false);
  currentProgram.getProgramContext().setValue(currentProgram.getRegister("TMode"),toAddr(0x08010000L),toAddr(0x08050000L),BigInteger.ONE);
  EmulatorHelper e=new EmulatorHelper(currentProgram);
  try {
   e.setContextRegister(currentProgram.getRegister("TMode"),BigInteger.ONE);
   e.writeMemory(toAddr(0x03000000L),new byte[0x8000]);
   long global=currentProgram.getMemory().getInt(toAddr(0x08022484L))&0xffffffffL;
   long offset=currentProgram.getMemory().getInt(toAddr(0x08022488L))&0xffffffffL;
   long table=currentProgram.getMemory().getInt(toAddr(0x0802248cL))&0xffffffffL;
   write(e,global,4,ctx);long donor=ctx+offset,target=donor+24;
   write(e,donor,2,339);write(e,donor+6,1,4);write(e,donor+7,1,acted?1:0);
   write(e,target,2,recipient);write(e,target+4,1,fuel);write(e,target+6,1,2);
   for(int w=0;w<4;w++){
    int type=currentProgram.getMemory().getByte(toAddr(table+339*92+0x27+w*16))&255;
    write(e,donor+8+w,1,type==2?stock:0);
   }
   e.writeRegister("sp",0x03007e00L);e.writeRegister("lr",0x03007f01L);
   for(int r=4;r<=12;r++)e.writeRegister("r"+r,0);
   e.writeRegister("r0",0);e.writeRegister("r1",0);e.writeRegister("r2",target);
   e.writeRegister("r3",table+recipient*92);e.writeRegister("pc",0x08022388L);
   int steps=0;
   // Stop after resource writes, before the XP helper/return sequence.
   while(e.getExecutionAddress().getOffset()!=0x0802246cL && steps++<10000){
    if(e.getExecutionAddress().getOffset()==0x0802242eL){
     long a=e.readRegister("r0").longValue(),b=e.readRegister("r1").longValue();
     check(b!=0,"division by zero");e.writeRegister("r0",a/b);
     e.writeRegister("pc",0x08022432L);
    }else {e.setContextRegister(currentProgram.getRegister("TMode"),BigInteger.ONE);check(e.step(monitor),e.getLastError());}
   }
   check(steps<10000,"ROM transfer did not return");
   int after=read(e,target+4),remain=0;
   for(int w=0;w<4;w++)remain+=read(e,donor+8+w);
   check(read(e,target+7)==0 && read(e,donor+7)==(acted?1:0),"transfer changed action flags");
   check(read(e,target+6)==2,"supply must not heal recipient HP");
   check(after>=fuel && remain<=stock,"invalid resource accounting");
   if(stock==0)check(after==fuel,"empty donor created fuel");
   else check(after>fuel,"helicopter did not receive fuel");
   out.printf("recipient=%d fuel=%d->%d stock=%d->%d ammo=%d,%d,%d,%d donor_acted=%s recipient_acted=false hp=2 steps=%d%n",
    recipient,fuel,after,stock,remain,read(e,target+8),read(e,target+9),read(e,target+10),read(e,target+11),acted,steps);
  } finally {e.dispose();}
 }
 public void run() throws Exception {
  PrintWriter out=new PrintWriter(getScriptArgs()[0],"UTF-8");
  try {probe(out,149,5,40,false);probe(out,149,35,40,false);probe(out,168,5,40,true);probe(out,149,5,12,false);probe(out,149,5,0,false);out.println("PASS isolated ROM resource core 08022388..0802246C; division call replaced by integer division; XP/return not executed");}
  finally {out.close();}
 }
}
