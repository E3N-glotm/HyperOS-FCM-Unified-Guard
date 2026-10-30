package io.github.e3n.fcmu.pk;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * PowerKeeper-only interception policy. The injector supplies a real ART
 * implementation of Installer; this class contains no LSPosed dependency.
 *
 * IMPORTANT: method discovery != hook installation != runtime equivalence.
 * Installing a failed hook never disables the independent Magisk FCM core.
 *
 * License: GPL-3.0-only. Behavior follows the E3N FCM Live PowerKeeper
 * policy, but excludes unsafe blanket modifications to other applications.
 */
public final class PowerKeeperRuntimePolicy {
    public static final String GMS = "com.google.android.gms";

    private PowerKeeperRuntimePolicy() {}

    public interface Proceed {
        Object call(Object receiver, Object[] args) throws Throwable;
    }

    public interface Interceptor {
        Object onInvoke(Object receiver, Object[] args, Proceed original) throws Throwable;
    }

    public interface Installer {
        /** True only when the actual ART interception was successfully installed. */
        boolean hook(Method method, Interceptor callback) throws Throwable;
    }

    public static final class Report {
        private final Map<String, String> results = new LinkedHashMap<String, String>();
        public Map<String, String> results() {
            return Collections.unmodifiableMap(results);
        }
        /** Installed hooks are not proof of runtime delivery or equivalence. */
        public int installed() {
            int n = 0;
            for (String v : results.values()) if (v.equals("hook_installed")) n++;
            return n;
        }
        private void put(String feature, String result) { results.put(feature, result); }
        public String toTsv() {
            StringBuilder b = new StringBuilder();
            for (Map.Entry<String, String> e : results.entrySet())
                b.append(e.getKey()).append('\t').append(e.getValue()).append('\n');
            return b.toString();
        }
    }

    /** Only names extracted from an installed APK should be passed by caller.
     * The default names cover historical implementations without any
     * model/ROM-version gate. */
    public static List<String> defaultCandidates() {
        return Arrays.asList(
                "com.miui.powerkeeper.utils.GmsObserver",
                "com.miui.powerkeeper.utils.NetdExecutor",
                "com.miui.powerkeeper.provider.GlobalFeatureConfigureHelper",
                "com.xiaomi.powerkeeper.utils.GmsObserver",
                "com.xiaomi.powerkeeper.utils.NetdExecutor",
                "com.xiaomi.powerkeeper.provider.GlobalFeatureConfigureHelper");
    }

    /** No-flag entrypoint: vendor DNS/firewall candidate stays disabled. */
    public static Report install(ClassLoader loader, Iterable<String> candidates, Installer hooks) {
        return install(loader, candidates, hooks, -1, false);
    }

    /** Optional experimental DNS guard: callers must verify the current OEM
     * method bytecode semantics AND resolve the installed GMS UID. Signature
     * presence alone must never enable this policy; it is never used by the
     * production bridge without explicit successful external verification.
     * No ROM/device-version allowlist and no hard-coded GMS UID. */
    public static Report install(ClassLoader loader, Iterable<String> candidates, Installer hooks,
                                 int verifiedGmsUid, boolean verifiedGmsDnsSemantics) {
        Report report = new Report();
        if (loader == null || hooks == null) {
            report.put("pk.runtime", "unavailable");
            return report;
        }
        Set<String> names = new LinkedHashSet<String>();
        for (String name : candidates) if (safeClassName(name)) names.add(name);
        for (String name : names) {
            String owner = name.endsWith(".GmsObserver") ? "gms" :
                    name.endsWith(".NetdExecutor") ? "firewall" :
                    name.endsWith(".GlobalFeatureConfigureHelper") ? "doze" : null;
            if (owner == null) continue;
            Class<?> klass;
            try { klass = Class.forName(name, false, loader); }
            catch (ClassNotFoundException e) { continue; }
            catch (LinkageError e) { report.put("pk." + owner + "." + name, "unavailable"); continue; }

            for (Method method : klass.getDeclaredMethods()) {
                String feature = null;
                Interceptor interceptor = null;
                if (owner.equals("gms") && method.getParameterTypes().length == 1 &&
                        method.getParameterTypes()[0] == boolean.class &&
                        (method.getReturnType() == boolean.class || method.getReturnType() == void.class) &&
                        (method.getName().equals("updateGmsAlarm") ||
                        method.getName().equals("updateGmsNetWork") ||
                        method.getName().equals("updateGoogleReletivesWakelock") ||
                        method.getName().equals("updateFrameworkGmsNetStatus"))) {
                    feature = "pk.gms." + method.getName();
                    interceptor = new Interceptor() {
                        @Override public Object onInvoke(Object receiver, Object[] args, Proceed original) throws Throwable {
                            Object[] updated = args.clone();
                            updated[0] = Boolean.FALSE;
                            return original.call(receiver, updated);
                        }
                    };
                } else if (owner.equals("firewall") && method.getName().equals("initGmsChain") &&
                        method.getParameterTypes().length == 3 &&
                        method.getParameterTypes()[0] == String.class &&
                        method.getParameterTypes()[1] == int.class &&
                        method.getParameterTypes()[2] == String.class &&
                        method.getReturnType() == void.class) {
                    feature = "pk.firewall.gmsChain";
                    interceptor = new Interceptor() {
                        @Override public Object onInvoke(Object receiver, Object[] args, Proceed original) throws Throwable {
                            Object[] updated = args.clone();
                            updated[2] = "ACCEPT";
                            return original.call(receiver, updated);
                        }
                    };
                } else if (owner.equals("firewall") &&
                        method.getName().equals("setGmsDnsBlockerState") &&
                        Modifier.isStatic(method.getModifiers()) &&
                        method.getParameterTypes().length == 2 &&
                        method.getParameterTypes()[0] == int.class &&
                        method.getParameterTypes()[1] == boolean.class &&
                        method.getReturnType() == void.class) {
                    feature = "pk.firewall.gmsDnsUidRule";
                    if (!verifiedGmsDnsSemantics || verifiedGmsUid < 10000) {
                        report.put(feature, "candidate_unverified");
                        continue;
                    }
                    interceptor = new Interceptor() {
                        @Override public Object onInvoke(Object receiver, Object[] args, Proceed original) throws Throwable {
                            // Preserve all other UIDs, all non-deny actions, and
                            // the OEM method's own side effects. Never write a
                            // global firewall / DNS policy or change GMS UID.
                            if (args == null || args.length != 2 ||
                                    !(args[0] instanceof Integer) || !(args[1] instanceof Boolean) ||
                                    ((Integer)args[0]).intValue() != verifiedGmsUid ||
                                    !((Boolean)args[1]).booleanValue())
                                return original.call(receiver, args);
                            Object[] narrowed = args.clone();
                            narrowed[1] = Boolean.FALSE;
                            return original.call(receiver, narrowed);
                        }
                    };
                } else if (owner.equals("doze") && method.getName().equals("getDozeWhiteListApps") &&
                        method.getParameterTypes().length == 1 &&
                        method.getParameterTypes()[0].getName().equals("android.os.Bundle") &&
                        List.class.isAssignableFrom(method.getReturnType())) {
                    feature = "pk.doze.whitelist";
                    interceptor = new Interceptor() {
                        @Override public Object onInvoke(Object receiver, Object[] args, Proceed original) throws Throwable {
                            Object result = original.call(receiver, args);
                            if (!(result instanceof List<?>)) return result;
                            List<?> items = (List<?>) result;
                            if (items.contains(GMS)) return result;
                            ArrayList<Object> copy = new ArrayList<Object>(items);
                            copy.add(GMS);
                            return copy;
                        }
                    };
                }
                if (feature == null) continue;
                // A vendor may retain duplicate-looking classes in separate
                // packages. Protect only one successful exact signature per
                // behavior; a failed candidate can be retried in another.
                if ("hook_installed".equals(report.results.get(feature))) continue;
                try {
                    if (!Modifier.isPublic(method.getModifiers())) method.setAccessible(true);
                    report.put(feature, hooks.hook(method, interceptor) ? "hook_installed" : "hook_failed");
                } catch (Throwable e) {
                    report.put(feature, "hook_failed");
                }
            }
        }
        for (String f : Arrays.asList(
                "pk.gms.updateGmsAlarm", "pk.gms.updateGmsNetWork",
                "pk.gms.updateGoogleReletivesWakelock",
                "pk.gms.updateFrameworkGmsNetStatus",
                "pk.firewall.gmsChain", "pk.firewall.gmsDnsUidRule", "pk.doze.whitelist")) {
            if (!report.results.containsKey(f)) report.put(f, "unavailable");
        }
        return report;
    }

    private static boolean safeClassName(String n) {
        return n != null && n.length() < 200 &&
                n.matches("[A-Za-z_$][A-Za-z0-9_$.]*") &&
                (n.endsWith(".GmsObserver") || n.endsWith(".NetdExecutor") ||
                 n.endsWith(".GlobalFeatureConfigureHelper"));
    }
}
