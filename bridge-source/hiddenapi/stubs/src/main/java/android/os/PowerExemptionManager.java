package android.os;

import android.annotation.NonNull;
import android.annotation.Nullable;
import android.content.Context;

import androidx.annotation.RequiresApi;

@RequiresApi(31)
public class PowerExemptionManager {
    public PowerExemptionManager(@NonNull Context context) {
        throw new UnsupportedOperationException("STUB");
    }

    public void addToTemporaryAllowList(@NonNull String packageName, int reasonCode,
                                        @Nullable String reason, long durationMs) {
        throw new UnsupportedOperationException("STUB");
    }

    public long addToTemporaryAllowListForEvent(@NonNull String packageName,
                                                int reasonCode, @Nullable String reason, int event) {
        throw new UnsupportedOperationException("STUB");
    }
}
