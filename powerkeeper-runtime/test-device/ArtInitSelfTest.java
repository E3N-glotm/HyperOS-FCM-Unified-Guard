/** Disposable Android app_process test. Never runs inside PowerKeeper. */
public final class ArtInitSelfTest {
    private static native int runInit();
    private static native int installHook();

    public static final class Target {
        public int answer(int value) { return value + 1; }
    }
    public static final class Hooker {
        public Object callback(Object[] args) {
            if (args == null || args.length != 2 || !(args[1] instanceof Integer))
                throw new IllegalArgumentException("hook callback arguments");
            return Integer.valueOf(((Integer) args[1]).intValue() + 100);
        }
    }

    public static void main(String[] args) {
        if (args.length != 1) throw new IllegalArgumentException("library path");
        System.out.println("FCMU_ART_TEST_BEGIN");
        try {
            System.load(args[0]);
            System.out.println("FCMU_LIBRARY_LOADED");
            int status = runInit();
            System.out.println("FCMU_LSPLANT_INIT=" + status);
            if (status != 1) System.exit(42);

            java.lang.reflect.Method method=Target.class.getDeclaredMethod("answer",int.class);
            Target target=new Target();
            int baseline=((Integer) method.invoke(target, Integer.valueOf(41))).intValue();
            System.out.println("FCMU_HOOK_BASELINE=" + baseline);
            if (baseline != 42) System.exit(44);

            int installed=installHook();
            System.out.println("FCMU_HOOK_INSTALLED=" + installed);
            if (installed != 1) System.exit(45);
            int hooked=((Integer) method.invoke(target, Integer.valueOf(41))).intValue();
            System.out.println("FCMU_HOOK_VALUE=" + hooked);
            if (hooked != 141) System.exit(46);
            System.out.println("FCMU_JAVA_HOOK_PASS");
            System.out.println("FCMU_ART_TEST_PASS");
        } catch (Throwable e) {
            e.printStackTrace();
            System.exit(43);
        }
    }
}
