package io.github.e3n.fcmu;
import java.util.*;
import java.io.*;
import java.util.zip.*;
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
 public static void main(String[] args)throws Exception{
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
  // Forced index-overflow fallback must retain every class exactly once.
  ClassDef unchanged=new ImmutableClassDef("LTest/Original;",1,"Ljava/lang/Object;",null,null,null,
      Collections.<Field>emptyList(),Collections.<Method>emptyList());
  ClassDef modified=new ImmutableClassDef("LTest/Patched;",1,"Ljava/lang/Object;",null,null,null,
      Collections.<Field>emptyList(),Collections.<Method>emptyList());
  Map<String,byte[]> split=new HashMap<String,byte[]>();
  Patcher.writeChangedDex("classes.dex",Arrays.asList(unchanged,modified),Arrays.asList(unchanged),
      Arrays.asList(modified),split,new HashSet<String>(Arrays.asList("classes.dex")),new int[]{2},true);
  if(split.size()!=2||!split.containsKey("classes.dex")||!split.containsKey("classes2.dex"))
   throw new AssertionError("Split fallback did not preserve source and extra DEX");
  File fixture=File.createTempFile("dex-split-", ".jar");
  try{
   try(ZipOutputStream zip=new ZipOutputStream(new FileOutputStream(fixture))){
    for(String dex:split.keySet()){
     zip.putNextEntry(new ZipEntry(dex));zip.write(split.get(dex));zip.closeEntry();
    }
   }
   MultiDexContainer<?> con=DexFileFactory.loadDexContainer(fixture,Opcodes.getDefault());
   Set<String> types=new HashSet<String>();
   for(String dex:con.getDexEntryNames())for(ClassDef cl:con.getEntry(dex).getDexFile().getClasses()){
    if(!types.add(cl.getType()))throw new AssertionError("Duplicated source class");
   }
   if(!types.contains("LTest/Original;")||!types.contains("LTest/Patched;")||types.size()!=2)
    throw new AssertionError("Split DEX dropped original or modified class");
  }finally{fixture.delete();}
  if(!Patcher.indexOverflow(new RuntimeException("Dex writer",new IllegalStateException(
      "Unsigned short value out of range: 65536"))))
   throw new AssertionError("Nested dexlib2 overflow was not recognized");
  System.out.println("PASS PatcherTest: branch targets, missing-field rejection, DEX split fallback");
 }
}
