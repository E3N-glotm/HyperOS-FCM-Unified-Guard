/*
 * SPDX-License-Identifier: GPL-3.0-only
 * Static equivalents of the HyperOS FCM Live policies. No runtime framework.
 */
package io.github.e3n.fcmu;
import java.io.*;import java.util.*;import java.util.zip.*;
import com.android.tools.smali.dexlib2.*;
import com.android.tools.smali.dexlib2.builder.*;
import com.android.tools.smali.dexlib2.builder.instruction.*;
import com.android.tools.smali.dexlib2.dexbacked.*;
import com.android.tools.smali.dexlib2.iface.*;
import com.android.tools.smali.dexlib2.iface.instruction.*;
import com.android.tools.smali.dexlib2.immutable.*;
import com.android.tools.smali.dexlib2.immutable.reference.*;
import com.android.tools.smali.dexlib2.writer.pool.DexPool;
public final class Patcher {
 static final String P="Lio/github/e3n/fcmu/StaticPolicy;";
 static final String O="Ljava/lang/Object;",S="Ljava/lang/String;";
 static Map<String,Integer> counts=new TreeMap<String,Integer>();
 static final String[] SYSTEM_CLASSES={"Lcom/android/server/am/ActivityManagerService;","Lcom/android/server/am/ProcessRecord;","Lcom/android/server/am/BroadcastRecord;"};
 static final String[] OEM_CLASSES={"Lcom/miui/server/greeze/GreezeManagerService;","Lcom/miui/server/greeze/DomesticPolicyManager;","Lcom/android/server/am/BroadcastQueueModernStubImpl;","Lcom/android/server/am/ProcessPolicy;","Lcom/miui/server/greeze/power/ListAppsManager;","Lcom/miui/server/greeze/power/AwareResourceControl;"};
 static String[] requiredMethods(boolean system){return system?new String[]{"ams.broadcast"}:new String[]{"greeze.allow","greeze.defer","greeze.limit","domestic.defer","broadcast.autostart","lists.constructor","lists.whitelist","network.constructor","process.whitelist"};}
 static void requireTargets(boolean system){
  for(String key:requiredMethods(system)){
   int n=counts.containsKey(key)?counts.get(key):0;
   if(n<1||(!key.endsWith("constructor")&&n!=1))throw new IllegalStateException("Missing/ambiguous required capability "+key+" count="+n);
  }
 }
 static void instanceMethod(Method m){
  if((m.getAccessFlags()&8)!=0)throw new IllegalStateException("Expected instance method: "+m.getDefiningClass()+"->"+m.getName()+sig(m));
 }
 static void probeJar(File source,boolean system)throws Exception{
  Set<String> required=new HashSet<String>(Arrays.asList(system?SYSTEM_CLASSES:OEM_CLASSES));
  Set<String> seen=new HashSet<String>();
  MultiDexContainer<?> con=DexFileFactory.loadDexContainer(source,Opcodes.getDefault());
  if(con.getDexEntryNames().isEmpty())throw new IllegalStateException("Framework has no usable DEX: "+source);
  for(String entry:con.getDexEntryNames())for(ClassDef c:con.getEntry(entry).getDexFile().getClasses()){
   if(c.getType().equals(P))throw new IllegalStateException("Source already patched; disable the old static module and reboot before reinstalling");
   if(required.contains(c.getType())){
    if(!seen.add(c.getType()))throw new IllegalStateException("Duplicate framework class: "+c.getType());
    validateClass(c);
   }
   for(Method m:c.getMethods())rewrite(m);
  }
  required.removeAll(seen);
  if(!required.isEmpty())throw new IllegalStateException("Missing required classes: "+required);
  requireTargets(system);
 }
 static void preflight(File services,File oem)throws Exception{
  counts.clear();
  try{
   probeJar(services,true);probeJar(oem,false);
   for(Map.Entry<String,Integer> e:counts.entrySet())System.out.println("CAPABILITY "+e.getKey()+"="+e.getValue());
   System.out.println("CAPABILITY_OK: framework contract matched; no device or OS-build allowlist");
  }finally{counts.clear();}
 }
 static void requireField(ClassDef c,String name,String type){
  for(Field f:c.getFields())if(f.getName().equals(name)&&f.getType().equals(type))return;
  throw new IllegalStateException("Required field missing: "+c.getType()+"->"+name+":"+type);
 }
 static void validateClass(ClassDef c){
  String n=c.getType();
  if(n.equals("Lcom/miui/server/greeze/GreezeManagerService;"))requireField(c,"mGmsLimitEnabled","Z");
  if(n.equals("Lcom/miui/server/greeze/power/ListAppsManager;")){
   requireField(c,"SYSTEM_BLACK_LIST","Ljava/util/List;");
   requireField(c,"USE_DATA_WHITE_LIST","Ljava/util/Set;");
  }
  if(n.equals("Lcom/miui/server/greeze/power/AwareResourceControl;"))requireField(c,"mNoNetworkBlackUids","Ljava/util/List;");
  if(n.equals("Lcom/android/server/am/ActivityManagerService;")){
   requireField(c,"mContext","Landroid/content/Context;");
   boolean found=false;
   for(Method m:c.getMethods())if(m.getName().equals("getRecordForAppLOSP")&&sig(m).equals("(Landroid/app/IApplicationThread;)Lcom/android/server/am/ProcessRecord;"))found=true;
   if(!found)throw new IllegalStateException("AMS caller identity lookup unavailable");
  }
  if(n.equals("Lcom/android/server/am/ProcessRecord;"))requireField(c,"info","Landroid/content/pm/ApplicationInfo;");
  if(n.equals("Lcom/android/server/am/BroadcastRecord;")){
   requireField(c,"callerPackage","Ljava/lang/String;");
   requireField(c,"intent","Landroid/content/Intent;");
  }
 }
 static int params(Method m){int n=(m.getAccessFlags()&8)==0?1:0;for(CharSequence t:m.getParameterTypes())n+=("J".contentEquals(t)||"D".contentEquals(t))?2:1;return n;}
 static String sig(Method m){String s="(";for(CharSequence t:m.getParameterTypes())s+=t;return s+")"+m.getReturnType();}
 static void hit(String key){Integer n=counts.get(key);counts.put(key,n==null?1:n+1);}
 static ImmutableMethod copy(Method m,MethodImplementation impl){return new ImmutableMethod(m.getDefiningClass(),m.getName(),m.getParameters(),m.getReturnType(),m.getAccessFlags(),m.getAnnotations(),m.getHiddenApiRestrictions(),impl);}
 static ImmutableMethodReference ref(String name,String ret,String...args){return new ImmutableMethodReference(P,name,Arrays.asList(args),ret);}
 static void insertCall(MutableMethodImplementation x,int index,int first,int n,ImmutableMethodReference ref){x.addInstruction(index,new BuilderInstruction3rc(Opcode.INVOKE_STATIC_RANGE,first,n,ref));}
 static Method prefix(Method m,String key,ImmutableMethodReference helper,int n,boolean conditional,boolean result){
  instanceMethod(m);
  MutableMethodImplementation x=new MutableMethodImplementation(m.getImplementation());
  int first=x.getRegisterCount()-params(m);
  if(conditional&&first<1)throw new IllegalStateException("No local scratch register: "+key);
  Label orig=x.newLabelForIndex(0);
  insertCall(x,0,first,n,helper);
  if(conditional){
   x.addInstruction(1,new BuilderInstruction11x(Opcode.MOVE_RESULT,0));
   x.addInstruction(2,new BuilderInstruction21t(Opcode.IF_EQZ,0,orig));
   x.addInstruction(3,new BuilderInstruction11n(Opcode.CONST_4,0,result?1:0));
   x.addInstruction(4,new BuilderInstruction11x(Opcode.RETURN,0));
  }
  hit(key);return copy(m,x);
 }
 static Method constructor(Method m,String key,String helper){
  MutableMethodImplementation x=new MutableMethodImplementation(m.getImplementation());
  int first=x.getRegisterCount()-params(m);
  int matched=0;
  for(int i=x.getInstructions().size()-1;i>=0;i--)if(x.getInstructions().get(i).getOpcode()==Opcode.RETURN_VOID){
   Set<Label> labels=new HashSet<Label>(x.getInstructions().get(i).getLocation().getLabels());
   for(Label label:labels)x.getInstructions().get(i).getLocation().getLabels().remove(label);
   insertCall(x,i,first,1,ref(helper,"V",O));
   x.getInstructions().get(i).getLocation().getLabels().addAll(labels);matched++;
  }
  if(matched==0)throw new IllegalStateException("Constructor has no successful return: "+key);
  hit(key);return copy(m,x);
 }
 static Method rewrite(Method m){
  if(m.getImplementation()==null)return m;
  String c=m.getDefiningClass(),n=m.getName(),s=sig(m);
  if(c.equals("Lcom/miui/server/greeze/GreezeManagerService;")){
   if(n.equals("isAllowBroadcast")&&s.equals("(ILjava/lang/String;ILjava/lang/String;Ljava/lang/String;)Z"))
    return prefix(m,"greeze.allow",ref("allowGreeze","Z",O,"I",S,"I",S,S),6,true,true);
   if(n.equals("deferBroadcastForMiui")&&s.equals("(Ljava/lang/String;)Z"))
    return prefix(m,"greeze.defer",ref("skipGreezeDefer","Z",O,S),2,true,false);
   if(n.equals("triggerGMSLimitAction")&&s.equals("()V")){
    instanceMethod(m);
    MutableMethodImplementation x=new MutableMethodImplementation(m.getImplementation());
    int first=x.getRegisterCount()-1;if(first<1||first>15)throw new IllegalStateException("Unsupported limiter frame");
    x.addInstruction(0,new BuilderInstruction11n(Opcode.CONST_4,0,0));
    x.addInstruction(1,new BuilderInstruction22c(Opcode.IPUT_BOOLEAN,0,first,new ImmutableFieldReference(c,"mGmsLimitEnabled","Z")));
    hit("greeze.limit");return copy(m,x);
   }
  }
  if(c.equals("Lcom/miui/server/greeze/DomesticPolicyManager;")&&n.equals("deferBroadcast")&&s.equals("(Ljava/lang/String;)Z"))
   return prefix(m,"domestic.defer",ref("skipDomesticDefer","Z",O,S),2,true,false);
  if(c.equals("Lcom/android/server/am/BroadcastQueueModernStubImpl;")&&n.equals("checkApplicationAutoStart")&&s.equals("(Lcom/android/server/am/BroadcastQueue;Lcom/android/server/am/BroadcastRecord;Landroid/content/pm/ResolveInfo;)Z"))
   return prefix(m,"broadcast.autostart",ref("autoStart","Z",O,O,O,O),4,true,true);
  if(c.equals("Lcom/miui/server/greeze/power/ListAppsManager;")){
   if(n.equals("<init>"))return constructor(m,"lists.constructor","listConstruct");
   if(n.equals("isInWhiteList")&&s.equals("(Ljava/lang/String;)Z"))
    return prefix(m,"lists.whitelist",ref("listWhite","V",O,S),2,false,false);
  }
  if(c.equals("Lcom/miui/server/greeze/power/AwareResourceControl;")&&n.equals("<init>"))
   return constructor(m,"network.constructor","awareConstruct");
  if(c.equals("Lcom/android/server/am/ProcessPolicy;")&&n.equals("getWhiteList")&&s.equals("(I)Ljava/util/List;")){
   instanceMethod(m);
   MutableMethodImplementation x=new MutableMethodImplementation(m.getImplementation());int flag=x.getRegisterCount()-1;
   if(flag>15)throw new IllegalStateException("Unsupported ProcessPolicy registers");
   for(int i=x.getInstructions().size()-1;i>=0;i--)if(x.getInstructions().get(i).getOpcode()==Opcode.RETURN_OBJECT){
    int r=((OneRegisterInstruction)x.getInstructions().get(i)).getRegisterA();
    if(r>15)throw new IllegalStateException("Unsupported return register");
    Set<Label> labels=new HashSet<Label>(x.getInstructions().get(i).getLocation().getLabels());
    for(Label label:labels)x.getInstructions().get(i).getLocation().getLabels().remove(label);
    x.addInstruction(i,new BuilderInstruction35c(Opcode.INVOKE_STATIC,2,r,flag,0,0,0,ref("processWhite","Ljava/util/List;","Ljava/util/List;","I")));
    x.getInstructions().get(i).getLocation().getLabels().addAll(labels);
    x.addInstruction(i+1,new BuilderInstruction11x(Opcode.MOVE_RESULT_OBJECT,r));
   }
   hit("process.whitelist");return copy(m,x);
  }
  if(c.equals("Lcom/android/server/am/ActivityManagerService;")&&n.equals("broadcastIntentWithFeature")&&s.equals("(Landroid/app/IApplicationThread;Ljava/lang/String;Landroid/content/Intent;Ljava/lang/String;Landroid/content/IIntentReceiver;ILjava/lang/String;Landroid/os/Bundle;[Ljava/lang/String;[Ljava/lang/String;[Ljava/lang/String;ILandroid/os/Bundle;ZZI)I"))
   return prefix(m,"ams.broadcast",ref("broadcast","V",O,O,S,"Landroid/content/Intent;"),4,false,false);
  return m;
 }
 static byte[] dexBytes(Collection<? extends ClassDef> classes)throws Exception{
  DexPool pool=new DexPool(Opcodes.getDefault());for(ClassDef c:classes)pool.internClass(c);
  com.android.tools.smali.dexlib2.writer.io.MemoryDataStore data=new com.android.tools.smali.dexlib2.writer.io.MemoryDataStore();
  pool.writeTo(data);byte[] out=data.getData();data.close();return out;
 }
 static byte[] read(InputStream s)throws Exception{ByteArrayOutputStream o=new ByteArrayOutputStream();byte[] t=new byte[65536];int n;while((n=s.read(t))>0)o.write(t,0,n);return o.toByteArray();}
 static void patch(File source,File target,byte[] helper,boolean system)throws Exception{
  MultiDexContainer<? extends DexBackedDexFile> con=DexFileFactory.loadDexContainer(source,Opcodes.getDefault());
  Map<String,byte[]> replaced=new HashMap<String,byte[]>();
  for(String entry:con.getDexEntryNames()){
   DexFile d=con.getEntry(entry).getDexFile();List<ClassDef> cls=new ArrayList<ClassDef>();boolean changed=false;
   for(ClassDef c:d.getClasses()){
    validateClass(c);
    if(c.getType().equals(P))throw new IllegalStateException("Source already patched");
    List<Method> methods=new ArrayList<Method>();boolean cc=false;
    for(Method m:c.getMethods()){Method r=rewrite(m);methods.add(r);if(r!=m)cc=true;}
    if(cc){changed=true;cls.add(new ImmutableClassDef(c.getType(),c.getAccessFlags(),c.getSuperclass(),c.getInterfaces(),c.getSourceFile(),c.getAnnotations(),c.getFields(),methods));}else cls.add(c);
   }
   if(changed)replaced.put(entry,dexBytes(cls));
  }
  requireTargets(system);
  if(system){
   int next=con.getDexEntryNames().size()+1;String entry="classes"+next+".dex";
   try(ZipFile z=new ZipFile(source)){if(z.getEntry(entry)!=null)throw new IllegalStateException("Helper dex collision");}
   replaced.put(entry,helper);
  }
  // STORED DEX entries are four-byte aligned for ART mmap. Use a private
  // extra field rather than silently producing a malformed ZIP header.
  try(ZipFile z=new ZipFile(source);FileOutputStream file=new FileOutputStream(target);CountingOutputStream count=new CountingOutputStream(file);ZipOutputStream out=new ZipOutputStream(count)){
   Set<String> emitted=new HashSet<String>();List<String> names=new ArrayList<String>();Enumeration<? extends ZipEntry> en=z.entries();while(en.hasMoreElements())names.add(en.nextElement().getName());
   for(String n:replaced.keySet())if(!names.contains(n))names.add(n);
   for(String name:names){
    ZipEntry old=z.getEntry(name);byte[] data=replaced.get(name);if(data==null)data=read(z.getInputStream(old));
    ZipEntry e=new ZipEntry(name);e.setTime(315532800000L);
    CRC32 crc=new CRC32();crc.update(data);e.setMethod(ZipEntry.STORED);e.setSize(data.length);e.setCrc(crc.getValue());
    int pad=(int)((4-((count.n+30+name.getBytes("UTF-8").length+4)%4))%4);byte[] extra=new byte[4+pad];extra[0]=0x35;extra[1]=(byte)0xd9;extra[2]=(byte)pad;e.setExtra(extra);
    out.putNextEntry(e);out.write(data);out.closeEntry();emitted.add(name);
   }
  }
 }
 static final class CountingOutputStream extends FilterOutputStream{
  long n;CountingOutputStream(OutputStream out){super(out);}
  public void write(int b)throws IOException{out.write(b);n++;}
  public void write(byte[] b,int off,int len)throws IOException{out.write(b,off,len);n+=len;}
 }
 public static void main(String[] a)throws Exception{
  if(a.length==3&&a[0].equals("--probe")){preflight(new File(a[1]),new File(a[2]));return;}
  if(a.length!=4){System.err.println("Usage: Patcher services.jar miui-services.jar policy.dex output-directory");System.exit(2);}
  File out=new File(a[3]);if(!out.isDirectory()&&!out.mkdirs())throw new IOException("Cannot create staging");
  File services=new File(out,"services.jar.part"),miui=new File(out,"miui-services.jar.part");
  if(services.exists()||miui.exists()||new File(out,"services.jar").exists()||new File(out,"miui-services.jar").exists())throw new IOException("Require empty staging directory");
  try{
   preflight(new File(a[0]),new File(a[1]));
   byte[] helper=read(new FileInputStream(a[2]));
   if(helper.length<112||helper[0]!='d'||helper[1]!='e'||helper[2]!='x')throw new IOException("Invalid policy DEX");
   patch(new File(a[0]),services,helper,true);patch(new File(a[1]),miui,helper,false);
   // Reparse every generated DEX before accepting a transaction.
   for(File f:Arrays.asList(services,miui)){MultiDexContainer<?> c=DexFileFactory.loadDexContainer(f,Opcodes.getDefault());for(String e:c.getDexEntryNames())for(ClassDef cl:c.getEntry(e).getDexFile().getClasses())for(Method m:cl.getMethods())if(m.getImplementation()!=null)for(com.android.tools.smali.dexlib2.iface.instruction.Instruction i:m.getImplementation().getInstructions())i.getOpcode();}
   if(!services.renameTo(new File(out,"services.jar"))||!miui.renameTo(new File(out,"miui-services.jar")))throw new IOException("Atomic staging rename failed");
   for(Map.Entry<String,Integer> e:counts.entrySet())System.out.println("PATCH "+e.getKey()+"="+e.getValue());
   System.out.println("STAGED: bytecode generation/reparse passed; runtime equivalence still needs boot and message tests");
  }catch(Throwable e){services.delete();miui.delete();new File(out,"services.jar").delete();new File(out,"miui-services.jar").delete();throw e;}
 }
}
