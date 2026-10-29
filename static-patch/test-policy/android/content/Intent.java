package android.content; public class Intent {
 public static final int FLAG_INCLUDE_STOPPED_PACKAGES=32;
 private String action,pkg;private int flags;
 public Intent(String a){action=a;}
 public String getAction(){return action;}public String getPackage(){return pkg;}
 public Intent setPackage(String p){pkg=p;return this;}
 public int getFlags(){return flags;}public Intent addFlags(int f){flags|=f;return this;}
}
