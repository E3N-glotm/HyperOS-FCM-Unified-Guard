package io.github.e3n.fcmu.pk;

import android.app.Application;
import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
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
            if (!context.getPackageName().toLowerCase(java.util.Locale.ROOT).contains("powerkeeper"))
                return result;
            List<String> names = new ArrayList<String>(PowerKeeperRuntimePolicy.defaultCandidates());
            for (String name : candidates) names.add(name);
            PowerKeeperRuntimePolicy.Report report =
                    PowerKeeperRuntimePolicy.install(context.getClassLoader(), names, new NativeInstaller());
            experimentalAudit(context, "hooks_installed=" + report.installed() + "\n" + report.toTsv());
            for (java.util.Map.Entry<String,String> value : report.results().entrySet()) {
                Log.i(TAG, value.getKey() + "=" + value.getValue());
            }
            // Never claim 10/10 framework implies these independent hooks work.
            Log.i(TAG, "PowerKeeper hooks installed=" + report.installed() + " (runtime behavior unverified)");
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
            if (invokedOnce.compareAndSet(false, true))
                experimentalAudit(auditContext, "method_invoked=" + methodName);
            return value;
        }
    }
}
