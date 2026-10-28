package io.github.e3n.fcmu;
import java.io.*;
import java.util.*;
import java.util.zip.*;
import com.android.tools.smali.dexlib2.*;
import com.android.tools.smali.dexlib2.iface.*;
import com.android.tools.smali.dexlib2.iface.instruction.*;
import com.android.tools.smali.dexlib2.immutable.*;
import com.android.tools.smali.dexlib2.immutable.instruction.*;
public final class CapabilityTest {
 static final String AM="Lcom/android/server/am/",GZ="Lcom/miui/server/greeze/";
 static Method method(String owner,String name,String ret,String...types){
  List<MethodParameter> args=new ArrayList<MethodParameter>();int slots=1;
  for(String t:types){args.add(new ImmutableMethodParameter(t,null,null));slots+=(t.equals("J")||t.equals("D"))?2:1;}
  List<Instruction> body=new ArrayList<Instruction>();
  if(ret.equals("V"))body.add(new ImmutableInstruction10x(Opcode.RETURN_VOID));
  else{body.add(new ImmutableInstruction11n(Opcode.CONST_4,0,0));body.add(new ImmutableInstruction11x(ret.startsWith("L")?Opcode.RETURN_OBJECT:Opcode.RETURN,0));}
  return new ImmutableMethod(owner,name,args,ret,name.equals("<init>")?65537:1,null,null,new ImmutableMethodImplementation(slots+2,body,null,null));
 }
 static Field field(String owner,String name,String type){return new ImmutableField(owner,name,type,2,null,null,null);}
 static ClassDef cls(String type,List<Field> fields,Method...methods){return new ImmutableClassDef(type,1,"Ljava/lang/Object;",null,null,null,fields,Arrays.asList(methods));}
 static Map<String,ClassDef> fixture(){
  Map<String,ClassDef> r=new LinkedHashMap<String,ClassDef>();String c=AM+"ActivityManagerService;";
  r.put(c,cls(c,Arrays.asList(field(c,"mContext","Landroid/content/Context;")),
   method(c,"getRecordForAppLOSP",AM+"ProcessRecord;","Landroid/app/IApplicationThread;"),
   method(c,"broadcastIntentWithFeature","I","Landroid/app/IApplicationThread;","Ljava/lang/String;","Landroid/content/Intent;","Ljava/lang/String;","Landroid/content/IIntentReceiver;","I","Ljava/lang/String;","Landroid/os/Bundle;","[Ljava/lang/String;","[Ljava/lang/String;","[Ljava/lang/String;","I","Landroid/os/Bundle;","Z","Z","I")));
  c=AM+"ProcessRecord;";r.put(c,cls(c,Arrays.asList(field(c,"info","Landroid/content/pm/ApplicationInfo;"))));
  c=AM+"BroadcastRecord;";r.put(c,cls(c,Arrays.asList(field(c,"callerPackage","Ljava/lang/String;"),field(c,"intent","Landroid/content/Intent;"))));
  c=GZ+"GreezeManagerService;";r.put(c,cls(c,Arrays.asList(field(c,"mGmsLimitEnabled","Z")),
   method(c,"isAllowBroadcast","Z","I","Ljava/lang/String;","I","Ljava/lang/String;","Ljava/lang/String;"),
   method(c,"deferBroadcastForMiui","Z","Ljava/lang/String;"),method(c,"triggerGMSLimitAction","V")));
  c=GZ+"DomesticPolicyManager;";r.put(c,cls(c,Collections.<Field>emptyList(),method(c,"deferBroadcast","Z","Ljava/lang/String;")));
  c=AM+"BroadcastQueueModernStubImpl;";r.put(c,cls(c,Collections.<Field>emptyList(),method(c,"checkApplicationAutoStart","Z",AM+"BroadcastQueue;",AM+"BroadcastRecord;","Landroid/content/pm/ResolveInfo;")));
  c=AM+"ProcessPolicy;";r.put(c,cls(c,Collections.<Field>emptyList(),method(c,"getWhiteList","Ljava/util/List;","I")));
  c=GZ+"power/ListAppsManager;";r.put(c,cls(c,Arrays.asList(field(c,"SYSTEM_BLACK_LIST","Ljava/util/List;"),field(c,"USE_DATA_WHITE_LIST","Ljava/util/Set;")),method(c,"<init>","V"),method(c,"isInWhiteList","Z","Ljava/lang/String;")));
  c=GZ+"power/AwareResourceControl;";r.put(c,cls(c,Arrays.asList(field(c,"mNoNetworkBlackUids","Ljava/util/List;")),method(c,"<init>","V")));
  return r;
 }
 static void jars(File services,File oem,Map<String,ClassDef> classes,boolean duplicate)throws Exception{
  for(boolean system:new boolean[]{true,false}){
   List<ClassDef> defs=new ArrayList<ClassDef>();Set<String> names=new HashSet<String>(Arrays.asList(Patcher.SYSTEM_CLASSES));
   for(ClassDef c:classes.values())if(names.contains(c.getType())==system)defs.add(c);
   try(ZipOutputStream z=new ZipOutputStream(new FileOutputStream(system?services:oem))){
    z.putNextEntry(new ZipEntry("classes.dex"));z.write(Patcher.dexBytes(defs));z.closeEntry();
    if(duplicate&&!system){z.putNextEntry(new ZipEntry("classes2.dex"));z.write(Patcher.dexBytes(Arrays.asList(classes.get(GZ+"GreezeManagerService;"))));z.closeEntry();}
   }
  }
 }
 public static void main(String[] args)throws Exception{
  File services=File.createTempFile("fcmu-services-",".jar"),oem=File.createTempFile("fcmu-oem-",".jar");int rejected=0;
  try{
   jars(services,oem,fixture(),false);Patcher.preflight(services,oem);
   for(String scenario:Arrays.asList("missing-class","wrong-signature","missing-field","static-method","duplicate-class","already-patched")){
    Map<String,ClassDef> r=fixture();String c=GZ+"GreezeManagerService;";
    if(scenario.equals("missing-class"))r.remove(AM+"BroadcastRecord;");
    if(scenario.equals("wrong-signature"))r.put(AM+"BroadcastQueueModernStubImpl;",cls(AM+"BroadcastQueueModernStubImpl;",Collections.<Field>emptyList(),method(AM+"BroadcastQueueModernStubImpl;","checkApplicationAutoStart","Z","I")));
    if(scenario.equals("missing-field"))r.put(c,cls(c,Collections.<Field>emptyList()));
    if(scenario.equals("static-method")){
     ClassDef old=r.get(c);List<Method> methods=new ArrayList<Method>();
     for(Method m:old.getMethods())methods.add(m.getName().equals("deferBroadcastForMiui")?new ImmutableMethod(c,m.getName(),m.getParameters(),m.getReturnType(),9,null,null,m.getImplementation()):m);
     r.put(c,new ImmutableClassDef(c,1,"Ljava/lang/Object;",null,null,null,old.getFields(),methods));
    }
    if(scenario.equals("already-patched"))r.put(Patcher.P,cls(Patcher.P,Collections.<Field>emptyList()));
    jars(services,oem,r,scenario.equals("duplicate-class"));
    try{Patcher.preflight(services,oem);throw new AssertionError("Accepted incompatible fixture: "+scenario);}
    catch(IllegalStateException expected){rejected++;System.out.println("REJECT_OK "+scenario+": "+expected.getMessage());}
   }
   if(rejected!=6)throw new AssertionError("Incomplete rejection coverage");
   System.out.println("PASS CapabilityTest: complete contract accepted; six incompatible contracts rejected without output patches");
  }finally{services.delete();oem.delete();}
 }
}
