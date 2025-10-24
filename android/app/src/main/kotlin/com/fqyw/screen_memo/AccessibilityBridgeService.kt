package com.fqyw.screen_memo

import android.app.Service
import android.content.Intent
import android.os.IBinder
 

/**
 * 桥接服务，用于提供AIDL接口访问AccessibilityService
 */
class AccessibilityBridgeService : Service() {
    
    companion object {
        private const val TAG = "AccessibilityBridge"
    }
    
    private val binder = object : IAccessibilityServiceAidl.Stub() {
        override fun isServiceRunning(): Boolean {
            return ScreenCaptureAccessibilityService.isServiceRunning
        }
        
        override fun startTimedScreenshot(intervalSeconds: Int): Boolean {
            val service = ScreenCaptureAccessibilityService.instance
            return service?.startTimedScreenshot(intervalSeconds) ?: false
        }
        
        override fun stopTimedScreenshot() {
            val service = ScreenCaptureAccessibilityService.instance
            service?.stopTimedScreenshot()
        }
        
        override fun captureScreenSync(): String? {
            val service = ScreenCaptureAccessibilityService.instance
            return service?.captureScreenSync()
        }
    }
    
    override fun onBind(intent: Intent?): IBinder {
        FileLogger.d(TAG, "服务绑定")
        return binder
    }
}