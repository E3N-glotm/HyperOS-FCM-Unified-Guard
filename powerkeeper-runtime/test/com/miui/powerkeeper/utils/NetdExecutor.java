package com.miui.powerkeeper.utils;
public class NetdExecutor {
    public String action;
    public void initGmsChain(String chain, int uid, String what) { action = what; }

    // Matches the observed HyperOS 4 PowerKeeper 4.2.00 signature. The
    // real method sends "deny" or "allow" to dnsproxyd setuiddnsrule.
    public static int lastDnsUid = -1;
    public static boolean lastDnsDenied = false;
    public static int dnsCallCount = 0;
    public static void setGmsDnsBlockerState(int uid, boolean deny) {
        lastDnsUid = uid;
        lastDnsDenied = deny;
        dnsCallCount++;
    }
}
