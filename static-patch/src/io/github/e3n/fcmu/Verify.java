package io.github.e3n.fcmu;
public final class Verify {
 public static void main(String[] args)throws Exception{
  if(args.length==2&&args[0].equals("--adaptive")){adaptive(args[1]);return;}
  if(args.length>0&&args[0].equals("--jar")){
   for(int i=1;i<args.length;i++)checkZip(args[i]);
   return;
  }
  for(String name:args){
   Class<?> c=Class.forName(name,false,Verify.class.getClassLoader());
   System.out.println("ART_LOAD "+c.getName()+" methods="+c.getDeclaredMethods().length);
  }
  Class<?> pem=Class.forName("android.os.PowerExemptionManager",false,Verify.class.getClassLoader());
  pem.getDeclaredConstructor(android.content.Context.class);
  pem.getDeclaredMethod("addToTemporaryAllowList",String.class,int.class,String.class,long.class);
  Class<?> ams=Class.forName("com.android.server.am.ActivityManagerService",false,Verify.class.getClassLoader());
  ams.getDeclaredMethod("getRecordForAppLOSP",Class.forName("android.app.IApplicationThread"));
  checkField(ams,"mContext",android.content.Context.class);
  checkField(Class.forName("com.android.server.am.ProcessRecord",false,Verify.class.getClassLoader()),"info",android.content.pm.ApplicationInfo.class);
  Class<?> br=Class.forName("com.android.server.am.BroadcastRecord",false,Verify.class.getClassLoader());
  checkField(br,"callerPackage",String.class);checkField(br,"intent",android.content.Intent.class);
  System.out.println("ART_API PowerExemptionManager signature OK");
  System.out.println("ART_API caller identity and broadcast fields OK");
 }
 static void adaptive(String path)throws Exception{
  int failures=0;
  try(java.io.BufferedReader in=new java.io.BufferedReader(new java.io.InputStreamReader(new java.io.FileInputStream(path),"UTF-8"))){
   String line;while((line=in.readLine())!=null){
    String[] cols=line.split("\t",3);if(cols.length<2||!cols[1].equals("ready"))continue;
    String k=cols[0];
    try{
     load("io.github.e3n.fcmu.StaticPolicy");
     if(k.equals("ams.broadcast")){
      Class<?> a=load("com.android.server.am.ActivityManagerService");
      a.getDeclaredMethod("getRecordForAppLOSP",Class.forName("android.app.IApplicationThread"));
      checkField(a,"mContext",android.content.Context.class);
      checkField(load("com.android.server.am.ProcessRecord"),"info",android.content.pm.ApplicationInfo.class);
      Class<?> pem=Class.forName("android.os.PowerExemptionManager");pem.getDeclaredConstructor(android.content.Context.class);
      pem.getDeclaredMethod("addToTemporaryAllowList",String.class,int.class,String.class,long.class);
     }else if(k.startsWith("greeze."))load("com.miui.server.greeze.GreezeManagerService");
     else if(k.equals("domestic.defer"))load("com.miui.server.greeze.DomesticPolicyManager");
     else if(k.equals("broadcast.autostart")){
      load("com.android.server.am.BroadcastQueueModernStubImpl");
      Class<?> br=load("com.android.server.am.BroadcastRecord");checkField(br,"callerPackage",String.class);checkField(br,"intent",android.content.Intent.class);
     }else if(k.startsWith("lists."))load("com.miui.server.greeze.power.ListAppsManager");
     else if(k.equals("network.constructor"))load("com.miui.server.greeze.power.AwareResourceControl");
     else if(k.equals("process.whitelist"))load("com.android.server.am.ProcessPolicy");
     else throw new IllegalArgumentException("unknown feature");
     System.out.println("VERIFY_OK\t"+k);
    }catch(Throwable e){failures++;System.out.println("VERIFY_FAIL\t"+k+"\t"+e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage()).replace('\n',' '));}
   }
  }
  if(failures>0)System.exit(3);
 }
 static Class<?> load(String name)throws Exception{Class<?> c=Class.forName(name,false,Verify.class.getClassLoader());c.getDeclaredMethods();return c;}
 static void checkField(Class<?> c,String name,Class<?> type)throws Exception{
  if(c.getDeclaredField(name).getType()!=type)throw new NoSuchFieldException(c.getName()+"->"+name+" type mismatch");
 }
 static void checkZip(String path)throws Exception{
  java.io.RandomAccessFile f=new java.io.RandomAccessFile(path,"r");int dexes=0;
  try{
   while(f.getFilePointer()+4<f.length()){
    int sig=Integer.reverseBytes(f.readInt());
    if(sig==0x02014b50)break;
    if(sig!=0x04034b50)throw new java.io.IOException("Invalid local ZIP header");
    f.skipBytes(2);int flags=Short.reverseBytes(f.readShort())&65535;
    int compression=Short.reverseBytes(f.readShort())&65535;f.skipBytes(8);
    long size=Integer.reverseBytes(f.readInt())&0xffffffffL;f.skipBytes(4);
    int names=Short.reverseBytes(f.readShort())&65535;
    int extras=Short.reverseBytes(f.readShort())&65535;
    byte[] n=new byte[names];f.readFully(n);f.skipBytes(extras);
    if((flags&8)!=0)throw new java.io.IOException("Unexpected streaming descriptor");
    long offset=f.getFilePointer();String name=new String(n,"UTF-8");
    if(name.endsWith(".dex")){dexes++;if(compression!=0||offset%4!=0)throw new java.io.IOException("Unaligned DEX "+name);System.out.println("DEX_ALIGN "+name+"="+offset);}
    f.seek(offset+size);
   }
   if(dexes==0)throw new java.io.IOException("No DEX entries");
   System.out.println("ZIP_OK "+path+" dexes="+dexes);
  }finally{f.close();}
 }
}
