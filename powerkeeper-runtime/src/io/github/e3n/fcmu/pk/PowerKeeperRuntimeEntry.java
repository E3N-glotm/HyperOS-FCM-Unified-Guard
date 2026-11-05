package io.github.e3n.fcmu.pk;

import android.app.Application;
import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.security.MessageDigest;
import android.content.pm.PackageManager;
import java.nio.charset.StandardCharsets;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Entry point intended for an optional, PowerKeeper-process-only Zygisk ART
 * adapter. This file does not load LSPosed or replace any signed OEM APK.
 * The native bridge must provide nativeHook via LSPlant and must not report
 * protection active unless the returned backup Method is valid.
 */
public final class PowerKeeperRuntimeEntry {
    private static final String TAG = "FCMU-PowerKeeper";
    private static volatile boolean attached;
    private static String[] candidates = new String[0];
    private static volatile Context auditContext;
    // The native Zygisk experiment build supplies this marker explicitly.
    // Ordinary/production builds never enable application-private trace I/O.
    private static final String DIAGNOSTIC_MARKER = "__FCMU_PK_EXPERIMENT_DIAGNOSTICS_ONLY__";
    private static volatile boolean diagnosticAuditEnabled;
    // Verified against the *installed* PowerKeeper 4.2.00 APK on 2026-11-04.
    // Its NetdExecutor.setGmsDnsBlockerState(int,boolean) maps true to
    // dnsproxyd "deny" and false to "allow". This is an APK content
    // fingerprint (not a phone/model/OS allowlist): other APK bytes fail
    // closed for the DNS-specific hook, preserving all other safe hooks.
    private static final String[] VERIFIED_GMS_DNS_APK_SHA256 = {
        "164f2b6271eef11afaf5c97984011f01329173099accf69bada3b815a26cbd44"
    };

    private static boolean verifiedGmsDnsSemantics(Context context) {
        try {
            if (context == null || !"com.miui.powerkeeper".equals(context.getPackageName()))
                return false;
            String path = context.getApplicationInfo().sourceDir;
            if (path == null || !path.endsWith(".apk")) return false;
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = new byte[32768];
            // One read at process initialization only; not a recurring poll.
            try (FileInputStream input = new FileInputStream(path)) {
                int size;
                while ((size = input.read(bytes)) != -1)
                    digest.update(bytes, 0, size);
            }
            byte[] sha = digest.digest();
            StringBuilder hex = new StringBuilder(64);
            for (byte b : sha) {
                hex.append(Character.forDigit((b >>> 4) & 15, 16));
                hex.append(Character.forDigit(b & 15, 16));
            }
            for (String known : VERIFIED_GMS_DNS_APK_SHA256) {
                if (known.equals(hex.toString())) return true;
            }
        } catch (Throwable ignored) {
            // An unreadable/updated APK is not evidence of matching semantics.
        }
        return false;
    }

    private static int verifiedGmsUid(Context context) {
        try {
            int uid = context.getPackageManager().getPackageUid(
                    PowerKeeperRuntimePolicy.GMS, 0);
            // Reject non-application, isolated and invalid identities.
            return uid >= 10000 && uid < 99000 ? uid : -1;
        } catch (Throwable unsupported) {
            return -1;
        }
    }


    // alpha14: durable ONE-SHOT, process-private evidence. The phone's main
    // logcat ring is only 64 KiB; boot-time hook evidence disappears quickly.
    // No separate daemon, timer, polling, or write on every method call.
    private static final String RUNTIME_AUDIT_NAME = "fcmu_pk_runtime_alpha14.tsv";
    private static synchronized void runtimeAudit(Context context, String event, boolean append) {
        if (context == null || event == null ||
                !"com.miui.powerkeeper".equals(context.getPackageName())) return;
        try {
            Context de = context.createDeviceProtectedStorageContext();
            File dir = de.getFilesDir();
            if (dir == null) return;
            File out = new File(dir, RUNTIME_AUDIT_NAME);
            if (append && out.isFile() && out.length() > 8192) return;
            try (FileOutputStream stream = new FileOutputStream(out, append)) {
                String line = System.currentTimeMillis() + "\t" + event + "\n";
                stream.write(line.getBytes(StandardCharsets.UTF_8));
            }
        } catch (Throwable ignored) {
            // Auditing is not allowed to prevent OEM application startup.
        }
    }

    // alpha14: avoid trusting "hook installed" to retroactively undo a DNS
    // deny written before Java Application.attach was intercepted. Only after
    // exact APK semantic fingerprint + dynamic GMS UID + successful hook,
    // send one idempotent GMS-only allow through the OEM method itself.
    private static void restoreGmsDnsOnce(Context context, int uid,
                                           boolean verified,
                                           PowerKeeperRuntimePolicy.Report report) {
        if (!verified || uid < 10000 ||
                report == null ||
                !"hook_installed".equals(
                    report.results().get("pk.firewall.gmsDnsUidRule"))) {
            runtimeAudit(context, "dns_initial_allow=skipped", true);
            return;
        }
        try {
            ClassLoader loader = context.getClassLoader();
            Class<?> netd = Class.forName(
                    "com.miui.powerkeeper.utils.NetdExecutor", false, loader);
            Method method = netd.getDeclaredMethod(
                    "setGmsDnsBlockerState", int.class, boolean.class);
            if (!java.lang.reflect.Modifier.isStatic(method.getModifiers()) ||
                    method.getReturnType() != void.class) {
                runtimeAudit(context, "dns_initial_allow=invalid_signature", true);
                return;
            }
            method.setAccessible(true);
            // This calls the same OEM netd rule API used by PowerKeeper.
            // The intercepted path transparently forwards uid,false.
            method.invoke(null, Integer.valueOf(uid), Boolean.FALSE);
            runtimeAudit(context, "dns_initial_allow=called uid=" + uid, true);
        } catch (Throwable error) {
            runtimeAudit(context, "dns_initial_allow=failed exception="
                    + error.getClass().getSimpleName(), true);
        }
    }

    private PowerKeeperRuntimeEntry() {}

    // Experimental-only Java runtime audit. This entry class is not included
    // in the shipped static Magisk baseline; no service or polling is used.
    // Device-protected app-private storage is safe before CE unlock.
    private static void experimentalAudit(Context context, String line) {
        if (!diagnosticAuditEnabled || context == null || line == null) return;
        try {
            Context de = context.createDeviceProtectedStorageContext();
            File dir = de.getFilesDir();
            if (dir == null) return;
            File out = new File(dir, "fcmu_pk_runtime_test.tsv");
            if (out.isFile() && out.length() > 16384) return;
            try (FileOutputStream stream = new FileOutputStream(out, true)) {
                stream.write(line.getBytes(StandardCharsets.UTF_8));
                stream.write('\n');
            }
        } catch (Throwable ignored) {
            // Diagnostics must never change OEM application behavior.
        }
    }

    /** LSPlant Hook(target, owner, callback) returns backup Method or null. */
    private static native Method nativeHook(Method target, Object owner, Method callback);

    public static synchronized boolean prepare(String[] discoveredClasses) {
        if (attached) return true;
        List<String> sanitized = new ArrayList<String>();
        diagnosticAuditEnabled = false;
        if (discoveredClasses != null) {
            for (String name : discoveredClasses) {
                if (DIAGNOSTIC_MARKER.equals(name))
                    diagnosticAuditEnabled = true;
                else if (name != null)
                    sanitized.add(name);
            }
        }
        candidates = sanitized.toArray(new String[0]);
        try {
            Method attach = Application.class.getDeclaredMethod("attach", Context.class);
            attach.setAccessible(true);
            AttachInterceptor interceptor = new AttachInterceptor();
            Method entry = AttachInterceptor.class.getDeclaredMethod("callback", Object[].class);
            Method backup = nativeHook(attach, interceptor, entry);
            if (backup == null) return false;
            interceptor.backup = backup;
            attached = true;
            Log.i(TAG, "PowerKeeper attach callback ready (not yet installed per-method protection)");
            return true;
        } catch (Throwable failure) {
            Log.w(TAG, "PowerKeeper attach interception unavailable", failure);
            return false;
        }
    }

    public static final class AttachInterceptor {
        private Method backup;
        public Object callback(Object[] arguments) throws Throwable {
            if (backup == null || arguments == null || arguments.length != 2)
                throw new IllegalStateException("invalid attach trampoline");
            Context context = (Context) arguments[1];
            experimentalAudit(context, "attach_callback_enter");
            final Object result;
            try { result = backup.invoke(arguments[0], arguments[1]); }
            catch (InvocationTargetException wrapped) { throw wrapped.getCause(); }
            experimentalAudit(context, "attach_backup_completed");
            auditContext = context;
            if (!"com.miui.powerkeeper".equals(context.getPackageName()))
                return result;
            // Reset on each PowerKeeper process attach: stale evidence from
            // yesterday must never be accepted as current boot hook success.
            runtimeAudit(context, "alpha14 attach_backup_completed pid="
                    + android.os.Process.myPid(), false);
            // OEM ClassLoader/reflection may fail on an untested ROM. These
            // optional hooks must never crash PowerKeeper after its original
            // Application.attach completed. Fail open, retaining base guard.
            try {
                List<String> names = new ArrayList<String>(PowerKeeperRuntimePolicy.defaultCandidates());
                for (String name : candidates) names.add(name);
                // The original E3N FCM Live intercepts PowerKeeper's
                // GmsObserver, but the OEM may also deny *GMS UID DNS* via
                // NetdExecutor. Only the independently verified APK
                // semantics + a freshly resolved GMS UID allow this narrow
                // additional hook. Others receive the existing safe hooks.
                boolean dnsVerified = verifiedGmsDnsSemantics(context);
                int gmsUid = dnsVerified ? verifiedGmsUid(context) : -1;
                PowerKeeperRuntimePolicy.Report report =
                        PowerKeeperRuntimePolicy.install(
                                context.getClassLoader(), names, new NativeInstaller(),
                                gmsUid, dnsVerified && gmsUid >= 10000);
                experimentalAudit(context, "hooks_installed=" + report.installed() + "\n" + report.toTsv());
                runtimeAudit(context, "apk_sha_verified=" + dnsVerified
                        + " gms_uid=" + gmsUid, true);
                for (java.util.Map.Entry<String,String> value : report.results().entrySet()) {
                    runtimeAudit(context, "hook " + value.getKey() + "=" + value.getValue(), true);
                    Log.i(TAG, value.getKey() + "=" + value.getValue());
                }
                // A hook preventing future deny does not clear a restriction
                // that was set during OEM initialization before attach.
                restoreGmsDnsOnce(context, gmsUid, dnsVerified, report);
                Log.i(TAG, "PowerKeeper hooks installed=" + report.installed()
                        + " (runtime behavior unverified)");
            } catch (Throwable unsupportedRom) {
                experimentalAudit(context, "optional_hook_install_failed");
                runtimeAudit(context, "install_failed exception="
                        + unsupportedRom.getClass().getSimpleName(), true);
                Log.w(TAG, "Optional PowerKeeper hooks unavailable; base FCM guard unaffected", unsupportedRom);
            }
            return result;
        }
    }

    private static final class NativeInstaller implements PowerKeeperRuntimePolicy.Installer {
        @Override public boolean hook(Method target, PowerKeeperRuntimePolicy.Interceptor intercept) {
            try {
                Method callback = MethodInterceptor.class.getDeclaredMethod("callback", Object[].class);
                MethodInterceptor trampoline = new MethodInterceptor(intercept, target);
                Method backup = nativeHook(target, trampoline, callback);
                if (backup == null) return false;
                trampoline.backup = backup;
                return true;
            } catch (Throwable failure) {
                Log.w(TAG, "Hook unavailable: " + target, failure);
                return false;
            }
        }
    }

    public static final class MethodInterceptor {
        private final PowerKeeperRuntimePolicy.Interceptor handler;
        private final boolean isStatic;
        private Method backup;
        private final String methodName;
        private final AtomicBoolean invokedOnce = new AtomicBoolean();
        MethodInterceptor(PowerKeeperRuntimePolicy.Interceptor callback, Method target) {
            handler = callback;
            isStatic = java.lang.reflect.Modifier.isStatic(target.getModifiers());
            methodName = target.getDeclaringClass().getName() + "#" + target.getName();
        }
        public Object callback(Object[] frame) throws Throwable {
            if (backup == null || frame == null || frame.length == 0)
                throw new IllegalStateException("missing ART backup method");
            final Object receiver = isStatic ? null : frame[0];
            int offset = isStatic ? 0 : 1;
            Object[] params = java.util.Arrays.copyOfRange(frame, offset, frame.length);
            Object value = handler.onInvoke(receiver, params, new PowerKeeperRuntimePolicy.Proceed() {
                @Override public Object call(Object self, Object[] args) throws Throwable {
                    try { return backup.invoke(self, args); }
                    catch (InvocationTargetException wrapped) { throw wrapped.getCause(); }
                }
            });
            if (invokedOnce.compareAndSet(false, true)) {
                experimentalAudit(auditContext, "method_invoked=" + methodName);
                // Only the very first successful invocation per hooked
                // method is persisted; no periodic I/O or new wakeup.
                runtimeAudit(auditContext, "first_hit=" + methodName, true);
            }
            return value;
        }
    }
}
