package com.xiaomi.powerkeeper.utils;
public class GmsObserver {
    public int changed;
    public void updateGmsAlarm(int value) { changed = value; }
    public boolean updateFrameworkGmsNetStatus(boolean value) { return value; }
}
