package com.miui.powerkeeper.provider;
import java.util.*;
public class GlobalFeatureConfigureHelper {
    public java.util.List<String> getDozeWhiteListApps(android.os.Bundle bundle) {
        return Collections.unmodifiableList(Arrays.asList("com.example.keep"));
    }
}
