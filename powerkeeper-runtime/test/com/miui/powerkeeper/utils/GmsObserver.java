package com.miui.powerkeeper.utils;
public class GmsObserver {
    public boolean latest;
    public boolean updateFrameworkGmsNetStatus(boolean value) {
        latest = value;
        return !value;
    }
    public void updateGmsAlarm(boolean value) { latest = value; }
    public void updateGmsNetWork(boolean value) { latest = value; }
    public void updateGoogleReletivesWakelock(boolean value) { latest = value; }
}
