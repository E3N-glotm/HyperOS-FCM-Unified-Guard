package io.github.e3n.fcmu;
import java.io.*;
import java.util.*;
import com.android.tools.smali.dexlib2.*;
import com.android.tools.smali.dexlib2.iface.*;
public final class Adaptive {
 static final String AM="Lcom/android/server/am/",GZ="Lcom/miui/server/greeze/";
 static final String[] KEYS={"ams.broadcast","greeze.allow","greeze.defer","greeze.limit","domestic.defer","broadcast.autostart","lists.constructor","lists.whitelist","network.constructor","process.whitelist"};
 static final class Plan {
  final Map<String,ClassDef> classes=new LinkedHashMap<String,ClassDef>();
  final Map<String,List<Method>> methods=new LinkedHashMap<String,List<Method>>();
  final Map<String,String> unavailable=new LinkedHashMap<String,String>();
  final Set<String> admitted=new HashSet<String>();
  boolean oemLoaded;
 }
 static void load(File source,Plan p)throws Exception{
  MultiDexContainer<?> jar=DexFileFactory.loadDexContainer(source,Opcodes.getDefault());
  if(jar.getDexEntryNames().isEmpty())throw new IOException("no DEX in "+source.getName());
  for(String entry:jar.getDexEntryNames())for(ClassDef c:jar.getEntry(entry).getDexFile().getClasses()){
   if(c.getType().equals(Patcher.P))throw new IOException("source already contains FCM policy");
   if(p.classes.put(c.getType(),c)!=null)throw new IOException("ambiguous class "+c.getType());
  }
 }
 static ClassDef cls(Plan p,String name){ClassDef c=p.classes.get(name);if(c==null)throw new IllegalStateException("missing class "+name);return c;}
 static void field(Plan p,String owner,String name,String type){Patcher.requireField(cls(p,owner),name,type);}
 static void dependencies(Plan p,String key){
  if(key.equals("ams.broadcast")){
   Patcher.validateClass(cls(p,AM+"ActivityManagerService;"));
   field(p,AM+"ProcessRecord;","info","Landroid/content/pm/ApplicationInfo;");
  }
  if(key.equals("broadcast.autostart"))Patcher.validateClass(cls(p,AM+"BroadcastRecord;"));
  if(key.equals("greeze.limit"))field(p,GZ+"GreezeManagerService;","mGmsLimitEnabled","Z");
  if(key.equals("lists.constructor"))field(p,GZ+"power/ListAppsManager;","SYSTEM_BLACK_LIST","Ljava/util/List;");
  if(key.equals("lists.whitelist"))field(p,GZ+"power/ListAppsManager;","USE_DATA_WHITE_LIST","Ljava/util/Set;");
  if(key.equals("network.constructor"))field(p,GZ+"power/AwareResourceControl;","mNoNetworkBlackUids","Ljava/util/List;");
 }
 static Plan plan(File services,File oem,Set<String> excluded)throws Exception{
  Plan p=new Plan();load(services,p);
  if(oem!=null){
   Plan other=new Plan();
   try{load(oem,other);for(String k:other.classes.keySet())if(p.classes.containsKey(k))throw new IOException("ambiguous OEM class "+k);p.classes.putAll(other.classes);p.oemLoaded=true;}
   catch(Exception e){System.out.println("OEM_UNAVAILABLE "+clean(e.getMessage()));}
  }
  Patcher.adaptiveMethods=null;
  for(ClassDef c:p.classes.values())for(Method m:c.getMethods()){
   Patcher.counts.clear();
   try{
    if(Patcher.rewrite(m)!=m)for(String key:Patcher.counts.keySet()){
     List<Method> list=p.methods.get(key);if(list==null)p.methods.put(key,list=new ArrayList<Method>());list.add(m);
    }
   }catch(RuntimeException ex){
    // Signature/frame mismatches are a missing capability, never an install failure.
   }
  }
  Patcher.counts.clear();
  for(String key:KEYS){
   try{
    if(excluded.contains(key))throw new IllegalStateException("ART check unavailable on this ROM");
    List<Method> ms=p.methods.get(key);
    if(ms==null||ms.isEmpty())throw new IllegalStateException("matching implementation unavailable");
    if(!key.endsWith("constructor")&&ms.size()!=1)throw new IllegalStateException("ambiguous target methods");
    dependencies(p,key);
    for(Method m:ms)p.admitted.add(Patcher.methodId(m));
   }catch(RuntimeException ex){p.unavailable.put(key,ex.getMessage());}
  }
  return p;
 }
 static String clean(String s){return s==null?"unknown":s.replace('\t',' ').replace('\n',' ').replace('\r',' ');}
 static void writePlan(Plan p,File f)throws Exception{
  try(PrintWriter out=new PrintWriter(new OutputStreamWriter(new FileOutputStream(f),"UTF-8"))){
   for(String key:KEYS)out.println(key+"\t"+(p.unavailable.containsKey(key)?"unavailable\t"+clean(p.unavailable.get(key)):"ready\tgenerated and pending runtime verification"));
  }
 }
 static void reparse(File f)throws Exception{
  MultiDexContainer<?> c=DexFileFactory.loadDexContainer(f,Opcodes.getDefault());
  for(String e:c.getDexEntryNames())for(ClassDef cl:c.getEntry(e).getDexFile().getClasses())for(Method m:cl.getMethods())if(m.getImplementation()!=null)for(com.android.tools.smali.dexlib2.iface.instruction.Instruction i:m.getImplementation().getInstructions())i.getOpcode();
 }
 public static void main(String[] args)throws Exception{
  if(args.length<4||args.length>5)throw new IllegalArgumentException("Adaptive services.jar OEM.jar|- policy.dex output-dir [excluded,csv]");
  File services=new File(args[0]),oem=args[1].equals("-")?null:new File(args[1]),out=new File(args[3]);
  if(!out.isDirectory()&&!out.mkdirs())throw new IOException("cannot create staging");
  Set<String> excluded=new HashSet<String>();if(args.length==5)excluded.addAll(Arrays.asList(args[4].split(",")));
  Plan p=plan(services,oem,excluded);writePlan(p,new File(out,"capabilities.tsv"));
  if(p.admitted.isEmpty())throw new IllegalStateException("no compatible static features; core-only mode remains available");
  byte[] helper;try(InputStream in=new FileInputStream(args[2])){helper=Patcher.read(in);}
  Patcher.adaptiveMethods=p.admitted;Patcher.counts.clear();
  try{
   File s=new File(out,"services.jar");if(s.exists())throw new IOException("staging must be fresh");
   Patcher.patch(services,s,helper,true);reparse(s);
   if(oem!=null&&p.oemLoaded){File m=new File(out,"miui-services.jar");Patcher.patch(oem,m,helper,false);reparse(m);}
   System.out.println("ADAPTIVE_OK features="+(KEYS.length-p.unavailable.size())+"/"+KEYS.length);
  }finally{Patcher.adaptiveMethods=null;Patcher.counts.clear();}
 }
}
