/*
 * SPDX-License-Identifier: GPL-3.0-only
 * Read-only, feature-oriented PowerKeeper interface audit.
 * "present" means a DEX signature exists, NEVER that a hook is active.
 * No model/ROM/version gate, no APK rewrite, no process injection.
 */
package io.github.e3n.fcmu;

import java.io.File;
import java.io.InputStream;
import java.util.*;
import java.util.zip.*;
import com.android.tools.smali.dexlib2.*;
import com.android.tools.smali.dexlib2.iface.*;
import com.android.tools.smali.dexlib2.iface.instruction.*;
import com.android.tools.smali.dexlib2.iface.reference.*;

public final class PowerKeeperProbe {
 static final String[][] FEATURES = {
  {"pk.gms.observer", "GmsObserver", "", ""},
  {"pk.gms.alarm", "GmsObserver", "updateGmsAlarm", "(Z)V"},
  {"pk.gms.network", "GmsObserver", "updateGmsNetWork", "(Z)V"},
  {"pk.gms.wakelock", "GmsObserver", "updateGoogleReletivesWakelock", "(Z)V"},
  {"pk.gms.framework", "GmsObserver", "updateFrameworkGmsNetStatus", "(Z)Z"},
  {"pk.gms.binder_chain", "GmsObserver", "#binder", "updateGmsNetStatus|getGmsNetStatus"},
  {"pk.firewall.legacy", "NetdExecutor", "initGmsChain", ""},
  {"pk.firewall.dns", "NetdExecutor", "setGmsDnsBlockerState", "(IZ)V"},
  {"pk.firewall.standby", "NetdExecutor", "enableFirewallStandbyChain", "()V"},
  {"pk.doze.list", "GlobalFeatureConfigureHelper", "getDozeWhiteListApps", "(Landroid/os/Bundle;)Ljava/util/List;"}
 };
 static String clean(String value){
  return value==null?"none":value.replace('\t',' ').replace('\n',' ').replace('\r',' ');
 }
 static String key(String type,String simple){
  String suffix="/"+simple+";";
  return type!=null && type.toLowerCase(Locale.ROOT).contains("/powerkeeper/") &&
         type.endsWith(suffix) ? simple : "";
 }
 static String signature(Method m){
  StringBuilder b=new StringBuilder("(");
  for(CharSequence t:m.getParameterTypes())b.append(t);
  return b.append(')').append(m.getReturnType()).toString();
 }
 static String[] inspect(Iterable<? extends ClassDef> classes){
  String[] result=new String[FEATURES.length];
  Arrays.fill(result,"missing\tmethod or class absent in inspected DEX");
  for(ClassDef c:classes){
   String type=c.getType();
   for(int i=0;i<FEATURES.length;i++){
    String[] f=FEATURES[i];
    if(key(type,f[1]).isEmpty())continue;
    if(f[2].isEmpty()){result[i]="present\t"+clean(type);continue;}
    if(f[2].equals("#binder")){
     boolean write=false,read=false;
     for(Method method:c.getMethods()){
      if(!method.getName().equals("updateFrameworkGmsNetStatus"))continue;
      MethodImplementation impl=method.getImplementation();
      if(impl==null)continue;
      for(Instruction op:impl.getInstructions()){
       if(!(op instanceof ReferenceInstruction))continue;
       Reference ref=((ReferenceInstruction)op).getReference();
       if(!(ref instanceof MethodReference))continue;
       MethodReference target=(MethodReference)ref;
       if(!target.getDefiningClass().contains("greez"))continue;
       if(target.getName().equals("updateGmsNetStatus"))write=true;
       if(target.getName().equals("getGmsNetStatus"))read=true;
      }
     }
     if(write && read)result[i]="present\trequest plus feedback read observed";
     else if(write)result[i]="variant\trequest observed; feedback verification not identified";
     else result[i]="unknown\tno direct Greeze invoke found; OEM may use reflection/Binder proxies";
     continue;
    }
    for(Method method:c.getMethods()){
     if(!method.getName().equals(f[2]))continue;
     String actual=signature(method);
     if(f[3].isEmpty() || actual.equals(f[3])){
      result[i]="present\t"+clean(type)+"->"+f[2]+actual;
      break;
     }
     if(!result[i].startsWith("present\t"))
      result[i]="variant\t"+clean(type)+"->"+f[2]+actual+" (expected "+f[3]+")";
    }
   }
  }
  return result;
 }
 static void merge(String[] overall,String[] part){
  for(int i=0;i<overall.length;i++){
   if(part[i].startsWith("present\t"))overall[i]=part[i];
   else if(part[i].startsWith("variant\t") && !overall[i].startsWith("present\t"))overall[i]=part[i];
  }
 }
 static String[] scan(File file)throws Exception {
  MultiDexContainer<?> container=DexFileFactory.loadDexContainer(file,Opcodes.getDefault());
  List<ClassDef> classes=new ArrayList<ClassDef>();
  for(String entry:container.getDexEntryNames()){
   // A split APK may hold multiple classesN.dex entries. Load every one.
   if(!entry.matches("classes[0-9]*\\.dex"))continue;
   for(ClassDef c:container.getEntry(entry).getDexFile().getClasses()){
    if(c.getType().toLowerCase(Locale.ROOT).contains("/powerkeeper/"))classes.add(c);
   }
  }
  if(container.getDexEntryNames().isEmpty() || classes.isEmpty())
   throw new IllegalArgumentException("no PowerKeeper DEX classes");
  return inspect(classes);
 }
 static String report(String[] values,int successes,int failures){
  StringBuilder out=new StringBuilder();
  out.append("pk.apk\t").append(successes>0?"present": "unknown")
     .append("\tinspectable_apks=").append(successes).append(";failed=").append(failures).append('\n');
  for(int i=0;i<FEATURES.length;i++)
   out.append(FEATURES[i][0]).append('\t').append(values[i]).append('\n');
  out.append("pk.equivalence\tunverified\tsignature presence does not prove hook behavior, delivery or power\n");
  return out.toString();
 }
 public static void main(String[] args){
  String[] all=new String[FEATURES.length];
  Arrays.fill(all,"unknown\tno parseable PowerKeeper APK; core independent");
  int success=0,failed=0;
  for(String arg:args){
   try{
    File f=new File(arg);
    if(!f.isFile()||!f.canRead())throw new IllegalArgumentException("unreadable");
    String[] scanned=scan(f);
    if(success++==0)Arrays.fill(all,"missing\tmethod or class absent in inspected DEX");
    merge(all,scanned);
   }catch(Exception e){
    failed++;
    System.err.println("POWERKEEPER_SCAN_WARN "+clean(new File(arg).getName())+" "+clean(e.getMessage()));
   }
  }
  System.out.print(report(all,success,failed));
 }
}
