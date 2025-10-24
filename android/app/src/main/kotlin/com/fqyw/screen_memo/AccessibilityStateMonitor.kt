package com.fqyw.screen_memo

import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
 

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
            
            FileLogger.d(TAG, "开始监听辅助功能状态")
            
            // 立即检查一次状态
            checkAccessibilityServiceStatus()
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动监听失败", e)
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
            FileLogger.d(TAG, "停止监听辅助功能状态")
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止监听失败", e)
        }
    }
    
    /**
     * 检查辅助功能服务状态
     */
    private fun checkAccessibilityServiceStatus() {
        try {
            val isEnabled = isAccessibilityServiceEnabled()
            FileLogger.d(TAG, "辅助功能服务状态: $isEnabled")
            
            if (!isEnabled) {
                FileLogger.w(TAG, "辅助功能服务已被禁用")
                onAccessibilityServiceDisabled()
            } else {
                FileLogger.d(TAG, "辅助功能服务正常运行")
                onAccessibilityServiceEnabled()
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查辅助功能状态失败", e)
        }
    }
    
    /**
     * 检查辅助功能服务是否已启用
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        try {
            // 1) 检查辅助功能总开关
            val accessibilityEnabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            ) == 1
            if (!accessibilityEnabled) {
                return false
            }

            val targetPkg = context.packageName
            val targetCls = ScreenCaptureAccessibilityService::class.java.name

            // 2) 从 Settings 读取并“规范化”每个条目后再比对，兼容短类名
            val enabledServicesRaw = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""

            var isEnabledInSettings = false
            if (enabledServicesRaw.isNotEmpty()) {
                val colonSplitter = TextUtils.SimpleStringSplitter(':')
                colonSplitter.setString(enabledServicesRaw)
                while (colonSplitter.hasNext()) {
                    val entry = colonSplitter.next()
                    val cn = ComponentName.unflattenFromString(entry)
                    if (cn != null) {
                        if (cn.packageName.equals(targetPkg, true) && cn.className.equals(targetCls, true)) {
                            isEnabledInSettings = true
                            break
                        }
                    } else {
                        val expectedFull = "$targetPkg/$targetCls"
                        val expectedShort = "$targetPkg/.${ScreenCaptureAccessibilityService::class.java.simpleName}"
                        if (entry.equals(expectedFull, true) || entry.equals(expectedShort, true)) {
                            isEnabledInSettings = true
                            break
                        }
                    }
                }
            }

            // 3) 通过 AccessibilityManager 再次核对
            var isEnabledInManager = false
            try {
                val am = context.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
                val list = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                isEnabledInManager = list.any { info ->
                    val si = info.resolveInfo.serviceInfo
                    si.packageName.equals(targetPkg, true) && si.name.equals(targetCls, true)
                }
            } catch (_: Exception) {}

            return isEnabledInSettings || isEnabledInManager
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查辅助功能服务状态失败", e)
            return false
        }
    }
    
    /**
     * 当辅助功能服务被启用时调用
     */
    private fun onAccessibilityServiceEnabled() {
        // 可以在这里添加服务启用后的逻辑
        FileLogger.i(TAG, "辅助功能服务已启用")
    }
    
    /**
     * 当辅助功能服务被禁用时调用
     */
    private fun onAccessibilityServiceDisabled() {
        FileLogger.w(TAG, "辅助功能服务已被禁用，需要用户重新启用")
        
        // 这里可以添加通知用户重新启用服务的逻辑
        // 例如发送通知、显示对话框等
        
        // 清理服务实例状态
        ScreenCaptureAccessibilityService.instance = null
        ScreenCaptureAccessibilityService.isServiceRunning = false
    }
}
