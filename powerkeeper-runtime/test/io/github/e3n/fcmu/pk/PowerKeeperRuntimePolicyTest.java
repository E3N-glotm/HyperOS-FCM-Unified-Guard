package io.github.e3n.fcmu.pk;

import java.lang.reflect.*;
import java.util.*;
import io.github.e3n.fcmu.pk.PowerKeeperRuntimePolicy.*;

public final class PowerKeeperRuntimePolicyTest {
    static void check(boolean valid, String reason) {
        if (!valid) throw new AssertionError(reason);
    }
    static final class Installed {
        final Method method;
        final Interceptor callback;
        Installed(Method m, Interceptor c) { method=m; callback=c; }
        Object invoke(Object receiver,Object... args) throws Throwable {
            return callback.onInvoke(receiver,args,new Proceed() {
                @Override public Object call(Object instance,Object[] arguments) throws Throwable {
                    try { return method.invoke(instance,arguments); }
                    catch(InvocationTargetException e) { throw e.getCause(); }
                }
            });
        }
    }
    public static void main(String[] args) throws Throwable {
        final Map<String, Installed> installed = new LinkedHashMap<String, Installed>();
        Installer hook = new Installer() {
            @Override public boolean hook(Method m, Interceptor callback) {
                installed.put(m.getDeclaringClass().getName()+"#"+m.getName(),new Installed(m,callback));
                return true;
            }
        };
        Report report = PowerKeeperRuntimePolicy.install(
                PowerKeeperRuntimePolicyTest.class.getClassLoader(),
                PowerKeeperRuntimePolicy.defaultCandidates(), hook);
        check(report.installed()==6,"legacy + modern + Doze six hooks should be installed");
        com.miui.powerkeeper.utils.GmsObserver g = new com.miui.powerkeeper.utils.GmsObserver();
        check((Boolean)installed.get("com.miui.powerkeeper.utils.GmsObserver#updateFrameworkGmsNetStatus").invoke(g,true),"modern return preserved");
        check(!g.latest,"Gms network request must be false upstream");
        for(String n:Arrays.asList("updateGmsAlarm","updateGmsNetWork","updateGoogleReletivesWakelock")) {
            installed.get("com.miui.powerkeeper.utils.GmsObserver#"+n).invoke(g,true);
            check(!g.latest,"legacy "+n+" not disabled");
        }
        com.miui.powerkeeper.utils.NetdExecutor network = new com.miui.powerkeeper.utils.NetdExecutor();
        installed.get("com.miui.powerkeeper.utils.NetdExecutor#initGmsChain")
                .invoke(network,"gms_wall",1234,"DROP");
        check("ACCEPT".equals(network.action),"firewall policy unchanged");
        Object list = installed.get("com.miui.powerkeeper.provider.GlobalFeatureConfigureHelper#getDozeWhiteListApps")
                .invoke(new com.miui.powerkeeper.provider.GlobalFeatureConfigureHelper(),new android.os.Bundle());
        check(list instanceof List && ((List<?>)list).contains("com.google.android.gms"),
              "Doze GMS must be included in immutable OEM list");
        check(((List<?>)list).contains("com.example.keep"),"Doze OEM values must be preserved");
        check(report.results().get("pk.gms.updateFrameworkGmsNetStatus").equals("hook_installed"),"modern not installed");
        check(report.toTsv().contains("pk.doze.whitelist\thook_installed"),"Doze report inaccurate");

        Report nonExisting = PowerKeeperRuntimePolicy.install(
                PowerKeeperRuntimePolicyTest.class.getClassLoader(),
                Arrays.asList("com.vendor.powerkeeper.MissingObserver", "com.miui.powerkeeper.utils.Nonexistent"),
                hook);
        check(nonExisting.installed()==0,"missing classes must fail closed");
        check("unavailable".equals(nonExisting.results().get("pk.doze.whitelist")),"missing not reported");

        Report variant = PowerKeeperRuntimePolicy.install(
                PowerKeeperRuntimePolicyTest.class.getClassLoader(),
                Arrays.asList("com.xiaomi.powerkeeper.utils.GmsObserver"),hook);
        check(variant.installed()==1,"only compatible new-version boolean signature allowed");
        check("unavailable".equals(variant.results().get("pk.gms.updateGmsAlarm")),"wrong parameter type hooked");
        com.xiaomi.powerkeeper.utils.GmsObserver x=new com.xiaomi.powerkeeper.utils.GmsObserver();
        Object reply=installed.get("com.xiaomi.powerkeeper.utils.GmsObserver#updateFrameworkGmsNetStatus").invoke(x,true);
        check(Boolean.FALSE.equals(reply),"new version boolean not clamped");

        Report failed = PowerKeeperRuntimePolicy.install(
            PowerKeeperRuntimePolicyTest.class.getClassLoader(),
            Arrays.asList("com.miui.powerkeeper.utils.GmsObserver"),new Installer(){
                @Override public boolean hook(Method method,Interceptor c){throw new IllegalStateException("ART missing");}
            });
        check(failed.installed()==0 && failed.results().get("pk.gms.updateGmsAlarm").equals("hook_failed"),
             "ART hook failures must not be counted as enabled");
        String dynamic = "pk.gms.network\tpresent\tLcom/oem/otherpowerkeeper/utils/GmsObserver;->updateGmsNetWork(Z)V\n"
                + "pk.doze.list\tvariant\tLcom/oem/otherpowerkeeper/provider/GlobalFeatureConfigureHelper;->getDozeWhiteListApps\n"
                + "pk.apk\tpresent\tinspectable_apks=1\n";
        java.util.List<String> fromApk = PowerKeeperClassCandidates.extract(dynamic);
        check(fromApk.contains("com.oem.otherpowerkeeper.utils.GmsObserver"), "vendor class not discovered");
        check(fromApk.contains("com.oem.otherpowerkeeper.provider.GlobalFeatureConfigureHelper"), "vendor Doze owner missing");
        Report custom=PowerKeeperRuntimePolicy.install(
                PowerKeeperRuntimePolicyTest.class.getClassLoader(),fromApk,hook);
        check(custom.installed()==1,"dynamic OEM class should hook only its compatible method");
        com.oem.otherpowerkeeper.utils.GmsObserver vendor=new com.oem.otherpowerkeeper.utils.GmsObserver();
        installed.get("com.oem.otherpowerkeeper.utils.GmsObserver#updateGmsNetWork").invoke(vendor,true);
        check(!vendor.limited, "vendor runtime boolean not overridden");
        System.out.println("PASS PowerKeeperRuntimePolicyTest: old/new/Doze/firewall/immutable list/variant/failure/core independence");
    }
}
