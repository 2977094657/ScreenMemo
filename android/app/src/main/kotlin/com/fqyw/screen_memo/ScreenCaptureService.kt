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
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.IBinder
import android.util.TypedValue
import java.util.Locale
 
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class ScreenCaptureService : Service() {
    
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "screen_capture_foreground_channel"

        private const val NOTIFICATION_PREFS = "screen_memo_foreground_notification"
        private const val KEY_FOREGROUND_PKG = "foreground_pkg"
        private const val KEY_INTERVAL_SECONDS = "interval_seconds"
        private const val KEY_LAST_SCREENSHOT_AT = "last_screenshot_at"
        private const val KEY_CAPTURE_ENABLED = "capture_enabled"
        private const val KEY_LAST_UPDATE_AT = "last_update_at"

        @Volatile private var cachedLargeIconPkg: String? = null
        @Volatile private var cachedLargeIconBitmap: Bitmap? = null
        
        var isServiceRunning = false

        fun updateNotificationState(
            context: Context,
            foregroundPackage: String? = null,
            intervalSeconds: Int? = null,
            lastScreenshotAt: Long? = null,
            captureEnabled: Boolean? = null
        ) {
            try {
                val sp = context.getSharedPreferences(NOTIFICATION_PREFS, Context.MODE_PRIVATE)
                val prevPkg = try { sp.getString(KEY_FOREGROUND_PKG, null) } catch (_: Exception) { null }
                val prevInterval = try { sp.getInt(KEY_INTERVAL_SECONDS, -1) } catch (_: Exception) { -1 }
                val prevLastShot = try { sp.getLong(KEY_LAST_SCREENSHOT_AT, 0L) } catch (_: Exception) { 0L }
                val prevCapture = try { sp.getBoolean(KEY_CAPTURE_ENABLED, false) } catch (_: Exception) { false }

                val edit = sp.edit()
                var changed = false
                if (foregroundPackage != null) {
                    if (foregroundPackage != prevPkg) {
                        edit.putString(KEY_FOREGROUND_PKG, foregroundPackage)
                        changed = true
                    }
                }
                if (intervalSeconds != null) {
                    if (intervalSeconds != prevInterval) {
                        edit.putInt(KEY_INTERVAL_SECONDS, intervalSeconds)
                        changed = true
                    }
                }
                if (lastScreenshotAt != null) {
                    if (lastScreenshotAt != prevLastShot) {
                        edit.putLong(KEY_LAST_SCREENSHOT_AT, lastScreenshotAt)
                        changed = true
                    }
                }
                if (captureEnabled != null) {
                    if (captureEnabled != prevCapture) {
                        edit.putBoolean(KEY_CAPTURE_ENABLED, captureEnabled)
                        changed = true
                    }
                }
                if (changed) {
                    edit.putLong(KEY_LAST_UPDATE_AT, System.currentTimeMillis())
                    edit.apply()
                }

                if (!changed) {
                    return
                }
            } catch (_: Exception) {}

            refreshNotification(context)
        }

        fun refreshNotification(context: Context) {
            try {
                if (!ServiceStateManager.isForegroundServiceRunning(context)) {
                    return
                }
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, buildNotification(context))
            } catch (_: Exception) {}
        }

        private fun resolveEffectiveLang(context: Context): String {
            return try {
                val langOpt = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getString("flutter.locale_option", "system") ?: "system"
                val sys = Locale.getDefault().language?.lowercase(Locale.ROOT) ?: "en"
                when (langOpt) {
                    "zh", "en", "ja", "ko" -> langOpt
                    "system" -> when {
                        sys.startsWith("zh") -> "zh"
                        sys.startsWith("ja") -> "ja"
                        sys.startsWith("ko") -> "ko"
                        else -> "en"
                    }
                    else -> "en"
                }
            } catch (_: Exception) {
                "en"
            }
        }

        private fun localizedContextForNotification(context: Context): Context {
            return try {
                val lang = resolveEffectiveLang(context)
                val locale = when (lang) {
                    "zh" -> Locale("zh")
                    "ja" -> Locale.JAPANESE
                    "ko" -> Locale.KOREAN
                    else -> Locale.ENGLISH
                }
                val config = android.content.res.Configuration(context.resources.configuration)
                config.setLocale(locale)
                context.createConfigurationContext(config)
            } catch (_: Exception) {
                context
            }
        }

        private fun formatRelativeTime(localizedContext: Context, timeMillis: Long, nowMillis: Long): String {
            return try {
                val diff = (nowMillis - timeMillis).coerceAtLeast(0L)
                val sec = diff / 1000L
                val min = sec / 60L
                val hr = min / 60L
                val day = hr / 24L
                when {
                    sec < 45L -> localizedContext.getString(R.string.fg_time_just_now)
                    min < 60L -> localizedContext.getString(R.string.fg_time_minutes_ago, min.toInt().coerceAtLeast(1))
                    hr < 24L -> localizedContext.getString(R.string.fg_time_hours_ago, hr.toInt().coerceAtLeast(1))
                    else -> localizedContext.getString(R.string.fg_time_days_ago, day.toInt().coerceAtLeast(1))
                }
            } catch (_: Exception) {
                "--"
            }
        }

        private fun buildNotification(context: Context): Notification {
            val lc = localizedContextForNotification(context)
            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val sp = try {
                context.getSharedPreferences(NOTIFICATION_PREFS, Context.MODE_PRIVATE)
            } catch (_: Exception) {
                null
            }

            val foregroundPkg = try { sp?.getString(KEY_FOREGROUND_PKG, null) } catch (_: Exception) { null }
            val intervalSeconds = try {
                val iv = sp?.getInt(KEY_INTERVAL_SECONDS, -1) ?: -1
                if (iv > 0) iv else run {
                    val prefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                    val a = prefs.getInt("screenshot_interval", -1)
                    val b = prefs.getInt("timed_screenshot_interval", -1)
                    when {
                        a > 0 -> a
                        b > 0 -> b
                        else -> -1
                    }
                }
            } catch (_: Exception) { -1 }

            val lastScreenshotAt = try { sp?.getLong(KEY_LAST_SCREENSHOT_AT, 0L) ?: 0L } catch (_: Exception) { 0L }

            val now = System.currentTimeMillis()
            val intervalText = if (intervalSeconds > 0) {
                try {
                    lc.getString(R.string.fg_notif_interval_value, intervalSeconds)
                } catch (_: Exception) {
                    "${intervalSeconds}s"
                }
            } else {
                "--"
            }

            val captureEnabled = try { sp?.getBoolean(KEY_CAPTURE_ENABLED, false) ?: false } catch (_: Exception) { false }
            val captureText = try {
                if (captureEnabled) lc.getString(R.string.fg_notif_capture_on) else lc.getString(R.string.fg_notif_capture_off)
            } catch (_: Exception) {
                if (captureEnabled) "ON" else "OFF"
            }

            val lastText = if (lastScreenshotAt > 0L) {
                formatRelativeTime(lc, lastScreenshotAt, now)
            } else {
                try { lc.getString(R.string.fg_notif_last_never) } catch (_: Exception) { "--" }
            }

            val content = try {
                lc.getString(R.string.fg_notif_status_collapsed, captureText, lastText)
            } catch (_: Exception) {
                "$captureText · $lastText"
            }
            val expandedText = try {
                lc.getString(R.string.fg_notif_status_expanded, captureText, lastText)
            } catch (_: Exception) {
                content
            }
            val titleBase = try { lc.getString(R.string.app_name) } catch (_: Exception) { "ScreenMemo" }
            val title = if (intervalSeconds > 0) {
                try {
                    lc.getString(R.string.fg_notif_title_with_interval, titleBase, intervalText)
                } catch (_: Exception) {
                    "$titleBase · $intervalText"
                }
            } else {
                titleBase
            }

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(content)
                .setStyle(NotificationCompat.BigTextStyle().bigText(expandedText))
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setShowWhen(false)
                .setLocalOnly(true)

            val largeIcon = if (!foregroundPkg.isNullOrBlank()) {
                val cachedPkg = cachedLargeIconPkg
                val cachedBmp = cachedLargeIconBitmap
                if (cachedPkg == foregroundPkg && cachedBmp != null && !cachedBmp.isRecycled) {
                    cachedBmp
                } else {
                    val bmp = try { loadAppIconBitmap(context, foregroundPkg) } catch (_: Exception) { null }
                    if (bmp != null) {
                        cachedLargeIconPkg = foregroundPkg
                        cachedLargeIconBitmap = bmp
                    }
                    bmp
                }
            } else {
                null
            }
            if (largeIcon != null) {
                builder.setLargeIcon(largeIcon)
            }

            return builder.build()
        }

        private fun loadAppIconBitmap(context: Context, packageName: String): Bitmap? {
            val pm = context.packageManager
            val drawable = try { pm.getApplicationIcon(packageName) } catch (_: Exception) { null }
            drawable ?: return null

            val sizePx = try {
                TypedValue.applyDimension(
                    TypedValue.COMPLEX_UNIT_DIP,
                    48f,
                    context.resources.displayMetrics
                ).toInt().coerceAtLeast(1)
            } catch (_: Exception) {
                48
            }

            return drawableToBitmap(drawable, sizePx, sizePx)
        }

        private fun drawableToBitmap(drawable: Drawable, width: Int, height: Int): Bitmap {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }
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

                val lc = localizedContextForNotification(this)
                val channelName = try { lc.getString(R.string.notification_channel_name) } catch (_: Exception) { "Screen capture" }
                val channelDesc = try { lc.getString(R.string.notification_channel_description) } catch (_: Exception) { "" }
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    channelName,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = channelDesc
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
        return buildNotification(this)
    }
}
