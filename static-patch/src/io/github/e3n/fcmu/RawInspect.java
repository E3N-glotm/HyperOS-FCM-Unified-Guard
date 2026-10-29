package io.github.e3n.fcmu;
import java.io.*;import java.util.*;import java.util.zip.*;
public class RawInspect {
 static byte[] b;static String[] ss,ts,ps,fs,ms;static int pos;
 static int u16(int p){return (b[p]&255)|((b[p+1]&255)<<8);}
 static int u32(int p){return u16(p)|(u16(p+2)<<16);}
 static int ul(){int v=0,s=0,c;do{c=b[pos++]&255;v|=(c&127)<<s;s+=7;}while((c&128)!=0);return v;}
 static byte[] read(InputStream s)throws Exception{ByteArrayOutputStream o=new ByteArrayOutputStream();byte[] t=new byte[65536];int n;while((n=s.read(t))>0)o.write(t,0,n);return o.toByteArray();}
 public static void main(String[] a)throws Exception{
  ZipFile z=new ZipFile(a[0]);Enumeration<? extends ZipEntry> es=z.entries();
  while(es.hasMoreElements()){ZipEntry e=es.nextElement();if(!e.getName().matches("classes[0-9]*\\.dex"))continue;b=read(z.getInputStream(e));
   int n=u32(56),off=u32(60);ss=new String[n];for(int i=0;i<n;i++){pos=u32(off+i*4);ul();int start=pos;while(b[pos]!=0)pos++;ss[i]=new String(b,start,pos-start,"UTF-8");}
   n=u32(64);off=u32(68);ts=new String[n];for(int i=0;i<n;i++)ts[i]=ss[u32(off+i*4)];
   n=u32(72);off=u32(76);ps=new String[n];for(int i=0;i<n;i++){int p=u32(off+i*12+8);String v="(";if(p!=0)for(int j=0;j<u32(p);j++)v+=ts[u16(p+4+j*2)];ps[i]=v+")"+ts[u32(off+i*12+4)];}
   n=u32(80);off=u32(84);fs=new String[n];for(int i=0;i<n;i++)fs[i]=ts[u16(off+i*8)]+"->"+ss[u32(off+i*8+4)]+":"+ts[u16(off+i*8+2)];
   n=u32(88);off=u32(92);ms=new String[n];for(int i=0;i<n;i++)ms[i]=ts[u16(off+i*8)]+"->"+ss[u32(off+i*8+4)]+ps[u16(off+i*8+2)];
   n=u32(96);off=u32(100);for(int i=0;i<n;i++){int p=off+i*32;String cl=ts[u32(p)];if(!cl.contains(a[1]))continue;pos=u32(p+24);if(pos==0)continue;System.out.println("CLASS "+e.getName()+" "+cl);int sf=ul(),inf=ul(),dm=ul(),vm=ul();for(int j=0;j<sf+inf;j++){ul();ul();}for(int kind=0;kind<2;kind++){int mi=0;for(int j=0;j<(kind==0?dm:vm);j++){mi+=ul();int flags=ul(),code=ul();if(!ms[mi].contains(a[2]))continue;System.out.println("METHOD "+ms[mi]+" flags="+flags+" code="+code);if(code==0)continue;int words=u32(code+12);System.out.println("REGS "+u16(code)+" PARAMS "+u16(code+2)+" WORDS "+words);for(int k=0;k<words;k++){int w=u16(code+16+k*2),op=w&255;String ref="";if(k+1<words){int ix=u16(code+18+k*2);if((op>=0x6e&&op<=0x72)||(op>=0x74&&op<=0x78)){if(ix<ms.length)ref=ms[ix];}else if(op>=0x52&&op<=0x6d){if(ix<fs.length)ref=fs[ix];}else if(op==0x1a&&ix<ss.length)ref=ss[ix];else if((op==0x1f||op==0x22)&&ix<ts.length)ref=ts[ix];}System.out.println(String.format("%04x %04x %s",k,w,ref));}}}
   }
  }z.close();
 }
}
