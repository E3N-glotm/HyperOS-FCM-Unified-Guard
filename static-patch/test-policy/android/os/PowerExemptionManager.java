package android.os;import android.content.Context;public class PowerExemptionManager {
 public static int calls;public static long duration;public static String target;
 public PowerExemptionManager(Context c){}
 public void addToTemporaryAllowList(String p,int reason,String tag,long time){if(reason!=102||!"GOOGLE_C2DM".equals(tag))throw new AssertionError();calls++;duration=time;target=p;}
}
