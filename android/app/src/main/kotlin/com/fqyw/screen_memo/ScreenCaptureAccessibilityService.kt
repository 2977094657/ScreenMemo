package com.fqyw.screen_memo

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.app.KeyguardManager
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
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.view.Surface
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
import kotlin.concurrent.timer
import android.os.IBinder
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.common.InputImage
import com.google.android.gms.tasks.Tasks

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
    
    // 去重：记录每个应用的上一张截图的 dHash（64-bit）
    private val lastDHashByApp: MutableMap<String, Long> = mutableMapOf()
    private val DEDUP_HASH_THRESHOLD = 5 // Hamming 距离阈值（<=5 视为重复）

    // 添加WakeLock防止Doze模式
    private var wakeLock: PowerManager.WakeLock? = null

    // 定时截屏相关
    private var screenshotTimer: Timer? = null
    private var screenshotInterval: Int = 5 // 默认5秒
    private var isTimedScreenshotRunning = false
    @Volatile private var pausedByScreenOff: Boolean = false

    // 段落推进心跳（无新截图时也能结束 collecting）
    private var segmentTickTimer: Timer? = null
    private val segmentTickIntervalMs = 60_000L

    // 前台应用检测定时器
    private var foregroundAppTimer: Timer? = null
    private var isForegroundDetectionRunning = false
    private val foregroundDetectionInterval = 2_000L // 调整为2秒，降低轮询功耗
    private var usageStatsManager: UsageStatsManager? = null

    // 当前前台应用包名
    private var currentForegroundApp: String? = null

    // 简化的应用会话管理
    private var currentSessionApp: String? = null  // 当前会话中的应用
    private var sessionStartTime: Long = 0         // 会话开始时间

    // 前台应用“稳定目标”与“遮罩容错”控制
    private val transientOverlayPackages = setOf(
        "com.android.systemui",
        "com.miui.systemui",
        "com.google.android.systemui",
        "com.samsung.android.systemui",
        "com.oppo.systemui",
        "com.coloros.systemui",
        "com.vivo.systemui",
        "com.huawei.systemui"
    )
    // 系统级浏览器包名（用于“模糊名称”兜底判断）
    private val systemBrowserPackages: Set<String> = setOf(
        "com.android.browser", // AOSP 浏览器（常见名：Browser/浏览器）
        "com.miui.browser", "com.mi.globalbrowser", // 小米/MIUI 浏览器（常见名：Mi 浏览器/小米浏览器）
        "com.sec.android.app.sbrowser", // 三星浏览器（Samsung Internet/三星浏览器）
        "com.huawei.browser", // 华为浏览器
        "com.heytap.browser", "com.coloros.browser", // OPPO/ColorOS 浏览器
        "com.vivo.browser" // vivo 浏览器
    )

    // 浏览器“名称关键字”（优先按应用名匹配；忽略空格/大小写）
    private val browserNameKeywords: Set<String> = setOf(
        // 国际常见
        "chrome", "googlechrome", "firefox", "edge", "opera", "operamini", "operatouch",
        "brave", "vivaldi", "duckduckgo", "kiwi", "yandex", "torbrowser",
        // 国内常见
        "qq浏览器", "uc浏览器", "夸克", "百度浏览器", "搜狗浏览器",
        "华为浏览器", "小米浏览器", "mibrowser", "oppo浏览器", "vivo浏览器",
        // 厂商/特色
        "samsunginternet", "三星浏览器", "naverwhale", "palemoon", "avastsecure",
        // 小众/轻量
        "via", "x浏览器", "米侠", "百分浏览器", "ecosia", "ucturbo",
        "operagx", "puffin", "lightning", "bromite", "aloha", "phoenix", "maxthon", "傲游"
    )

    // 含糊/泛化名称（如“浏览器/Internet”）——仅当包名属于 systemBrowserPackages 时判为浏览器
    private val ambiguousBrowserNameKeywords: Set<String> = setOf(
        "浏览器", "internet", "browser"
    )

    private fun isBrowserByNameOrSystemPackage(packageName: String): Boolean {
        val appLabel = try { getAppName(packageName) } catch (_: Exception) { null }
        val normalized = appLabel?.lowercase(Locale.ROOT)?.replace(" ", "")
        if (normalized.isNullOrBlank()) {
            // 名称不可用：仅对系统级浏览器按包名兜底
            return systemBrowserPackages.contains(packageName)
        }
        // 强匹配：名称包含任一浏览器关键字
        for (kw in browserNameKeywords) {
            if (normalized.contains(kw)) return true
        }
        // 模糊匹配：仅系统级浏览器放行
        for (kw in ambiguousBrowserNameKeywords) {
            if (normalized == kw || normalized.contains(kw)) {
                return systemBrowserPackages.contains(packageName)
            }
        }
        return false
    }
    private val FOREGROUND_STABLE_MS = 800L   // 前台应用切换稳定时间阈值
    private val OVERLAY_GRACE_MS = 5000L      // 系统遮罩期间沿用上次稳定应用的宽限时长
    private var lastStableMonitoredApp: String? = null
    private var lastStableSeenAt: Long = 0L
    private var pendingCandidateApp: String? = null
    private var pendingCandidateSince: Long = 0L
    // 事件优先：记录最近一次 AccessibilityEvent 到达时间
    @Volatile private var lastAccessibilityEventAt: Long = 0L

    // 复用 OCR 识别器，避免频繁创建带来的CPU/内存抖动
    @Volatile private var sharedTextRecognizer: com.google.mlkit.vision.text.TextRecognizer? = null


    // 启用输入法(IME)集合与正则兜底，用于排除键盘被误判为前台应用
    @Volatile private var imePackages: Set<String> = emptySet()
    @Volatile private var lastImeRefreshAt: Long = 0L
    private val imeRegexes: List<Regex> = listOf(
        Regex("inputmethod", RegexOption.IGNORE_CASE),
        Regex("(^|\\.)ime(\\.|$)", RegexOption.IGNORE_CASE),
        Regex("keyboard", RegexOption.IGNORE_CASE),
        Regex("pinyin", RegexOption.IGNORE_CASE),
        Regex("sogou", RegexOption.IGNORE_CASE),
        Regex("baidu\\.input", RegexOption.IGNORE_CASE),
        Regex("iflytek", RegexOption.IGNORE_CASE),
        Regex("swiftkey", RegexOption.IGNORE_CASE),
        Regex("qq(input|\\.input)", RegexOption.IGNORE_CASE),
        Regex("google\\.android\\.inputmethod", RegexOption.IGNORE_CASE)
    )

    private fun isImePackage(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        if (imePackages.contains(pkg)) return true
        return imeRegexes.any { it.containsMatchIn(pkg) }
    }

    private fun refreshImePackages(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && (now - lastImeRefreshAt) < 10 * 60_000) return
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            val list = imm.enabledInputMethodList?.map { it.packageName } ?: emptyList()
            imePackages = list.toSet()
            lastImeRefreshAt = now
            if (FileLogger.isDebugEnabled()) {
                FileLogger.d(TAG, "IME包集合已刷新: ${imePackages}")
            }
        } catch (e: Exception) {
            FileLogger.w(TAG, "刷新IME包集合失败: ${e.message}")
        }
    }

    /**
     * 处理前台应用候选，只有在持续稳定一段时间后才认定为稳定前台应用；
     * 对于系统遮罩（通知栏、系统UI），不改变稳定应用，仅更新宽限期内沿用。
     */
    private fun onForegroundCandidateDetected(candidatePackage: String?) {
        val now = System.currentTimeMillis()
        if (candidatePackage.isNullOrEmpty()) {
            return
        }

        // 输入法：忽略，不参与稳定候选
        if (isImePackage(candidatePackage)) {
            FileLogger.d(TAG, "检测到输入法窗口 $candidatePackage，忽略该候选")
            return
        }

        // 桌面/Launcher：认为用户已回到桌面/后台 -> 立即清空稳定会话并暂停截屏
        if (launcherApps.contains(candidatePackage)) {
            FileLogger.i(TAG, "检测到桌面/Launcher: $candidatePackage，清除稳定会话并暂停截屏")
            lastStableMonitoredApp = null
            lastStableSeenAt = 0L
            pendingCandidateApp = null
            pendingCandidateSince = 0L
            return
        }

        // 系统遮罩：沿用上次稳定应用，不更新候选
        if (transientOverlayPackages.contains(candidatePackage) || isMiuiSystemApp(candidatePackage)) {
            // 宽限期内保持 lastStableMonitoredApp 可用
            FileLogger.d(TAG, "检测到系统遮罩/系统UI: $candidatePackage，沿用上次稳定应用: $lastStableMonitoredApp")
            return
        }

        // 非监控列表应用：完全忽略，不作为候选，不影响稳定目标/锁定
        if (!isAppInMonitorList(candidatePackage)) {
            FileLogger.d(TAG, "忽略非监控应用: $candidatePackage")
            return
        }

        // 相同于当前稳定应用：刷新最近出现时间
        if (lastStableMonitoredApp == candidatePackage) {
            lastStableSeenAt = now
            pendingCandidateApp = null
            FileLogger.d(TAG, "稳定前台应用保持: $lastStableMonitoredApp")
            return
        }

        // 候选稳定化判定
        if (pendingCandidateApp == candidatePackage) {
            if (now - pendingCandidateSince >= FOREGROUND_STABLE_MS) {
                lastStableMonitoredApp = candidatePackage
                lastStableSeenAt = now
                pendingCandidateApp = null
                FileLogger.i(TAG, "前台应用稳定化: $lastStableMonitoredApp (阈值 ${FOREGROUND_STABLE_MS}ms)")
            }
        } else {
            pendingCandidateApp = candidatePackage
            pendingCandidateSince = now
            FileLogger.d(TAG, "检测到新的前台候选: $candidatePackage，开始稳定计时")
        }
    }



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

                    // 移除服务级长期持锁：截屏时再短时获取WakeLock

                    // 初始化UsageStatsManager
                    usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    FileLogger.e(TAG, "UsageStatsManager已初始化")

                    // 刷新启用的输入法集合，避免输入法被判为前台
                    refreshImePackages(force = true)

                    // 前台应用检测改为在定时截屏运行时启动（降低后台轮询功耗）

                    // 启动段落推进心跳（每60秒推进所有collecting并回填）
                    startSegmentTickTimer()
                    FileLogger.e(TAG, "段落推进心跳已启动")

                    // 更新心跳
                    AccessibilityServiceWatchdog.updateHeartbeat()

                    // 如之前定时截屏在运行，自动恢复
                    try {
                        val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                        val wasRunning = sharedPrefs.getBoolean("timed_screenshot_was_running", false)
                        // 多键兜底恢复，避免某些路径只写了其一
                        val lastInterval = run {
                            val a = sharedPrefs.getInt("timed_screenshot_interval", -1)
                            val b = sharedPrefs.getInt("screenshot_interval", -1)
                            if (a != -1) a else if (b != -1) b else 5
                        }
                        if (wasRunning && !isTimedScreenshotRunning) {
                            FileLogger.e(TAG, "检测到定时截屏之前在运行，自动恢复，间隔: ${lastInterval}秒")
                            startTimedScreenshot(lastInterval)
                        }
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "恢复定时截屏状态失败", e)
                    }

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

        // 停止截屏相关服务（保持持久化运行标记，不要清除以便自动恢复）
        cancelTimedScreenshotSilently()

        // 停止前台应用检测
        stopForegroundAppDetection()

        // 停止段落推进心跳
        stopSegmentTickTimer()

        // 释放WakeLock
        releaseWakeLock()

        // 关闭共享 OCR 识别器
        try {
            sharedTextRecognizer?.close()
        } catch (_: Exception) {}
        sharedTextRecognizer = null

        // 保存服务停止状态
        saveServiceState(false)

        // 设置重启闹钟
        scheduleRestart()

        FileLogger.e(TAG, "=== 无障碍服务已销毁 ===")
    }

    /**
     * 启动段落推进心跳：周期性调用 SegmentSummaryManager.tick()
     */
    private fun startSegmentTickTimer() {
        try {
            segmentTickTimer?.cancel()
            segmentTickTimer = timer(
                name = "SegmentTickTimer",
                daemon = true,
                period = segmentTickIntervalMs
            ) {
                try {
                    SegmentSummaryManager.tick(this@ScreenCaptureAccessibilityService)
                } catch (e: Exception) {
                    FileLogger.w(TAG, "Segment tick 调用失败: ${e.message}")
                }
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动段落推进心跳失败", e)
        }
    }

    /**
     * 停止段落推进心跳
     */
    private fun stopSegmentTickTimer() {
        try {
            segmentTickTimer?.cancel()
            segmentTickTimer = null
            FileLogger.i(TAG, "段落推进心跳已停止")
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止段落推进心跳失败", e)
        }
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

        // 处理无障碍事件，检测当前前台应用（引入稳定化与遮罩容错）
        event?.let {
            lastAccessibilityEventAt = System.currentTimeMillis()
            if (it.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                val candidate = it.packageName?.toString()
                val prevStable = lastStableMonitoredApp
                onForegroundCandidateDetected(candidate)
                val stable = lastStableMonitoredApp

                // 仅在稳定目标发生变化时更新会话
                if (stable != null && stable != prevStable) {
                    currentForegroundApp = stable
                    FileLogger.d(TAG, "稳定前台应用(AccessibilityEvent): $stable")
                    updateAppSession(stable)
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
            // 在截屏前检查屏幕/锁屏状态，避免息屏状态下产生黑图
            if (shouldPauseForScreenState()) {
                callback(false, null)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                FileLogger.d(TAG, "使用无障碍服务takeScreenshot API截屏")
                // 截屏前短时获取WakeLock，避免在息屏边缘时CPU被挂起
                acquireWakeLock()
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

                                    // 保存前进行“自动裁剪系统栏 + dHash 去重”判断（仍保存完整图）
                                    try {
                                        if (isDuplicateScreenshot(bitmap, targetApp)) {
                                            FileLogger.i(TAG, "检测到重复截图（基于系统栏裁剪 + dHash），已跳过保存: $targetApp")
                                            // 视为成功但无新文件
                                            callback(true, null)
                                            return
                                        }
                                    } catch (e: Exception) {
                                        FileLogger.w(TAG, "重复判定失败，忽略并继续保存: ${e.message}")
                                    }

                                    val savedPath = saveScreenshotBitmap(bitmap, targetApp)
                                    // 释放WakeLock后再回调
                                    releaseWakeLock()
                                    callback(true, savedPath)
                                } else {
                                    FileLogger.e(TAG, "无法从截屏结果创建Bitmap")
                                    releaseWakeLock()
                                    callback(false, null)
                                }
                            } catch (e: Exception) {
                                FileLogger.e(TAG, "处理截屏结果失败", e)
                                releaseWakeLock()
                                callback(false, null)
                            }
                        }

                        override fun onFailure(errorCode: Int) {
                            FileLogger.e(TAG, "截屏失败，错误码: $errorCode")
                            releaseWakeLock()
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
            // 出错时确保释放WakeLock（若已获取）
            releaseWakeLock()
            callback(false, null)
        }
    }

    /**
     * 基于“自动裁剪系统栏”的 dHash 去重：仅用于判定，不影响最终保存的完整截图
     */
    private fun isDuplicateScreenshot(originalBitmap: Bitmap, packageName: String): Boolean {
        // 1) 归一化方向，并确保为可读写（非硬件）位图
        val normalized = try { normalizeBitmapOrientationForHash(originalBitmap) } catch (_: Exception) { originalBitmap }

        val w = normalized.width
        val h = normalized.height
        if (w <= 0 || h <= 0) return false

        // 2) 自动计算系统栏高度（px）。若设备隐藏系统栏，则可能返回 0。
        val statusBarPx = getStatusBarHeight().coerceAtLeast(0)
        val navBarPx = getNavigationBarHeight().coerceAtLeast(0)

        // 为了稳妥：系统栏裁剪不超过画面 1/3；若裁剪后过小，退化为仅裁顶部 5% 的容错。
        val cropTop = statusBarPx.coerceAtMost(h / 3)
        val cropBottom = navBarPx.coerceAtMost(h / 3)
        var roiY = cropTop
        var roiH = h - cropTop - cropBottom
        if (roiH < 16) {
            // 退化策略：避免 ROI 过小导致哈希不稳定
            roiY = (h * 0.05f).toInt().coerceIn(0, h - 1)
            roiH = (h * 0.90f).toInt().coerceAtLeast(16).coerceAtMost(h - roiY)
        }

        val roi = try { Bitmap.createBitmap(normalized, 0, roiY, w, roiH) } catch (_: Exception) { normalized }

        // 3) 计算 64-bit dHash
        val curHash = computeDHash64FromBitmap(roi)

        // 4) 读取上一张哈希（内存优先，其次持久化）
        val prevHash = lastDHashByApp[packageName]
            ?: ScreenshotDatabaseHelper.getLastDHash(this, packageName)
        if (prevHash != null) {
            val dist = java.lang.Long.bitCount(curHash xor prevHash)
            if (dist <= DEDUP_HASH_THRESHOLD) {
                return true
            }
        }

        // 5) 更新哈希
        lastDHashByApp[packageName] = curHash
        // DB 持久化 last_dhash；appName 可为 null，Helper 内部会兜底为包名
        ScreenshotDatabaseHelper.setLastDHash(this, packageName, null, curHash)
        return false
    }

    /**
     * 将位图标准化为便于计算哈希的方向与格式（复制为 ARGB_8888，依据设备旋转做最小必要旋转）。
     */
    private fun normalizeBitmapOrientationForHash(bitmap: Bitmap): Bitmap {
        val swBitmap = try {
            if (bitmap.config == Bitmap.Config.HARDWARE || bitmap.config == null) {
                FileLogger.d(TAG, "位图为硬件配置，拷贝为ARGB_8888用于哈希计算")
                bitmap.copy(Bitmap.Config.ARGB_8888, false)
            } else bitmap
        } catch (_: Exception) { bitmap }

        val rotation = try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                display?.rotation ?: Surface.ROTATION_0
            } else {
                val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                @Suppress("DEPRECATION")
                wm.defaultDisplay.rotation
            }
        } catch (_: Exception) { Surface.ROTATION_0 }

        val w = swBitmap.width
        val h = swBitmap.height
        val aspect = if (h != 0) (w.toFloat() / h.toFloat()) else 0f
        val isLandscapeDevice = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE ||
                rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270
        val isWide = w > h && aspect > 1.2f
        val shouldRotate = isLandscapeDevice && isWide

        if (!shouldRotate) return swBitmap

        val m = Matrix()
        val degrees = when (rotation) {
            Surface.ROTATION_90 -> 270f
            Surface.ROTATION_270 -> 90f
            else -> 90f
        }
        m.postRotate(degrees)
        return try {
            Bitmap.createBitmap(swBitmap, 0, 0, w, h, m, true)
        } catch (_: Exception) {
            swBitmap
        }
    }

    /**
     * 计算 64-bit dHash（9x8 灰度差分）。
     */
    private fun computeDHash64FromBitmap(src: Bitmap): Long {
        val resized = try { Bitmap.createScaledBitmap(src, 9, 8, true) } catch (_: Exception) { src }
        var bitIndex = 0
        var hash = 0L

        fun luminance(x: Int, y: Int): Int {
            val c = resized.getPixel(x, y)
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = (c) and 0xFF
            return (r + g + b) / 3
        }

        for (y in 0 until 8) {
            for (x in 0 until 8) {
                val left = luminance(x, y)
                val right = luminance(x + 1, y)
                if (left > right) {
                    hash = hash or (1L shl bitIndex)
                }
                bitIndex++
            }
        }
        return hash
    }

    private fun getStatusBarHeight(): Int {
        return try {
            val resId = resources.getIdentifier("status_bar_height", "dimen", "android")
            if (resId > 0) resources.getDimensionPixelSize(resId) else 0
        } catch (_: Exception) { 0 }
    }

    private fun getNavigationBarHeight(): Int {
        return try {
            val orientation = resources.configuration.orientation
            val name = if (orientation == Configuration.ORIENTATION_LANDSCAPE) "navigation_bar_height_landscape" else "navigation_bar_height"
            val resId = resources.getIdentifier(name, "dimen", "android")
            if (resId > 0) resources.getDimensionPixelSize(resId) else 0
        } catch (_: Exception) { 0 }
    }

    // 已移除 SharedPreferences 方案，改为数据库 app_stats.last_dhash 持久化

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
            pausedByScreenOff = false

            // 启动定时器（初始用全局间隔，后续按应用动态调整）
            screenshotTimer = timer(name = "ScreenshotTimer", daemon = true, period = (screenshotInterval * 1000).toLong()) {
                if (isTimedScreenshotRunning) {
                    performTimedScreenshot()
                }
            }

            // 在定时截屏运行期间启动前台应用检测（事件优先+兜底轮询）
            startForegroundAppDetection()

            // 立即持久化运行状态，便于崩溃/被杀后自动恢复
            try {
                val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                sharedPrefs.edit().apply {
                    putBoolean("timed_screenshot_was_running", true)
                    putInt("timed_screenshot_interval", screenshotInterval)
                    apply()
                }
            } catch (e: Exception) {
                FileLogger.e(TAG, "持久化定时截屏状态失败", e)
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

            // 停止前台应用检测，降低后台轮询功耗
            stopForegroundAppDetection()
            
            FileLogger.i(TAG, "定时截屏已停止")
            // 清理持久化的运行标记，避免误恢复
            try {
                val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                sharedPrefs.edit().apply {
                    putBoolean("timed_screenshot_was_running", false)
                }.apply()
            } catch (e: Exception) {
                FileLogger.e(TAG, "清理定时截屏持久化状态失败", e)
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止定时截屏失败", e)
        }
    }

    /**
     * 灭屏时的暂停：仅取消计时器，不清理“正在运行”持久化标记，以便亮屏后自动恢复
     */
    fun pauseTimedScreenshotForScreenOff() {
        try {
            if (!isTimedScreenshotRunning && screenshotTimer == null) {
                // 已不在运行，无需处理
                pausedByScreenOff = false
                return
            }
            pausedByScreenOff = true
            screenshotTimer?.cancel()
            screenshotTimer = null
            isTimedScreenshotRunning = false
            FileLogger.i(TAG, "定时截屏因灭屏已暂停")
        } catch (e: Exception) {
            FileLogger.e(TAG, "暂停定时截屏失败", e)
        }
    }

    /**
     * 亮屏/解锁后恢复：仅当因灭屏被暂停过时恢复
     */
    fun resumeTimedScreenshotIfPaused() {
        try {
            if (!pausedByScreenOff) {
                return
            }
            pausedByScreenOff = false
            val interval = if (screenshotInterval > 0) screenshotInterval else 5
            FileLogger.i(TAG, "尝试从灭屏暂停中恢复定时截屏，间隔: ${interval}秒")
            startTimedScreenshot(interval)
        } catch (e: Exception) {
            FileLogger.e(TAG, "恢复定时截屏失败", e)
        }
    }

    /**
     * 仅用于系统回收/销毁时取消定时器，不更改“正在运行”的持久化标记。
     */
    private fun cancelTimedScreenshotSilently() {
        try {
            isTimedScreenshotRunning = false
            screenshotTimer?.cancel()
            screenshotTimer = null
            FileLogger.i(TAG, "定时截屏计时器已取消(静默)")
        } catch (e: Exception) {
            FileLogger.e(TAG, "静默取消定时截屏失败", e)
        }
    }

    /**
     * 执行定时截屏
     */
    private fun performTimedScreenshot() {
        try {
            // 息屏/锁屏或者显示不可见时跳过
            if (shouldPauseForScreenState()) {
                FileLogger.d(TAG, "屏幕不可交互或处于锁屏/息屏状态，本次定时截屏跳过")
                return
            }
            // 确定要截图的应用
            val targetApp = getScreenshotTargetApp()
            if (targetApp == null) {
                FileLogger.d(TAG, "没有需要截图的目标应用，跳过截屏")
                return
            }

            // 动态应用每应用自定义间隔：若与当前不同则重建计时器
            try {
                val customIv = PerAppSettingsBridge.readIntervalIfCustom(this, targetApp)
                if (customIv != null && customIv > 0 && customIv != screenshotInterval) {
                    FileLogger.i(TAG, "应用($targetApp)自定义间隔=${customIv}s，当前=${screenshotInterval}s -> 重置计时器")
                    screenshotInterval = customIv
                    // 重建计时器以应用新间隔
                    screenshotTimer?.cancel()
                    screenshotTimer = timer(name = "ScreenshotTimer", daemon = true, period = (screenshotInterval * 1000).toLong()) {
                        if (isTimedScreenshotRunning) {
                            performTimedScreenshot()
                        }
                    }
                    // 备份到SharedPreferences，便于恢复
                    try {
                        val sp = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                        sp.edit().apply {
                            putInt("timed_screenshot_interval", screenshotInterval)
                            putInt("screenshot_interval", screenshotInterval)
                            apply()
                        }
                    } catch (_: Exception) {}
                }
            } catch (e: Exception) {
                FileLogger.w(TAG, "读取每应用间隔失败: ${e.message}")
            }

            FileLogger.d(TAG, "开始截屏：$targetApp (会话应用: $currentSessionApp, 前台应用: $currentForegroundApp)")

            // 使用无障碍服务截屏
            takeScreenshotUsingAccessibility { success, filePath ->
                if (success) {
                    if (filePath != null) {
                        FileLogger.i(TAG, "定时截屏成功：$filePath")
                    } else {
                        // 重复判定命中：成功但无新文件
                        FileLogger.i(TAG, "定时截屏：重复判定命中，已跳过保存")
                    }
                } else {
                    FileLogger.e(TAG, "定时截屏失败")
                }
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "执行定时截屏失败", e)
        }
    }

    /**
     * 是否因屏幕状态而应暂停截屏：
     * - 设备不可交互（息屏/休眠）
     * - 锁屏界面（Keyguard）
     * - 显示状态为OFF/DOZE/DOZE_SUSPEND
     */
    private fun shouldPauseForScreenState(): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val isInteractive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                powerManager.isInteractive
            } else {
                @Suppress("DEPRECATION")
                powerManager.isScreenOn
            }

            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val isLocked = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    keyguardManager.isDeviceLocked || keyguardManager.isKeyguardLocked
                } else {
                    keyguardManager.isKeyguardLocked
                }
            } catch (_: Exception) { keyguardManager.isKeyguardLocked }

            val isDisplayOn = isDisplayReallyOn()

            val pause = (!isInteractive) || isLocked || (!isDisplayOn)
            if (FileLogger.isDebugEnabled()) {
                FileLogger.d(TAG, "屏幕状态 -> interactive: ${isInteractive}, locked: ${isLocked}, displayOn: ${isDisplayOn}, pause: ${pause}")
            }
            pause
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查屏幕状态失败，出于保守策略将跳过截屏", e)
            true
        }
    }

    /**
     * 判断显示是否真正点亮：Display.STATE_ON 视为点亮，其它（OFF/DOZE/DOZE_SUSPEND）视为未点亮。
     */
    private fun isDisplayReallyOn(): Boolean {
        return try {
            val state = try {
                val disp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
                    @Suppress("DEPRECATION")
                    dm.getDisplay(Display.DEFAULT_DISPLAY)
                }
                disp?.state ?: Display.STATE_UNKNOWN
            } catch (_: Exception) { Display.STATE_UNKNOWN }

            when (state) {
                Display.STATE_ON -> true
                Display.STATE_UNKNOWN -> {
                    // 回退：以 PowerManager.isInteractive 作为近似
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) pm.isInteractive else @Suppress("DEPRECATION") pm.isScreenOn
                }
                else -> false // 包括 OFF/DOZE/DOZE_SUSPEND
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "检测显示状态失败，按未点亮处理", e)
            false
        }
    }

    /**
     * 获取截图目标应用
     * 简化逻辑：直接根据前台应用判断，不依赖会话管理
     */
    private fun getScreenshotTargetApp(): String? {
        val now = System.currentTimeMillis()

        // 稳定前台（仅在监控列表中才有效）
        val stable = lastStableMonitoredApp
        if (stable == null || !isAppInMonitorList(stable)) {
            FileLogger.d(TAG, "无有效稳定前台或不在监控列表，暂停截屏")
            return null
        }

        // 当前可见顶层应用（尽量用UsageStats，其次AccessibilityEvent）
        // 偶尔刷新IME集合
        refreshImePackages(force = false)
        val visibleTop = getForegroundAppUsingUsageStats() ?: currentForegroundApp

        // 系统遮罩/系统UI：继续把截图归属到稳定前台
        if (visibleTop != null && (transientOverlayPackages.contains(visibleTop) || isMiuiSystemApp(visibleTop) || isImePackage(visibleTop))) {
            FileLogger.d(TAG, "顶层为系统遮罩/系统UI($visibleTop)，继续使用稳定前台: $stable")
            return stable
        }

        // 桌面/Launcher：暂停截屏并等待新会话
        if (visibleTop != null && launcherApps.contains(visibleTop)) {
            FileLogger.d(TAG, "顶层为桌面/Launcher($visibleTop)，暂停截屏，等待新会话")
            return null
        }

        // 顶层为监控应用（可能与stable相同或不同），在未解锁前仍归属stable
        FileLogger.d(TAG, "顶层为监控应用($visibleTop)，归属稳定前台: $stable")
        return stable
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

            // 新的目录结构：应用+时间 (output/screen/包名/年月/日期/)
            val now = Date()
            val yearMonth = SimpleDateFormat("yyyy-MM", Locale.getDefault()).format(now)
            val day = SimpleDateFormat("dd", Locale.getDefault()).format(now)
            val relativeDir = "output/screen/$packageName/$yearMonth/$day"
            val timestamp = SimpleDateFormat("HHmmss_SSS", Locale.getDefault()).format(now)
            // 最终文件名后缀依据实际编码格式决定
            val baseName = timestamp
            
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

            // 先完成旋转与可编辑位图
            var finalExt = "jpg" // 临时占位，稍后依据编码结果修正
            var file = File(outputDir, baseName + "." + finalExt)

            // 纯图像维度与方向判定，避免依赖窗口API带来的不稳定
            val rotatedOrOriginal = try {
                val rotation = try {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        display?.rotation ?: Surface.ROTATION_0
                    } else {
                        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                        @Suppress("DEPRECATION")
                        wm.defaultDisplay.rotation
                    }
                } catch (_: Exception) { Surface.ROTATION_0 }

                // 确保可编辑位图（硬件位图需要拷贝为软件位图）
                val swBitmap = try {
                    if (bitmap.config == Bitmap.Config.HARDWARE || bitmap.config == null) {
                        FileLogger.d(TAG, "位图为硬件配置，拷贝为ARGB_8888以便旋转处理")
                        bitmap.copy(Bitmap.Config.ARGB_8888, false)
                    } else bitmap
                } catch (_: Exception) { bitmap }

                val w = swBitmap.width
                val h = swBitmap.height
                val aspect = if (h != 0) (w.toFloat() / h.toFloat()) else 0f
                val isLandscapeDevice = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE ||
                        rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270
                val isWide = w > h && aspect > 1.2f // 1.2 作为宽高阈值容差，规避状态栏/导航栏干扰

                val shouldRotate = isLandscapeDevice && isWide
                if (FileLogger.isDebugEnabled()) {
                    FileLogger.d(TAG, "截图旋转判定 -> size: ${w}x${h}, aspect: ${"%.2f".format(aspect)}, rotation: ${rotation}, deviceLandscape: ${isLandscapeDevice}, shouldRotate: ${shouldRotate}")
                }

                if (shouldRotate) {
                    val m = Matrix()
                    // 将横屏图片旋回竖屏：默认顺时针90度；按 rotation 精细化
                    val degrees = when (rotation) {
                        Surface.ROTATION_90 -> 270f // 设备向左横置，图像需逆时针旋回
                        Surface.ROTATION_270 -> 90f  // 设备向右横置，图像需顺时针旋回
                        else -> 90f
                    }
                    m.postRotate(degrees)
                    try {
                        Bitmap.createBitmap(swBitmap, 0, 0, w, h, m, true)
                    } catch (e: Exception) {
                        FileLogger.w(TAG, "位图旋转失败，回退使用原图: ${e.message}")
                        swBitmap
                    }
                } else swBitmap
            } catch (_: Exception) { bitmap }

            // 应用压缩设置（不改变分辨率，仅通过编码质量/格式控制大小；可选灰度）
            val encodeResult = encodeToBytesAccordingToSettings(rotatedOrOriginal ?: bitmap)
            val bytes = encodeResult.first
            finalExt = encodeResult.second
            if (bytes == null) {
                FileLogger.e(TAG, "编码失败：返回空字节流")
                return null
            }
            // 用实际后缀重建文件并写入
            file = File(outputDir, baseName + "." + finalExt)
            try {
                FileOutputStream(file).use { it.write(bytes) }
            } catch (e: Exception) {
                FileLogger.e(TAG, "写入文件失败", e)
                return null
            }

            // 关键修改：只返回相对路径给Flutter端
            val relativePath = File(relativeDir, baseName + "." + finalExt).path 
            FileLogger.i(TAG, "截图已保存，绝对路径: ${file.absolutePath}")
            FileLogger.i(TAG, "返回给Flutter的相对路径: $relativePath")
            
            // 仅当应用识别为浏览器（名称优先，系统包兜底）时，才尝试提取并复用 URL
            val pageUrl = if (isBrowserByNameOrSystemPackage(packageName)) {
                try {
                    FileLogger.d(TAG, "浏览器匹配，准备提取页面URL（启发式，顶部区域+BFS）: $packageName")
                    val u = extractCurrentPageUrlSafe()
                    if (u.isNullOrBlank()) {
                        FileLogger.i(TAG, "URL提取完成：无匹配结果（浏览器）")
                    } else {
                        FileLogger.i(TAG, "URL提取完成：$u（浏览器）")
                    }
                    u
                } catch (e: Exception) {
                    FileLogger.e(TAG, "URL提取异常（浏览器）", e)
                    null
                }
            } else {
                FileLogger.d(TAG, "非浏览器应用，跳过URL提取: $packageName")
                null
            }

            // 先在原生侧实时入库（Flutter未就绪时也能写入）
            try {
                ScreenshotDatabaseHelper.insertIfNotExists(
                    this@ScreenCaptureAccessibilityService,
                    packageName,
                    appName,
                    file.absolutePath,
                    System.currentTimeMillis(),
                    pageUrl
                )
            } catch (e: Exception) {
                FileLogger.w(TAG, "原生侧入库失败: ${e.message}")
            }

            // 通知段落管理器（用于段落开始与采样调度）
            try {
                SegmentSummaryManager.onScreenshotSaved(
                    this@ScreenCaptureAccessibilityService,
                    packageName,
                    appName,
                    file.absolutePath,
                    System.currentTimeMillis()
                )
                    // 在每次截图后，后台补齐未完成的段落直到最新可完整时段
                    try { SegmentSummaryManager.backfillToLatest(this@ScreenCaptureAccessibilityService) } catch (_: Exception) {}
            } catch (e: Exception) {
                FileLogger.w(TAG, "SegmentSummaryManager 调用失败: ${e.message}")
            }

            // 在“原图（未压缩）”上执行 OCR，并将结果异步写回数据库
            try {
                val forOcr = rotatedOrOriginal ?: bitmap
                runOcrAsyncAndPersist(forOcr, file.absolutePath)
            } catch (e: Exception) {
                FileLogger.w(TAG, "启动OCR失败: ${e.message}")
            }

            // 通知Flutter端更新数据库（作为第二路径，方便UI即刻刷新）
            try {
                notifyScreenshotSaved(packageName, appName, relativePath, pageUrl)
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
     * 使用 ML Kit 中文文本识别在原始位图上执行 OCR，并将结果写入对应记录（按文件路径更新）。
     * 离线：模型将随依赖一起打包入 APK；无网络也可识别。
     */
    private fun runOcrAsyncAndPersist(srcBitmap: Bitmap, absolutePath: String) {
        try {
            val recognizer = ensureTextRecognizer()
            Thread {
                try {
                    val portrait = try { srcBitmap.height >= srcBitmap.width } catch (_: Exception) { true }
                    val base = if (portrait) {
                        val topCropped = cropTopStatusBarPortrait(srcBitmap)
                        val bothCropped = cropBottomNavBarPortrait(topCropped)
                        preprocessForOcrPortrait(bothCropped)
                    } else srcBitmap
                    val text = if (portrait) {
                        recognizePortraitBySlices(recognizer, base)
                    } else {
                        // 横屏暂用整图识别
                        val img = InputImage.fromBitmap(base, 0)
                        try { Tasks.await(recognizer.process(img)).text ?: "" } catch (e: Exception) { "" }
                    }
                    val finalText = text.trim().ifEmpty { null }
                    ScreenshotDatabaseHelper.updateOcrTextByFilePath(
                        this@ScreenCaptureAccessibilityService,
                        absolutePath,
                        finalText
                    )
                    FileLogger.i(TAG, "OCR完成(切片=${portrait}), 长度=${finalText?.length ?: 0}")
                } catch (e: Exception) {
                    FileLogger.w(TAG, "OCR线程异常: ${e.message}")
                }
            }.start()
        } catch (e: Exception) {
            FileLogger.w(TAG, "启动OCR异常: ${e.message}")
        }
    }

    private fun ensureTextRecognizer(): com.google.mlkit.vision.text.TextRecognizer {
        val existing = sharedTextRecognizer
        if (existing != null) return existing
        val created = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        sharedTextRecognizer = created
        return created
    }

    /**
     * 裁剪竖屏截图顶部状态栏区域，避免无关内容参与识别。
     */
    private fun cropTopStatusBarPortrait(src: Bitmap): Bitmap {
        return try {
            val w = src.width
            val h = src.height
            val status = getStatusBarHeight().coerceAtLeast(0)
            val cropTop = status.coerceAtMost(h / 6)
            if (cropTop <= 0 || cropTop >= h - 16) return src
            Bitmap.createBitmap(src, 0, cropTop, w, h - cropTop)
        } catch (_: Exception) { src }
    }

    /**
     * 竖屏：对比度增强 + 轻锐化（不旋转、不改分辨率）。
     */
    private fun preprocessForOcrPortrait(src: Bitmap): Bitmap {
        return try {
            val w = src.width
            val h = src.height
            val safe = if (src.config != Bitmap.Config.ARGB_8888) src.copy(Bitmap.Config.ARGB_8888, true) else src.copy(Bitmap.Config.ARGB_8888, true)
            val pixels = IntArray(w * h)
            safe.getPixels(pixels, 0, w, 0, 0, w, h)
            // 简单对比度增强（可配置：flutter.ocr_contrast_1e2，默认118 => 1.18）
            val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val cVal = spGetIntCompat(sp, "flutter.ocr_contrast_1e2", 118).coerceIn(100, 140)
            val contrast = cVal / 100f
            val brightness = 0f
            for (i in pixels.indices) {
                val c = pixels[i]
                val a = c ushr 24 and 0xFF
                var r = c ushr 16 and 0xFF
                var g = c ushr 8 and 0xFF
                var b = c and 0xFF
                r = clamp255(((r - 128) * contrast + 128 + brightness).toInt())
                g = clamp255(((g - 128) * contrast + 128 + brightness).toInt())
                b = clamp255(((b - 128) * contrast + 128 + brightness).toInt())
                pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
            }
            safe.setPixels(pixels, 0, w, 0, 0, w, h)
            safe
        } catch (_: Exception) { src }
    }

    private fun clamp255(v: Int): Int = if (v < 0) 0 else if (v > 255) 255 else v

    /**
     * 竖屏切片 + 小字放大：纵向步进切片，重叠15%，宽度不足则放大至1080。
     */
    private fun recognizePortraitBySlices(recognizer: com.google.mlkit.vision.text.TextRecognizer, bmp: Bitmap): String {
        val w = bmp.width
        val h = bmp.height
        val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val sliceTarget = spGetIntCompat(sp, "flutter.ocr_slice_height", 1900).coerceIn(900, 2600)
        val overlapPct = spGetIntCompat(sp, "flutter.ocr_slice_overlap_percent", 22).coerceIn(8, 35)
        val overlapRatio = overlapPct / 100f
        val step = (sliceTarget * (1 - overlapRatio)).toInt().coerceAtLeast(500)
        val slices = mutableListOf<Bitmap>()
        var y = 0
        while (y < h) {
            val sh = if (y + sliceTarget <= h) sliceTarget else (h - y)
            if (sh <= 0) break
            try {
                val sub = Bitmap.createBitmap(bmp, 0, y, w, sh)
                val scaled = upscaleIfNeeded(sub)
                if (scaled !== sub) sub.recycle()
                slices.add(scaled)
            } catch (_: Exception) {}
            y += step
        }
        if (slices.isEmpty()) {
            val img = InputImage.fromBitmap(bmp, 0)
            return try { Tasks.await(recognizer.process(img)).text ?: "" } catch (e: Exception) { "" }
        }
        val seen = LinkedHashSet<String>()
        for (s in slices) {
            try {
                val text = Tasks.await(recognizer.process(InputImage.fromBitmap(s, 0)))
                for (block in text.textBlocks) {
                    for (line in block.lines) {
                        val t = line.text?.trim() ?: ""
                        if (t.isNotEmpty() && !seen.contains(t)) {
                            seen.add(t)
                        }
                    }
                }
            } catch (_: Exception) {
            } finally {
                try { s.recycle() } catch (_: Exception) {}
            }
        }
        if (seen.isEmpty()) {
            // 回退：整图一次
            val img = InputImage.fromBitmap(bmp, 0)
            return try { Tasks.await(recognizer.process(img)).text ?: "" } catch (e: Exception) { "" }
        }
        val sb = StringBuilder()
        for (l in seen) {
            if (sb.isNotEmpty()) sb.append('\n')
            sb.append(l)
        }
        return sb.toString()
    }

    private fun upscaleIfNeeded(bm: Bitmap): Bitmap {
        return try {
            val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val minWidth = spGetIntCompat(sp, "flutter.ocr_upscale_min_width", 1440).coerceIn(900, 2000)
            if (bm.width >= minWidth) bm else {
                val scale = minWidth.toFloat() / bm.width.toFloat()
                val tw = (bm.width * scale).toInt()
                val th = (bm.height * scale).toInt()
                Bitmap.createScaledBitmap(bm, tw, th, true)
            }
        } catch (_: Exception) { bm }
    }

    /**
     * 裁剪竖屏截图底部导航栏区域，减少无关误检。
     */
    private fun cropBottomNavBarPortrait(src: Bitmap): Bitmap {
        return try {
            val w = src.width
            val h = src.height
            val nav = getNavigationBarHeight().coerceAtLeast(0)
            val cropBottom = nav.coerceAtMost(h / 6)
            if (cropBottom <= 0 || cropBottom >= h - 16) return src
            Bitmap.createBitmap(src, 0, 0, w, h - cropBottom)
        } catch (_: Exception) { src }
    }

    /**
     * 根据用户设置进行编码（格式/质量/目标大小/灰度），不改变分辨率。
     * FlutterSharedPreferences 键：
     *  - flutter.image_format: jpeg | png | webp_lossy | webp_lossless (默认 webp_lossless)
     *  - flutter.image_quality: Int 1..100（默认 90，仅对 lossy 生效）
     *  - flutter.use_target_size: Bool（默认 false，仅对 lossy 生效）
     *  - flutter.target_size_kb: Int（默认 50，仅对 lossy 生效）
     *  - flutter.grayscale: Bool（默认 false）
     */
    // 返回 Pair<字节数组, 扩展名>
    private fun encodeToBytesAccordingToSettings(src: Bitmap): Pair<ByteArray?, String> {
            val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var format = (sp.getString("flutter.image_format", null)
            ?: (sp.all["flutter.image_format"] as? String)
            ?: "webp_lossless")
            var quality = spGetIntCompat(sp, "flutter.image_quality", 90).coerceIn(1, 100)
            var useTarget = spGetBoolCompat(sp, "flutter.use_target_size", false)
            var targetKb = spGetIntCompat(sp, "flutter.target_size_kb", 50).coerceAtLeast(50)

            // 覆盖为每应用设置：从每应用 SQLite settings 读取（若 use_custom=true）
            try {
                val per = PerAppSettingsBridge.readQualitySettingsIfCustom(this, getScreenshotTargetApp())
                if (per != null) {
                    format = per.format ?: format
                    quality = per.quality ?: quality
                    useTarget = per.useTargetSize ?: useTarget
                    targetKb = per.targetSizeKb ?: targetKb
                }
            } catch (_: Exception) {}

        // 可选灰度转换（不改变尺寸）
        val bitmap = src // 灰度已移除

        // 选择编码器
        val (cf, isLossy, isLossless, ext) = when (format) {
            "jpeg" -> Quad(Bitmap.CompressFormat.JPEG, true, false, "jpg")
            "png" -> Quad(Bitmap.CompressFormat.PNG, false, true, "png")
            "webp_lossless" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Quad(Bitmap.CompressFormat.WEBP_LOSSLESS, false, true, "webp")
            } else {
                // 退化到 PNG 以确保无损
                Quad(Bitmap.CompressFormat.PNG, false, true, "png")
            }
            else -> { // webp_lossy
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Quad(Bitmap.CompressFormat.WEBP_LOSSY, true, false, "webp")
                } else {
                    Quad(Bitmap.CompressFormat.WEBP, true, false, "webp")
                }
            }
        }

        FileLogger.i(TAG, "编码设置 -> format=${format}, lossy=${isLossy}, lossless=${isLossless}, quality=${quality}, useTarget=${useTarget}, targetKb=${targetKb}")

        // 目标大小仅在有损编码时生效
        if (isLossy && useTarget) {
            val bytes = compressToTargetSize(bitmap, cf, targetKb * 1024, minQ = 1, maxQ = 100)
                ?: compressOnce(bitmap, cf, 1)
            FileLogger.i(TAG, "目标大小编码完成 -> 实际字节=${bytes.size}, 目标字节=${targetKb * 1024}")
            return Pair(bytes, ext)
        }

        // 否则按质量单次压缩；无损忽略质量
        return try {
            val appliedQ = if (isLossless) 100 else quality
            val data = compressOnce(bitmap, cf, appliedQ)
            FileLogger.i(TAG, "单次编码完成 -> 实际字节=${data.size}, 格式=${format}, 质量=${appliedQ}")
            Pair(data, ext)
        } catch (e: Exception) { Pair(null, ext) }
    }

    private data class Quad<A,B,C,D>(val a: A, val b: B, val c: C, val d: D)

    private fun compressOnce(bm: Bitmap, cf: Bitmap.CompressFormat, q: Int): ByteArray {
        val baos = java.io.ByteArrayOutputStream()
        bm.compress(cf, q.coerceIn(1,100), baos)
            return baos.toByteArray()
    }

    /**
     * 二分质量以尽量接近目标大小（仅 lossy）。
     */
    private fun compressToTargetSize(bm: Bitmap, cf: Bitmap.CompressFormat, targetBytes: Int, minQ: Int, maxQ: Int): ByteArray? {
        var lo = minQ.coerceIn(1, 100)
        var hi = maxQ.coerceIn(lo, 100)
        var bestUnder: ByteArray? = null
        var bestOver: ByteArray? = null
        var iterations = 0
        while (lo <= hi && iterations < 12) {
            iterations++
            val mid = (lo + hi) / 2
            val data = compressOnce(bm, cf, mid)
            FileLogger.d(TAG, "压缩二分 -> 第${iterations}次, q=${mid}, size=${data.size}, target=${targetBytes}")
            if (data.size <= targetBytes) {
                // 记录当前最接近目标的“不过线”方案，继续提高质量以更接近目标
                if (bestUnder == null || data.size > bestUnder.size) bestUnder = data
                lo = mid + 1
            } else {
                // 记录当前最小的“超过目标”方案，降低质量
                if (bestOver == null || data.size < bestOver.size) bestOver = data
                hi = mid - 1
            }
        }
        val result = bestUnder ?: bestOver
        if (result != null) {
            FileLogger.i(TAG, "压缩二分完成 -> 最终size=${result.size}, 目标=${targetBytes}")
        } else {
            FileLogger.w(TAG, "压缩二分未找到合适质量")
        }
        return result
    }

    private fun spGetIntCompat(sp: android.content.SharedPreferences, key: String, def: Int): Int {
        return try {
            val any = sp.all[key]
            when (any) {
                is Int -> any
                is Long -> {
                    if (any > Int.MAX_VALUE) Int.MAX_VALUE else if (any < Int.MIN_VALUE) Int.MIN_VALUE else any.toInt()
                }
                is String -> any.toIntOrNull() ?: def
                else -> try { sp.getInt(key, def) } catch (_: Exception) { def }
            }
        } catch (_: Exception) { def }
    }

    private fun spGetBoolCompat(sp: android.content.SharedPreferences, key: String, def: Boolean): Boolean {
        return try {
            val any = sp.all[key]
            when (any) {
                is Boolean -> any
                is String -> any.equals("true", ignoreCase = true)
                is Int -> any != 0
                is Long -> any != 0L
                else -> sp.getBoolean(key, def)
            }
        } catch (_: Exception) { def }
    }

    private fun toGrayscale(src: Bitmap): Bitmap {
        return try {
            val w = src.width
            val h = src.height
            val gray = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c = Canvas(gray)
            val paint = Paint()
            val cm = ColorMatrix()
            cm.setSaturation(0f)
            paint.colorFilter = ColorMatrixColorFilter(cm)
            c.drawBitmap(src, 0f, 0f, paint)
            gray
        } catch (_: Exception) { src }
    }

    /**
     * 判断当前目标应用是否处于“全屏”
     * 策略：存在 TYPE_APPLICATION 窗口且其 root 节点 bounds 覆盖全屏，或窗口层级仅一层 APP 窗口
     */
    private fun isCurrentAppFullScreen(): Boolean {
        return try {
            val dispWidth = resources.displayMetrics.widthPixels
            val dispHeight = resources.displayMetrics.heightPixels
            val screenRect = Rect(0, 0, dispWidth, dispHeight)

            val ws = windows ?: return false
            var hasAppWindow = false
            var fullCover = false
            for (w in ws) {
                if (w.type == AccessibilityWindowInfo.TYPE_APPLICATION) {
                    hasAppWindow = true
                    val root = w.root ?: continue
                    val nodeRect = Rect()
                    try {
                        root.getBoundsInScreen(nodeRect)
                        // 允许 2px 容差
                        if (nodeRect.left <= screenRect.left + 2 &&
                            nodeRect.top <= screenRect.top + 2 &&
                            nodeRect.right >= screenRect.right - 2 &&
                            nodeRect.bottom >= screenRect.bottom - 2) {
                            fullCover = true
                            root.recycle()
                            break
                        }
                    } catch (_: Exception) {
                    } finally {
                        try { root.recycle() } catch (_: Exception) {}
                    }
                }
            }
            // 如果只有一个应用窗口，也可认为是全屏应用
            val onlyOneApp = ws.count { it.type == AccessibilityWindowInfo.TYPE_APPLICATION } == 1
            (hasAppWindow && fullCover) || onlyOneApp
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 通知Flutter端更新数据库
     */
    private fun notifyScreenshotSaved(packageName: String, appName: String, filePath: String, pageUrl: String?) {
        try {
            // 发送广播通知MainActivity
            val intent = Intent("com.fqyw.screen_memo.SCREENSHOT_SAVED").apply {
                setPackage(this@ScreenCaptureAccessibilityService.packageName)
                putExtra("packageName", packageName)
                putExtra("appName", appName)
                putExtra("filePath", filePath)
                putExtra("captureTime", System.currentTimeMillis())
                if (!pageUrl.isNullOrBlank()) putExtra("pageUrl", pageUrl)
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
                    "屏忆服务",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "用于显示屏忆辅助功能服务状态"
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
                .setContentTitle("屏幕截图服务")
                .setContentText("正在后台运行，确保截图功能可用")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setAutoCancel(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setShowWhen(false)
                .setLocalOnly(true)
                .build()

            FileLogger.e(TAG, "前台服务通知创建成功")
            return notification

        } catch (e: Exception) {
            FileLogger.e(TAG, "创建前台服务通知失败", e)

            // 创建一个简单的备用通知
            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("屏幕截图服务")
                .setContentText("正在后台运行，确保截图功能可用")
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
            FileLogger.e(TAG, "准备启动前台服务（仅保持独立前台服务，避免重复通知）")

            // 仅确保独立的前台服务运行，所有通知由 ScreenCaptureService 负责
            if (!ScreenCaptureService.isServiceRunning) {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                FileLogger.e(TAG, "独立前台服务启动成功")
            } else {
                FileLogger.e(TAG, "独立前台服务已在运行，跳过重复启动")
            }
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
                "ScreenMemory:AccessibilityWakeLock"
            )
            // 短时持锁：10秒超时，避免长期占用
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                wakeLock?.acquire(10_000L)
            } else {
                wakeLock?.acquire()
                // 旧版本：在截屏完成路径与定时器停止时主动释放
            }
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

            // 设置在5秒后触发重启（核心保活，快速拉起）
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
            val now = System.currentTimeMillis()
            val elapsedSinceEvent = now - lastAccessibilityEventAt
            // 事件优先：若最近2秒内收到过事件，则跳过本次轮询，降低轮询频率
            if (elapsedSinceEvent <= 2000L) {
                return
            }
            val candidate = getForegroundAppUsingUsageStats()
            val prevStable = lastStableMonitoredApp
            if (candidate != null) {
                onForegroundCandidateDetected(candidate)
            }
            val stable = lastStableMonitoredApp
            if (stable != null && stable != prevStable) {
                FileLogger.d(TAG, "定时检测稳定前台变化: $prevStable -> $stable")
                currentForegroundApp = stable
                updateAppSession(stable)
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
            val startTime = currentTime - 3000 // 收窄到最近3秒，减少遍历事件成本

            // 获取使用事件
            val usageEvents = usageStats.queryEvents(startTime, currentTime)
            var lastEvent: UsageEvents.Event? = null
            var eventCount = 0

            // 遍历事件，找到最近的前台事件（前台/恢复皆可）
            while (usageEvents.hasNextEvent()) {
                val event = UsageEvents.Event()
                usageEvents.getNextEvent(event)
                eventCount++

                val isForegroundLike = (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
                        || event.eventType == UsageEvents.Event.ACTIVITY_RESUMED)

                if (isForegroundLike) {
                    if (lastEvent == null || event.timeStamp > lastEvent!!.timeStamp) {
                        lastEvent = event
                    }
                }
            }

            var result = lastEvent?.packageName
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

    /**
     * 安全提取当前页面URL（启发式）：
     * - 遍历无障碍树，查找位于屏幕上方区域的文本节点/可编辑节点；
     * - 使用URL正则匹配 http/https；
     * - 不进行浏览器包名硬编码。
     */
    private fun extractCurrentPageUrlSafe(): String? {
        return try {
            val root = rootInActiveWindow
            if (root == null) {
                FileLogger.d(TAG, "extractURL: rootInActiveWindow 为 null")
                return null
            }
            val display = resources.displayMetrics
            val screenH = display.heightPixels
            val topThreshold = (screenH * 0.25f).toInt() // 仅在顶部四分之一区域查找
            FileLogger.d(TAG, "extractURL: screenH=${screenH}, topThreshold=${topThreshold}")

            val queue: ArrayDeque<AccessibilityNodeInfo> = ArrayDeque()
            queue.add(root)
            var bestUrl: String? = null
            var bestY = Int.MAX_VALUE
            var visited = 0
            var matched = 0
            var loggedSamples = 0

            fun candidateText(node: AccessibilityNodeInfo): String? {
                val sb = StringBuilder()
                try {
                    val t = node.text?.toString()
                    if (!t.isNullOrBlank()) sb.append(t)
                } catch (_: Exception) {}
                try {
                    val cd = node.contentDescription?.toString()
                    if (!cd.isNullOrBlank()) {
                        if (sb.isNotEmpty()) sb.append(' ')
                        sb.append(cd)
                    }
                } catch (_: Exception) {}
                val s = sb.toString().trim()
                return if (s.isEmpty()) null else s
            }

            // 主要匹配：显式 http/https 链接（更稳健，避免字符类嵌套导致转义问题）
            val urlRegex = Regex("(?i)\\bhttps?://[^\\s\"<>]+")

            // 回退匹配：无 scheme 的域名（如 example.com/path），命中则默认补全为 https://
            val domainFallback = Regex("(?i)\\b((?:[a-z0-9-]+\\.)+[a-z]{2,})(?:/[\\S]*)?")

            while (queue.isNotEmpty()) {
                val n = queue.removeFirst()
                visited++
                try {
                    val rect = android.graphics.Rect()
                    n.getBoundsInScreen(rect)
                    val y = rect.top
                    if (y in 0..topThreshold) {
                        val text = candidateText(n)
                        if (!text.isNullOrEmpty()) {
                            val m = urlRegex.find(text)
                            if (m != null) {
                                matched++
                                if (loggedSamples < 5) {
                                    val snippet = if (text.length > 120) text.substring(0, 120) + "…" else text
                                    FileLogger.d(TAG, "extractURL: 命中候选 y=${y}, url='${m.value}', text='${snippet}'")
                                    loggedSamples++
                                }
                                if (y < bestY) {
                                    bestY = y
                                    bestUrl = m.value
                                }
                            } else if (bestUrl == null) {
                                // 仅在尚未命中显式URL时，尝试域名回退
                                val dm = domainFallback.find(text)
                                if (dm != null) {
                                    val reconstructed = "https://" + dm.value
                                    if (loggedSamples < 5) {
                                        val snippet = if (text.length > 120) text.substring(0, 120) + "…" else text
                                        FileLogger.d(TAG, "extractURL: 回退命中 y=${y}, domain='${dm.value}', url='${reconstructed}', text='${snippet}'")
                                        loggedSamples++
                                    }
                                    if (y < bestY) {
                                        bestY = y
                                        bestUrl = reconstructed
                                    }
                                }
                            }
                        }
                    }
                    for (i in 0 until (n.childCount ?: 0)) {
                        val c = n.getChild(i)
                        if (c != null) queue.add(c)
                    }
                } catch (_: Exception) {
                }
            }
            if (bestUrl != null) {
                FileLogger.i(TAG, "extractURL: 选定最优 url='${bestUrl}', y=${bestY}, visited=${visited}, matched=${matched}")
            } else {
                FileLogger.i(TAG, "extractURL: 未找到URL, visited=${visited}, matched=${matched}")
            }
            bestUrl
        } catch (e: Exception) {
            FileLogger.e(TAG, "extractURL 异常", e)
            null
        }
    }
}
