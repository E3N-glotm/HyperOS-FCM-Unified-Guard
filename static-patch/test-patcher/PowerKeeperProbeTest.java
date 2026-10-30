package io.github.e3n.fcmu;
import java.io.*;
import java.util.*;
import java.util.zip.*;
import com.android.tools.smali.dexlib2.iface.*;
import com.android.tools.smali.dexlib2.immutable.*;
public final class PowerKeeperProbeTest {
 static void check(boolean b,String msg){if(!b)throw new AssertionError(msg);}
 static ClassDef owner(String name,Method...methods){
  return new ImmutableClassDef("Lcom/miui/powerkeeper/utils/"+name+";",1,"Ljava/lang/Object;",null,null,null,
   Collections.<Field>emptyList(),Arrays.asList(methods));
 }
 static String state(String[] values,int index){return values[index].split("\t",2)[0];}
 public static void main(String[] args)throws Exception{
  String o="Lcom/miui/powerkeeper/utils/GmsObserver;";
  ClassDef old=owner("GmsObserver",
    CapabilityTest.method(o,"updateGmsAlarm","V","Z"),
    CapabilityTest.method(o,"updateGmsNetWork","V","Z"),
    CapabilityTest.method(o,"updateGoogleReletivesWakelock","V","Z"));
  String[] oldResult=PowerKeeperProbe.inspect(Arrays.asList(old));
  check(state(oldResult,0).equals("present"),"legacy observer missing");
  check(state(oldResult,1).equals("present")&&state(oldResult,2).equals("present")&&state(oldResult,3).equals("present"),"legacy hooks missing");
  check(state(oldResult,4).equals("missing"),"missing new hook incorrectly present");
  ClassDef modern=owner("GmsObserver",CapabilityTest.method(o,"updateFrameworkGmsNetStatus","Z","Z"),CapabilityTest.method(o,"updateGmsAlarm","V","I"));
  String[] newResult=PowerKeeperProbe.inspect(Arrays.asList(modern));
  check(state(newResult,4).equals("present"),"modern entry absent");
  check(state(newResult,1).equals("variant"),"different overload must not count as present");
  check(state(newResult,2).equals("missing"),"method absence incorrectly present");
  String doze="Lcom/xiaomi/powerkeeper/provider/GlobalFeatureConfigureHelper;";
  ClassDef another=new ImmutableClassDef(doze,1,"Ljava/lang/Object;",null,null,null,
    Collections.<Field>emptyList(),Arrays.asList(CapabilityTest.method(doze,"getDozeWhiteListApps","Ljava/util/List;","Landroid/os/Bundle;")));
  check(state(PowerKeeperProbe.inspect(Arrays.asList(another)),9).equals("present"),"vendor package name unexpectedly gated");
  File apk=File.createTempFile("fcmu-pk-", ".apk");
  try{
   try(ZipOutputStream zip=new ZipOutputStream(new FileOutputStream(apk))){
    zip.putNextEntry(new ZipEntry("classes.dex"));zip.write(Patcher.dexBytes(Arrays.asList(old)));zip.closeEntry();
    zip.putNextEntry(new ZipEntry("classes2.dex"));zip.write(Patcher.dexBytes(Arrays.asList(another)));zip.closeEntry();
   }
   String[] split=PowerKeeperProbe.scan(apk);
   check(state(split,1).equals("present")&&state(split,9).equals("present"),"multi-DEX scan lost a feature");
  }finally{apk.delete();}
  String[] none=PowerKeeperProbe.inspect(Collections.<ClassDef>emptyList());
  check(PowerKeeperProbe.report(none,0,1).contains("pk.apk\tunknown"),"failed APK must stay unknown");
  check(PowerKeeperProbe.report(newResult,1,0).contains("pk.equivalence\tunverified"),"scan should not claim equivalence");
  System.out.println("PASS PowerKeeperProbeTest: legacy/modern/method variant/missing vendor prefix multidex");
 }
}
