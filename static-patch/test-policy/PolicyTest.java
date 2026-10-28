import io.github.e3n.fcmu.StaticPolicy;
import java.util.*;import android.content.*;import android.content.pm.*;import android.app.*;import android.os.*;
public class PolicyTest {
 static int checks;
 static void ok(boolean b,String m){checks++;if(!b)throw new AssertionError(m);}
 public static class Greeze {public String getPackageNameFromUid(int uid){return uid==42?StaticPolicy.GMS:"other";}}
 public static class Lists {public static List<String> SYSTEM_BLACK_LIST=new ArrayList<String>(Arrays.asList("other",StaticPolicy.GMS));public static Set<String> USE_DATA_WHITE_LIST=new HashSet<String>();}
 public static class Aware {public List<String> mNoNetworkBlackUids=new ArrayList<String>(Arrays.asList("other",StaticPolicy.GMS));}
 public static class Record {public String callerPackage;public Intent intent;Record(String p,Intent i){callerPackage=p;intent=i;}}
 public static class Proc {public ApplicationInfo info=new ApplicationInfo();}
 public static class ThreadStub implements IApplicationThread {}
 public static class AMS {public Context mContext=new Context();public Proc p=new Proc();public Proc getRecordForAppLOSP(IApplicationThread t){return p;}}
 public static void main(String[] args){
  Greeze g=new Greeze();String receive=StaticPolicy.RECEIVE;
  ok(StaticPolicy.allowGreeze(g,1,StaticPolicy.GMS,12,"target",receive),"GMS receive");
  ok(!StaticPolicy.allowGreeze(g,1,"fake",12,"target",receive),"other origin preserves OEM");
  ok(!StaticPolicy.allowGreeze(g,1,StaticPolicy.GMS,42,StaticPolicy.GMS,"other.action"),"unrelated broadcast unchanged");
  for(String e:Arrays.asList("com.google.android.intent.action.GCM_RECONNECT","com.google.android.gcm.DISCONNECTED","com.google.android.gcm.CONNECTED","com.google.android.gms.gcm.HEARTBEAT_ALARM")){
   ok(StaticPolicy.allowGreeze(g,1,"android",42,"fallback",e),"FCM event allow");
   ok(!StaticPolicy.allowGreeze(g,1,"android",13,"other",e),"event for another receiver stays OEM");
   ok(StaticPolicy.skipGreezeDefer(g,e),"greeze defer");
   ok(StaticPolicy.skipDomesticDefer(g,e),"domestic defer");
  }
  ok(!StaticPolicy.skipGreezeDefer(g,"other"),"other defer preserved");
  ok(StaticPolicy.skipDomesticDefer(g,receive),"domestic c2dm");
  ok(!StaticPolicy.autoStart(null,null,new Record("fake",new Intent(receive)),null),"fake sender not exempt");
  ok(StaticPolicy.autoStart(null,null,new Record(StaticPolicy.GMS,new Intent(receive)),null),"legitimate autostart");
  ok(!StaticPolicy.autoStart(null,null,new Record(StaticPolicy.GMS,new Intent("other")),null),"other action not exempt");
  List<String> original=Collections.unmodifiableList(Arrays.asList("other"));
  ok(StaticPolicy.processWhite(original,0)==original,"unselected flags preserve list");
  List<?> adjusted=StaticPolicy.processWhite(original,1);
  ok(adjusted.contains("other")&&adjusted.contains(StaticPolicy.GMS)&&adjusted.contains(StaticPolicy.GMS+".persistent"),"GMS entries added");
  ok(original.size()==1,"immutable original unmodified");
  Lists l=new Lists();StaticPolicy.listConstruct(l);StaticPolicy.listWhite(l,"x");
  ok(Lists.SYSTEM_BLACK_LIST.equals(Arrays.asList("other")),"only GMS removed from blacklist");
  ok(Lists.USE_DATA_WHITE_LIST.contains(StaticPolicy.GMS),"GMS data allowlist");
  Aware a=new Aware();StaticPolicy.awareConstruct(a);ok(a.mNoNetworkBlackUids.equals(Arrays.asList("other")),"only GMS network restriction removed");
  AMS ams=new AMS();ThreadStub caller=new ThreadStub();
  Intent fake=new Intent(receive).setPackage("receiver");ams.p.info.packageName="fake";
  StaticPolicy.broadcast(ams,caller,null,fake);ok(fake.getFlags()==0&&PowerExemptionManager.calls==0,"untrusted caller unchanged");
  Intent valid=new Intent(receive).setPackage("receiver");ams.p.info.packageName=StaticPolicy.GMS;
  StaticPolicy.broadcast(ams,caller,null,valid);
  ok((valid.getFlags()&32)!=0,"include stopped packages retained");
  ok(PowerExemptionManager.calls==1&&PowerExemptionManager.duration==2000L&&"receiver".equals(PowerExemptionManager.target),"temporary two-second receiver exemption");
  Intent other=new Intent("other").setPackage("receiver");StaticPolicy.broadcast(ams,caller,null,other);
  ok(other.getFlags()==0&&PowerExemptionManager.calls==1,"unrelated action unchanged");
  System.out.println("PASS PolicyTest checks="+checks);
 }
}
