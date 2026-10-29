package io.github.e3n.fcmu;
import java.io.*;
import java.util.*;
import java.util.zip.*;
import com.android.tools.smali.dexlib2.*;
import com.android.tools.smali.dexlib2.iface.*;
import com.android.tools.smali.dexlib2.iface.instruction.*;
import com.android.tools.smali.dexlib2.iface.reference.*;
public final class Inspect {
 public static void main(String[] a) throws Exception {
  MultiDexContainer<?> c=DexFileFactory.loadDexContainer(new File(a[0]),Opcodes.getDefault());
  String[] targets=Arrays.copyOfRange(a,1,a.length);
  for(String entry:c.getDexEntryNames()) {
   DexFile dex=c.getEntry(entry).getDexFile();
   for(ClassDef cl:dex.getClasses()) {
    boolean take=false;
    for(String t:targets) if(cl.getType().contains(t)) take=true;
    if(!take)continue;
    System.out.println("CLASS "+entry+" "+cl.getType()+" extends "+cl.getSuperclass());
    for(Field f:cl.getFields())System.out.println("FIELD "+f.getName()+":"+f.getType()+" = "+f.getInitialValue());
    for(Method m:cl.getMethods()){
     System.out.println("METHOD "+m.getName()+m.getParameterTypes()+m.getReturnType()+" flags="+m.getAccessFlags());
     if(m.getImplementation()==null)continue;
     MethodImplementation impl=m.getImplementation();
     System.out.println("REGS "+impl.getRegisterCount());
     int pc=0;
     for(Instruction i:impl.getInstructions()) {
      String regs="";
      if(i instanceof RegisterRangeInstruction) {
       RegisterRangeInstruction r=(RegisterRangeInstruction)i; regs=" v"+r.getStartRegister()+".."+(r.getStartRegister()+r.getRegisterCount()-1);
      } else if(i instanceof FiveRegisterInstruction) {
       FiveRegisterInstruction r=(FiveRegisterInstruction)i;regs=" count="+r.getRegisterCount()+" "+r.getRegisterC()+","+r.getRegisterD()+","+r.getRegisterE()+","+r.getRegisterF()+","+r.getRegisterG();
      } else if(i instanceof ThreeRegisterInstruction) {
       ThreeRegisterInstruction r=(ThreeRegisterInstruction)i;regs=" v"+r.getRegisterA()+",v"+r.getRegisterB()+",v"+r.getRegisterC();
      } else if(i instanceof TwoRegisterInstruction) {
       TwoRegisterInstruction r=(TwoRegisterInstruction)i;regs=" v"+r.getRegisterA()+",v"+r.getRegisterB();
      } else if(i instanceof OneRegisterInstruction)regs=" v"+((OneRegisterInstruction)i).getRegisterA();
      if(i instanceof NarrowLiteralInstruction)regs+=" #"+((NarrowLiteralInstruction)i).getNarrowLiteral();
      if(i instanceof OffsetInstruction)regs+=" ->"+(pc+((OffsetInstruction)i).getCodeOffset());
      if(i instanceof ReferenceInstruction)regs+=" "+((ReferenceInstruction)i).getReference();
      System.out.println(String.format("%04x %s%s",pc,i.getOpcode().name,regs));
      pc+=i.getCodeUnits();
     }
    }
   }
  }
 }
}
