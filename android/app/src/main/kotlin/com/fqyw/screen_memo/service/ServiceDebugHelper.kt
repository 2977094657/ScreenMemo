package com.fqyw.screen_memo.service

import com.fqyw.screen_memo.capture.ScreenCaptureAccessibilityService
import com.fqyw.screen_memo.capture.ScreenCaptureService
import com.fqyw.screen_memo.logging.FileLogger
import android.app.ActivityManager
import android.content.Context
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import java.text.SimpleDateFormat
import java.util.*

/**
 * 服务调试助手
 * 用于监控和调试服务状态
 */
object ServiceDebugHelper {
    
    private const val TAG = "ServiceDebugHelper"
    
    /**
     * 检查AccessibilityService是否在系统中启用
     */
    fun isAccessibilityServiceEnabledInSystem(context: Context): Boolean {
        return try {
            // 1) 检查辅助功能总开关
            val accessibilityEnabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            ) == 1
            FileLogger.d(TAG, "系统辅助功能启用状态: $accessibilityEnabled")
            if (!accessibilityEnabled) {
                FileLogger.d(TAG, "系统辅助功能未启用")
                return false
            }

            val targetPkg = context.packageName
            val targetCls = ScreenCaptureAccessibilityService::class.java.name

            // 2) 从 Settings 读取并“规范化”每个条目后再比对
            val enabledServicesRaw = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""
            FileLogger.d(TAG, "已启用的服务列表: $enabledServicesRaw")

            var isEnabledInSettings = false
            if (enabledServicesRaw.isNotEmpty()) {
                val colonSplitter = TextUtils.SimpleStringSplitter(':')
                colonSplitter.setString(enabledServicesRaw)
                while (colonSplitter.hasNext()) {
                    val entry = colonSplitter.next()
                    // 使用 ComponentName 解析：可自动处理诸如 ".Class" 的短类名
                    val cn = ComponentName.unflattenFromString(entry)
                    if (cn != null) {
                        val pkg = cn.packageName
                        val cls = cn.className // 若为短类名将被还原为完整限定名
                        FileLogger.d(TAG, "检查服务组件: $entry -> 规范化: ${pkg}/${cls}")
                        if (pkg.equals(targetPkg, true) && cls.equals(targetCls, true)) {
                            isEnabledInSettings = true
                            break
                        }
                    } else {
                        // 兜底：直接比较可能存在的两种字符串形式
                        val expectedFull = "$targetPkg/$targetCls"
                        val expectedShort = "$targetPkg/.${ScreenCaptureAccessibilityService::class.java.simpleName}"
                        if (entry.equals(expectedFull, ignoreCase = true) || entry.equals(expectedShort, ignoreCase = true)) {
                            isEnabledInSettings = true
                            break
                        }
                    }
                }
            }

            // 3) 通过 AccessibilityManager 再次核对
            var isEnabledInManager = false
            try {
                val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
                val list = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                isEnabledInManager = list.any { info ->
                    val si = info.resolveInfo.serviceInfo
                    si.packageName.equals(targetPkg, true) && si.name.equals(targetCls, true)
                }
            } catch (e: Exception) {
                FileLogger.w(TAG, "通过AccessibilityManager检查失败: ${e.message}")
            }

            val result = isEnabledInSettings || isEnabledInManager
            FileLogger.d(TAG, "系统启用检查 - Settings: $isEnabledInSettings, Manager: $isEnabledInManager, 最终: $result")
            if (!result) {
                FileLogger.d(TAG, "完整对比 - 期望: $targetPkg/$targetCls")
                FileLogger.d(TAG, "完整对比 - 实际: $enabledServicesRaw")
            }
            result
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查AccessibilityService系统状态失败", e)
            false
        }
    }

    /**
     * 检查服务进程是否在运行
     */
    fun isServiceProcessRunning(context: Context): Boolean {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningProcesses = activityManager.runningAppProcesses
            
            val accessibilityProcessName = "${context.packageName}:accessibility"
            
            runningProcesses?.forEach { processInfo ->
                FileLogger.d(TAG, "运行中的进程: ${processInfo.processName}, PID: ${processInfo.pid}")
                if (processInfo.processName == accessibilityProcessName) {
                    FileLogger.d(TAG, "AccessibilityService进程正在运行: ${processInfo.processName}")
                    return true
                }
            }
            
            FileLogger.d(TAG, "AccessibilityService进程未运行")
            return false
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查服务进程失败", e)
            return false
        }
    }
    
    /**
     * 检查服务实例状态
     */
    fun checkServiceInstanceStatus(): Map<String, Any> {
        return mapOf(
            "instanceExists" to (ScreenCaptureAccessibilityService.instance != null),
            "isServiceRunning" to ScreenCaptureAccessibilityService.isServiceRunning,
            "foregroundServiceRunning" to ScreenCaptureService.isServiceRunning
        )
    }
    
    /**
     * 执行完整的服务状态检查
     */
    fun performFullStatusCheck(context: Context) {
        FileLogger.writeSeparator("开始完整服务状态检查")

        // 检查系统状态
        val systemEnabled = isAccessibilityServiceEnabledInSystem(context)
        FileLogger.d(TAG, "系统中AccessibilityService启用状态: $systemEnabled")

        // 检查进程状态
        val processRunning = isServiceProcessRunning(context)
        FileLogger.d(TAG, "AccessibilityService进程运行状态: $processRunning")

        // 检查实例状态
        val instanceStatus = checkServiceInstanceStatus()
        FileLogger.d(TAG, "服务实例状态: $instanceStatus")

        // 检查SharedPreferences状态
        ServiceStateManager.printAllStates(context)

        // 检查当前进程信息
        FileLogger.d(TAG, "当前进程ID: ${android.os.Process.myPid()}")
        FileLogger.d(TAG, "当前进程名: ${getCurrentProcessName(context)}")

        FileLogger.writeSeparator("服务状态检查完成")
    }
    
    /**
     * 获取当前进程名
     */
    private fun getCurrentProcessName(context: Context): String {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningProcesses = activityManager.runningAppProcesses
            val currentPid = android.os.Process.myPid()
            
            runningProcesses?.forEach { processInfo ->
                if (processInfo.pid == currentPid) {
                    return processInfo.processName
                }
            }
            "Unknown"
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取进程名失败", e)
            "Error"
        }
    }
    
    /**
     * 监控服务状态变化
     */
    fun startStatusMonitoring(context: Context, intervalMs: Long = 10000) {
        FileLogger.d(TAG, "开始监控服务状态，间隔: ${intervalMs}ms")
        
        val timer = Timer()
        timer.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                try {
                    FileLogger.d(TAG, "--- 定时状态检查 ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())} ---")
                    performFullStatusCheck(context)
                } catch (e: Exception) {
                    FileLogger.e(TAG, "定时状态检查失败", e)
                }
            }
        }, 0, intervalMs)
    }
    
    /**
     * 尝试重启AccessibilityService
     */
    fun attemptRestartAccessibilityService(context: Context) {
        FileLogger.d(TAG, "尝试重启AccessibilityService")
        
        try {
            // 检查当前状态
            performFullStatusCheck(context)
            
            // 如果系统中已启用但实例不存在，可能需要用户重新启用
            val systemEnabled = isAccessibilityServiceEnabledInSystem(context)
            val instanceExists = ScreenCaptureAccessibilityService.instance != null
            
            if (systemEnabled && !instanceExists) {
                FileLogger.w(TAG, "系统中已启用但实例不存在，可能需要用户重新启用服务")
            } else if (!systemEnabled) {
                FileLogger.w(TAG, "系统中未启用AccessibilityService，需要用户手动启用")
            }
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "重启AccessibilityService失败", e)
        }
    }
}
