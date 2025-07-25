package com.fqyw.screen_memo

import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Log

/**
 * 监听辅助功能服务状态变化的类
 * 当辅助功能服务被禁用时，会尝试提醒用户重新启用
 */
class AccessibilityStateMonitor(private val context: Context) {
    
    companion object {
        private const val TAG = "AccessibilityStateMonitor"
    }
    
    private var contentObserver: ContentObserver? = null
    private val handler = Handler(Looper.getMainLooper())
    
    /**
     * 开始监听辅助功能状态
     */
    fun startMonitoring() {
        try {
            contentObserver = object : ContentObserver(handler) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    checkAccessibilityServiceStatus()
                }
            }
            
            // 监听辅助功能设置变化
            context.contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(Settings.Secure.ACCESSIBILITY_ENABLED),
                false,
                contentObserver!!
            )
            
            // 监听已启用的辅助功能服务列表变化
            context.contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES),
                false,
                contentObserver!!
            )
            
            Log.d(TAG, "开始监听辅助功能状态")
            
            // 立即检查一次状态
            checkAccessibilityServiceStatus()
        } catch (e: Exception) {
            Log.e(TAG, "启动监听失败", e)
        }
    }
    
    /**
     * 停止监听辅助功能状态
     */
    fun stopMonitoring() {
        try {
            contentObserver?.let {
                context.contentResolver.unregisterContentObserver(it)
            }
            contentObserver = null
            Log.d(TAG, "停止监听辅助功能状态")
        } catch (e: Exception) {
            Log.e(TAG, "停止监听失败", e)
        }
    }
    
    /**
     * 检查辅助功能服务状态
     */
    private fun checkAccessibilityServiceStatus() {
        try {
            val isEnabled = isAccessibilityServiceEnabled()
            Log.d(TAG, "辅助功能服务状态: $isEnabled")
            
            if (!isEnabled) {
                Log.w(TAG, "辅助功能服务已被禁用")
                onAccessibilityServiceDisabled()
            } else {
                Log.d(TAG, "辅助功能服务正常运行")
                onAccessibilityServiceEnabled()
            }
        } catch (e: Exception) {
            Log.e(TAG, "检查辅助功能状态失败", e)
        }
    }
    
    /**
     * 检查辅助功能服务是否已启用
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        try {
            // 检查辅助功能是否总体启用
            val accessibilityEnabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            ) == 1
            
            if (!accessibilityEnabled) {
                return false
            }
            
            // 检查我们的服务是否在已启用的服务列表中
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            
            if (enabledServices.isNullOrEmpty()) {
                return false
            }
            
            val serviceName = "${context.packageName}/${ScreenCaptureAccessibilityService::class.java.name}"
            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServices)
            
            while (colonSplitter.hasNext()) {
                val componentName = colonSplitter.next()
                if (componentName.equals(serviceName, ignoreCase = true)) {
                    return true
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "检查辅助功能服务状态失败", e)
            return false
        }
    }
    
    /**
     * 当辅助功能服务被启用时调用
     */
    private fun onAccessibilityServiceEnabled() {
        // 可以在这里添加服务启用后的逻辑
        Log.i(TAG, "辅助功能服务已启用")
    }
    
    /**
     * 当辅助功能服务被禁用时调用
     */
    private fun onAccessibilityServiceDisabled() {
        Log.w(TAG, "辅助功能服务已被禁用，需要用户重新启用")
        
        // 这里可以添加通知用户重新启用服务的逻辑
        // 例如发送通知、显示对话框等
        
        // 清理服务实例状态
        ScreenCaptureAccessibilityService.instance = null
        ScreenCaptureAccessibilityService.isServiceRunning = false
    }
}
