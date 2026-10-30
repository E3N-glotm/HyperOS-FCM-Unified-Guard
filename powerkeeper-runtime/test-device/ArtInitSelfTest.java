/** Disposable Android app_process test. Never runs inside PowerKeeper. */
public final class ArtInitSelfTest {
    private static native int runInit();
    public static void main(String[] args) {
        if (args.length != 1) throw new IllegalArgumentException("library path");
        System.out.println("FCMU_ART_TEST_BEGIN");
        try {
            System.load(args[0]);
            System.out.println("FCMU_LIBRARY_LOADED");
            int status = runInit();
            System.out.println("FCMU_LSPLANT_INIT="+status);
            if (status != 1) System.exit(42);
            System.out.println("FCMU_ART_TEST_PASS");
        } catch (Throwable e) {
            e.printStackTrace();
            System.exit(43);
        }
    }
}
