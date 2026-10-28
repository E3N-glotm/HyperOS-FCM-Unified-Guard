package io.github.e3n.fcmu;
public final class Verify {
 public static void main(String[] args)throws Exception{
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
  System.out.println("ART_API PowerExemptionManager signature OK");
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
