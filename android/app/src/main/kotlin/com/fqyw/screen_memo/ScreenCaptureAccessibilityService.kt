package com.fqyw.screen_memo

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
import kotlin.concurrent.timer
import android.os.IBinder

class ScreenCaptureAccessibilityService : AccessibilityService() {
    
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "screen_capture_channel"
        private const val REQUEST_CODE = 1000
        private const val RESTART_REQUEST_CODE = 2000

        var instance: ScreenCaptureAccessibilityService? = null
        var isServiceRunning = false
    }
    
    // 添加WakeLock防止Doze模式
    private var wakeLock: PowerManager.WakeLock? = null

    // 定时截屏相关
    private var screenshotTimer: Timer? = null
    private var screenshotInterval: Int = 5 // 默认5秒
    private var isTimedScreenshotRunning = false

    // 前台应用检测定时器
    private var foregroundAppTimer: Timer? = null
    private var isForegroundDetectionRunning = false
    private val foregroundDetectionInterval = 500L // 0.5秒检测间隔
    private var usageStatsManager: UsageStatsManager? = null

    // 当前前台应用包名
    private var currentForegroundApp: String? = null

    // 简化的应用会话管理
    private var currentSessionApp: String? = null  // 当前会话中的应用
    private var sessionStartTime: Long = 0         // 会话开始时间



    // 简化的处理器（仅用于基本操作）
    private val handler = Handler(Looper.getMainLooper())

    // 首页/桌面应用包名列表
    private val launcherApps = setOf(
        "com.android.launcher",
        "com.android.launcher3",
        "com.miui.home",
        "com.huawei.android.launcher",
        "com.oppo.launcher",
        "com.vivo.launcher",
        "com.samsung.android.app.launcher",
        "com.oneplus.launcher",
        "com.realme.launcher",
        "com.xiaomi.launcher"
    )
    
    override fun onCreate() {
        super.onCreate()

        // 初始化文件日志
        FileLogger.init(this)
        FileLogger.writeSeparator("AccessibilityService onCreate")
        FileLogger.writeSystemInfo(this)

        FileLogger.e(TAG, "=== 无障碍服务 onCreate 开始 ===")
        FileLogger.e(TAG, "无障碍服务已创建，进程ID: ${android.os.Process.myPid()}")
        FileLogger.e(TAG, "当前时间: ${System.currentTimeMillis()}")
        FileLogger.e(TAG, "日志文件路径: ${FileLogger.getLogFilePath()}")

        // 预设instance，以防onServiceConnected没有被调用
        instance = this
        FileLogger.e(TAG, "已在onCreate中设置instance")

        FileLogger.e(TAG, "=== 无障碍服务 onCreate 完成 ===")
    }
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        FileLogger.writeSeparator("AccessibilityService onServiceConnected")
        FileLogger.e(TAG, "=== 无障碍服务 onServiceConnected 开始 ===")
        FileLogger.e(TAG, "无障碍服务已连接到系统")
        FileLogger.e(TAG, "当前进程ID: ${android.os.Process.myPid()}")

        // 确保服务状态正确
        instance = this
        isServiceRunning = true

        try {
            // 使用新的状态管理器保存状态
            FileLogger.e(TAG, "准备设置服务状态...")
            ServiceStateManager.setAccessibilityServiceRunning(this, true)
            ServiceStateManager.setAccessibilityServiceEnabled(this, true)
            FileLogger.e(TAG, "服务状态设置完成")

            ServiceStateManager.printAllStates(this)

            // 启动看门狗监控
            AccessibilityServiceWatchdog.startWatchdog(this)
            AccessibilityServiceWatchdog.updateHeartbeat()
            FileLogger.e(TAG, "看门狗监控已启动")

            // 延迟初始化其他功能，避免阻塞服务启动
            handler.postDelayed({
                try {
                    // 启动前台服务
                    startForegroundService()
                    FileLogger.e(TAG, "前台服务已启动")

                    // 获取WakeLock
                    acquireWakeLock()
                    FileLogger.e(TAG, "WakeLock已获取")

                    // 初始化UsageStatsManager
                    usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    FileLogger.e(TAG, "UsageStatsManager已初始化")

                    // 启动前台应用检测
                    startForegroundAppDetection()
                    FileLogger.e(TAG, "前台应用检测已启动")

                    // 更新心跳
                    AccessibilityServiceWatchdog.updateHeartbeat()

                } catch (e: Exception) {
                    FileLogger.e(TAG, "延迟初始化过程中发生错误", e)
                }
            }, 1000)

        } catch (e: Exception) {
            FileLogger.e(TAG, "onServiceConnected 过程中发生错误", e)
        }

        FileLogger.e(TAG, "=== 无障碍服务连接完成，进程ID: ${android.os.Process.myPid()} ===")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        FileLogger.writeSeparator("AccessibilityService onUnbind - 服务断开连接")
        FileLogger.e(TAG, "=== 无障碍服务正在断开连接 ===")
        FileLogger.e(TAG, "断开原因: 可能是应用被清理或服务被禁用")
        FileLogger.e(TAG, "当前进程ID: ${android.os.Process.myPid()}")

        // 清理资源
        stopScreenCapture()
        releaseWakeLock()

        // 使用新的状态管理器保存状态
        ServiceStateManager.setAccessibilityServiceRunning(this, false)
        ServiceStateManager.setAccessibilityServiceEnabled(this, false)
        ServiceStateManager.printAllStates(this)

        instance = null
        isServiceRunning = false

        FileLogger.e(TAG, "=== 无障碍服务已断开连接 ===")

        // 返回false表示不希望重新绑定
        return false
    }

    override fun onDestroy() {
        super.onDestroy()
        FileLogger.writeSeparator("AccessibilityService onDestroy - 服务销毁")
        FileLogger.e(TAG, "=== 无障碍服务正在销毁 ===")
        FileLogger.e(TAG, "当前进程ID: ${android.os.Process.myPid()}")

        // 停止看门狗监控
        AccessibilityServiceWatchdog.stopWatchdog()
        FileLogger.e(TAG, "看门狗监控已停止")

        instance = null
        isServiceRunning = false

        // 停止截屏相关服务
        stopTimedScreenshot()

        // 停止前台应用检测
        stopForegroundAppDetection()

        // 释放WakeLock
        releaseWakeLock()

        // 保存服务停止状态
        saveServiceState(false)

        // 设置重启闹钟
        scheduleRestart()

        FileLogger.e(TAG, "=== 无障碍服务已销毁 ===")
    }

    /**
     * 当应用任务被移除时调用（用户清理后台应用）
     * 这是保活的关键方法
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        FileLogger.writeSeparator("AccessibilityService onTaskRemoved - 应用被清理")
        FileLogger.e(TAG, "=== 应用任务被移除 ===")
        FileLogger.e(TAG, "rootIntent: $rootIntent")
        FileLogger.e(TAG, "当前进程ID: ${android.os.Process.myPid()}")

        try {
            // 保存服务状态，表明服务应该继续运行
            saveServiceState(true)
            FileLogger.e(TAG, "服务状态已保存为运行中")

            // 立即设置重启闹钟
            scheduleRestart()
            FileLogger.e(TAG, "重启闹钟已设置")

            // 启动前台服务来保持应用活跃
            try {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                startForegroundService(serviceIntent)
                FileLogger.e(TAG, "前台服务启动成功")
            } catch (e: Exception) {
                FileLogger.e(TAG, "启动前台服务失败", e)
            }
            
            // 保存当前的定时截屏状态
            if (isTimedScreenshotRunning) {
                val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                sharedPrefs.edit().apply {
                    putBoolean("timed_screenshot_was_running", true)
                    putInt("timed_screenshot_interval", screenshotInterval)
                    apply()
                }
                FileLogger.e(TAG, "定时截屏状态已保存")
            }

        } catch (e: Exception) {
            FileLogger.e(TAG, "onTaskRemoved处理失败", e)
        }

        FileLogger.e(TAG, "=== onTaskRemoved处理完成 ===")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 更新看门狗心跳
        AccessibilityServiceWatchdog.updateHeartbeat()
        
        // 处理无障碍事件，检测当前前台应用
        event?.let {
            if (it.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                val packageName = it.packageName?.toString()
                if (packageName != null && packageName != currentForegroundApp) {
                    // 直接更新前台应用，不需要稳定性验证
                    currentForegroundApp = packageName
                    FileLogger.d(TAG, "AccessibilityEvent检测到前台应用变化: $packageName")
                    updateAppSession(packageName)
                }
            }
        }
    }

    /**
     * 简化的应用会话更新逻辑
     * 仅用于日志记录，不影响截屏判断
     */
    private fun updateAppSession(packageName: String) {
        val currentTime = System.currentTimeMillis()

        when {
            // 检测到首页/桌面应用
            launcherApps.contains(packageName) -> {
                if (currentSessionApp != null) {
                    FileLogger.d(TAG, "检测到首页: $packageName，记录会话结束: $currentSessionApp")
                    currentSessionApp = null
                    sessionStartTime = 0
                } else {
                    FileLogger.d(TAG, "检测到首页: $packageName，当前无活跃会话")
                }
            }

            // 检测到监控列表中的应用
            isAppInMonitorList(packageName) -> {
                if (currentSessionApp != packageName) {
                    val previousApp = currentSessionApp
                    currentSessionApp = packageName
                    sessionStartTime = currentTime

                    if (previousApp != null) {
                        FileLogger.i(TAG, "切换应用会话: $previousApp -> $packageName")
                    } else {
                        FileLogger.i(TAG, "开始新的应用会话: $packageName")
                    }
                } else {
                    FileLogger.d(TAG, "继续当前会话: $packageName")
                }
            }

            // 检测到其他应用
            else -> {
                if (isMiuiSystemApp(packageName)) {
                    FileLogger.d(TAG, "检测到MIUI系统应用: $packageName，忽略")
                } else {
                    FileLogger.d(TAG, "检测到其他应用: $packageName")
                }
            }
        }
    }

    /**
     * 检查是否是MIUI系统应用
     */
    private fun isMiuiSystemApp(packageName: String): Boolean {
        val miuiSystemApps = setOf(
            "com.miui.personalassistant",  // MIUI个人助理
            "com.miui.securitycenter",     // MIUI安全中心
            "com.miui.powerkeeper",        // MIUI电源管理
            "com.miui.notification",       // MIUI通知管理
            "com.miui.systemui",           // MIUI系统界面
            "com.android.systemui",        // Android系统界面
            "com.miui.contentextension",   // MIUI内容扩展
            "com.miui.touchassistant"      // MIUI悬浮球
        )
        return miuiSystemApps.contains(packageName)
    }





    /**
     * 主动获取当前前台应用
     * 通过AccessibilityService的能力获取当前窗口信息
     */
    private fun getCurrentForegroundApp(): String? {
        try {
            // 尝试通过AccessibilityService获取当前窗口
            val windows = windows
            if (windows != null && windows.isNotEmpty()) {
                for (window in windows) {
                    if (window.type == AccessibilityWindowInfo.TYPE_APPLICATION) {
                        val root = window.root
                        if (root != null) {
                            val packageName = root.packageName?.toString()
                            root.recycle()
                            if (packageName != null) {
                                FileLogger.d(TAG, "通过窗口信息获取到前台应用: $packageName")
                                return packageName
                            }
                        }
                    }
                }
            }

            // 如果无法通过窗口获取，返回最后记录的前台应用
            FileLogger.d(TAG, "无法通过窗口获取前台应用，使用最后记录的: $currentForegroundApp")
            return currentForegroundApp
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取当前前台应用失败", e)
            return currentForegroundApp
        }
    }
    
    override fun onInterrupt() {
        Log.d(TAG, "无障碍服务被中断")
    }
    
    
    /**
     * 使用无障碍服务截取屏幕
     */
    private fun takeScreenshotUsingAccessibility(callback: (Boolean, String?) -> Unit) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                FileLogger.d(TAG, "使用无障碍服务takeScreenshot API截屏")
                
                takeScreenshot(
                    android.view.Display.DEFAULT_DISPLAY,
                    { runnable -> runnable.run() },
                    object : AccessibilityService.TakeScreenshotCallback {
                        override fun onSuccess(screenshotResult: AccessibilityService.ScreenshotResult) {
                            try {
                                FileLogger.d(TAG, "截屏成功，开始保存")
                                val bitmap = Bitmap.wrapHardwareBuffer(
                                    screenshotResult.hardwareBuffer, 
                                    screenshotResult.colorSpace
                                )
                                
                                if (bitmap != null) {
                                    val targetApp = getScreenshotTargetApp() ?: "unknown"
                                    val savedPath = saveScreenshotBitmap(bitmap, targetApp)
                                    callback(true, savedPath)
                                } else {
                                    FileLogger.e(TAG, "无法从截屏结果创建Bitmap")
                                    callback(false, null)
                                }
                            } catch (e: Exception) {
                                FileLogger.e(TAG, "处理截屏结果失败", e)
                                callback(false, null)
                            }
                        }

                        override fun onFailure(errorCode: Int) {
                            FileLogger.e(TAG, "截屏失败，错误码: $errorCode")
                            callback(false, null)
                        }
                    }
                )
            } else {
                FileLogger.e(TAG, "Android版本过低，不支持无障碍截屏 (需要API 30+)")
                callback(false, null)
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "无障碍截屏异常", e)
            callback(false, null)
        }
    }

    /**
     * 设置媒体投影权限结果 (已废弃，仅为兼容保留)
     */
    @Deprecated("不再需要MediaProjection权限")
    fun setMediaProjectionData(resultCode: Int, resultData: Intent?) {
        FileLogger.w(TAG, "setMediaProjectionData已废弃，现在使用无障碍截屏")
    }
    
    /**
     * 开始屏幕截图 (已废弃，仅为兼容保留)
     */
    @Deprecated("不再需要MediaProjection，现在使用无障碍截屏")
    fun startScreenCapture(): Boolean {
        FileLogger.w(TAG, "startScreenCapture已废弃，现在直接使用无障碍截屏")
        return true
    }
    
    /**
     * 停止屏幕截图 (已废弃，仅为兼容保留)
     */
    @Deprecated("不再需要MediaProjection")
    fun stopScreenCapture() {
        FileLogger.w(TAG, "stopScreenCapture已废弃")
    }
    
    /**
     * 启动定时截屏
     */
    fun startTimedScreenshot(intervalSeconds: Int): Boolean {
        FileLogger.e(TAG, "=== AccessibilityService.startTimedScreenshot 开始 ===")
        FileLogger.e(TAG, "请求间隔: ${intervalSeconds}秒")
        FileLogger.e(TAG, "当前运行状态: $isTimedScreenshotRunning")

        if (isTimedScreenshotRunning) {
            FileLogger.w(TAG, "定时截屏已在运行，直接返回成功")
            return true
        }

        // 检查Android版本
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            FileLogger.e(TAG, "Android版本过低，不支持无障碍截屏 (当前API: ${Build.VERSION.SDK_INT}, 需要API 30+)")
            return false
        }

        try {
            FileLogger.e(TAG, "开始启动定时截屏服务...")
            screenshotInterval = intervalSeconds
            isTimedScreenshotRunning = true

            // 启动定时器
            screenshotTimer = timer(name = "ScreenshotTimer", daemon = true, period = (intervalSeconds * 1000).toLong()) {
                if (isTimedScreenshotRunning) {
                    performTimedScreenshot()
                }
            }

            FileLogger.e(TAG, "=== 定时截屏启动成功，间隔: ${intervalSeconds}秒 ===")
            return true
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动定时截屏失败", e)
            isTimedScreenshotRunning = false
            FileLogger.e(TAG, "=== 定时截屏启动失败 ===")
            return false
        }
    }

    /**
     * 停止定时截屏
     */
    fun stopTimedScreenshot() {
        try {
            isTimedScreenshotRunning = false
            screenshotTimer?.cancel()
            screenshotTimer = null
            
            FileLogger.i(TAG, "定时截屏已停止")
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止定时截屏失败", e)
        }
    }

    /**
     * 执行定时截屏
     */
    private fun performTimedScreenshot() {
        try {
            // 确定要截图的应用
            val targetApp = getScreenshotTargetApp()
            if (targetApp == null) {
                FileLogger.d(TAG, "没有需要截图的目标应用，跳过截屏")
                return
            }

            FileLogger.d(TAG, "开始截屏：$targetApp (会话应用: $currentSessionApp, 前台应用: $currentForegroundApp)")

            // 使用无障碍服务截屏
            takeScreenshotUsingAccessibility { success, filePath ->
                if (success && filePath != null) {
                    FileLogger.i(TAG, "定时截屏成功：$filePath")
                } else {
                    FileLogger.e(TAG, "定时截屏失败")
                }
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "执行定时截屏失败", e)
        }
    }

    /**
     * 获取截图目标应用
     * 简化逻辑：直接根据前台应用判断，不依赖会话管理
     */
    private fun getScreenshotTargetApp(): String? {
        // 优先使用UsageStats获取的前台应用（更准确）
        val usageStatsApp = getForegroundAppUsingUsageStats()
        if (usageStatsApp != null && isAppInMonitorList(usageStatsApp)) {
            FileLogger.d(TAG, "UsageStats检测到监控应用: $usageStatsApp")
            return usageStatsApp
        }

        // 备用：使用AccessibilityEvent检测的前台应用
        val currentApp = currentForegroundApp
        if (currentApp != null && isAppInMonitorList(currentApp)) {
            FileLogger.d(TAG, "AccessibilityEvent检测到监控应用: $currentApp")
            return currentApp
        }

        FileLogger.d(TAG, "当前前台应用不在监控列表中 - UsageStats: $usageStatsApp, Accessibility: $currentApp")
        return null
    }

    /**
     * 同步截取屏幕（用于手动截屏）
     */
    fun captureScreenSync(): String? {
        FileLogger.d(TAG, "开始手动截屏")
        
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            FileLogger.e(TAG, "Android版本过低，不支持无障碍截屏")
            return null
        }

        var result: String? = null
        val lock = Object()
        
        takeScreenshotUsingAccessibility { success, filePath ->
            synchronized(lock) {
                result = if (success) filePath else null
                lock.notify()
            }
        }
        
        // 等待截屏完成，最多等待5秒
        synchronized(lock) {
            try {
                lock.wait(5000)
            } catch (e: InterruptedException) {
                FileLogger.e(TAG, "等待截屏完成被中断", e)
            }
        }
        
        return result
    }

    /**
     * 保存截图到指定目录
     */
    private fun saveScreenshotBitmap(bitmap: Bitmap, packageName: String): String? {
        return try {
            val appName = getAppName(packageName) ?: packageName

            // 定义相对路径的根目录和文件名
            // 使用packageName作为文件夹名，确保与数据库查询一致
            val relativeDir = "output/screen/$packageName"
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.getDefault()).format(Date())
            val fileName = "${timestamp}.jpg"
            
            // 使用应用专属的外部存储目录
            val baseDir = this.getExternalFilesDir(null)
            if (baseDir == null) {
                FileLogger.e(TAG, "无法获取应用专属存储目录")
                return null
            }

            // 创建完整的输出目录
            val outputDir = File(baseDir, relativeDir)
            if (!outputDir.exists()) {
                outputDir.mkdirs()
            }

            val file = File(outputDir, fileName)

            // 保存图片
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }

            // 关键修改：只返回相对路径给Flutter端
            val relativePath = File(relativeDir, fileName).path 
            FileLogger.i(TAG, "截图已保存，绝对路径: ${file.absolutePath}")
            FileLogger.i(TAG, "返回给Flutter的相对路径: $relativePath")
            
            // 通知Flutter端更新数据库
            try {
                notifyScreenshotSaved(packageName, appName, relativePath) // <--- 使用相对路径
            } catch (e: Exception) {
                FileLogger.w(TAG, "通知Flutter更新数据库失败: ${e.message}")
            }
            
            relativePath // 返回相对路径
        } catch (e: Exception) {
            FileLogger.e(TAG, "保存截图失败", e)
            null
        }
    }

    /**
     * 通知Flutter端更新数据库
     */
    private fun notifyScreenshotSaved(packageName: String, appName: String, filePath: String) {
        try {
            // 发送广播通知MainActivity
            val intent = Intent("com.fqyw.screen_memo.SCREENSHOT_SAVED").apply {
                setPackage(this@ScreenCaptureAccessibilityService.packageName)
                putExtra("packageName", packageName)
                putExtra("appName", appName)
                putExtra("filePath", filePath)
                putExtra("captureTime", System.currentTimeMillis())
            }
            sendBroadcast(intent)
            FileLogger.d(TAG, "已发送截图保存通知广播")
        } catch (e: Exception) {
            FileLogger.e(TAG, "发送截图保存通知失败", e)
        }
    }

    /**
     * 检查应用是否在监控列表中
     */
    private fun isAppInMonitorList(packageName: String): Boolean {
        return try {
            val sharedPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val selectedAppsJson = sharedPrefs.getString("flutter.selected_apps", null)

            if (selectedAppsJson != null) {
                // 简单检查包名是否在JSON字符串中
                selectedAppsJson.contains("\"packageName\":\"$packageName\"")
            } else {
                false
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查监控列表失败", e)
            false
        }
    }

    /**
     * 获取应用名称
     */
    private fun getAppName(packageName: String): String? {
        return try {
            val packageManager = packageManager
            val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (e: Exception) {
            FileLogger.w(TAG, "获取应用名称失败: $packageName - ${e.message}")
            null
        }
    }

    /**
     * 创建通知渠道
     */
    private fun createNotificationChannel() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                FileLogger.e(TAG, "准备创建通知渠道")

                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // 检查渠道是否已存在
                val existingChannel = notificationManager.getNotificationChannel(CHANNEL_ID)
                if (existingChannel != null) {
                    FileLogger.e(TAG, "通知渠道已存在: ${existingChannel.name}")
                    return
                }

                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "屏幕备忘录服务",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "用于显示屏幕备忘录辅助功能服务状态"
                    setShowBadge(false)
                    // 设置为不可关闭，提高保活能力
                    setBypassDnd(false)
                    enableLights(false)
                    enableVibration(false)
                    setSound(null, null)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }

                notificationManager.createNotificationChannel(channel)
                FileLogger.e(TAG, "通知渠道创建成功: $CHANNEL_ID")

                // 验证渠道创建是否成功
                val createdChannel = notificationManager.getNotificationChannel(CHANNEL_ID)
                if (createdChannel != null) {
                    FileLogger.e(TAG, "通知渠道验证成功，重要性级别: ${createdChannel.importance}")
                } else {
                    FileLogger.e(TAG, "通知渠道验证失败")
                }
            } else {
                FileLogger.e(TAG, "Android版本低于8.0，无需创建通知渠道")
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "创建通知渠道失败", e)
        }
    }
    
    /**
     * 保存服务状态
     */
    private fun saveServiceState(isRunning: Boolean) {
        try {
            val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            sharedPrefs.edit().putBoolean("accessibility_service_running", isRunning).apply()
            Log.d(TAG, "服务状态已保存: $isRunning")
        } catch (e: Exception) {
            Log.e(TAG, "保存服务状态失败: $e")
        }
    }

    /**
     * 获取保存的服务状态
     */
    private fun getSavedServiceState(): Boolean {
        return try {
            val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            sharedPrefs.getBoolean("accessibility_service_running", false)
        } catch (e: Exception) {
            Log.e(TAG, "获取服务状态失败: $e")
            false
        }
    }

    /**
     * 创建前台服务通知
     */
    private fun createNotification(): Notification {
        try {
            FileLogger.e(TAG, "准备创建前台服务通知")

            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("屏幕备忘录服务")
                .setContentText("辅助功能服务正在运行，点击打开应用")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentIntent(pendingIntent)
                .setOngoing(true) // 设置为持续通知，不可滑动删除
                .setAutoCancel(false) // 点击后不自动取消
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setShowWhen(false)
                .setLocalOnly(true) // 不在穿戴设备上显示
                .build()

            FileLogger.e(TAG, "前台服务通知创建成功")
            return notification

        } catch (e: Exception) {
            FileLogger.e(TAG, "创建前台服务通知失败", e)

            // 创建一个简单的备用通知
            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("屏幕备忘录服务")
                .setContentText("服务运行中")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
        }
    }

    /**
     * 启动前台服务
     */
    private fun startForegroundService() {
        try {
            FileLogger.e(TAG, "准备启动前台服务")

            // 创建通知渠道
            createNotificationChannel()

            // 创建持久通知
            val notification = createNotification()
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, notification)
            FileLogger.e(TAG, "AccessibilityService通知已创建")

            // 启动独立的前台服务来保持应用活跃
            try {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                FileLogger.e(TAG, "独立前台服务启动成功")
            } catch (e: Exception) {
                FileLogger.e(TAG, "启动独立前台服务失败", e)
            }

            // 更新前台服务状态
            ServiceStateManager.setForegroundServiceRunning(this, true)

        } catch (e: Exception) {
            FileLogger.e(TAG, "启动前台服务失败", e)
        }
    }

    /**
     * 获取WakeLock防止Doze模式
     */
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ScreenMemo:AccessibilityWakeLock"
            )
            wakeLock?.acquire()
            FileLogger.e(TAG, "WakeLock已获取")
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取WakeLock失败", e)
        }
    }

    /**
     * 释放WakeLock
     */
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    FileLogger.e(TAG, "WakeLock已释放")
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            FileLogger.e(TAG, "释放WakeLock失败", e)
        }
    }

    /**
     * 设置重启闹钟
     * 使用AlarmManager在服务被杀死后重启
     */
    private fun scheduleRestart() {
        try {
            FileLogger.e(TAG, "准备设置重启闹钟")

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            // 设置多个重启机制
            // 1. RestartReceiver
            val restartIntent = Intent(this, RestartReceiver::class.java).apply {
                action = RestartReceiver.ACTION_RESTART_SERVICE
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                RESTART_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 设置在5秒后触发重启
            val triggerTime = android.os.SystemClock.elapsedRealtime() + 5000

            // 使用setExactAndAllowWhileIdle确保在Doze模式下也能触发
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            }
            
            // 2. 设置备用重启机制 - 启动ScreenCaptureService
            val serviceIntent = Intent(this, ScreenCaptureService::class.java)
            val servicePendingIntent = PendingIntent.getService(
                this,
                RESTART_REQUEST_CODE + 1,
                serviceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                android.os.SystemClock.elapsedRealtime() + 10000, // 10秒后
                servicePendingIntent
            )

            FileLogger.e(TAG, "重启闹钟设置成功，将在5秒和10秒后分别触发")

        } catch (e: Exception) {
            FileLogger.e(TAG, "设置重启闹钟失败", e)
        }
    }

    /**
     * 取消重启闹钟
     */
    private fun cancelRestart() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val restartIntent = Intent(this, RestartReceiver::class.java).apply {
                action = RestartReceiver.ACTION_RESTART_SERVICE
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                RESTART_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            alarmManager.cancel(pendingIntent)
            FileLogger.e(TAG, "重启闹钟已取消")

        } catch (e: Exception) {
            FileLogger.e(TAG, "取消重启闹钟失败", e)
        }
    }

    /**
     * 从MainActivity重新请求MediaProjection权限
     */
    private fun requestMediaProjectionFromMainActivity(): Boolean {
        return try {
            FileLogger.e(TAG, "尝试通过广播请求MediaProjection权限")
            
            // 发送广播给MainActivity请求重新获取权限
            val intent = Intent("com.fqyw.screen_memo.REQUEST_MEDIA_PROJECTION").apply {
                setPackage(packageName)
            }
            sendBroadcast(intent)
            
            FileLogger.e(TAG, "MediaProjection权限请求广播已发送")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "发送MediaProjection权限请求失败", e)
            false
        }
    }

    /**
     * 检查OEM权限状态
     */
    private fun checkOEMPermissions() {
        try {
            FileLogger.e(TAG, "=== 开始检查OEM权限状态 ===")
            FileLogger.e(TAG, OEMCompatibilityHelper.getDeviceInfo())

            // 检查电池优化状态
            val isIgnoringBatteryOptimizations = OEMCompatibilityHelper.isIgnoringBatteryOptimizations(this)
            FileLogger.e(TAG, "电池优化白名单状态: $isIgnoringBatteryOptimizations")

            // 获取权限建议
            val suggestions = OEMCompatibilityHelper.checkOEMPermissionsAndSuggest(this)
            FileLogger.e(TAG, "权限建议: $suggestions")

            // 如果不在电池优化白名单中，记录警告并设置提醒标记
            if (!isIgnoringBatteryOptimizations) {
                FileLogger.w(TAG, "应用未在电池优化白名单中，可能影响截屏服务稳定性")

                // 保存需要用户手动设置的标记
                val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                sharedPrefs.edit().apply {
                    putBoolean("needs_battery_optimization_whitelist", true)
                    putBoolean("needs_autostart_permission", true)
                    putBoolean("needs_background_unlimited", true)
                    putLong("permission_check_time", System.currentTimeMillis())
                    apply()
                }

                FileLogger.w(TAG, "已设置权限提醒标记，建议引导用户进行权限设置")
            } else {
                FileLogger.i(TAG, "应用已在电池优化白名单中")
            }

            // 根据设备厂商记录特定建议
            when {
                OEMCompatibilityHelper.isXiaomiDevice() -> {
                    FileLogger.w(TAG, "小米设备检测：请确保在自启动管理和后台应用管理中正确设置")
                }
                OEMCompatibilityHelper.isHuaweiDevice() -> {
                    FileLogger.w(TAG, "华为设备检测：请确保在启动管理中正确设置")
                }
                OEMCompatibilityHelper.isOppoDevice() -> {
                    FileLogger.w(TAG, "OPPO设备检测：请确保在自启动管理中正确设置")
                }
                OEMCompatibilityHelper.isVivoDevice() -> {
                    FileLogger.w(TAG, "VIVO设备检测：请确保在后台高耗电管理中正确设置")
                }
            }

            FileLogger.e(TAG, "=== OEM权限状态检查完成 ===")

        } catch (e: Exception) {
            FileLogger.e(TAG, "检查OEM权限状态失败", e)
        }
    }

    /**
     * 启动前台应用检测
     */
    private fun startForegroundAppDetection() {
        if (isForegroundDetectionRunning) {
            FileLogger.w(TAG, "前台应用检测已在运行")
            return
        }

        try {
            isForegroundDetectionRunning = true
            FileLogger.e(TAG, "启动前台应用检测，间隔: ${foregroundDetectionInterval}ms")

            // 启动定时器，每0.5秒检测一次前台应用
            foregroundAppTimer = timer(
                name = "ForegroundAppDetectionTimer",
                daemon = true,
                period = foregroundDetectionInterval
            ) {
                if (isForegroundDetectionRunning) {
                    detectForegroundAppPeriodically()
                }
            }

            FileLogger.e(TAG, "前台应用检测启动成功")
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动前台应用检测失败", e)
            isForegroundDetectionRunning = false
        }
    }

    /**
     * 停止前台应用检测
     */
    private fun stopForegroundAppDetection() {
        try {
            isForegroundDetectionRunning = false
            foregroundAppTimer?.cancel()
            foregroundAppTimer = null
            FileLogger.i(TAG, "前台应用检测已停止")
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止前台应用检测失败", e)
        }
    }

    /**
     * 定时检测前台应用
     */
    private fun detectForegroundAppPeriodically() {
        try {
            val foregroundApp = getForegroundAppUsingUsageStats()
            if (foregroundApp != null && foregroundApp != currentForegroundApp) {
                FileLogger.d(TAG, "定时检测到前台应用变化: $currentForegroundApp -> $foregroundApp")
                currentForegroundApp = foregroundApp
                updateAppSession(foregroundApp)
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "定时检测前台应用失败", e)
        }
    }

    /**
     * 使用UsageStats获取前台应用
     */
    private fun getForegroundAppUsingUsageStats(): String? {
        try {
            val usageStats = usageStatsManager ?: return null
            val currentTime = System.currentTimeMillis()
            val startTime = currentTime - 2000 // 查询最近2秒的使用情况

            // 获取使用事件
            val usageEvents = usageStats.queryEvents(startTime, currentTime)
            var lastEvent: UsageEvents.Event? = null
            var eventCount = 0

            // 遍历事件，找到最近的前台事件
            while (usageEvents.hasNextEvent()) {
                val event = UsageEvents.Event()
                usageEvents.getNextEvent(event)
                eventCount++

                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    if (lastEvent == null || event.timeStamp > lastEvent.timeStamp) {
                        lastEvent = event
                    }
                }
            }

            val result = lastEvent?.packageName
            if (result != null) {
                FileLogger.d(TAG, "UsageStats检测到前台应用: $result (共${eventCount}个事件)")
            } else {
                FileLogger.d(TAG, "UsageStats未检测到前台应用 (共${eventCount}个事件)")
            }

            return result
        } catch (e: Exception) {
            FileLogger.e(TAG, "使用UsageStats获取前台应用失败", e)
            return null
        }
    }
}
