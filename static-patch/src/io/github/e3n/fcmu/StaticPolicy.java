/*
 * SPDX-License-Identifier: GPL-3.0-only
 * FCM policy ported from Howard20181 HyperOS_FCM_Live and E3N's OS4 fork.
 */
package io.github.e3n.fcmu;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import java.lang.reflect.*;
import java.util.*;
public final class StaticPolicy {
 public static final String GMS="com.google.android.gms";
 public static final String RECEIVE="com.google.android.c2dm.intent.RECEIVE";
 private static final Set<String> EVENTS=new HashSet<String>(Arrays.asList(
  "com.google.android.intent.action.GCM_RECONNECT","com.google.android.gcm.DISCONNECTED",
  "com.google.android.gcm.CONNECTED","com.google.android.gms.gcm.HEARTBEAT_ALARM"));
 private static volatile Method lookup,record,allow;
 private static volatile Field appInfo,context,callerPackage,broadcastIntent;
 private static volatile Constructor<?> exemption;
 private StaticPolicy(){}
 private static Field field(Class<?> c,String name)throws Exception{
  while(c!=null){try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f;}catch(NoSuchFieldException e){c=c.getSuperclass();}}
  throw new NoSuchFieldException(name);
 }
 private static Method method(Class<?> c,String name,Class<?>...types)throws Exception{
  while(c!=null){try{Method m=c.getDeclaredMethod(name,types);m.setAccessible(true);return m;}catch(NoSuchMethodException e){c=c.getSuperclass();}}
  throw new NoSuchMethodException(name);
 }
 public static boolean allowGreeze(Object self,int callerUid,String caller,int calleeUid,String callee,String action){
  if(RECEIVE.equals(action)&&GMS.equals(caller))return true;
  if(!EVENTS.contains(action))return false;
  try{Method m=lookup;if(m==null)lookup=m=method(self.getClass(),"getPackageNameFromUid",int.class);
   Object v=m.invoke(self,calleeUid);if(v instanceof String)callee=(String)v;
  }catch(Exception ignored){}
  return GMS.equals(callee)||(GMS+".persistent").equals(callee);
 }
 public static boolean skipGreezeDefer(Object ignored,String action){return EVENTS.contains(action);}
 public static boolean skipDomesticDefer(Object ignored,String action){return EVENTS.contains(action)||RECEIVE.equals(action);}
 public static boolean autoStart(Object ignored,Object queue,Object br,Object resolve){
  if(br==null)return false;
  try{
   Field cp=callerPackage,bi=broadcastIntent;
   if(cp==null)callerPackage=cp=field(br.getClass(),"callerPackage");
   if(bi==null)broadcastIntent=bi=field(br.getClass(),"intent");
   Object i=bi.get(br);
   return GMS.equals(cp.get(br))&&i instanceof Intent&&RECEIVE.equals(((Intent)i).getAction());
  }catch(Exception ignoredError){return false;}
 }
 @SuppressWarnings({"rawtypes","unchecked"})
 public static void listConstruct(Object self){
  try{Object v=field(self.getClass(),"SYSTEM_BLACK_LIST").get(self);if(v instanceof List)((List)v).remove(GMS);}catch(Exception ignored){}
 }
 @SuppressWarnings({"rawtypes","unchecked"})
 public static void listWhite(Object self,String ignored){
  try{Object v=field(self.getClass(),"USE_DATA_WHITE_LIST").get(self);if(v instanceof Set)((Set)v).add(GMS);}catch(Exception ignoredError){}
 }
 @SuppressWarnings({"rawtypes","unchecked"})
 public static void awareConstruct(Object self){
  try{Object v=field(self.getClass(),"mNoNetworkBlackUids").get(self);if(v instanceof List)((List)v).remove(GMS);}catch(Exception ignored){}
 }
 public static List<?> processWhite(List<?> original,int flags){
  if(original==null||(flags&1)==0)return original;
  ArrayList<Object> r=new ArrayList<Object>(original);
  if(!r.contains(GMS))r.add(GMS);
  if(!r.contains(GMS+".persistent"))r.add(GMS+".persistent");
  return r;
 }
 // The first four AMS parameter registers are contiguous even when the method
 // has >16 registers. The injector uses invoke-static/range without clobbering them.
 public static void broadcast(Object self,Object caller,String feature,Intent intent){
  if(caller==null||intent==null||!RECEIVE.equals(intent.getAction()))return;
  try{
   Method rm=record;
   if(rm==null)record=rm=method(self.getClass(),"getRecordForAppLOSP",Class.forName("android.app.IApplicationThread"));
   Object pr=rm.invoke(self,caller);if(pr==null)return;
   Field ai=appInfo;if(ai==null)appInfo=ai=field(pr.getClass(),"info");
   Object raw=ai.get(pr);
   if(!(raw instanceof ApplicationInfo)||!GMS.equals(((ApplicationInfo)raw).packageName))return;
   // Preserve the original FCM Live behavior, including stopped-package delivery.
   intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES);
   String target=intent.getPackage();if(target==null)return;
   Field cf=context;if(cf==null)context=cf=field(self.getClass(),"mContext");
   Context ctx=(Context)cf.get(self);if(ctx==null)return;
   Class<?> pc=Class.forName("android.os.PowerExemptionManager");
   Constructor<?> ctor=exemption;
   if(ctor==null){ctor=pc.getDeclaredConstructor(Context.class);ctor.setAccessible(true);exemption=ctor;}
   Method am=allow;
   if(am==null){am=pc.getDeclaredMethod("addToTemporaryAllowList",String.class,int.class,String.class,long.class);am.setAccessible(true);allow=am;}
   am.invoke(ctor.newInstance(ctx),target,102,"GOOGLE_C2DM",2000L);
  }catch(Exception ignored){}
 }
}
