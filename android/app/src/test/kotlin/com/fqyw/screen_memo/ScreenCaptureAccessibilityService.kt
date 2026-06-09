package com.fqyw.screen_memo.capture

import com.fqyw.screen_memo.database.ScreenshotDatabaseHelper
import com.fqyw.screen_memo.diagnostics.OEMCompatibilityHelper
import com.fqyw.screen_memo.diagnostics.RuntimeDiagnostics
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.MainActivity
import com.fqyw.screen_memo.mcp.McpServerService
import com.fqyw.screen_memo.segment.SegmentSummaryManager
import com.fqyw.screen_memo.service.RestartReceiver
import com.fqyw.screen_memo.service.ServiceStateManager
import com.fqyw.screen_memo.settings.PerAppSettingsBridge
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
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.system.Os
 
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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.timer
import android.os.IBinder
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.common.InputImage
import com.google.android.gms.tasks.Tasks
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import org.json.JSONArray
import org.json.JSONObject

class ScreenCaptureAccessibilityService : AccessibilityService() {
    
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val PERF_TAG = "ScreenshotPerf"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "screen_capture_channel"
        private const val REQUEST_CODE = 1000
        private const val RESTART_REQUEST_CODE = 2000

        var instance: ScreenCaptureAccessibilityService? = null
        var isServiceRunning = false
    }

    private fun normalizeScreenshotIntervalSeconds(seconds: Int): Int {
        return seconds.coerceIn(1, 60)
    }

    private fun screenshotIntervalMillis(seconds: Int): Long {
        return normalizeScreenshotIntervalSeconds(seconds).toLong() * 1000L
    }

    private fun formatIntervalSeconds(seconds: Int): String {
        return seconds.toString()
    }

    internal fun perf(message: String) {
        // 使用独立 tag，避免“截图分类日志”关闭时看不到关键链路耗时。
        FileLogger.i(PERF_TAG, message)
    }

    internal fun nextCaptureTraceId(): Long = captureTraceCounter.incrementAndGet()

    private fun persistTimedScreenshotRunningState() {
        try {
            val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            val normalizedInterval = normalizeScreenshotIntervalSeconds(baseScreenshotInterval)
            sharedPrefs.edit().apply {
                putBoolean("timed_screenshot_was_running", true)
                // 这里只保存“全局基础间隔”用于服务重启恢复，不能保存每应用临时生效间隔。
                putInt("timed_screenshot_interval", normalizedInterval)
                putInt("screenshot_interval", normalizedInterval)
                apply()
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "持久化定时截屏状态失败", e)
        }
    }

    private fun resolveEffectiveScreenshotInterval(targetApp: String): EffectiveScreenshotInterval {
        val intervalStartMs = SystemClock.elapsedRealtime()
        val customIv = PerAppSettingsBridge.readIntervalIfCustom(this, targetApp)
        val normalizedCustom = customIv?.let { normalizeScreenshotIntervalSeconds(it) }
        val readMs = SystemClock.elapsedRealtime() - intervalStartMs
        return if (normalizedCustom != null && normalizedCustom > 0) {
            EffectiveScreenshotInterval(
                seconds = normalizedCustom,
                source = "custom",
                customSeconds = normalizedCustom,
                readMs = readMs
            )
        } else {
            EffectiveScreenshotInterval(
                seconds = baseScreenshotInterval,
                source = "global",
                customSeconds = null,
                readMs = readMs
            )
        }
    }

    private fun applyEffectiveScreenshotInterval(targetApp: String): IntervalApplyResult {
        val effective = resolveEffectiveScreenshotInterval(targetApp)
        val desiredInterval = normalizeScreenshotIntervalSeconds(effective.seconds)
        var timerReset = false
        if (desiredInterval != screenshotInterval) {
            FileLogger.i(
                TAG,
                "应用($targetApp)生效间隔=${formatIntervalSeconds(desiredInterval)}s，" +
                    "source=${effective.source}, custom=${effective.customSeconds ?: "-"}, " +
                    "global=${formatIntervalSeconds(baseScreenshotInterval)}s, " +
                    "current=${formatIntervalSeconds(screenshotInterval)}s -> 重置计时器"
            )
            screenshotInterval = desiredInterval
            timerReset = true

            try {
                ScreenCaptureService.updateNotificationState(
                    this,
                    intervalSeconds = screenshotInterval
                )
            } catch (_: Exception) {}

            screenshotTimer?.cancel()
            screenshotTimer = timer(
                name = "ScreenshotTimer",
                daemon = true,
                period = screenshotIntervalMillis(screenshotInterval)
            ) {
                if (isTimedScreenshotRunning) {
                    performTimedScreenshot()
                }
            }

            // 只刷新运行标记和全局基础间隔，避免自定义间隔污染全局恢复值。
            persistTimedScreenshotRunningState()
        }
        return IntervalApplyResult(effective, timerReset)
    }

    private fun idleNotificationIntervalSeconds(): Int? {
        val interval = if (baseScreenshotInterval > 0) baseScreenshotInterval else screenshotInterval
        return if (interval > 0) interval else null
    }

    private fun applyIntervalForForegroundNotification(packageName: String): Int? {
        return if (!isTimedScreenshotRunning) {
            if (screenshotInterval > 0) screenshotInterval else idleNotificationIntervalSeconds()
        } else {
            try {
                applyEffectiveScreenshotInterval(packageName)
                if (screenshotInterval > 0) screenshotInterval else null
            } catch (e: Exception) {
                FileLogger.w(TAG, "前台通知应用间隔失败: ${e.message}")
                if (screenshotInterval > 0) screenshotInterval else idleNotificationIntervalSeconds()
            }
        }
    }

    private data class EffectiveScreenshotInterval(
        val seconds: Int,
        val source: String,
        val customSeconds: Int?,
        val readMs: Long
    )

    private data class IntervalApplyResult(
        val effective: EffectiveScreenshotInterval,
        val timerReset: Boolean
    )

    private fun tryReserveScreenshotSaveSlot(): Int {
        while (true) {
            val current = pendingScreenshotSaves.get()
            if (current >= maxPendingScreenshotSaves) {
                return -1
            }
            if (pendingScreenshotSaves.compareAndSet(current, current + 1)) {
                return current + 1
            }
        }
    }
    
    // 去重：保留裁剪后画面的版本化签名（兼容旧精确签名）
    private val lastSignatureByApp: MutableMap<String, String> = mutableMapOf()

    // 添加WakeLock防止Doze模式
    private var wakeLock: PowerManager.WakeLock? = null
    private var packageInstallReceiver: BroadcastReceiver? = null
    private val selectedAppsPrefsLock = Any()

    // 定时截屏相关
    private var screenshotTimer: Timer? = null
    // 全局基础间隔只表示用户在全局设置中的默认值；每应用自定义间隔不能写回这里。
    private var baseScreenshotInterval: Int = 5
    // 当前生效间隔：有每应用自定义时用自定义值，否则恢复到 baseScreenshotInterval。
    private var screenshotInterval: Int = 5 // 默认5秒
    private var isTimedScreenshotRunning = false
    @Volatile private var pausedByScreenOff: Boolean = false
    private val screenshotCallbackExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "ScreenMemoScreenshotCallback").apply { isDaemon = true }
    }
    private val screenshotSaveExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "ScreenMemoScreenshotSave").apply { isDaemon = true }
    }
    internal val screenshotCompressionExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "ScreenMemoScreenshotCompress").apply { isDaemon = true }
    }
    internal val ocrExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "ScreenMemoScreenshotOcr").apply { isDaemon = true }
    }
    private val pendingScreenshotSaves = AtomicInteger(0)
    private val maxPendingScreenshotSaves = 20
    internal val pendingDeferredCompressions = AtomicInteger(0)
    private val captureTraceCounter = AtomicLong(0)

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
    private var lastDetailedFailureSnapshotAt: Long = 0L
    private var lastNoTargetSnapshotAt: Long = 0L

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
    private val OVERLAY_GRACE_MS = 5000L      // 系统遮罩期间沿用上次稳定应用的宽限时长
    private val FOREGROUND_EVENT_MAX_AGE_MS = 1_500L
    private val LONG_WINDOW_EVENT_MAX_AGE_MS = 7_000L
    private val ACCESSIBILITY_EVENT_MAX_AGE_MS = 1_500L
    private var lastStableMonitoredApp: String? = null
    private var lastStableSeenAt: Long = 0L
    @Volatile private var isSelfForeground: Boolean = false
    // 分离任意事件与真正窗口前台事件，避免 B 站等内容事件持续刷新后抑制兜底轮询
    @Volatile private var lastAnyAccessibilityEventAt: Long = 0L
    @Volatile private var lastAccessibilityWindowEventAt: Long = 0L

    private data class CaptureValidationResult(
        val allowed: Boolean,
        val reason: String,
        val visiblePackage: String? = null
    )

    private fun isLauncherPackage(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        if (staticLauncherPackages.contains(packageName)) return true
        if (resolvedLauncherPackages.contains(packageName)) return true
        return false
    }

    private fun refreshResolvedLauncherPackages() {
        try {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            val resolved = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            val pkgs = resolved.mapNotNull { it.activityInfo?.packageName }
                .filter { !it.isNullOrBlank() }
                .toSet()
            resolvedLauncherPackages = pkgs
            if (FileLogger.isDebugEnabled()) {
                FileLogger.d(TAG, "默认桌面解析: $resolvedLauncherPackages")
            }
        } catch (e: Exception) {
            FileLogger.w(TAG, "刷新默认桌面包失败: ${e.message}")
        }
    }

    private fun isLauncherCurrentlyForeground(candidatePackage: String): Boolean {
        return try {
            val windowList = windows ?: return false
            if (windowList.isEmpty()) return true
            var launcherWindowFound = false
            var conflictingWindowFound = false
            for (w in windowList) {
                if (w.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                val root = w.root
                val pkg = try {
                    root?.packageName?.toString()
                } finally {
                    try { root?.recycle() } catch (_: Exception) {}
                }
                if (pkg.isNullOrBlank()) continue
                when {
                    pkg == candidatePackage -> launcherWindowFound = true
                    pkg == packageName -> Unit
                    isLauncherPackage(pkg) -> Unit
                    transientOverlayPackages.contains(pkg) -> Unit
                    isMiuiSystemApp(pkg) -> Unit
                    isImePackage(pkg) -> Unit
                    isAutomationSkipPackage(pkg) -> Unit
                    else -> {
                        conflictingWindowFound = true
                        break
                    }
                }
            }
            !conflictingWindowFound && (launcherWindowFound || windowList.none { it.type == AccessibilityWindowInfo.TYPE_APPLICATION })
        } catch (e: Exception) {
            FileLogger.w(TAG, "确认桌面窗口失败: ${e.message}")
            false
        }
    }

    // 复用 OCR 识别器，避免频繁创建带来的CPU/内存抖动
    @Volatile internal var sharedTextRecognizer: com.google.mlkit.vision.text.TextRecognizer? = null


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

    private val automationSkipPackagePrefixes: List<String> = listOf(
        "li.gkd",
        "li.songe.gkd"
    )

    private fun isImePackage(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        if (imePackages.contains(pkg)) return true
        return imeRegexes.any { it.containsMatchIn(pkg) }
    }

    private fun isAutomationSkipPackage(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        val normalized = pkg.lowercase(Locale.ROOT)
        for (prefix in automationSkipPackagePrefixes) {
            if (normalized == prefix || normalized.startsWith("$prefix.")) {
                return true
            }
        }
        return false
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
     * 处理前台应用候选：检测到监控应用立即认定为稳定前台；
     * 对于系统遮罩（通知栏、系统UI），不改变稳定应用，仅更新宽限期内沿用。
     */
    private fun onForegroundCandidateDetected(candidatePackage: String?) {
        val now = System.currentTimeMillis()
        if (candidatePackage.isNullOrEmpty()) {
            return
        }

        // 本应用：置顶时仅暂停截屏，保留稳定目标以便离开后快速恢复
        if (candidatePackage == packageName) {
            if (!isSelfForeground) {
                FileLogger.i(TAG, "检测到本应用窗口(${candidatePackage})，暂停截屏但保留稳定目标")
            } else {
                FileLogger.d(TAG, "本应用窗口仍在前台，保持暂停状态")
            }
            isSelfForeground = true
            // 关键：同步清空当前前台缓存，避免 getCurrentForegroundApp() 兜底返回旧值
            currentForegroundApp = null
            try {
                ScreenCaptureService.updateNotificationState(
                    this,
                    intervalSeconds = idleNotificationIntervalSeconds(),
                    captureEnabled = false,
                    clearForegroundPackage = true
                )
            } catch (_: Exception) {}
            return
        }

        if (isSelfForeground) {
            FileLogger.d(TAG, "检测到非本应用窗口(${candidatePackage})，恢复前台候选检测")
        }
        isSelfForeground = false

        // 输入法：忽略，不参与稳定候选
        if (isImePackage(candidatePackage)) {
            if (lastStableMonitoredApp != null) {
                lastStableSeenAt = now
            }
            FileLogger.d(TAG, "检测到输入法窗口 $candidatePackage，忽略该候选")
            return
        }

        if (isAutomationSkipPackage(candidatePackage)) {
            if (lastStableMonitoredApp != null) {
                lastStableSeenAt = now
            }
            FileLogger.d(TAG, "检测到自动化辅助应用 $candidatePackage，忽略该候选")
            return
        }

        if (!staticLauncherPackages.contains(candidatePackage) && !resolvedLauncherPackages.contains(candidatePackage)) {
            refreshResolvedLauncherPackages()
        }

        // 桌面/Launcher：增加窗口验证，避免误判
        if (isLauncherPackage(candidatePackage)) {
            if (!isLauncherCurrentlyForeground(candidatePackage)) {
                FileLogger.d(TAG, "检测到桌面候选($candidatePackage)但窗口仍显示其他应用，忽略")
                return
            }
            FileLogger.i(TAG, "检测到桌面/Launcher: $candidatePackage，清除稳定会话并暂停截屏")
            lastStableMonitoredApp = null
            lastStableSeenAt = 0L
            // 同步清空当前前台缓存
            currentForegroundApp = null
            try {
                ScreenCaptureService.updateNotificationState(
                    this,
                    intervalSeconds = idleNotificationIntervalSeconds(),
                    captureEnabled = false,
                    clearForegroundPackage = true
                )
            } catch (_: Exception) {}
            return
        }

        // 系统遮罩：沿用上次稳定应用，不更新候选（宽限逻辑在 getScreenshotTargetApp 中执行）
        if (transientOverlayPackages.contains(candidatePackage) || isMiuiSystemApp(candidatePackage)) {
            if (lastStableMonitoredApp != null) {
                lastStableSeenAt = now
            }
            FileLogger.d(TAG, "检测到系统遮罩/系统UI: $candidatePackage，维持当前稳定应用: $lastStableMonitoredApp")
            return
        }

        // 非监控列表应用：完全忽略，不作为候选，不影响稳定目标/锁定
        if (!isAppInMonitorList(candidatePackage)) {
            FileLogger.d(TAG, "忽略非监控应用: $candidatePackage")
            try {
                ScreenCaptureService.updateNotificationState(
                    this,
                    intervalSeconds = idleNotificationIntervalSeconds(),
                    captureEnabled = false,
                    clearForegroundPackage = true
                )
            } catch (_: Exception) {}
            return
        }

        // 相同于当前稳定应用：刷新最近出现时间
        if (lastStableMonitoredApp == candidatePackage) {
            lastStableSeenAt = now
            FileLogger.d(TAG, "稳定前台应用保持: $lastStableMonitoredApp")
            try {
                ScreenCaptureService.updateNotificationState(
                    this,
                    foregroundPackage = candidatePackage,
                    intervalSeconds = applyIntervalForForegroundNotification(candidatePackage),
                    captureEnabled = isTimedScreenshotRunning
                )
            } catch (_: Exception) {}
            return
        }

        // 去掉稳定晋升：检测到候选即刻认定为稳定前台
        lastStableMonitoredApp = candidatePackage
        lastStableSeenAt = now
        FileLogger.i(TAG, "前台应用更新: $lastStableMonitoredApp")
        try {
            ScreenCaptureService.updateNotificationState(
                this,
                foregroundPackage = candidatePackage,
                intervalSeconds = applyIntervalForForegroundNotification(candidatePackage),
                captureEnabled = isTimedScreenshotRunning
            )
        } catch (_: Exception) {}
    }



    // 简化的处理器（仅用于基本操作）
    private val handler = Handler(Looper.getMainLooper())

    // 首页/桌面应用包名列表
    private val staticLauncherPackages = setOf(
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

    @Volatile private var resolvedLauncherPackages: Set<String> = emptySet()
    
    override fun onCreate() {
        super.onCreate()

        // 初始化文件日志
        FileLogger.init(this)
        // 同步 FlutterSharedPreferences 中的 logging_enabled
        try { FileLogger.syncFromFlutterPrefs(this) } catch (_: Exception) {}
        FileLogger.writeSeparator("AccessibilityService onCreate")
        FileLogger.writeSystemInfo(this)

        FileLogger.e(TAG, "=== 无障碍服务 onCreate 开始 ===")
        FileLogger.e(TAG, "无障碍服务已创建，进程ID: ${android.os.Process.myPid()}")
        FileLogger.e(TAG, "当前时间: ${System.currentTimeMillis()}")
        FileLogger.e(TAG, "日志文件路径: ${FileLogger.getLogFilePath()}")
        RuntimeDiagnostics.logProcessStart(this, TAG, "accessibility_onCreate", force = true)

        // 预设instance，以防onServiceConnected没有被调用
        instance = this
        FileLogger.e(TAG, "已在onCreate中设置instance")
        restoreMcpServerIfEnabled("accessibility_onCreate")
        registerPackageInstallReceiver()

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
            restoreMcpServerIfEnabled("accessibility_onServiceConnected")
            RuntimeDiagnostics.logSnapshot(
                this,
                TAG,
                "accessibility_onServiceConnected",
                extras = mapOf(
                    "savedServiceState" to getSavedServiceState(),
                    "timedRunning" to isTimedScreenshotRunning,
                    "onePlus" to OEMCompatibilityHelper.isOnePlusDevice(),
                ),
                force = true,
            )

            // 延迟初始化其他功能，避免阻塞服务启动
            handler.postDelayed({
                try {
                    // 启动前台服务
                    startForegroundService()
                    FileLogger.e(TAG, "前台服务已启动")
                    restoreMcpServerIfEnabled("accessibility_delayed_init")

                    // 移除服务级长期持锁：截屏时再短时获取WakeLock

                    // 初始化UsageStatsManager
                    usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    FileLogger.e(TAG, "UsageStatsManager已初始化")

                    // 刷新启用的输入法集合，避免输入法被判为前台
                    refreshImePackages(force = true)
                    refreshResolvedLauncherPackages()

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
                            val a = spGetIntCompat(sharedPrefs, "timed_screenshot_interval", -1)
                            val b = spGetIntCompat(sharedPrefs, "screenshot_interval", -1)
                            normalizeScreenshotIntervalSeconds(if (a != -1) a else if (b != -1) b else 5)
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
        RuntimeDiagnostics.logSnapshot(
            this,
            TAG,
            "accessibility_onUnbind",
            extras = mapOf(
                "intent" to (intent?.toString() ?: "-"),
                "timedRunning" to isTimedScreenshotRunning,
            ),
            force = true,
        )

        // 清理资源
        stopScreenCapture()
        releaseWakeLock()
        unregisterPackageInstallReceiver()

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
        RuntimeDiagnostics.logSnapshot(
            this,
            TAG,
            "accessibility_onDestroy",
            extras = mapOf(
                "timedRunning" to isTimedScreenshotRunning,
                "pausedByScreenOff" to pausedByScreenOff,
                "currentForegroundApp" to (currentForegroundApp ?: "-"),
                "stableApp" to (lastStableMonitoredApp ?: "-"),
            ),
            force = true,
        )

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
        unregisterPackageInstallReceiver()

        // 关闭截图保存队列，避免服务销毁后继续编码/写文件
        try {
            screenshotCallbackExecutor.shutdownNow()
        } catch (_: Exception) {}
        try {
            screenshotSaveExecutor.shutdownNow()
        } catch (_: Exception) {}
        try {
            screenshotCompressionExecutor.shutdownNow()
        } catch (_: Exception) {}
        try {
            ocrExecutor.shutdownNow()
            ocrExecutor.awaitTermination(1500, TimeUnit.MILLISECONDS)
        } catch (_: Exception) {}
        pendingScreenshotSaves.set(0)
        pendingDeferredCompressions.set(0)

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
        RuntimeDiagnostics.logSnapshot(
            this,
            TAG,
            "accessibility_onTaskRemoved",
            extras = mapOf(
                "rootIntent" to (rootIntent?.toString() ?: "-"),
                "timedRunning" to isTimedScreenshotRunning,
                "pausedByScreenOff" to pausedByScreenOff,
                "currentForegroundApp" to (currentForegroundApp ?: "-"),
                "stableApp" to (lastStableMonitoredApp ?: "-"),
                "onePlus" to OEMCompatibilityHelper.isOnePlusDevice(),
            ),
            force = true,
        )

        try {
            // 保存服务状态，表明服务应该继续运行
            saveServiceState(true)
            FileLogger.e(TAG, "服务状态已保存为运行中")

            // 立即设置重启闹钟（作为兜底）
            scheduleRestart()
            FileLogger.e(TAG, "重启闹钟已设置")

            // 避免重复拉起前台服务导致通知闪烁：仅在未运行时再启动
            val fgRunning = try {
                ServiceStateManager.isForegroundServiceRunning(this)
            } catch (_: Exception) {
                false
            }
            if (fgRunning) {
                FileLogger.e(TAG, "前台服务已在运行，跳过重复启动（避免通知闪烁）")
            } else {
                try {
                    val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                    startForegroundService(serviceIntent)
                    FileLogger.e(TAG, "前台服务启动成功")
                } catch (e: Exception) {
                    FileLogger.e(TAG, "启动前台服务失败", e)
                }
            }
            
            // 保存当前的定时截屏状态
            if (isTimedScreenshotRunning) {
                persistTimedScreenshotRunningState()
                FileLogger.e(TAG, "定时截屏状态已保存")
            }

            restoreMcpServerIfEnabled("accessibility_onTaskRemoved")

        } catch (e: Exception) {
            FileLogger.e(TAG, "onTaskRemoved处理失败", e)
        }

        FileLogger.e(TAG, "=== onTaskRemoved处理完成 ===")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 更新看门狗心跳
        AccessibilityServiceWatchdog.updateHeartbeat()

        // 处理无障碍事件，检测当前前台应用（含遮罩容错）
        event?.let {
            val now = System.currentTimeMillis()
            lastAnyAccessibilityEventAt = now
            if (it.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
                it.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED
            ) {
                lastAccessibilityWindowEventAt = now
                val candidate = if (it.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
                    getCurrentForegroundApp() ?: it.packageName?.toString()
                } else {
                    it.packageName?.toString()
                }
                val eventAge = try { SystemClock.uptimeMillis() - it.eventTime } catch (_: Exception) { 0L }
                if (eventAge > ACCESSIBILITY_EVENT_MAX_AGE_MS) {
                    FileLogger.d(TAG, "忽略过期的无障碍前台事件: $candidate, age=${eventAge}ms")
                    return@let
                }
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
            isLauncherPackage(packageName) -> {
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

            // 如果无法通过窗口获取，则返回 null（避免使用过期缓存）
            return null
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取当前前台应用失败", e)
            return null
        }
    }
    
    override fun onInterrupt() {
        FileLogger.d(TAG, "无障碍服务被中断")
        RuntimeDiagnostics.logSnapshot(this, TAG, "accessibility_onInterrupt", force = true)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        RuntimeDiagnostics.logSnapshot(
            this,
            TAG,
            "accessibility_onTrimMemory",
            extras = mapOf(
                "level" to level,
                "timedRunning" to isTimedScreenshotRunning,
                "stableApp" to (lastStableMonitoredApp ?: "-"),
            ),
            force = true,
        )
    }

    override fun onLowMemory() {
        super.onLowMemory()
        RuntimeDiagnostics.logSnapshot(
            this,
            TAG,
            "accessibility_onLowMemory",
            extras = mapOf(
                "timedRunning" to isTimedScreenshotRunning,
                "stableApp" to (lastStableMonitoredApp ?: "-"),
            ),
            force = true,
        )
    }
    
    
    /**
     * 使用无障碍服务截取屏幕
     */
    private fun takeScreenshotUsingAccessibility(
        targetPackage: String?,
        traceId: Long = nextCaptureTraceId(),
        tickStartMs: Long = SystemClock.elapsedRealtime(),
        captureTimeMillis: Long = System.currentTimeMillis(),
        callback: (Boolean, String?) -> Unit
    ) {
        val apiStartMs = SystemClock.elapsedRealtime()
        try {
            // 在截屏前检查屏幕/锁屏状态，避免息屏状态下产生黑图
            if (shouldPauseForScreenState()) {
                perf(
                    "trace=$traceId stage=precheck result=screen_state_blocked " +
                        "target=${targetPackage ?: "-"} elapsedMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                )
                maybeLogDetailedFailure(
                    "screen_state_blocked",
                    mapOf(
                        "timedRunning" to isTimedScreenshotRunning,
                        "stableApp" to (lastStableMonitoredApp ?: "-"),
                    )
                )
                callback(false, null)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val targetLabel = targetPackage ?: "auto"
                FileLogger.d(TAG, "使用无障碍服务takeScreenshot API截屏, target=$targetLabel")
                perf(
                    "trace=$traceId stage=takeScreenshot_request target=$targetLabel " +
                        "sinceTickMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                )
                // 截屏前短时获取 WakeLock，避免在息屏边缘时 CPU 被挂起
                acquireWakeLock()
                takeScreenshot(
                    android.view.Display.DEFAULT_DISPLAY,
                    screenshotCallbackExecutor,
                    object : AccessibilityService.TakeScreenshotCallback {
                        override fun onSuccess(screenshotResult: AccessibilityService.ScreenshotResult) {
                            var shouldReleaseWakeLock = true
                            try {
                                val apiMs = SystemClock.elapsedRealtime() - apiStartMs
                                val callbackAtMs = SystemClock.elapsedRealtime()
                                val wrapStartMs = SystemClock.elapsedRealtime()
                                FileLogger.d(TAG, "截屏成功，开始包装 Bitmap")
                                val hardwareBuffer = screenshotResult.hardwareBuffer
                                val bitmap = try {
                                    Bitmap.wrapHardwareBuffer(
                                        hardwareBuffer,
                                        screenshotResult.colorSpace
                                    )
                                } finally {
                                    try { hardwareBuffer.close() } catch (_: Exception) {}
                                }
                                val wrapMs = SystemClock.elapsedRealtime() - wrapStartMs

                                if (bitmap == null) {
                                    perf(
                                        "trace=$traceId stage=takeScreenshot_success result=bitmap_null " +
                                            "target=$targetLabel apiMs=$apiMs sinceTickMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                    )
                                    FileLogger.e(TAG, "无法从截屏结果创建 Bitmap")
                                    RuntimeDiagnostics.noteCaptureFailure(
                                        this@ScreenCaptureAccessibilityService,
                                        TAG,
                                        "bitmap_null"
                                    )
                                    releaseWakeLock()
                                    callback(false, null)
                                    return
                                }

                                val lockedTarget = targetPackage ?: getScreenshotTargetApp() ?: "unknown"
                                if (targetPackage != null && lockedTarget.isBlank()) {
                                    perf(
                                        "trace=$traceId stage=discard result=invalid_target " +
                                            "target=$targetLabel apiMs=$apiMs wrapMs=$wrapMs sinceTickMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                    )
                                    FileLogger.d(TAG, "截图成功但没有有效锁定目标，丢弃本次图片")
                                    try { bitmap.recycle() } catch (_: Exception) {}
                                    releaseWakeLock()
                                    callback(true, null)
                                    return
                                }

                                if (targetPackage != null) {
                                    val validationStartMs = SystemClock.elapsedRealtime()
                                    val validation = validateCaptureStillBelongsToTarget(lockedTarget)
                                    val validationMs = SystemClock.elapsedRealtime() - validationStartMs
                                    if (!validation.allowed) {
                                        val visibleLabel = validation.visiblePackage ?: "-"
                                        perf(
                                            "trace=$traceId stage=validation result=discard reason=${validation.reason} " +
                                                "target=$lockedTarget visible=$visibleLabel apiMs=$apiMs wrapMs=$wrapMs " +
                                                "validationMs=$validationMs sinceTickMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                        )
                                        FileLogger.i(
                                            TAG,
                                            "截图保存前校验未通过，丢弃: reason=${validation.reason}, target=$lockedTarget, visible=$visibleLabel"
                                        )
                                        try {
                                            ScreenCaptureService.updateNotificationState(
                                                this@ScreenCaptureAccessibilityService,
                                                intervalSeconds = idleNotificationIntervalSeconds(),
                                                captureEnabled = false,
                                                clearForegroundPackage = validation.reason == "discard_self_foreground" ||
                                                    validation.reason == "discard_launcher_foreground" ||
                                                    validation.reason == "discard_non_monitor_foreground"
                                            )
                                        } catch (_: Exception) {}
                                        try { bitmap.recycle() } catch (_: Exception) {}
                                        releaseWakeLock()
                                        callback(true, null)
                                        return
                                    }
                                    val visibleLabel = validation.visiblePackage ?: "-"
                                    perf(
                                        "trace=$traceId stage=validation result=allow reason=${validation.reason} " +
                                            "target=$lockedTarget visible=$visibleLabel validationMs=$validationMs"
                                    )
                                    FileLogger.d(
                                        TAG,
                                        "截图保存前校验通过: reason=${validation.reason}, target=$lockedTarget, visible=$visibleLabel"
                                    )
                                }

                                val pendingAfterEnqueue = tryReserveScreenshotSaveSlot()
                                if (pendingAfterEnqueue < 0) {
                                    val pendingBeforeEnqueue = pendingScreenshotSaves.get()
                                    perf(
                                        "trace=$traceId stage=save_guard result=skip reason=save_queue_full " +
                                            "target=$lockedTarget pending=$pendingBeforeEnqueue limit=$maxPendingScreenshotSaves " +
                                            "apiMs=$apiMs wrapMs=$wrapMs sinceTickMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                    )
                                    FileLogger.w(TAG, "save_queue_full_skip: 截图保存队列已满，丢弃当前帧 target=$lockedTarget, pending=$pendingBeforeEnqueue")
                                    try {
                                        ScreenCaptureService.updateNotificationState(
                                            this@ScreenCaptureAccessibilityService,
                                            foregroundPackage = lockedTarget,
                                            intervalSeconds = if (screenshotInterval > 0) screenshotInterval else null,
                                            captureEnabled = true
                                        )
                                    } catch (_: Exception) {}
                                    try { bitmap.recycle() } catch (_: Exception) {}
                                    releaseWakeLock()
                                    callback(true, null)
                                    return
                                }

                                try {
                                    perf(
                                        "trace=$traceId stage=save_enqueue target=$lockedTarget " +
                                            "pending=$pendingAfterEnqueue apiMs=$apiMs wrapMs=$wrapMs sinceTickMs=${callbackAtMs - tickStartMs}"
                                    )
                                    screenshotSaveExecutor.execute {
                                    try {
                                        val workerStartMs = SystemClock.elapsedRealtime()
                                        val duplicateStartMs = SystemClock.elapsedRealtime()
                                        try {
                                            if (isDuplicateScreenshot(bitmap, lockedTarget, traceId)) {
                                                val duplicateMs = SystemClock.elapsedRealtime() - duplicateStartMs
                                                perf(
                                                    "trace=$traceId stage=duplicate_check result=duplicate target=$lockedTarget " +
                                                        "apiMs=$apiMs wrapMs=$wrapMs duplicateMs=$duplicateMs " +
                                                        "workerMs=${SystemClock.elapsedRealtime() - workerStartMs} " +
                                                        "totalMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                                )
                                                FileLogger.i(TAG, "检测到重复截图，已跳过保存: $lockedTarget, duplicateMs=${duplicateMs}, apiMs=${apiMs}, wrapMs=${wrapMs}")
                                                try {
                                                    ScreenCaptureService.updateNotificationState(
                                                        this@ScreenCaptureAccessibilityService,
                                                        foregroundPackage = lockedTarget,
                                                        intervalSeconds = if (screenshotInterval > 0) screenshotInterval else null,
                                                        lastScreenshotAt = captureTimeMillis,
                                                        captureEnabled = true
                                                    )
                                                } catch (_: Exception) {}
                                                RuntimeDiagnostics.noteCaptureSuccess(
                                                    this@ScreenCaptureAccessibilityService,
                                                    TAG,
                                                    lockedTarget,
                                                    null
                                                )
                                                callback(true, null)
                                                return@execute
                                            }
                                        } catch (e: Exception) {
                                            FileLogger.w(TAG, "重复判定失败，忽略并继续保存: ${e.message}")
                                        }
                                        val duplicateMs = SystemClock.elapsedRealtime() - duplicateStartMs

                                        val savedPath = saveScreenshotBitmap(
                                            bitmap,
                                            lockedTarget,
                                            traceId,
                                            tickStartMs,
                                            captureTimeMillis
                                        )
                                        try {
                                            ScreenCaptureService.updateNotificationState(
                                                this@ScreenCaptureAccessibilityService,
                                                foregroundPackage = lockedTarget,
                                                intervalSeconds = if (screenshotInterval > 0) screenshotInterval else null,
                                                lastScreenshotAt = captureTimeMillis,
                                                captureEnabled = true
                                            )
                                        } catch (_: Exception) {}
                                        RuntimeDiagnostics.noteCaptureSuccess(
                                            this@ScreenCaptureAccessibilityService,
                                            TAG,
                                            lockedTarget,
                                            savedPath
                                        )
                                        FileLogger.i(
                                            TAG,
                                            "截图链路耗时: target=$lockedTarget, apiMs=$apiMs, wrapMs=$wrapMs, duplicateMs=$duplicateMs, workerTotalMs=${SystemClock.elapsedRealtime() - workerStartMs}"
                                        )
                                        perf(
                                            "trace=$traceId stage=capture_complete result=${if (savedPath != null) "saved" else "no_file"} " +
                                                "target=$lockedTarget apiMs=$apiMs wrapMs=$wrapMs duplicateMs=$duplicateMs " +
                                                "workerMs=${SystemClock.elapsedRealtime() - workerStartMs} " +
                                                "totalMs=${SystemClock.elapsedRealtime() - tickStartMs} path=${savedPath ?: "-"}"
                                        )
                                        callback(true, savedPath)
                                    } catch (e: Exception) {
                                        perf(
                                            "trace=$traceId stage=save_worker result=exception target=$lockedTarget " +
                                                "message=${e.message ?: "-"} totalMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                        )
                                        FileLogger.e(TAG, "后台保存截图失败", e)
                                        RuntimeDiagnostics.noteCaptureFailure(
                                            this@ScreenCaptureAccessibilityService,
                                            TAG,
                                            "save_worker_exception",
                                            extras = mapOf("message" to (e.message ?: "-"))
                                        )
                                        callback(false, null)
                                    } finally {
                                        try { bitmap.recycle() } catch (_: Exception) {}
                                        pendingScreenshotSaves.decrementAndGet()
                                        releaseWakeLock()
                                    }
                                }
                                    shouldReleaseWakeLock = false
                                } catch (e: Exception) {
                                    pendingScreenshotSaves.decrementAndGet()
                                    perf(
                                        "trace=$traceId stage=save_enqueue result=exception target=$lockedTarget " +
                                            "message=${e.message ?: "-"} totalMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                    )
                                    FileLogger.e(TAG, "提交后台保存任务失败", e)
                                    RuntimeDiagnostics.noteCaptureFailure(
                                        this@ScreenCaptureAccessibilityService,
                                        TAG,
                                        "save_executor_rejected",
                                        extras = mapOf("message" to (e.message ?: "-"))
                                    )
                                    throw e
                                }
                            } catch (e: Exception) {
                                perf(
                                    "trace=$traceId stage=handle_result result=exception target=$targetLabel " +
                                        "message=${e.message ?: "-"} totalMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                                )
                                FileLogger.e(TAG, "处理截屏结果失败", e)
                                RuntimeDiagnostics.noteCaptureFailure(
                                    this@ScreenCaptureAccessibilityService,
                                    TAG,
                                    "handle_result_exception",
                                    extras = mapOf("message" to (e.message ?: "-"))
                                )
                                if (shouldReleaseWakeLock) {
                                    releaseWakeLock()
                                }
                                callback(false, null)
                            }
                        }

                        override fun onFailure(errorCode: Int) {
                            val apiMs = SystemClock.elapsedRealtime() - apiStartMs
                            perf(
                                "trace=$traceId stage=takeScreenshot_failure target=$targetLabel " +
                                    "errorCode=$errorCode errorName=${RuntimeDiagnostics.accessibilityScreenshotErrorName(errorCode)} " +
                                    "apiMs=$apiMs totalMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                            )
                            FileLogger.e(TAG, "截屏失败，错误码: $errorCode")
                            RuntimeDiagnostics.noteCaptureFailure(
                                this@ScreenCaptureAccessibilityService,
                                TAG,
                                "take_screenshot_failure",
                                errorCode = errorCode
                            )
                            maybeLogDetailedFailure(
                                "take_screenshot_failure",
                                mapOf(
                                    "errorCode" to errorCode,
                                    "errorName" to RuntimeDiagnostics.accessibilityScreenshotErrorName(errorCode),
                                    "currentForegroundApp" to (currentForegroundApp ?: "-"),
                                    "stableApp" to (lastStableMonitoredApp ?: "-"),
                                )
                            )
                            releaseWakeLock()
                            callback(false, null)
                        }
                    }
                )
            } else {
                perf(
                    "trace=$traceId stage=precheck result=sdk_too_low " +
                        "sdk=${Build.VERSION.SDK_INT} totalMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                )
                FileLogger.e(TAG, "Android版本过低，不支持无障碍截屏 (需要API 30+)")
                RuntimeDiagnostics.noteCaptureFailure(this, TAG, "sdk_too_low")
                callback(false, null)
            }
        } catch (e: Exception) {
            perf(
                "trace=$traceId stage=takeScreenshot_exception target=${targetPackage ?: "-"} " +
                    "message=${e.message ?: "-"} totalMs=${SystemClock.elapsedRealtime() - tickStartMs}"
            )
            FileLogger.e(TAG, "无障碍截屏异常", e)
            RuntimeDiagnostics.noteCaptureFailure(
                this,
                TAG,
                "take_screenshot_exception",
                extras = mapOf("message" to (e.message ?: "-"))
            )
            maybeLogDetailedFailure(
                "take_screenshot_exception",
                mapOf("message" to (e.message ?: "-"))
            )
            // 出错时确保释放 WakeLock（若已获取）
            releaseWakeLock()
            callback(false, null)
        }
    }

    private fun readScreenshotDedupeMode(): ScreenshotDedupeHelper.Mode {
        val raw = try {
            UserSettingsStorage.getString(
                this,
                UserSettingsKeysNative.SCREENSHOT_DEDUPE_MODE,
                defaultValue = ScreenshotDedupeHelper.Mode.BALANCED.rawValue
            )
        } catch (_: Exception) {
            ScreenshotDedupeHelper.Mode.BALANCED.rawValue
        }
        return ScreenshotDedupeHelper.Mode.fromRaw(raw)
    }

    private data class DedupePixelSample(
        val width: Int,
        val height: Int,
        val pixels: IntArray,
        val sampledBitmap: Bitmap?
    )

    private fun sampleBitmapPixelsForDedupe(
        bitmap: Bitmap,
        mode: ScreenshotDedupeHelper.Mode
    ): DedupePixelSample {
        val width = bitmap.width
        val height = bitmap.height
        val sampleSize = ScreenshotDedupeHelper.sampleSizeForMode(width, height, mode)
        val sampled = if (sampleSize.width != width || sampleSize.height != height) {
            try {
                Bitmap.createScaledBitmap(bitmap, sampleSize.width, sampleSize.height, true)
            } catch (e: Exception) {
                FileLogger.w(TAG, "截图去重采样缩放失败，使用原图采样: ${e.message}")
                bitmap
            }
        } else {
            bitmap
        }
        val sampleWidth = sampled.width
        val sampleHeight = sampled.height
        val pixels = IntArray(sampleWidth * sampleHeight)
        sampled.getPixels(pixels, 0, sampleWidth, 0, 0, sampleWidth, sampleHeight)
        return DedupePixelSample(
            width = sampleWidth,
            height = sampleHeight,
            pixels = pixels,
            sampledBitmap = if (sampled !== bitmap) sampled else null
        )
    }

    private fun recycleDedupeBitmaps(
        sample: DedupePixelSample?,
        roi: Bitmap,
        normalized: Bitmap,
        originalBitmap: Bitmap
    ) {
        val sampled = sample?.sampledBitmap
        try { sampled?.recycle() } catch (_: Exception) {}
        if (roi !== originalBitmap && roi !== sampled) {
            try { roi.recycle() } catch (_: Exception) {}
        }
        if (normalized !== originalBitmap && normalized !== roi && normalized !== sampled) {
            try { normalized.recycle() } catch (_: Exception) {}
        }
    }

    /**
     * 基于“自动裁剪系统栏”的近似去重：先比精确签名，再按感知哈希与缩略图差异判断。
     */
    private fun isDuplicateScreenshot(originalBitmap: Bitmap, packageName: String, traceId: Long): Boolean {
        val dedupeStartMs = SystemClock.elapsedRealtime()
        var sample: DedupePixelSample? = null
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
            // 退化策略：避免 ROI 过小导致签名不稳定
            roiY = (h * 0.05f).toInt().coerceIn(0, h - 1)
            roiH = (h * 0.90f).toInt().coerceAtLeast(16).coerceAtMost(h - roiY)
        }

        val roi = try { Bitmap.createBitmap(normalized, 0, roiY, w, roiH) } catch (_: Exception) { normalized }

        // 3) 读取模式并构建当前签名特征。非精确模式先采样，避免保存队列被全图哈希拖慢。
        val mode = readScreenshotDedupeMode()
        val currentFeatures = try {
            val sampleStartMs = SystemClock.elapsedRealtime()
            sample = sampleBitmapPixelsForDedupe(roi, mode)
            val sampleMs = SystemClock.elapsedRealtime() - sampleStartMs
            val s = sample ?: return false
            val featureStartMs = SystemClock.elapsedRealtime()
            val features = ScreenshotDedupeHelper.buildFeatures(s.width, s.height, s.pixels)
            perf(
                "trace=$traceId stage=dedupe_features result=ok source=${roi.width}x${roi.height} " +
                    "sample=${s.width}x${s.height} sampleMs=$sampleMs featureMs=${SystemClock.elapsedRealtime() - featureStartMs}"
            )
            features
        } catch (e: Exception) {
            FileLogger.w(TAG, "构建截图去重特征失败，降级为不重复: ${e.message}")
            recycleDedupeBitmaps(sample, roi, normalized, originalBitmap)
            return false
        }

        // 4) 读取上一张签名（内存优先，其次持久化）
        val previousSignature = lastSignatureByApp[packageName]
            ?: ScreenshotDatabaseHelper.getLastSignature(this, packageName)
        val compareResult = ScreenshotDedupeHelper.shouldSkip(previousSignature, currentFeatures, mode)
        if (compareResult.duplicate) {
            FileLogger.i(
                TAG,
                "截图去重命中: target=$packageName mode=${mode.rawValue} reason=${compareResult.reason} " +
                    "hashDistance=${compareResult.hashDistance} changedPixelRatio=${compareResult.changedPixelRatio} " +
                    "changedBlocks=${compareResult.changedBlocks} changedRows=${compareResult.changedRows} changedCols=${compareResult.changedCols}"
            )
            perf(
                "trace=$traceId stage=dedupe result=duplicate target=$packageName mode=${mode.rawValue} " +
                    "reason=${compareResult.reason} totalMs=${SystemClock.elapsedRealtime() - dedupeStartMs}"
            )
            recycleDedupeBitmaps(sample, roi, normalized, originalBitmap)
            return true
        }

        // 5) 更新签名
        val currentSignature = currentFeatures.toSignature()
        lastSignatureByApp[packageName] = currentSignature
        ScreenshotDatabaseHelper.setLastSignature(this, packageName, null, currentSignature)
        perf(
            "trace=$traceId stage=dedupe result=changed target=$packageName mode=${mode.rawValue} " +
                "reason=${compareResult.reason} totalMs=${SystemClock.elapsedRealtime() - dedupeStartMs}"
        )
        recycleDedupeBitmaps(sample, roi, normalized, originalBitmap)
        return false
    }

    /**
     * 将位图标准化为便于计算签名的方向与格式（复制为 ARGB_8888，依据设备旋转做最小必要旋转）。
     */
    private fun normalizeBitmapOrientationForHash(bitmap: Bitmap): Bitmap {
        val swBitmap = try {
            if (bitmap.config == Bitmap.Config.HARDWARE || bitmap.config == null) {
                FileLogger.d(TAG, "位图为硬件配置，拷贝为ARGB_8888用于签名计算")
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
            val rotated = Bitmap.createBitmap(swBitmap, 0, 0, w, h, m, true)
            if (rotated !== swBitmap && swBitmap !== bitmap) {
                try { swBitmap.recycle() } catch (_: Exception) {}
            }
            rotated
        } catch (_: Exception) {
            swBitmap
        }
    }

    internal fun getStatusBarHeight(): Int {
        return try {
            val resId = resources.getIdentifier("status_bar_height", "dimen", "android")
            if (resId > 0) resources.getDimensionPixelSize(resId) else 0
        } catch (_: Exception) { 0 }
    }

    internal fun getNavigationBarHeight(): Int {
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
        FileLogger.w(TAG, "开始屏幕捕获已废弃，现在直接使用无障碍截屏")
        return true
    }
    
    /**
     * 停止屏幕截图 (已废弃，仅为兼容保留)
     */
    @Deprecated("不再需要MediaProjection")
    fun stopScreenCapture() {
        FileLogger.w(TAG, "停止屏幕捕获已废弃")
    }
    
    /**
     * 启动定时截屏
     */
    fun startTimedScreenshot(intervalSeconds: Int): Boolean {
        FileLogger.e(TAG, "=== 无障碍服务开始定时截屏 ===")
        FileLogger.e(TAG, "请求间隔: ${formatIntervalSeconds(intervalSeconds)}秒")
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
            baseScreenshotInterval = normalizeScreenshotIntervalSeconds(intervalSeconds)
            screenshotInterval = baseScreenshotInterval
            isTimedScreenshotRunning = true
            pausedByScreenOff = false

            try {
                val fg = try {
                    getForegroundAppUsingUsageStats() ?: getCurrentForegroundApp()
                } catch (_: Exception) {
                    null
                }
                val cap = try {
                    fg != null && isAppInMonitorList(fg)
                } catch (_: Exception) {
                    false
                }
                ScreenCaptureService.updateNotificationState(
                    this,
                    foregroundPackage = if (cap) fg else null,
                    intervalSeconds = screenshotInterval,
                    captureEnabled = cap,
                    clearForegroundPackage = !cap
                )
            } catch (_: Exception) {}

            // 启动定时器（初始用全局间隔，后续按应用动态调整）
            screenshotTimer = timer(name = "ScreenshotTimer", daemon = true, period = screenshotIntervalMillis(screenshotInterval)) {
                if (isTimedScreenshotRunning) {
                    performTimedScreenshot()
                }
            }

            // 在定时截屏运行期间启动前台应用检测（事件优先+兜底轮询）
            startForegroundAppDetection()

            // 立即持久化运行状态，便于崩溃/被杀后自动恢复
            persistTimedScreenshotRunningState()

            FileLogger.e(TAG, "=== 定时截屏启动成功，间隔: ${formatIntervalSeconds(screenshotInterval)}秒 ===")
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
            try {
                ScreenCaptureService.updateNotificationState(
                    this,
                    captureEnabled = false
                )
            } catch (_: Exception) {}
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
            val interval = if (baseScreenshotInterval > 0) baseScreenshotInterval else screenshotInterval
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
        val traceId = nextCaptureTraceId()
        val tickStartMs = SystemClock.elapsedRealtime()
        try {
            // 息屏/锁屏或者显示不可见时跳过
            if (shouldPauseForScreenState()) {
                perf(
                    "trace=$traceId stage=tick result=skip reason=screen_state " +
                        "elapsedMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                )
                try {
                    ScreenCaptureService.updateNotificationState(
                        this,
                        captureEnabled = false
                    )
                } catch (_: Exception) {}
                return
            }
            // 确定要截图的应用
            val targetResolveStartMs = SystemClock.elapsedRealtime()
            val targetApp = getScreenshotTargetApp()
            val targetResolveMs = SystemClock.elapsedRealtime() - targetResolveStartMs
            if (targetApp == null) {
                perf(
                    "trace=$traceId stage=tick result=skip reason=no_target " +
                        "targetResolveMs=$targetResolveMs elapsedMs=${SystemClock.elapsedRealtime() - tickStartMs}"
                )
                FileLogger.d(TAG, "没有需要截图的目标应用，跳过截屏")
                maybeLogNoTargetSnapshot()
                try {
                    ScreenCaptureService.updateNotificationState(
                        this,
                        captureEnabled = false
                    )
                } catch (_: Exception) {}
                return
            }

            // 动态应用每应用自定义间隔：若与当前不同则重建计时器
            var intervalReadMs = 0L
            var timerReset = false
            var intervalSource = "global"
            var customIntervalText = "-"
            var baseIntervalText = formatIntervalSeconds(baseScreenshotInterval)
            try {
                val intervalResult = applyEffectiveScreenshotInterval(targetApp)
                intervalReadMs = intervalResult.effective.readMs
                timerReset = intervalResult.timerReset
                intervalSource = intervalResult.effective.source
                customIntervalText = intervalResult.effective.customSeconds?.let { formatIntervalSeconds(it) } ?: "-"
                baseIntervalText = formatIntervalSeconds(baseScreenshotInterval)
            } catch (e: Exception) {
                FileLogger.w(TAG, "读取每应用间隔失败: ${e.message}")
            }

            perf(
                "trace=$traceId stage=tick result=target target=$targetApp " +
                    "targetResolveMs=$targetResolveMs intervalReadMs=$intervalReadMs " +
                    "timerReset=$timerReset intervalSource=$intervalSource customInterval=$customIntervalText " +
                    "baseInterval=$baseIntervalText effectiveInterval=${formatIntervalSeconds(screenshotInterval)} " +
                    "intervalMs=${screenshotIntervalMillis(screenshotInterval)} " +
                    "elapsedMs=${SystemClock.elapsedRealtime() - tickStartMs}"
            )
            FileLogger.d(TAG, "开始截屏：$targetApp (会话应用: $currentSessionApp, 前台应用: $currentForegroundApp)")

            try {
                ScreenCaptureService.updateNotificationState(
                    this,
                    foregroundPackage = targetApp,
                    intervalSeconds = if (screenshotInterval > 0) screenshotInterval else null,
                    captureEnabled = true
                )
            } catch (_: Exception) {}

            // 使用无障碍服务截屏
            takeScreenshotUsingAccessibility(targetApp, traceId, tickStartMs) { success, filePath ->
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
            perf(
                "trace=$traceId stage=tick result=exception " +
                    "message=${e.message ?: "-"} elapsedMs=${SystemClock.elapsedRealtime() - tickStartMs}"
            )
            FileLogger.e(TAG, "执行定时截屏失败", e)
            RuntimeDiagnostics.noteCaptureFailure(
                this,
                TAG,
                "perform_timed_screenshot_exception",
                extras = mapOf("message" to (e.message ?: "-"))
            )
            maybeLogDetailedFailure(
                "perform_timed_screenshot_exception",
                mapOf("message" to (e.message ?: "-"))
            )
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
            pause
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查屏幕状态失败，出于保守策略将跳过截屏", e)
            true
        }
    }

    private fun maybeLogDetailedFailure(reason: String, extras: Map<String, Any?> = emptyMap()) {
        val now = System.currentTimeMillis()
        if (now - lastDetailedFailureSnapshotAt < 30_000L) {
            return
        }
        lastDetailedFailureSnapshotAt = now
        RuntimeDiagnostics.logSnapshot(
            this,
            TAG,
            "accessibility_failure_detail",
            extras = linkedMapOf<String, Any?>(
                "reason" to reason,
                "timedRunning" to isTimedScreenshotRunning,
                "pausedByScreenOff" to pausedByScreenOff,
                "currentForegroundApp" to (currentForegroundApp ?: "-"),
                "stableApp" to (lastStableMonitoredApp ?: "-"),
                "sessionApp" to (currentSessionApp ?: "-"),
                "sinceLastAccessibilityEventMs" to (System.currentTimeMillis() - lastAnyAccessibilityEventAt),
                "sinceLastWindowAccessibilityEventMs" to (System.currentTimeMillis() - lastAccessibilityWindowEventAt),
                "onePlus" to OEMCompatibilityHelper.isOnePlusDevice(),
            ).apply { putAll(extras) },
            force = true,
        )
    }

    private fun maybeLogNoTargetSnapshot() {
        val now = System.currentTimeMillis()
        if (now - lastNoTargetSnapshotAt < 30_000L) {
            return
        }
        lastNoTargetSnapshotAt = now
        RuntimeDiagnostics.logSnapshot(
            this,
            TAG,
            "no_target_app",
            extras = mapOf(
                "timedRunning" to isTimedScreenshotRunning,
                "pausedByScreenOff" to pausedByScreenOff,
                "currentForegroundApp" to (currentForegroundApp ?: "-"),
                "stableApp" to (lastStableMonitoredApp ?: "-"),
                "sessionApp" to (currentSessionApp ?: "-"),
                "sinceLastAccessibilityEventMs" to (System.currentTimeMillis() - lastAnyAccessibilityEventAt),
                "sinceLastWindowAccessibilityEventMs" to (System.currentTimeMillis() - lastAccessibilityWindowEventAt),
                "onePlus" to OEMCompatibilityHelper.isOnePlusDevice(),
            ),
            force = OEMCompatibilityHelper.isOnePlusDevice(),
        )
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

        // 当前可见顶层应用（尽量用UsageStats，其次窗口列表）
        // 偶尔刷新IME集合
        refreshImePackages(force = false)
        val visibleTop = getForegroundAppUsingUsageStats() ?: getCurrentForegroundApp()

        // 稳定前台（仅在监控列表中才有效）
        var stable = lastStableMonitoredApp
        if (stable == null || !isAppInMonitorList(stable)) {
            if (visibleTop != null && isAppInMonitorList(visibleTop)) {
                FileLogger.i(TAG, "无稳定前台但顶层为监控应用($visibleTop)，建立稳定目标")
                lastStableMonitoredApp = visibleTop
                lastStableSeenAt = now
                currentForegroundApp = visibleTop
                stable = visibleTop
            } else {
                FileLogger.d(TAG, "无有效稳定前台或不在监控列表，暂停截屏")
                return null
            }
        }

        if (visibleTop == packageName) {
            if (!isSelfForeground) {
                FileLogger.d(TAG, "顶层为本应用(${visibleTop})，暂停截屏，等待新会话")
            } else {
                FileLogger.d(TAG, "顶层仍为本应用，保持暂停截屏")
            }
            isSelfForeground = true
            return null
        }

        if (visibleTop != null && isSelfForeground) {
            FileLogger.d(TAG, "检测到非本应用顶层(${visibleTop})，恢复截屏候选")
            isSelfForeground = false
        }

        if (visibleTop == null && isSelfForeground) {
            FileLogger.d(TAG, "顶层未知但记录本应用在前，暂停截屏")
            return null
        }

        // 系统遮罩/系统UI：继续把截图归属到稳定前台
        if (visibleTop != null && (transientOverlayPackages.contains(visibleTop) || isMiuiSystemApp(visibleTop) || isImePackage(visibleTop) || isAutomationSkipPackage(visibleTop))) {
            FileLogger.d(TAG, "顶层为系统遮罩/系统UI($visibleTop)，继续使用稳定前台: $stable")
            return stable
        }

        // 桌面/Launcher：增加窗口验证避免误判
        if (visibleTop != null && isLauncherPackage(visibleTop)) {
            if (!isLauncherCurrentlyForeground(visibleTop)) {
                FileLogger.d(TAG, "顶层候选桌面($visibleTop)但窗口仍为监控应用，继续归属: $stable")
                return stable
            }
            FileLogger.i(TAG, "顶层为桌面/Launcher($visibleTop)，清空稳定监控并暂停截屏")
            lastStableMonitoredApp = null
            lastStableSeenAt = 0L
            return null
        }

        // 非监控应用：仅在离开稳定前台后的宽限期内继续归属，否则暂停
        if (visibleTop != null && !isAppInMonitorList(visibleTop)) {
            val since = now - lastStableSeenAt
            return if (since <= OVERLAY_GRACE_MS) {
                FileLogger.d(TAG, "顶层非监控应用($visibleTop)，仍在宽限期${since}ms<=${OVERLAY_GRACE_MS}ms，继续归属: $stable")
                stable
            } else {
                FileLogger.d(TAG, "顶层非监控应用($visibleTop)，超过宽限期${since}ms>${OVERLAY_GRACE_MS}ms，暂停截屏")
                null
            }
        }

        // 顶层为监控应用时，以当前可见顶层为准；若 stable 仍是旧应用，立即修正，避免错归属。
        if (visibleTop != null && isAppInMonitorList(visibleTop)) {
            if (visibleTop != stable) {
                FileLogger.i(TAG, "顶层监控应用($visibleTop)与稳定前台($stable)不一致，修正稳定目标")
                lastStableMonitoredApp = visibleTop
                lastStableSeenAt = now
                currentForegroundApp = visibleTop
                try {
                    ScreenCaptureService.updateNotificationState(
                        this,
                        foregroundPackage = visibleTop,
                        intervalSeconds = applyIntervalForForegroundNotification(visibleTop),
                        captureEnabled = isTimedScreenshotRunning
                    )
                } catch (_: Exception) {}
            } else {
                lastStableSeenAt = now
            }
            FileLogger.d(TAG, "顶层为监控应用($visibleTop)，归属当前顶层")
            return visibleTop
        }

        FileLogger.d(TAG, "顶层未知，归属稳定前台: $stable")
        return stable
    }

    /**
     * 截图 API 返回后、保存前做一次轻量校验，避免用户已切回屏忆/桌面/其他 App 时错入库。
     */
    private fun validateCaptureStillBelongsToTarget(targetPackage: String): CaptureValidationResult {
        if (targetPackage.isBlank() || targetPackage == "unknown") {
            return CaptureValidationResult(false, "discard_invalid_target")
        }
        return try {
            refreshImePackages(force = false)
            val visibleTop = getForegroundAppUsingUsageStats() ?: getCurrentForegroundApp()
            when {
                visibleTop == null -> CaptureValidationResult(true, "allow_visible_unknown", visibleTop)

                visibleTop == packageName -> {
                    isSelfForeground = true
                    CaptureValidationResult(false, "discard_self_foreground", visibleTop)
                }

                transientOverlayPackages.contains(visibleTop) ||
                    isMiuiSystemApp(visibleTop) ||
                    isImePackage(visibleTop) ||
                    isAutomationSkipPackage(visibleTop) -> {
                    CaptureValidationResult(true, "allow_transient_overlay", visibleTop)
                }

                isLauncherPackage(visibleTop) -> {
                    if (!isLauncherCurrentlyForeground(visibleTop)) {
                        CaptureValidationResult(true, "allow_launcher_false_positive", visibleTop)
                    } else {
                        lastStableMonitoredApp = null
                        lastStableSeenAt = 0L
                        currentForegroundApp = null
                        CaptureValidationResult(false, "discard_launcher_foreground", visibleTop)
                    }
                }

                !isAppInMonitorList(visibleTop) -> {
                    CaptureValidationResult(false, "discard_non_monitor_foreground", visibleTop)
                }

                visibleTop != targetPackage -> {
                    lastStableMonitoredApp = visibleTop
                    lastStableSeenAt = System.currentTimeMillis()
                    currentForegroundApp = visibleTop
                    CaptureValidationResult(false, "discard_target_changed", visibleTop)
                }

                else -> {
                    lastStableSeenAt = System.currentTimeMillis()
                    CaptureValidationResult(true, "allow_target_visible", visibleTop)
                }
            }
        } catch (e: Exception) {
            FileLogger.w(TAG, "截图归属校验失败，保守允许保存: ${e.message}")
            CaptureValidationResult(true, "allow_validation_exception")
        }
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

        val traceId = nextCaptureTraceId()
        val tickStartMs = SystemClock.elapsedRealtime()
        var result: String? = null
        val lock = Object()
        
        takeScreenshotUsingAccessibility(null, traceId, tickStartMs) { success, filePath ->
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
    private fun saveScreenshotBitmap(
        bitmap: Bitmap,
        packageName: String,
        traceId: Long = nextCaptureTraceId(),
        captureStartMs: Long = SystemClock.elapsedRealtime(),
        captureTimeMillis: Long = System.currentTimeMillis()
    ): String? {
        val saveTotalStartMs = SystemClock.elapsedRealtime()
        var rotateMs = 0L
        var encodeMs = 0L
        var writeMs = 0L
        var nativeDbMs = 0L
        var segmentMs = 0L
        var flutterNotifyMs = 0L
        var urlMs = 0L
        var ocrLaunchMs = 0L
        var appNameMs = 0L
        var mkdirMs = 0L
        var encodedBytes = 0
        var outputBytes = 0L
        var saveBitmapForCleanup: Bitmap? = null
        var saveBitmapHandedToOcr = false
        return try {
            val appNameStartMs = SystemClock.elapsedRealtime()
            val appName = getAppName(packageName) ?: packageName
            appNameMs = SystemClock.elapsedRealtime() - appNameStartMs

            // 新的目录结构：应用+时间 (output/screen/包名/年月/日期/)
            val now = Date(captureTimeMillis)
            val yearMonth = SimpleDateFormat("yyyy-MM", Locale.getDefault()).format(now)
            val day = SimpleDateFormat("dd", Locale.getDefault()).format(now)
            val relativeDir = "output/screen/$packageName/$yearMonth/$day"
            val timestamp = SimpleDateFormat("HHmmss_SSS", Locale.getDefault()).format(now)
            // 最终文件名后缀依据实际编码格式决定
            val baseName = timestamp
            
            // 使用应用内部私有存储目录
            val baseDir = this.filesDir

            // 创建完整的输出目录
            val outputDir = File(baseDir, relativeDir)
            val mkdirStartMs = SystemClock.elapsedRealtime()
            if (!outputDir.exists()) {
                outputDir.mkdirs()
            }
            mkdirMs = SystemClock.elapsedRealtime() - mkdirStartMs

            // 先完成旋转与可编辑位图
            var finalExt = "jpg" // 临时占位，稍后依据编码结果修正
            var file = File(outputDir, baseName + "." + finalExt)

            // 纯图像维度与方向判定，避免依赖窗口API带来的不稳定
            val rotateStartMs = SystemClock.elapsedRealtime()
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
            rotateMs = SystemClock.elapsedRealtime() - rotateStartMs

            // 应用压缩设置（不改变分辨率，仅通过编码质量/格式控制大小；可选灰度）
            val encodeStartMs = SystemClock.elapsedRealtime()
            val bitmapForSave = rotatedOrOriginal ?: bitmap
            if (bitmapForSave !== bitmap) {
                saveBitmapForCleanup = bitmapForSave
            }
            val encodeResult = encodeToBytesAccordingToSettings(
                bitmapForSave,
                packageName,
                traceId,
            )
            encodeMs = SystemClock.elapsedRealtime() - encodeStartMs
            val bytes = encodeResult.bytes
            finalExt = encodeResult.ext
            if (bytes == null) {
                FileLogger.e(TAG, "编码失败：返回空字节流")
                return null
            }
            encodedBytes = bytes.size
            // 用实际后缀重建文件并写入
            file = File(outputDir, baseName + "." + finalExt)
            try {
                val writeStartMs = SystemClock.elapsedRealtime()
                FileOutputStream(file).use { it.write(bytes) }
                writeMs = SystemClock.elapsedRealtime() - writeStartMs
                outputBytes = try { file.length() } catch (_: Exception) { bytes.size.toLong() }
            } catch (e: Exception) {
                FileLogger.e(TAG, "写入文件失败", e)
                return null
            }

            // 关键修改：只返回相对路径给Flutter端
            val relativePath = File(relativeDir, baseName + "." + finalExt).path 
            FileLogger.i(TAG, "截图已保存，绝对路径: ${file.absolutePath}")
            FileLogger.i(TAG, "返回给Flutter的相对路径: $relativePath")

            // 仅当应用识别为浏览器（名称优先，系统包兜底）时，才尝试提取并复用 URL
            val urlStartMs = SystemClock.elapsedRealtime()
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
            urlMs = SystemClock.elapsedRealtime() - urlStartMs

            // 先在原生侧实时入库（Flutter未就绪时也能写入）
            try {
                val nativeDbStartMs = SystemClock.elapsedRealtime()
                ScreenshotDatabaseHelper.insertIfNotExists(
                    this@ScreenCaptureAccessibilityService,
                    packageName,
                    appName,
                    file.absolutePath,
                    captureTimeMillis,
                    pageUrl
                )
                nativeDbMs = SystemClock.elapsedRealtime() - nativeDbStartMs
            } catch (e: Exception) {
                FileLogger.w(TAG, "原生侧入库失败: ${e.message}")
            }

            encodeResult.deferredTarget?.let { spec ->
                enqueueDeferredTargetCompression(
                    file = file,
                    relativePath = relativePath,
                    packageName = packageName,
                    spec = spec,
                    traceId = traceId,
                    initialBytes = outputBytes
                )
            }

            // 通知段落管理器（用于段落开始与采样调度）
            try {
                val segmentStartMs = SystemClock.elapsedRealtime()
                SegmentSummaryManager.onScreenshotSaved(
                    this@ScreenCaptureAccessibilityService,
                    packageName,
                    appName,
                    file.absolutePath,
                    captureTimeMillis
                )
                segmentMs = SystemClock.elapsedRealtime() - segmentStartMs
            } catch (e: Exception) {
                FileLogger.w(TAG, "SegmentSummaryManager 调用失败: ${e.message}")
            }

            // 在“原图（未压缩）”上执行 OCR，并将结果异步写回数据库。
            // 注意：截图保存 worker 结束时会释放 takeScreenshot 返回的原始 bitmap，
            // 如果 OCR 需要沿用该对象，必须先复制一份，避免异步线程读到已释放位图。
            try {
                val ocrLaunchStartMs = SystemClock.elapsedRealtime()
                val ocrSource = bitmapForSave
                val needsOcrCopy = ocrSource === bitmap
                val forOcr = if (needsOcrCopy) {
                    try {
                        ocrSource.copy(Bitmap.Config.ARGB_8888, false)
                    } catch (e: Exception) {
                        FileLogger.w(TAG, "OCR位图复制失败，跳过本次OCR以避免异步读取已释放位图: ${e.message}")
                        null
                    }
                } else {
                    ocrSource
                }
                if (forOcr != null) {
                    val recycleOcrSourceWhenDone = forOcr !== bitmap
                    if (forOcr === saveBitmapForCleanup) {
                        saveBitmapHandedToOcr = true
                    }
                    runOcrAsyncAndPersist(
                        forOcr,
                        file.absolutePath,
                        recycleSourceWhenDone = recycleOcrSourceWhenDone,
                        traceId = traceId
                    )
                }
                ocrLaunchMs = SystemClock.elapsedRealtime() - ocrLaunchStartMs
            } catch (e: Exception) {
                FileLogger.w(TAG, "启动OCR失败: ${e.message}")
            }

            // 通知Flutter端更新数据库（作为第二路径，方便UI即刻刷新）
            try {
                val flutterNotifyStartMs = SystemClock.elapsedRealtime()
                notifyScreenshotSaved(
                    packageName,
                    appName,
                    relativePath,
                    pageUrl,
                    traceId,
                    captureTimeMillis
                )
                flutterNotifyMs = SystemClock.elapsedRealtime() - flutterNotifyStartMs
            } catch (e: Exception) {
                FileLogger.w(TAG, "通知Flutter更新数据库失败: ${e.message}")
            }

            FileLogger.i(
                TAG,
                "截图保存耗时: app=$packageName rotateMs=$rotateMs encodeMs=$encodeMs writeMs=$writeMs nativeDbMs=$nativeDbMs segmentMs=$segmentMs flutterNotifyMs=$flutterNotifyMs saveTotalMs=${SystemClock.elapsedRealtime() - saveTotalStartMs}"
            )
            perf(
                "trace=$traceId stage=save_breakdown result=saved app=$packageName " +
                    "appNameMs=$appNameMs mkdirMs=$mkdirMs rotateMs=$rotateMs encodeMs=$encodeMs " +
                    "writeMs=$writeMs urlMs=$urlMs nativeDbMs=$nativeDbMs segmentMs=$segmentMs " +
                    "ocrLaunchMs=$ocrLaunchMs flutterNotifyMs=$flutterNotifyMs saveTotalMs=${SystemClock.elapsedRealtime() - saveTotalStartMs} " +
                    "totalMs=${SystemClock.elapsedRealtime() - captureStartMs} bytes=$encodedBytes fileBytes=$outputBytes " +
                    "deferredTarget=${encodeResult.deferredTarget != null} ext=$finalExt path=$relativePath"
            )
            
            relativePath // 返回相对路径
        } catch (e: Exception) {
            perf(
                "trace=$traceId stage=save_breakdown result=exception app=$packageName " +
                    "message=${e.message ?: "-"} saveTotalMs=${SystemClock.elapsedRealtime() - saveTotalStartMs} " +
                    "totalMs=${SystemClock.elapsedRealtime() - captureStartMs}"
            )
            FileLogger.e(TAG, "保存截图失败", e)
            null
        } finally {
            if (!saveBitmapHandedToOcr) {
                try { saveBitmapForCleanup?.recycle() } catch (_: Exception) {}
            }
        }
    }

    /**
     * 使用 ML Kit 中文文本识别在原始位图上执行 OCR，并将结果写入对应记录（按文件路径更新）。
     * 离线：模型将随依赖一起打包入 APK；无网络也可识别。
     */

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
    private fun notifyScreenshotSaved(
        packageName: String,
        appName: String,
        filePath: String,
        pageUrl: String?,
        traceId: Long = nextCaptureTraceId(),
        captureTimeMillis: Long = System.currentTimeMillis()
    ) {
        try {
            val startMs = SystemClock.elapsedRealtime()
            // 发送广播通知MainActivity
            val intent = Intent("com.fqyw.screen_memo.SCREENSHOT_SAVED").apply {
                setPackage(this@ScreenCaptureAccessibilityService.packageName)
                putExtra("packageName", packageName)
                putExtra("appName", appName)
                putExtra("filePath", filePath)
                putExtra("captureTime", captureTimeMillis)
                if (!pageUrl.isNullOrBlank()) putExtra("pageUrl", pageUrl)
            }
            sendBroadcast(intent)
            perf(
                "trace=$traceId stage=flutter_broadcast result=sent app=$packageName " +
                    "sendMs=${SystemClock.elapsedRealtime() - startMs} path=$filePath"
            )
            FileLogger.d(TAG, "已发送截图保存通知广播")
        } catch (e: Exception) {
            perf(
                "trace=$traceId stage=flutter_broadcast result=exception app=$packageName " +
                    "message=${e.message ?: "-"} path=$filePath"
            )
            FileLogger.e(TAG, "发送截图保存通知失败", e)
        }
    }

    internal fun notifyScreenshotFileRecompressed(
        packageName: String,
        relativePath: String,
        absolutePath: String,
        newSize: Long,
        nativeDbUpdated: Boolean,
        traceId: Long = nextCaptureTraceId()
    ) {
        try {
            val startMs = SystemClock.elapsedRealtime()
            val intent = Intent("com.fqyw.screen_memo.SCREENSHOT_RECOMPRESSED").apply {
                setPackage(this@ScreenCaptureAccessibilityService.packageName)
                putExtra("packageName", packageName)
                putExtra("filePath", relativePath)
                putExtra("absolutePath", absolutePath)
                putExtra("newSize", newSize)
                putExtra("nativeDbUpdated", nativeDbUpdated)
            }
            sendBroadcast(intent)
            perf(
                "trace=$traceId stage=deferred_compress_broadcast result=sent app=$packageName " +
                    "sendMs=${SystemClock.elapsedRealtime() - startMs} newSize=$newSize path=$relativePath"
            )
        } catch (e: Exception) {
            perf(
                "trace=$traceId stage=deferred_compress_broadcast result=exception app=$packageName " +
                    "message=${e.message ?: "-"} path=$relativePath"
            )
            FileLogger.w(TAG, "发送延后压缩完成通知失败: ${e.message}")
        }
    }

    /**
     * 检查应用是否在监控列表中
     */
    private fun registerPackageInstallReceiver() {
        if (packageInstallReceiver != null) return

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != Intent.ACTION_PACKAGE_ADDED) return
                if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return

                val installedPackage = intent.data?.schemeSpecificPart?.trim().orEmpty()
                if (installedPackage.isEmpty()) return

                handler.post {
                    maybeAutoAddNewInstalledApp(installedPackage)
                }
            }
        }

        val filter = IntentFilter(Intent.ACTION_PACKAGE_ADDED).apply {
            addDataScheme("package")
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(receiver, filter)
            }
            packageInstallReceiver = receiver
            FileLogger.i(TAG, "新安装应用监听已注册")
        } catch (e: Exception) {
            FileLogger.w(TAG, "注册新安装应用监听失败: ${e.message}")
        }
    }

    private fun unregisterPackageInstallReceiver() {
        val receiver = packageInstallReceiver ?: return
        try {
            unregisterReceiver(receiver)
        } catch (_: Exception) {
        } finally {
            packageInstallReceiver = null
        }
    }

    private fun maybeAutoAddNewInstalledApp(packageName: String) {
        try {
            val enabled = UserSettingsStorage.getBoolean(
                this,
                UserSettingsKeysNative.AUTO_ADD_NEW_APPS_TO_CAPTURE,
                false
            )
            if (!enabled) {
                FileLogger.d(TAG, "新安装应用自动加入已关闭，忽略: $packageName")
                return
            }

            val appInfo = resolveSelectableInstalledApp(packageName) ?: return
            val added = appendAppToSelectedApps(appInfo)
            if (added) {
                FileLogger.i(TAG, "新安装应用已自动加入截屏列表: ${appInfo.appName}(${appInfo.packageName})")
            }
        } catch (e: Exception) {
            FileLogger.w(TAG, "处理新安装应用失败: $packageName, ${e.message}")
        }
    }

    private data class AutoSelectedAppInfo(
        val packageName: String,
        val appName: String,
        val version: String,
        val isSystemApp: Boolean
    )

    private fun resolveSelectableInstalledApp(packageName: String): AutoSelectedAppInfo? {
        if (packageName.isBlank() || packageName == this.packageName) return null
        if (!staticLauncherPackages.contains(packageName) && !resolvedLauncherPackages.contains(packageName)) {
            refreshResolvedLauncherPackages()
        }
        if (isImePackage(packageName) || isLauncherPackage(packageName) || isAutomationSkipPackage(packageName)) {
            FileLogger.d(TAG, "新安装应用不适合自动加入截屏列表，已跳过: $packageName")
            return null
        }

        return try {
            val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
            val isSystemApp =
                (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0 ||
                    (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            if (isSystemApp) {
                FileLogger.d(TAG, "新安装系统应用已跳过: $packageName")
                return null
            }

            val appName = packageManager.getApplicationLabel(applicationInfo)?.toString()
                ?.takeIf { it.isNotBlank() }
                ?: packageName
            val version = try {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0).versionName ?: ""
            } catch (_: Exception) {
                ""
            }
            AutoSelectedAppInfo(
                packageName = packageName,
                appName = appName,
                version = version,
                isSystemApp = false
            )
        } catch (e: Exception) {
            FileLogger.w(TAG, "解析新安装应用失败: $packageName - ${e.message}")
            null
        }
    }

    private fun appendAppToSelectedApps(appInfo: AutoSelectedAppInfo): Boolean {
        synchronized(selectedAppsPrefsLock) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val selectedKey = "flutter.selected_apps"
            val raw = prefs.getString(selectedKey, null)
            val selectedArray = try {
                if (raw.isNullOrBlank()) JSONArray() else JSONArray(raw)
            } catch (e: Exception) {
                FileLogger.w(TAG, "选中应用列表 JSON 解析失败，跳过自动加入: ${e.message}")
                return false
            }

            if (jsonArrayContainsPackage(selectedArray, appInfo.packageName)) {
                FileLogger.d(TAG, "新安装应用已在截屏列表中: ${appInfo.packageName}")
                return false
            }

            val appJson = buildSelectedAppJson(appInfo)
            selectedArray.put(appJson)

            val editor = prefs.edit()
                .putString(selectedKey, selectedArray.toString())
                .remove("flutter.all_apps_cache")
                .remove("flutter.all_apps_cache_ts")

            appendAppIdentityCache(editor, prefs, appJson, appInfo.packageName)
            editor.apply()
            return true
        }
    }

    private fun buildSelectedAppJson(appInfo: AutoSelectedAppInfo): JSONObject {
        return JSONObject().apply {
            put("packageName", appInfo.packageName)
            put("appName", appInfo.appName)
            put("version", appInfo.version)
            put("isSystemApp", appInfo.isSystemApp)
            put("isInstalled", true)
            put("isSelected", true)
            put("icon", JSONObject.NULL)
        }
    }

    private fun appendAppIdentityCache(
        editor: android.content.SharedPreferences.Editor,
        prefs: android.content.SharedPreferences,
        appJson: JSONObject,
        packageName: String
    ) {
        val identityKey = "flutter.app_identity_cache"
        val raw = prefs.getString(identityKey, null)
        val identityArray = try {
            if (raw.isNullOrBlank()) JSONArray() else JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
        if (!jsonArrayContainsPackage(identityArray, packageName)) {
            identityArray.put(JSONObject(appJson.toString()))
            editor.putString(identityKey, identityArray.toString())
        }
    }

    private fun jsonArrayContainsPackage(array: JSONArray, packageName: String): Boolean {
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (obj.optString("packageName") == packageName) {
                return true
            }
        }
        return false
    }

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
            FileLogger.d(TAG, "服务状态已保存: $isRunning")
        } catch (e: Exception) {
            FileLogger.e(TAG, "保存服务状态失败: $e")
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
            FileLogger.e(TAG, "获取服务状态失败: $e")
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
     * 无障碍服务作为系统绑定锚点存在时，同步恢复用户已开启的 MCP 前台服务。
     */
    private fun restoreMcpServerIfEnabled(reason: String) {
        try {
            McpServerService.restoreIfEnabled(this)
            FileLogger.e(TAG, "MCP 服务恢复检查完成: $reason")
        } catch (e: Exception) {
            FileLogger.e(TAG, "MCP 服务恢复检查失败: $reason", e)
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

            FileLogger.e(TAG, "重启闹钟设置成功，将在5秒后触发")

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
                OEMCompatibilityHelper.isOnePlusDevice() -> {
                    FileLogger.w(TAG, "OnePlus设备检测：请重点检查自动启动、后台活动/电池不限制，以及最近任务锁定")
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
            val elapsedSinceWindowEvent = now - lastAccessibilityWindowEventAt
            // 事件优先但不被普通内容事件抑制：仅窗口事件后的极短窗口跳过一次轮询。
            // B站等应用会持续产生内容事件，如果用任意事件时间会导致兜底检测长期不运行。
            if (elapsedSinceWindowEvent in 0..750L) {
                return
            }
            var candidate = getForegroundAppUsingUsageStats()
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

            // 兜底：UsageStats 无结果时仍检查长窗口事件与窗口列表，即使已有旧 stable，
            // 避免从 QQ 切到 B站后 stable 长时间停留在旧应用。
            if (candidate == null) {
                // 1) 长窗口 UsageEvents（例如 15 秒）
                val longWindowPkg = getForegroundAppUsingUsageEventsLongWindow(15_000L)
                if (longWindowPkg != null) {
                    FileLogger.d(TAG, "UsageEvents(15s) 兜底命中前台: ${longWindowPkg}")
                    onForegroundCandidateDetected(longWindowPkg)
                } else {
                    // 2) Accessibility 窗口列表兜底
                    val fromWindows = getCurrentForegroundApp()
                    if (!fromWindows.isNullOrEmpty()) {
                        FileLogger.d(TAG, "窗口列表兜底命中前台: ${fromWindows}")
                        onForegroundCandidateDetected(fromWindows)
                    }
                }

                val stable2 = lastStableMonitoredApp
                if (stable2 != null && stable2 != prevStable) {
                    FileLogger.d(TAG, "兜底后稳定前台变化: $prevStable -> $stable2")
                    currentForegroundApp = stable2
                    updateAppSession(stable2)
                }
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
            var lastEventTimestamp = -1L
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
                        lastEventTimestamp = event.timeStamp
                    }
                }
            }

            val result = lastEvent?.packageName
            if (result != null) {
                val age = if (lastEventTimestamp > 0) currentTime - lastEventTimestamp else 0L
                if (lastEventTimestamp > 0 && age > FOREGROUND_EVENT_MAX_AGE_MS) {
                    FileLogger.d(TAG, "UsageStats忽略过期事件: $result, age=${age}ms (共${eventCount}个事件)")
                    return null
                }
                FileLogger.d(TAG, "UsageStats检测到前台应用: $result (共${eventCount}个事件)")
            }

            return result
        } catch (e: Exception) {
            FileLogger.e(TAG, "使用UsageStats获取前台应用失败", e)
            return null
        }
    }

    /**
     * 使用较长窗口的 UsageEvents 进行一次兜底前台判定（不作为主路径，以减少功耗）。
     * 选取最近的 "前台相关" 事件对应的包名。
     */
    private fun getForegroundAppUsingUsageEventsLongWindow(windowMs: Long = 15_000L): String? {
        return try {
            val usageStats = usageStatsManager ?: return null
            val now = System.currentTimeMillis()
            val from = (now - windowMs).coerceAtLeast(0)
            val events = usageStats.queryEvents(from, now)
            var lastPkg: String? = null
            var lastPkgTimestamp = 0L
            var total = 0
            var fgHits = 0
            val tmp = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(tmp)
                total++
                val t = tmp.eventType
                val isFg = (t == UsageEvents.Event.MOVE_TO_FOREGROUND
                        || t == UsageEvents.Event.ACTIVITY_RESUMED)
                if (isFg) {
                    fgHits++
                    // 排除本应用，避免把应用内前台当成候选
                    val pkg = tmp.packageName
                    if (pkg != null && pkg != packageName) {
                        lastPkg = pkg
                        lastPkgTimestamp = tmp.timeStamp
                    }
                }
            }
            if (lastPkg != null) {
                val age = now - lastPkgTimestamp
                if (lastPkgTimestamp > 0 && age > LONG_WINDOW_EVENT_MAX_AGE_MS) {
                    FileLogger.d(TAG, "UsageEvents 长窗口忽略过期事件: ${lastPkg}, age=${age}ms, total=${total}")
                    return null
                }
                FileLogger.d(TAG, "UsageEvents 长窗口: total=${total}, fgHits=${fgHits}, last=${lastPkg}")
            }
            lastPkg
        } catch (e: Exception) {
            FileLogger.e(TAG, "UsageEvents 长窗口兜底失败", e)
            null
        }
    }

}
