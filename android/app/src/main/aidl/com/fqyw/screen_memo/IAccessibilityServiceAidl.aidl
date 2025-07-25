package com.fqyw.screen_memo;

interface IAccessibilityServiceAidl {
    boolean isServiceRunning();
    boolean startTimedScreenshot(int intervalSeconds);
    void stopTimedScreenshot();
    String captureScreenSync();
}