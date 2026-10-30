package com.oem.otherpowerkeeper.provider;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
/** Simulates newer OEM ROM exposing Context-only Doze API. */
public final class GlobalFeatureConfigureHelper {
    public List<String> getDozeWhiteListApps(android.content.Context context) {
        return Collections.unmodifiableList(Arrays.asList("com.example.original"));
    }
}
