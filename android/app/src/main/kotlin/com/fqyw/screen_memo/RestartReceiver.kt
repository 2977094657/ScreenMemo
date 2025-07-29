package com.fqyw.screen_memo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 服务重启广播接收器
 * 用于在应用被杀死后重启AccessibilityService
 */
class RestartReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "RestartReceiver"
        const val ACTION_RESTART_SERVICE = "com.fqyw.screen_memo.RESTART_SERVICE"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        FileLogger.init(context)
        FileLogger.e(TAG, "=== RestartReceiver 收到广播 ===")
        FileLogger.e(TAG, "广播动作: ${intent.action}")
        FileLogger.e(TAG, "当前进程ID: ${android.os.Process.myPid()}")
        
        when (intent.action) {
            ACTION_RESTART_SERVICE -> {
                FileLogger.e(TAG, "收到服务重启请求")
                restartAccessibilityService(context)
            }
            Intent.ACTION_BOOT_COMPLETED -> {
                FileLogger.e(TAG, "系统启动完成，检查是否需要重启服务")
                checkAndRestartService(context)
            }
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                FileLogger.e(TAG, "应用更新完成，检查是否需要重启服务")
                checkAndRestartService(context)
            }
        }
    }
    
    /**
     * 重启AccessibilityService
     */
    private fun restartAccessibilityService(context: Context) {
        try {
            FileLogger.e(TAG, "准备重启AccessibilityService")
            
            // 使用看门狗进行状态检查
            val watchdogStatus = AccessibilityServiceWatchdog.checkServiceStatus(context)
            FileLogger.e(TAG, "看门狗状态检查结果:")
            FileLogger.e(TAG, "- 系统启用: ${watchdogStatus.isSystemEnabled}")
            FileLogger.e(TAG, "- 实例存在: ${watchdogStatus.isInstanceExists}")
            FileLogger.e(TAG, "- 进程存活: ${watchdogStatus.isProcessAlive}")
            FileLogger.e(TAG, "- 需要重启: ${watchdogStatus.needsRestart}")
            
            if (watchdogStatus.isSystemEnabled) {
                if (watchdogStatus.needsRestart) {
                    FileLogger.e(TAG, "检测到服务需要重启，开始重启流程")
                    
                    // 启动前台服务来保持应用活跃
                    try {
                        val serviceIntent = Intent(context, ScreenCaptureService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                        FileLogger.e(TAG, "前台服务启动成功")
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "启动前台服务失败", e)
                    }
                    
                    // 启动状态监听器
                    try {
                        val monitor = AccessibilityStateMonitor(context)
                        monitor.startMonitoring()
                        FileLogger.e(TAG, "状态监听器启动成功")
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "启动状态监听器失败", e)
                    }
                    
                    // 启动看门狗监控
                    try {
                        AccessibilityServiceWatchdog.startWatchdog(context)
                        FileLogger.e(TAG, "看门狗监控已启动")
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "启动看门狗监控失败", e)
                    }
                    
                } else {
                    FileLogger.e(TAG, "服务状态正常，无需重启")
                }
            } else {
                FileLogger.w(TAG, "AccessibilityService在系统中未启用，无法自动重启")
                FileLogger.w(TAG, "需要用户手动在设置中重新启用AccessibilityService")
            }
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "重启AccessibilityService失败", e)
        }
    }
    
    /**
     * 检查并重启服务
     */
    private fun checkAndRestartService(context: Context) {
        try {
            // 检查服务之前是否在运行
            val sharedPrefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            val wasServiceRunning = sharedPrefs.getBoolean("accessibility_service_running", false)
            
            FileLogger.e(TAG, "服务之前运行状态: $wasServiceRunning")
            
            if (wasServiceRunning) {
                FileLogger.e(TAG, "服务之前在运行，尝试重启")
                restartAccessibilityService(context)
            } else {
                FileLogger.e(TAG, "服务之前未运行，跳过重启")
            }
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查服务状态失败", e)
        }
    }
}
