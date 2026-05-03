package com.fqyw.screen_memo.service

import com.fqyw.screen_memo.capture.ScreenCaptureAccessibilityService
import com.fqyw.screen_memo.capture.ScreenCaptureService
import com.fqyw.screen_memo.IAccessibilityServiceAidl
import com.fqyw.screen_memo.logging.FileLogger
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.os.Process
 
import androidx.core.app.NotificationCompat
import java.util.Timer
import java.util.TimerTask

/**
 * 守护服务，用于监控和维护AccessibilityService的运行状态
 * 运行在独立进程中
 */
// 已弃用：避免重复前台通知，调试需要可临时恢复
class DaemonService : Service() {
    
    companion object {
        private const val TAG = "DaemonService"
        private const val NOTIFICATION_ID = 1003
        private const val CHANNEL_ID = "daemon_service_channel"
        private const val CHECK_INTERVAL = 10000L // 10秒检查一次
    }
    
    private var checkTimer: Timer? = null
    private var accessibilityBinder: IAccessibilityServiceAidl? = null
    
    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            FileLogger.e(TAG, "AccessibilityService连接成功")
            accessibilityBinder = IAccessibilityServiceAidl.Stub.asInterface(service)
        }
        
        override fun onServiceDisconnected(name: ComponentName?) {
            FileLogger.e(TAG, "AccessibilityService连接断开")
            accessibilityBinder = null
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        FileLogger.init(this)
        FileLogger.e(TAG, "守护服务创建，进程ID: ${Process.myPid()}")
        
        // 已禁用前台通知，避免状态栏重复
        // startForegroundService()
        
        // 绑定AccessibilityService
        bindAccessibilityService()
        
        // 停止定期检查，交由前台服务与系统事件维持
        // startChecking()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        FileLogger.e(TAG, "守护服务启动命令")
        return START_STICKY // 被杀后自动重启
    }
    
    override fun onDestroy() {
        super.onDestroy()
        FileLogger.e(TAG, "守护服务销毁")
        
        // 停止检查
        checkTimer?.cancel()
        checkTimer = null
        
        // 解绑服务
        try {
            unbindService(serviceConnection)
        } catch (e: Exception) {
            FileLogger.e(TAG, "解绑服务失败", e)
        }
        
        // 尝试重启自己
        sendBroadcast(Intent("com.fqyw.screen_memo.RESTART_DAEMON"))
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        FileLogger.e(TAG, "任务被移除，尝试重启")
        
        // 发送重启广播
        sendBroadcast(Intent("com.fqyw.screen_memo.RESTART_DAEMON"))
    }
    
    private fun startForegroundService() {
        try {
            createNotificationChannel()
            val notification = createNotification()
            startForeground(NOTIFICATION_ID, notification)
            FileLogger.e(TAG, "守护服务前台通知创建成功")
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动前台服务失败", e)
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "守护服务",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "用于保持截屏服务稳定运行"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("屏忆守护服务")
            .setContentText("正在保护截屏服务稳定运行")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }
    
    private fun bindAccessibilityService() {
        try {
            val intent = Intent().apply {
                component = ComponentName(packageName, "$packageName.ScreenCaptureAccessibilityService")
            }
            bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
            FileLogger.e(TAG, "开始绑定AccessibilityService")
        } catch (e: Exception) {
            FileLogger.e(TAG, "绑定AccessibilityService失败", e)
        }
    }
    
    private fun startChecking() {
        checkTimer = Timer("DaemonCheckTimer", true)
        checkTimer?.schedule(object : TimerTask() {
            override fun run() {
                checkServices()
            }
        }, CHECK_INTERVAL, CHECK_INTERVAL)
        
        FileLogger.e(TAG, "开始定期检查服务状态")
    }
    
    private fun checkServices() {
        try {
            // 检查AccessibilityService是否在系统中启用
            val isSystemEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(this)
            FileLogger.d(TAG, "AccessibilityService系统启用状态: $isSystemEnabled")
            
            // 检查服务实例是否存在
            val isRunning = try {
                accessibilityBinder?.isServiceRunning() ?: false
            } catch (e: Exception) {
                FileLogger.w(TAG, "无法获取服务运行状态: ${e.message}")
                false
            }
            
            FileLogger.d(TAG, "AccessibilityService运行状态: $isRunning")
            
            // 如果系统中已启用但服务未运行，尝试触发重连
            if (isSystemEnabled && !isRunning) {
                FileLogger.w(TAG, "检测到服务异常，尝试修复")
                triggerServiceReconnection()
            }
            
            // 检查前台服务
            if (!ScreenCaptureService.isServiceRunning) {
                FileLogger.w(TAG, "前台服务未运行，尝试启动")
                startForegroundServiceCompat()
            }
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查服务状态失败", e)
        }
    }
    
    private fun triggerServiceReconnection() {
        try {
            // 方法1：发送广播触发重连
            sendBroadcast(Intent("com.fqyw.screen_memo.TRIGGER_ACCESSIBILITY_RECONNECT"))
            
            // 方法2：不再启动Activity，避免打断当前前台界面
            // 仅依赖广播与服务重连来恢复
            
            // 方法3：重新绑定服务
            try {
                unbindService(serviceConnection)
            } catch (e: Exception) {
                // 忽略解绑错误
            }
            bindAccessibilityService()
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "触发服务重连失败", e)
        }
    }
    
    private fun startForegroundServiceCompat() {
        try {
            val serviceIntent = Intent(this, ScreenCaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动前台服务失败", e)
        }
    }
}