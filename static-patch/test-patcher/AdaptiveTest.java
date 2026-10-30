package io.github.e3n.fcmu;
import java.io.*;
import java.util.*;
import com.android.tools.smali.dexlib2.iface.*;
import com.android.tools.smali.dexlib2.immutable.*;
public final class AdaptiveTest {
 static void check(boolean ok,String message){if(!ok)throw new AssertionError(message);}
 public static void main(String[] args)throws Exception{
  File services=File.createTempFile("adaptive-services-",".jar"),oem=File.createTempFile("adaptive-oem-",".jar");
  try{
   Map<String,ClassDef> f=CapabilityTest.fixture();CapabilityTest.jars(services,oem,f,false);
   Adaptive.Plan full=Adaptive.plan(services,oem,Collections.<String>emptySet());check(full.unavailable.isEmpty(),"complete plan must keep ten features");
   Adaptive.Plan base=Adaptive.plan(services,null,Collections.<String>emptySet());check(base.unavailable.size()==9&&!base.unavailable.containsKey("ams.broadcast"),"OEM absence must retain AMS capability");
   String c="Lcom/miui/server/greeze/GreezeManagerService;";ClassDef old=f.get(c);
   f.put(c,new ImmutableClassDef(c,1,"Ljava/lang/Object;",null,null,null,Collections.<Field>emptyList(),old.getMethods()));
   CapabilityTest.jars(services,oem,f,false);
   Adaptive.Plan partial=Adaptive.plan(services,oem,Collections.<String>emptySet());
   check(partial.unavailable.size()==1&&partial.unavailable.containsKey("greeze.limit"),"missing limiter field must not suppress unrelated capabilities");
   // Regression: the old LSPosed module supports two OEM field naming
   // conventions. Both must be admitted by static adaptation.
   Map<String,ClassDef> aliases=CapabilityTest.fixture();
   String list="Lcom/miui/server/greeze/power/ListAppsManager;";
   ClassDef li=aliases.get(list);
   aliases.put(list,new ImmutableClassDef(list,1,"Ljava/lang/Object;",null,null,null,
       Arrays.<Field>asList(CapabilityTest.field(list,"mSystemBlackList","Ljava/util/List;"),
           CapabilityTest.field(list,"mUseDataWhiteList","Ljava/util/Set;")),li.getMethods()));
   String g="Lcom/miui/server/greeze/GreezeManagerService;";
   ClassDef gr=aliases.get(g);
   List<Method> altered=new ArrayList<Method>();
   for(Method m:gr.getMethods())
    if(m.getName().equals("triggerGMSLimitAction"))
     altered.add(CapabilityTest.method(g,"triggerGMSLimitAction","V","Z"));
    else altered.add(m);
   aliases.put(g,new ImmutableClassDef(g,1,"Ljava/lang/Object;",null,null,null,
       Collections.<Field>emptyList(),altered));
   CapabilityTest.jars(services,oem,aliases,false);
   Adaptive.Plan aliasPlan=Adaptive.plan(services,oem,Collections.<String>emptySet());
   check(aliasPlan.unavailable.isEmpty(),"legacy field aliases and boolean limiter must preserve 10/10");
   CapabilityTest.jars(services,oem,CapabilityTest.fixture(),false);
   Adaptive.Plan excluded=Adaptive.plan(services,oem,new HashSet<String>(Arrays.asList("ams.broadcast")));
   check(excluded.unavailable.size()==1&&excluded.unavailable.containsKey("ams.broadcast"),"failed runtime API must disable only its feature");
   try(FileOutputStream out=new FileOutputStream(oem)){out.write(new byte[]{1,2,3});}
   Adaptive.Plan corrupt=Adaptive.plan(services,oem,Collections.<String>emptySet());
   check(!corrupt.oemLoaded&&!corrupt.unavailable.containsKey("ams.broadcast"),"unreadable OEM DEX must keep service-only adaptation");
   System.out.println("PASS AdaptiveTest: full/partial/OEM-absent/ART-excluded/corrupt-OEM capabilities remain independent");
  }finally{services.delete();oem.delete();}
 }
}
