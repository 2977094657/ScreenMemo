package com.fqyw.screen_memo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
 

/**
 * 系统事件广播接收器
 * 监听系统事件来触发服务重启
 */
class SystemEventReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "SystemEventReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        FileLogger.init(context)
        FileLogger.e(TAG, "=== 收到系统广播: ${intent.action} ===")
        
        when (intent.action) {
            // 屏幕解锁
            Intent.ACTION_USER_PRESENT -> {
                FileLogger.e(TAG, "用户解锁屏幕")
                checkAndRestartServices(context)
                // 解锁恢复定时截屏
                tryResumeTimedScreenshot()
            }
            
            // 屏幕亮起
            Intent.ACTION_SCREEN_ON -> {
                FileLogger.e(TAG, "屏幕亮起")
                checkAndRestartServices(context)
                // 亮屏恢复定时截屏
                tryResumeTimedScreenshot()
            }
            
            // 屏幕熄灭
            Intent.ACTION_SCREEN_OFF -> {
                FileLogger.e(TAG, "屏幕熄灭")
                tryPauseTimedScreenshot()
            }
            
            // 网络连接变化
            "android.net.conn.CONNECTIVITY_CHANGE" -> {
                FileLogger.e(TAG, "网络状态变化")
                checkAndRestartServices(context)
            }
            
            // 电源连接
            Intent.ACTION_POWER_CONNECTED -> {
                FileLogger.e(TAG, "电源已连接")
                checkAndRestartServices(context)
            }
            
            // 时间变化（每分钟）
            Intent.ACTION_TIME_TICK -> {
                // 每分钟触发一次，用于定期检查
                checkServicesQuietly(context)
            }
            
            // 自定义广播：触发AccessibilityService重连
            "com.fqyw.screen_memo.TRIGGER_ACCESSIBILITY_RECONNECT" -> {
                FileLogger.e(TAG, "收到触发重连请求")
                triggerAccessibilityReconnect(context)
            }
            
            // 自定义广播：重启守护服务
            "com.fqyw.screen_memo.RESTART_DAEMON" -> {
                FileLogger.e(TAG, "收到重启守护服务请求")
                startDaemonService(context)
            }
        }
    }
    
    /**
     * 检查并重启服务
     */
    private fun checkAndRestartServices(context: Context) {
        try {
            // 检查AccessibilityService状态
            val isSystemEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(context)
            val instanceExists = ScreenCaptureAccessibilityService.instance != null
            
            FileLogger.e(TAG, "AccessibilityService系统启用: $isSystemEnabled, 实例存在: $instanceExists")
            
            if (isSystemEnabled && !instanceExists) {
                FileLogger.e(TAG, "检测到服务异常，尝试修复")
                
                // 启动前台服务
                startForegroundServiceCompat(context)
                
                // 触发AccessibilityService重连
                triggerAccessibilityReconnect(context)
            }
            
            // 不再单独启动守护服务，仅依赖前台服务
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查服务状态失败", e)
        }
    }

    /**
     * 尝试暂停定时截屏（灭屏）
     */
    private fun tryPauseTimedScreenshot() {
        try {
            ScreenCaptureAccessibilityService.instance?.pauseTimedScreenshotForScreenOff()
        } catch (e: Exception) {
            FileLogger.e(TAG, "暂停定时截屏失败", e)
        }
    }

    /**
     * 尝试恢复定时截屏（亮屏/解锁）
     */
    private fun tryResumeTimedScreenshot() {
        try {
            ScreenCaptureAccessibilityService.instance?.resumeTimedScreenshotIfPaused()
        } catch (e: Exception) {
            FileLogger.e(TAG, "恢复定时截屏失败", e)
        }
    }
    
    /**
     * 静默检查服务（不记录详细日志）
     */
    private fun checkServicesQuietly(context: Context) {
        try {
            val isSystemEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(context)
            val instanceExists = ScreenCaptureAccessibilityService.instance != null
            
            if (isSystemEnabled && !instanceExists) {
                // 只在发现问题时记录日志
                FileLogger.w(TAG, "定期检查发现服务异常")
                checkAndRestartServices(context)
            }
        } catch (e: Exception) {
            // 静默失败
        }
    }
    
    /**
     * 触发AccessibilityService重连
     */
    private fun triggerAccessibilityReconnect(context: Context) {
        try {
            // 启动MainActivity（静默模式）
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION or Intent.FLAG_ACTIVITY_NO_USER_ACTION
                putExtra("silent_start", true)
                putExtra("check_service_only", true)
            }
            context.startActivity(intent)
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "触发重连失败", e)
        }
    }
    
    /**
     * 启动守护服务
     */
    private fun startDaemonService(context: Context) {
        try {
            val serviceIntent = Intent(context, DaemonService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            FileLogger.e(TAG, "守护服务启动成功")
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动守护服务失败", e)
        }
    }
    
    /**
     * 启动前台服务
     */
    private fun startForegroundServiceCompat(context: Context) {
        try {
            val serviceIntent = Intent(context, ScreenCaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动前台服务失败", e)
        }
    }
}