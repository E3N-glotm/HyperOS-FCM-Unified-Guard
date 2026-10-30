package io.github.e3n.fcmu.pk;

import android.app.Application;
import android.content.Context;
import android.util.Log;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

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
    private PowerKeeperRuntimeEntry() {}

    /** LSPlant Hook(target, owner, callback) returns backup Method or null. */
    private static native Method nativeHook(Method target, Object owner, Method callback);

    public static synchronized boolean prepare(String[] discoveredClasses) {
        if (attached) return true;
        candidates = discoveredClasses == null ? new String[0] : discoveredClasses.clone();
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
            final Object result;
            try { result = backup.invoke(arguments[0], arguments[1]); }
            catch (InvocationTargetException wrapped) { throw wrapped.getCause(); }
            Context context = (Context) arguments[1];
            if (!context.getPackageName().toLowerCase(java.util.Locale.ROOT).contains("powerkeeper"))
                return result;
            List<String> names = new ArrayList<String>(PowerKeeperRuntimePolicy.defaultCandidates());
            for (String name : candidates) names.add(name);
            PowerKeeperRuntimePolicy.Report report =
                    PowerKeeperRuntimePolicy.install(context.getClassLoader(), names, new NativeInstaller());
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
        MethodInterceptor(PowerKeeperRuntimePolicy.Interceptor callback, Method target) {
            handler = callback;
            isStatic = java.lang.reflect.Modifier.isStatic(target.getModifiers());
        }
        public Object callback(Object[] frame) throws Throwable {
            if (backup == null || frame == null || frame.length == 0)
                throw new IllegalStateException("missing ART backup method");
            final Object receiver = isStatic ? null : frame[0];
            int offset = isStatic ? 0 : 1;
            Object[] params = java.util.Arrays.copyOfRange(frame, offset, frame.length);
            return handler.onInvoke(receiver, params, new PowerKeeperRuntimePolicy.Proceed() {
                @Override public Object call(Object self, Object[] args) throws Throwable {
                    try { return backup.invoke(self, args); }
                    catch (InvocationTargetException wrapped) { throw wrapped.getCause(); }
                }
            });
        }
    }
}
