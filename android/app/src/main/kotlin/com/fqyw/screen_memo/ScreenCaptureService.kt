package com.fqyw.screen_memo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
 
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class ScreenCaptureService : Service() {
    
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "screen_capture_foreground_channel"
        
        var isServiceRunning = false
    }
    
    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        FileLogger.d(TAG, "前台服务已创建，进程ID: ${android.os.Process.myPid()}")

        // 同步文件日志开关（避免 Accessibility 尚未就绪时丢日志）
        try { FileLogger.syncFromFlutterPrefs(this) } catch (_: Exception) {}

        // 创建通知渠道
        createNotificationChannel()

        // 更新状态
        ServiceStateManager.setForegroundServiceRunning(this, true)
        ServiceStateManager.printAllStates(this)
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        FileLogger.e(TAG, "=== 前台服务 onStartCommand 开始 ===")
        FileLogger.e(TAG, "前台服务已启动，进程ID: ${android.os.Process.myPid()}")

        try {
            // 启动前台服务
            // 注意：我们使用的是无障碍服务截屏，不需要MEDIA_PROJECTION类型
            startForeground(NOTIFICATION_ID, createNotification())
            FileLogger.e(TAG, "前台服务通知已创建，服务类型: MEDIA_PROJECTION")

            // 更新状态
            ServiceStateManager.setForegroundServiceRunning(this, true)
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动前台服务失败", e)
        }

        // 保障段落采样在服务生命周期内可被触发（即便应用被刷掉）
        try {
            // 这里不做定时器常驻，只保证进程在，实际采样在每次截图后由 SegmentSummaryManager 驱动
            FileLogger.e(TAG, "SegmentSummaryManager 保活环境就绪")
        } catch (_: Exception) {}

        FileLogger.e(TAG, "=== 前台服务 onStartCommand 完成 ===")
        return START_STICKY // 服务被杀死后自动重启
    }
    
    override fun onDestroy() {
        super.onDestroy()
        isServiceRunning = false
        FileLogger.e(TAG, "前台服务已销毁")

        // 更新状态
        ServiceStateManager.setForegroundServiceRunning(this, false)
        ServiceStateManager.printAllStates(this)
    }

    /**
     * 当应用任务被移除时调用
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        FileLogger.e(TAG, "=== 前台服务 onTaskRemoved ===")
        FileLogger.e(TAG, "应用任务被移除，重启服务")

        try {
            // 重启自己
            val restartIntent = Intent(applicationContext, ScreenCaptureService::class.java)
            val pendingIntent = PendingIntent.getService(
                applicationContext,
                1,
                restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME,
                android.os.SystemClock.elapsedRealtime() + 1000,
                pendingIntent
            )

            FileLogger.e(TAG, "前台服务重启闹钟已设置")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置前台服务重启失败", e)
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    /**
     * 创建通知渠道
     */
    private fun createNotificationChannel() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                FileLogger.e(TAG, "准备创建前台服务通知渠道")

                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // 检查渠道是否已存在
                val existingChannel = notificationManager.getNotificationChannel(CHANNEL_ID)
                if (existingChannel != null) {
                    FileLogger.e(TAG, "前台服务通知渠道已存在: ${existingChannel.name}")
                    return
                }

                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "屏幕截图前台服务",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "用于保持屏幕截图功能在后台运行"
                    setShowBadge(false)
                    setBypassDnd(false)
                    enableLights(false)
                    enableVibration(false)
                    setSound(null, null)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }

                notificationManager.createNotificationChannel(channel)
                FileLogger.e(TAG, "前台服务通知渠道创建成功: $CHANNEL_ID")

                // 验证渠道创建是否成功
                val createdChannel = notificationManager.getNotificationChannel(CHANNEL_ID)
                if (createdChannel != null) {
                    FileLogger.e(TAG, "前台服务通知渠道验证成功，重要性级别: ${createdChannel.importance}")
                } else {
                    FileLogger.e(TAG, "前台服务通知渠道验证失败")
                }
            } else {
                FileLogger.e(TAG, "Android版本低于8.0，无需创建前台服务通知渠道")
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "创建前台服务通知渠道失败", e)
        }
    }
    
    /**
     * 创建前台服务通知
     */
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("屏幕截图服务")
            .setContentText("正在后台运行，确保截图功能可用")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
