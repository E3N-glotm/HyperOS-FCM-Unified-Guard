package io.github.e3n.fcmu;
import java.util.*;
import com.android.tools.smali.dexlib2.*;
import com.android.tools.smali.dexlib2.iface.*;
import com.android.tools.smali.dexlib2.iface.instruction.*;
import com.android.tools.smali.dexlib2.immutable.*;
import com.android.tools.smali.dexlib2.immutable.instruction.*;
public final class PatcherTest {
 static void assertBranchRunsPolicy(Method m){
  Map<Integer,Instruction> code=new HashMap<Integer,Instruction>();int p=0,target=-1;
  for(Instruction i:m.getImplementation().getInstructions()){
   code.put(p,i);if(i.getOpcode()==Opcode.IF_EQZ)target=p+((OffsetInstruction)i).getCodeOffset();p+=i.getCodeUnits();
  }
  if(target<0||code.get(target).getOpcode()!=Opcode.INVOKE_STATIC_RANGE&&code.get(target).getOpcode()!=Opcode.INVOKE_STATIC)
   throw new AssertionError("A branch bypasses the injected exit policy");
 }
 public static void main(String[] args){
  List<Instruction> init=Arrays.<Instruction>asList(new ImmutableInstruction11n(Opcode.CONST_4,0,0),new ImmutableInstruction21t(Opcode.IF_EQZ,0,3),new ImmutableInstruction10x(Opcode.NOP),new ImmutableInstruction10x(Opcode.RETURN_VOID));
  Method ctor=new ImmutableMethod("LTest;","<init>",Collections.<MethodParameter>emptyList(),"V",65537,null,null,new ImmutableMethodImplementation(2,init,null,null));
  assertBranchRunsPolicy(Patcher.constructor(ctor,"fixture.constructor","listConstruct"));
  List<Instruction> get=Arrays.<Instruction>asList(new ImmutableInstruction11n(Opcode.CONST_4,0,0),new ImmutableInstruction21t(Opcode.IF_EQZ,2,3),new ImmutableInstruction10x(Opcode.NOP),new ImmutableInstruction11x(Opcode.RETURN_OBJECT,0));
  MethodParameter flag=new ImmutableMethodParameter("I",null,"flags");
  Method wl=new ImmutableMethod("Lcom/android/server/am/ProcessPolicy;","getWhiteList",Arrays.asList(flag),"Ljava/util/List;",1,null,null,new ImmutableMethodImplementation(3,get,null,null));
  assertBranchRunsPolicy(Patcher.rewrite(wl));
  Method unrelated=new ImmutableMethod("Lunrelated;","deferBroadcast",Collections.<MethodParameter>emptyList(),"V",1,null,null,new ImmutableMethodImplementation(1,Arrays.<Instruction>asList(new ImmutableInstruction10x(Opcode.RETURN_VOID)),null,null));
  if(Patcher.rewrite(unrelated)!=unrelated)throw new AssertionError("Unrelated method modified");
  boolean rejected=false;
  try{Patcher.validateClass(new ImmutableClassDef("Lcom/miui/server/greeze/GreezeManagerService;",1,"Ljava/lang/Object;",null,null,null,Collections.<Field>emptyList(),Collections.<Method>emptyList()));}
  catch(IllegalStateException expected){rejected=true;}
  if(!rejected)throw new AssertionError("Missing required OEM field was accepted");
  System.out.println("PASS PatcherTest: exit branch targets, unrelated method, missing-field rejection");
 }
}
