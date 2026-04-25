package com.fqyw.screen_memo

import android.app.Activity
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.database.ContentObserver
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.inputmethod.InputMethodInfo
import android.view.inputmethod.InputMethodManager
import android.os.Environment
import android.content.ContentValues
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngineCache
import android.view.View
import android.graphics.Color
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.core.view.WindowCompat
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ImageView
import android.widget.TextView
import android.view.Gravity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import android.util.TypedValue
import android.app.Dialog
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipOutputStream
import java.util.zip.ZipEntry
import java.util.zip.Deflater
import java.util.zip.ZipInputStream
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.ArrayList
import kotlin.math.max
import kotlin.math.min
import com.fqyw.screen_memo.OutputFileLogger
import com.fqyw.screen_memo.storage.StorageAnalyzer
import com.fqyw.screen_memo.replay.ReplayExportNotificationHelper
import com.fqyw.screen_memo.replay.ReplayVideoComposer

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.fqyw.screen_memo/accessibility"
        private const val REQUEST_MEDIA_PROJECTION = 1001
        private const val REQUEST_ACCESSIBILITY_SETTINGS = 1002
    }

    private lateinit var methodChannel: MethodChannel
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var accessibilityObserver: ContentObserver? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var accessibilityStateMonitor: AccessibilityStateMonitor? = null
    private var mediaProjectionRequestReceiver: BroadcastReceiver? = null
    private var screenshotSavedReceiver: BroadcastReceiver? = null
    private var accessibilityServiceBinder: IAccessibilityServiceAidl? = null
    private var didRunPostFirstFrameInit: Boolean = false
    private var activityCreateTs: Long = 0L
    private var splashDialog: Dialog? = null
    private val outputCacheDirTokens = setOf("cache", "tmp", "temp", ".thumbnails")
    private val replayExecutor = Executors.newSingleThreadExecutor()
    
    private val accessibilityServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            FileLogger.e(TAG, "AccessibilityService连接成功")
            accessibilityServiceBinder = IAccessibilityServiceAidl.Stub.asInterface(service)
        }
        
        override fun onServiceDisconnected(name: ComponentName?) {
            FileLogger.e(TAG, "AccessibilityService连接断开")
            accessibilityServiceBinder = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 仅做必要初始化，避免阻塞首帧
        FileLogger.d(TAG, "configureFlutterEngine：最小初始化开始")

        // 初始化媒体投影管理器
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // 创建方法通道
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hideStatusBar" -> {
                    hideStatusBar()
                    result.success(true)
                }
                "showStatusBar" -> {
                    showStatusBar()
                    result.success(true)
                }
                "checkAccessibilityPermission" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibilityPermission" -> {
                    requestAccessibilityPermission()
                    result.success(null)
                }
                "checkUsageStatsPermission" -> {
                    result.success(isUsageStatsPermissionGranted())
                }
                "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission()
                    result.success(null)
                }
                "isServiceRunning" -> {
                    // 使用增强的看门狗状态检测
                    val watchdogStatus = AccessibilityServiceWatchdog.checkServiceStatus(this)
                    val running = watchdogStatus.isReallyRunning
                    
                    FileLogger.i(TAG, AccessibilityServiceWatchdog.getStatusSummary(this))
                    
                    // 如果系统中已启用但实际不运行，记录详细信息并尝试触发连接
                    if (watchdogStatus.needsRestart) {
                        FileLogger.e(TAG, "检测到服务需要重启，状态详情：")
                        FileLogger.e(TAG, "- 系统启用: ${watchdogStatus.isSystemEnabled}")
                        FileLogger.e(TAG, "- 实例存在: ${watchdogStatus.isInstanceExists}")
                        FileLogger.e(TAG, "- 进程存活: ${watchdogStatus.isProcessAlive}")
                        FileLogger.e(TAG, "- 心跳有效: ${watchdogStatus.isHeartbeatValid}")
                        FileLogger.e(TAG, "- 功能正常: ${watchdogStatus.isFunctional}")
                        
                        triggerAccessibilityServiceConnection()
                    }
                    
                    result.success(running)
                }
                "nativeLog" -> {
                    try {
                        val level = call.argument<String>("level") ?: "info"
                        val tag = call.argument<String>("tag") ?: "Flutter"
                        val msg = call.argument<String>("message") ?: ""
                        // 统一通过 FileLogger 控制，是否落盘由 FileLogger 决定
                        when (level.lowercase()) {
                            "debug" -> FileLogger.d(tag, msg)
                            "warn" -> FileLogger.w(tag, msg)
                            "error" -> FileLogger.e(tag, msg)
                            else -> FileLogger.i(tag, msg)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("log_error", e.message, null)
                    }
                }
                "setFileLoggingEnabled" -> {
                    try {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        sp.edit().putBoolean("logging_enabled", enabled).apply()
                        FileLogger.enableFileLogging(enabled)
                        FileLogger.setLevel(if (enabled) 4 else 1)
                        try { OutputFileLogger.setEnabled(enabled) } catch (_: Exception) {}
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("log_toggle_error", e.message, null)
                    }
                }
                "setNativeLogLevel" -> {
                    try {
                        val level = call.argument<String>("level")?.lowercase() ?: "debug"
                        val lvl = when(level) {
                            "error" -> 1
                            "warn" -> 2
                            "info" -> 3
                            else -> 4
                        }
                        FileLogger.setLevel(lvl)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("log_level_error", e.message, null)
                    }
                }
                "setCategoryLoggingEnabled" -> {
                    try {
                        val category = call.argument<String>("category") ?: ""
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (category.isNotBlank()) {
                            FileLogger.setCategoryEnabled(this, category, enabled)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("log_category_error", e.message, null)
                    }
                }
                "getOutputLogsDirToday" -> {
                    val dir = OutputFileLogger.getTodayDir(this)
                    result.success(dir?.absolutePath)
                }
                "getPendingRuntimeDiagnostic" -> {
                    result.success(RuntimeDiagnostics.getPendingIssueSummary(this))
                }
                "markRuntimeDiagnosticHandled" -> {
                    val issueId = call.argument<String>("id")
                    RuntimeDiagnostics.markIssueHandled(this, issueId)
                    result.success(true)
                }
                "openDiagnosticFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "path is blank", null)
                    } else {
                        openDiagnosticFile(path, result)
                    }
                }
                "getSegmentsAIConfig" -> {
                    try {
                        val cfg = AISettingsNative.readConfig(this)
                        val map = mapOf(
                            "baseUrl" to (cfg.baseUrl ?: ""),
                            "model" to (cfg.model ?: ""),
                            "apiKey" to (cfg.apiKey ?: "")
                        )
                        result.success(map)
                    } catch (e: Exception) {
                        result.error("read_failed", e.message, null)
                    }
                }
                "setSegmentSettings" -> {
                    try {
                        val sample = (call.argument<Int>("sampleIntervalSec") ?: 20).coerceAtLeast(5)
                        val duration = (call.argument<Int>("segmentDurationSec") ?: 300).coerceAtLeast(60)
                        try { FileLogger.i(TAG, "设置段落参数(call)：sampleIntervalSec=${sample} segmentDurationSec=${duration}") } catch (_: Exception) {}
                        UserSettingsStorage.putInt(
                            this,
                            UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC,
                            sample
                        )
                        UserSettingsStorage.putInt(
                            this,
                            UserSettingsKeysNative.SEGMENT_DURATION_SEC,
                            duration
                        )
                        try {
                            val n = SegmentDatabaseHelper.updateCollectingSegmentsSampleInterval(this, sample)
                            val cur = try { SegmentDatabaseHelper.getCollectingSegment(this) } catch (_: Exception) { null }
                            val persistedSample = try {
                                UserSettingsStorage.getInt(this, UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC, 20)
                            } catch (_: Exception) { -1 }
                            val persistedDuration = try {
                                UserSettingsStorage.getInt(this, UserSettingsKeysNative.SEGMENT_DURATION_SEC, 300)
                            } catch (_: Exception) { -1 }
                            try {
                                FileLogger.i(
                                    TAG,
                                    "setSegmentSettings(persisted): sample=${persistedSample}, duration=${persistedDuration}, updatedCollecting=${n}, collectingId=${cur?.id}, collectingInterval=${cur?.sampleIntervalSec}"
                                )
                            } catch (_: Exception) {}
                        } catch (_: Exception) {}
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("invalid_args", e.message, null)
                    }
                }
                "getSegmentSettings" -> {
                    try {
                        val sample = UserSettingsStorage.getInt(
                            this,
                            UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC,
                            20
                        ).coerceAtLeast(5)
                        val duration = UserSettingsStorage.getInt(
                            this,
                            UserSettingsKeysNative.SEGMENT_DURATION_SEC,
                            300
                        ).coerceAtLeast(60)
                        try { FileLogger.i(TAG, "获取段落参数：sampleIntervalSec=${sample} segmentDurationSec=${duration}") } catch (_: Exception) {}
                        result.success(
                            mapOf(
                                "sampleIntervalSec" to sample,
                                "segmentDurationSec" to duration
                            )
                        )
                    } catch (e: Exception) {
                        result.error("read_failed", e.message, null)
                    }
                }
                "getDynamicAutoRepairEnabled" -> {
                    try {
                        val enabled = UserSettingsStorage.getBoolean(
                            this,
                            UserSettingsKeysNative.DYNAMIC_AUTO_REPAIR_ENABLED,
                            true
                        )
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.error("read_failed", e.message, null)
                    }
                }
                "setDynamicAutoRepairEnabled" -> {
                    try {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        UserSettingsStorage.putBoolean(
                            this,
                            UserSettingsKeysNative.DYNAMIC_AUTO_REPAIR_ENABLED,
                            enabled
                        )
                        try {
                            FileLogger.i(
                                TAG,
                                "设置动态自动补建开关：enabled=${enabled}"
                            )
                        } catch (_: Exception) {}
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.error("invalid_args", e.message, null)
                    }
                }
                "setDynamicMergeLimits" -> {
                    try {
                        val spanRaw = call.argument<Int>("maxSpanSec") ?: (3 * 3600)
                        val gapRaw = call.argument<Int>("maxGapSec") ?: 3600
                        val maxImagesRaw = call.argument<Int>("maxImages") ?: 200
                        val span = when {
                            spanRaw < 0 -> 0
                            spanRaw > 7 * 24 * 3600 -> 7 * 24 * 3600
                            else -> spanRaw
                        }
                        val gap = when {
                            gapRaw < 0 -> 0
                            gapRaw > 7 * 24 * 3600 -> 7 * 24 * 3600
                            else -> gapRaw
                        }
                        val maxImages = when {
                            maxImagesRaw < 0 -> 0
                            maxImagesRaw > 100000 -> 100000
                            else -> maxImagesRaw
                        }
                        UserSettingsStorage.putInt(
                            this,
                            UserSettingsKeysNative.MERGE_DYNAMIC_MAX_SPAN_SEC,
                            span
                        )
                        UserSettingsStorage.putInt(
                            this,
                            UserSettingsKeysNative.MERGE_DYNAMIC_MAX_GAP_SEC,
                            gap
                        )
                        UserSettingsStorage.putInt(
                            this,
                            UserSettingsKeysNative.MERGE_DYNAMIC_MAX_IMAGES,
                            maxImages
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("invalid_args", e.message, null)
                    }
                }
                "getDynamicMergeLimits" -> {
                    try {
                        val span = UserSettingsStorage.getInt(
                            this,
                            UserSettingsKeysNative.MERGE_DYNAMIC_MAX_SPAN_SEC,
                            3 * 3600
                        ).let { if (it < 0) 0 else it }
                        val gap = UserSettingsStorage.getInt(
                            this,
                            UserSettingsKeysNative.MERGE_DYNAMIC_MAX_GAP_SEC,
                            3600
                        ).let { if (it < 0) 0 else it }
                        val maxImages = UserSettingsStorage.getInt(
                            this,
                            UserSettingsKeysNative.MERGE_DYNAMIC_MAX_IMAGES,
                            200
                        ).let { if (it < 0) 0 else it }
                        result.success(
                            mapOf(
                                "maxSpanSec" to span,
                                "maxGapSec" to gap,
                                "maxImages" to maxImages
                            )
                        )
                    } catch (e: Exception) {
                        result.error("read_failed", e.message, null)
                    }
                }
                "setAiRequestIntervalSec" -> {
                    try {
                        val secRaw = call.argument<Int>("seconds") ?: 3
                        val sec = when {
                            secRaw < 1 -> 1
                            secRaw > 60 -> 60
                            else -> secRaw
                        }
                        UserSettingsStorage.putInt(
                            this,
                            UserSettingsKeysNative.AI_MIN_REQUEST_INTERVAL_SEC,
                            sec
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("invalid_args", e.message, null)
                    }
                }
                "getAiRequestIntervalSec" -> {
                    try {
                        val sec = UserSettingsStorage.getInt(
                            this,
                            UserSettingsKeysNative.AI_MIN_REQUEST_INTERVAL_SEC,
                            3
                        )
                        result.success(
                            when {
                                sec < 1 -> 1
                                sec > 60 -> 60
                                else -> sec
                            }
                        )
                    } catch (e: Exception) {
                        result.error("read_failed", e.message, null)
                    }
                }
                "startForegroundService" -> {
                    startForegroundService()
                    result.success(null)
                }
                "stopForegroundService" -> {
                    stopForegroundService()
                    result.success(null)
                }
                "startScreenCapture" -> {
                    FileLogger.e(TAG, "=== 收到开始屏幕捕获请求 ===")
                    val success = startScreenCapture()
                    FileLogger.e(TAG, "=== 开始屏幕捕获结果: $success ===")
                    result.success(success)
                }
                "stopScreenCapture" -> {
                    FileLogger.e(TAG, "=== 收到停止屏幕捕获请求 ===")
                    stopScreenCapture()
                    result.success(null)
                }
                "startTimedScreenshot" -> {
                    // 统一从 SharedPreferences 读取一次持久化间隔，避免调用方传参不同步
                    val intervalPersisted = try {
                        val stored = UserSettingsStorage.getInt(
                            this,
                            UserSettingsKeysNative.SCREENSHOT_INTERVAL,
                            5,
                            legacyPrefKeys = LegacySettingKeysNative.SCREENSHOT_INTERVAL
                        )
                        stored
                    } catch (_: Exception) { 5 }
                    val interval = call.argument<Int>("interval") ?: intervalPersisted
                    FileLogger.e(TAG, "=== 收到开始定时截屏请求，间隔: ${interval}秒 ===")
                    val success = startTimedScreenshot(interval)
                    FileLogger.e(TAG, "=== 定时截屏启动结果: $success ===")
                    result.success(success)
                }
                "stopTimedScreenshot" -> {
                    FileLogger.e(TAG, "=== 收到停止定时截屏请求 ===")
                    stopTimedScreenshot()
                    result.success(null)
                }
                "captureScreen" -> {
                    FileLogger.e(TAG, "=== 收到立即截屏请求 ===")
                    val filePath = captureScreen()
                    FileLogger.e(TAG, "=== 立即截屏结果: $filePath ===")
                    result.success(filePath)
                }
                "checkPermissionGuideNeeded" -> {
                    result.success(PermissionGuideHelper.shouldShowPermissionGuide(this))
                }
                "getPermissionGuideText" -> {
                    result.success(PermissionGuideHelper.getPermissionGuideText(this))
                }
                "openAppDetailsSettings" -> {
                    result.success(PermissionGuideHelper.openAppDetailsSettings(this))
                }
                "openBatteryOptimizationSettings" -> {
                    result.success(PermissionGuideHelper.openBatteryOptimizationSettings(this))
                }
                "openAutoStartSettings" -> {
                    result.success(PermissionGuideHelper.openAutoStartSettings(this))
                }
                "markPermissionConfigured" -> {
                    val permissionType = call.argument<String>("type") ?: "all"
                    PermissionGuideHelper.markPermissionConfigured(this, permissionType)
                    result.success(true)
                }
                "getPermissionStatus" -> {
                    result.success(PermissionGuideHelper.checkPermissionStatus(this))
                }
                "getPermissionReport" -> {
                    result.success(PermissionGuideHelper.generatePermissionReport(this))
                }
                "getDeviceInfo" -> {
                    result.success(OEMCompatibilityHelper.getDeviceInfo())
                }
                "switchLauncherAlias" -> {
                    try {
                        val lang = call.argument<String>("lang") ?: ""
                        val ok = switchLauncherAliasInternal(lang)
                        result.success(ok)
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "切换Launcher别名失败", e)
                        result.error("alias_switch_failed", e.message, null)
                    }
                }
                "getEnabledImeList" -> {
                    try {
                        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                        val pms = packageManager
                        val list = imm.enabledInputMethodList?.map { imi ->
                            val pkg = imi.packageName
                            val label = try { imi.loadLabel(pms)?.toString() ?: pkg } catch (_: Exception) { pkg }
                            mapOf(
                                "packageName" to pkg,
                                "appName" to label,
                            )
                        } ?: emptyList()
                        result.success(list)
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "获取启用的输入法列表失败", e)
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "getDefaultInputMethod" -> {
                    try {
                        val id = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
                        if (id.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            // id like: com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME
                            val pkg = id.substringBefore('/')
                            val pms = packageManager
                            val appName = try {
                                val ai = pms.getApplicationInfo(pkg, 0)
                                pms.getApplicationLabel(ai)?.toString() ?: pkg
                            } catch (_: Exception) { pkg }
                            result.success(mapOf(
                                "id" to id,
                                // UI 不展示包名，避免对用户造成困惑
                                "packageName" to "",
                                "appName" to appName,
                            ))
                        }
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "读取默认输入法失败", e)
                        result.success(null)
                    }
                }
                "exportFileToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val displayName = call.argument<String>("displayName")
                    val subDir = call.argument<String>("subDir")

                    if (sourcePath.isNullOrEmpty()) {
                        result.error("invalid_args", "sourcePath is required", null)
                        return@setMethodCallHandler
                    }

                    val src = File(sourcePath)
                    if (!src.exists()) {
                        result.error("source_not_found", "Source file not found", sourcePath)
                        return@setMethodCallHandler
                    }

                    val name = if (!displayName.isNullOrEmpty()) displayName else src.name
                    Thread {
                        try {
                            val exportResult = exportFileToDownloadsInternal(src, name, subDir)
                            runOnUiThread { result.success(exportResult) }
                        } catch (e: Exception) {
                            FileLogger.e(TAG, "导出文件到下载目录失败", e)
                            runOnUiThread { result.error("export_failed", e.message, null) }
                        }
                    }.start()
                }
                "deleteExportedArtifact" -> {
                    try {
                        val contentUri = call.argument<String>("contentUri")
                        val absolutePath = call.argument<String>("absolutePath")
                        result.success(deleteExportedArtifactInternal(contentUri, absolutePath))
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "删除导出文件失败", e)
                        result.error("delete_export_failed", e.message, null)
                    }
                }
                "exportOutputToDownloadsNative" -> {
                    // 极致速度：原生 Java ZipOutputStream(BEST_SPEED) 直接写入 Downloads（无中间临时文件）
                    val displayName = call.argument<String>("displayName") ?: "output_export.zip"
                    val subDir = call.argument<String>("subDir")
                    Thread {
                        try {
                            val map = exportOutputToDownloadsNativeInternal(displayName, subDir)
                            runOnUiThread { result.success(map) }
                        } catch (e: Exception) {
                            FileLogger.e(TAG, "原生导出压缩失败", e)
                            runOnUiThread { result.error("native_export_failed", e.message, null) }
                        }
                    }.start()
                }
                "importZipToOutput" -> {
                    val zipPath = call.argument<String>("zipPath")
                    val overwrite = call.argument<Boolean>("overwrite") ?: true
                    if (zipPath.isNullOrBlank()) {
                        result.error("import_arg", "zipPath is null or empty", null)
                    } else {
                        importZipToOutputAsync(zipPath, overwrite, result)
                    }
                }
                "importFromExtractedOutputDir" -> {
                    val srcDir = call.argument<String>("srcDir")
                    val overwrite = call.argument<Boolean>("overwrite") ?: true
                    if (srcDir.isNullOrBlank()) {
                        result.error("import_arg", "srcDir is null or empty", null)
                    } else {
                        importFromExtractedOutputDirAsync(srcDir, overwrite, result)
                    }
                }
                "insertScreenshotRecord" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: ""
                    val filePath = call.argument<String>("filePath") ?: ""
                    val captureTime = call.argument<Long>("captureTime") ?: System.currentTimeMillis()
                    val pageUrl = call.argument<String>("pageUrl")
                    
                    FileLogger.i(TAG, "收到截图记录插入请求: $appName - $filePath")
                    
                    // 通知Flutter端插入数据库记录
                    methodChannel.invokeMethod("onScreenshotSaved", mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "filePath" to filePath,
                        "captureTime" to captureTime,
                        "pageUrl" to pageUrl
                    ))
                    
                    result.success(true)
                }
                "testAutoStartPermission" -> {
                    result.success(testAutoStartPermission())
                }
                "getExternalFilesDir" -> {
                    val subDir = call.argument<String>("subDir")
                    val path = getExternalFilesDirPath(subDir)
                    result.success(path)
                }
                "getInternalFilesDir" -> {
                    val subDir = call.argument<String>("subDir")
                    val path = getInternalFilesDirPath(subDir)
                    result.success(path)
                }
                "composeReplayVideo" -> {
                    val framesJsonlPath = call.argument<String>("framesJsonlPath") ?: ""
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    val fps = call.argument<Int>("fps") ?: 24
                    val shortSide = call.argument<Int>("shortSide") ?: 720
                    val quality = call.argument<String>("quality") ?: "medium"
                    val overlayEnabled = call.argument<Boolean>("overlayEnabled") ?: true
                    val appProgressBarEnabled = call.argument<Boolean>("appProgressBarEnabled") ?: false
                    val appProgressBarPosition = call.argument<String>("appProgressBarPosition") ?: "right"
                    val nsfwMode = call.argument<String>("nsfwMode") ?: "mask"
                    val nsfwTitle = call.argument<String>("nsfwTitle")
                    val nsfwSubtitle = call.argument<String>("nsfwSubtitle")

                    if (framesJsonlPath.isBlank() || outputPath.isBlank()) {
                        result.error("invalid_args", "framesJsonlPath/outputPath are required", null)
                        return@setMethodCallHandler
                    }

                    val pendingResult = result
                    ReplayExportNotificationHelper.showPreparing(applicationContext)
                    replayExecutor.execute {
                        try {
                            val map = ReplayVideoComposer.compose(
                                context = applicationContext,
                                framesJsonlPath = framesJsonlPath,
                                outputPath = outputPath,
                                fps = fps,
                                shortSide = shortSide,
                                quality = quality,
                                overlayEnabled = overlayEnabled,
                                appProgressBarEnabled = appProgressBarEnabled,
                                appProgressBarPosition = appProgressBarPosition,
                                nsfwMode = nsfwMode,
                                nsfwTitle = nsfwTitle,
                                nsfwSubtitle = nsfwSubtitle,
                                onProgress = { processed, total ->
                                    ReplayExportNotificationHelper.updateProgress(
                                        applicationContext,
                                        processed,
                                        total,
                                    )
                                },
                            )
                            ReplayExportNotificationHelper.showCompleted(applicationContext)
                            mainHandler.post { pendingResult.success(map) }
                        } catch (e: Exception) {
                            FileLogger.e(TAG, "composeReplayVideo 失败", e)
                            ReplayExportNotificationHelper.showFailed(
                                applicationContext,
                                e.message,
                            )
                            mainHandler.post { pendingResult.error("compose_failed", e.message, null) }
                        }
                    }
                }
                "getDetailedStorageStats" -> {
                    val pendingResult = result
                    Thread {
                        try {
                            val data = StorageAnalyzer.collect(applicationContext)
                            runOnUiThread { pendingResult.success(data) }
                        } catch (e: Exception) {
                            FileLogger.e(TAG, "获取详细存储统计失败", e)
                            runOnUiThread {
                                pendingResult.error("storage_stats_failed", e.message, null)
                            }
                        }
                    }.start()
                }
                "getStorageMigrationStatus" -> {
                    try {
                        val status = StorageMigrationManager.getStatus(applicationContext)
                        result.success(status.toMap())
                    } catch (e: Exception) {
                        result.error("migration_status_error", e.message, null)
                    }
                }
                "startStorageMigration" -> {
                    val pendingResult = result
                    Thread {
                        try {
                            val migrationResult = StorageMigrationManager.migrate(
                                applicationContext
                            ) { progress ->
                                runOnUiThread {
                                    try {
                                        methodChannel.invokeMethod(
                                            "onStorageMigrationProgress",
                                            progress.toMap()
                                        )
                                    } catch (_: Exception) {
                                    }
                                }
                            }
                            runOnUiThread {
                                pendingResult.success(migrationResult.toMap())
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                pendingResult.error("migration_failed", e.message, null)
                            }
                        }
                    }.start()
                }
                "checkServiceHealth" -> {
                    // 手动触发看门狗健康检查
                    val watchdogStatus = AccessibilityServiceWatchdog.checkServiceStatus(this)
                    val statusSummary = AccessibilityServiceWatchdog.getStatusSummary(this)
                    
                    FileLogger.i(TAG, "手动健康检查结果：")
                    FileLogger.i(TAG, statusSummary)
                    
                    result.success(mapOf(
                        "isReallyRunning" to watchdogStatus.isReallyRunning,
                        "needsRestart" to watchdogStatus.needsRestart,
                        "isSystemEnabled" to watchdogStatus.isSystemEnabled,
                        "isInstanceExists" to watchdogStatus.isInstanceExists,
                        "isProcessAlive" to watchdogStatus.isProcessAlive,
                        "isHeartbeatValid" to watchdogStatus.isHeartbeatValid,
                        "isFunctional" to watchdogStatus.isFunctional,
                        "statusSummary" to statusSummary
                    ))
                }
                "getOcrMatchBoxes" -> {
                    try {
                        val filePath = call.argument<String>("filePath")
                        val query = call.argument<String>("query")
                        if (filePath.isNullOrBlank() || query.isNullOrBlank()) {
                            result.error("invalid_args", "filePath and query are required", null)
                            return@setMethodCallHandler
                        }

                        Thread {
                            try {
                                val bmp = BitmapFactory.decodeFile(filePath)
                                if (bmp == null) {
                                    runOnUiThread { result.error("decode_failed", "decode image failed", null) }
                                    return@Thread
                                }
                                val image = InputImage.fromBitmap(bmp, 0)
                                val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
                                val vt = Tasks.await(recognizer.process(image))
                                val q = query.lowercase()
                                val boxes = mutableListOf<Map<String, Int>>()
                                for (block in vt.textBlocks) {
                                    for (line in block.lines) {
                                        val t = (line.text ?: "").trim().lowercase()
                                        if (t.contains(q)) {
                                            val rect = line.boundingBox
                                            if (rect != null) {
                                                boxes.add(mapOf(
                                                    "left" to rect.left,
                                                    "top" to rect.top,
                                                    "right" to rect.right,
                                                    "bottom" to rect.bottom
                                                ))
                                            }
                                        }
                                    }
                                }
                                val out = mapOf(
                                    "width" to bmp.width,
                                    "height" to bmp.height,
                                    "boxes" to boxes
                                )
                                try { bmp.recycle() } catch (_: Exception) {}
                                runOnUiThread { result.success(out) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("ocr_failed", e.message, null) }
                            }
                        }.start()
                    } catch (e: Exception) {
                        result.error("ocr_error", e.message, null)
                    }
                }
                "repairImportOcrBatch" -> {
                    val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()
                    Thread {
                        try {
                            val report = runImportOcrBatch(filePaths)
                            runOnUiThread { result.success(report) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("repair_import_ocr_failed", e.message, null) }
                        }
                    }.start()
                }
                "startImportOcrRepairTask" -> {
                    try {
                        val onlyMissing = call.argument<Boolean>("onlyMissing") ?: true
                        val batchSize = call.argument<Int>("batchSize") ?: 12
                        val status = ImportOcrRepairService.startOrResumeTask(
                            applicationContext,
                            onlyMissing,
                            batchSize,
                        )
                        result.success(status)
                    } catch (e: Exception) {
                        result.error("start_import_ocr_task_failed", e.message, null)
                    }
                }
                "getImportOcrRepairTaskStatus" -> {
                    try {
                        result.success(ImportOcrRepairService.getTaskStatus(applicationContext))
                    } catch (e: Exception) {
                        result.error("get_import_ocr_task_status_failed", e.message, null)
                    }
                }
                "ensureImportOcrRepairTaskResumed" -> {
                    try {
                        result.success(
                            ImportOcrRepairService.ensureResumedIfPending(
                                applicationContext,
                                "flutter_request",
                            )
                        )
                    } catch (e: Exception) {
                        result.error("ensure_import_ocr_task_resumed_failed", e.message, null)
                    }
                }
                "cancelImportOcrRepairTask" -> {
                    try {
                        result.success(ImportOcrRepairService.cancelTask(applicationContext))
                    } catch (e: Exception) {
                        result.error("cancel_import_ocr_task_failed", e.message, null)
                    }
                }
                "startDynamicRebuildTask" -> {
                    try {
                        val resumeExisting = call.argument<Boolean>("resumeExisting") ?: false
                        val dayConcurrency = call.argument<Int>("dayConcurrency")
                        val status = DynamicRebuildService.startOrResumeTask(
                            applicationContext,
                            resumeExisting,
                            dayConcurrency,
                        )
                        result.success(status)
                    } catch (e: Exception) {
                        result.error("start_dynamic_rebuild_task_failed", e.message, null)
                    }
                }
                "getDynamicRebuildTaskStatus" -> {
                    try {
                        result.success(DynamicRebuildService.getTaskStatus(applicationContext))
                    } catch (e: Exception) {
                        result.error("get_dynamic_rebuild_task_status_failed", e.message, null)
                    }
                }
                "ensureDynamicRebuildTaskResumed" -> {
                    try {
                        result.success(
                            DynamicRebuildService.ensureResumedIfPending(
                                applicationContext,
                                "flutter_request",
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("ensure_dynamic_rebuild_task_resumed_failed", e.message, null)
                    }
                }
                "cancelDynamicRebuildTask" -> {
                    try {
                        result.success(DynamicRebuildService.cancelTask(applicationContext))
                    } catch (e: Exception) {
                        result.error("cancel_dynamic_rebuild_task_failed", e.message, null)
                    }
                }
                "showMemoryRebuildNotification" -> {
                    try {
                        val status = call.argument<String>("status") ?: "running"
                        val processed = call.argument<Int>("processed") ?: 0
                        val failed = call.argument<Int>("failed") ?: 0
                        val total = call.argument<Int>("total") ?: 0
                        val currentPosition = call.argument<Int>("currentPosition") ?: 0
                        val currentSegmentId = call.argument<Int>("currentSegmentId") ?: 0
                        val segmentSampleCursor = call.argument<Int>("segmentSampleCursor") ?: 0
                        val segmentSampleTotal = call.argument<Int>("segmentSampleTotal") ?: 0
                        val pauseReason = call.argument<String>("pauseReason")
                        val lastError = call.argument<String>("lastError")
                        result.success(
                            MemoryRebuildNotifier.show(
                                applicationContext,
                                status,
                                processed,
                                failed,
                                total,
                                currentPosition,
                                currentSegmentId,
                                segmentSampleCursor,
                                segmentSampleTotal,
                                pauseReason,
                                lastError,
                            )
                        )
                    } catch (e: Exception) {
                        result.error("show_memory_rebuild_notification_failed", e.message, null)
                    }
                }
                "cancelMemoryRebuildNotification" -> {
                    try {
                        MemoryRebuildNotifier.cancel(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("cancel_memory_rebuild_notification_failed", e.message, null)
                    }
                }
                "compressScreenshotFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val format = call.argument<String>("format") ?: "webp_lossy"
                    val targetBytes = call.argument<Int>("targetBytes") ?: 0
                    val quality = call.argument<Int>("quality") ?: 90
                    val useTargetSize = call.argument<Boolean>("useTargetSize") ?: true
                    if (filePath.isNullOrBlank() || targetBytes <= 0) {
                        result.error("invalid_args", "filePath and targetBytes are required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val resp = compressScreenshotFileInternal(
                            filePath,
                            format,
                            targetBytes,
                            quality,
                            useTargetSize,
                        )
                        runOnUiThread { result.success(resp) }
                    }.start()
                }
                "compressScreenshotsBatch" -> {
                    val tasksArg = call.argument<List<Map<String, Any?>>>("tasks") ?: emptyList()
                    val format = call.argument<String>("format") ?: "webp_lossy"
                    val targetBytes = call.argument<Int>("targetBytes") ?: 0
                    val quality = call.argument<Int>("quality") ?: 90
                    val useTargetSize = call.argument<Boolean>("useTargetSize") ?: true
                    val parallelism = call.argument<Int>("parallelism")
                    compressScreenshotsBatch(
                        tasksArg,
                        format,
                        targetBytes,
                        quality,
                        useTargetSize,
                        parallelism,
                        result,
                    )
                }
                "triggerSegmentTick" -> {
                    try {
                        try { FileLogger.i(TAG, "triggerSegmentTick 调用") } catch (_: Exception) {}
                        Thread {
                            try {
                                try { FileLogger.i(TAG, "triggerSegmentTick 线程开始") } catch (_: Exception) {}
                                SegmentSummaryManager.tick(this)
                                try { FileLogger.i(TAG, "triggerSegmentTick 线程结束") } catch (_: Exception) {}
                            } catch (e: Exception) {
                                FileLogger.w(TAG, "手动 tick 失败：${e.message}")
                            }
                        }.start()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("tick_failed", e.message, null)
                    }
                }
                "retrySegments" -> {
                    try {
                        val ids = (call.argument<List<Int>>("ids") ?: emptyList()).map { it.toLong() }
                        val force = call.argument<Boolean>("force") ?: false
                        try { FileLogger.i(TAG, "retrySegments：ids=${ids} force=${force}") } catch (_: Exception) {}
                        Thread {
                            try {
                                val n = SegmentSummaryManager.retrySegmentsByIds(this, ids, force)
                                runOnUiThread { result.success(n) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("retry_failed", e.message, null) }
                            }
                        }.start()
                    } catch (e: Exception) {
                        result.error("invalid_args", e.message, null)
                    }
                }
                "forceMergeSegment" -> {
                    try {
                        val id = (call.argument<Int>("id") ?: 0).toLong()
                        val prevId = call.argument<Int>("prev_id")?.toLong()
                        try { FileLogger.i(TAG, "forceMergeSegment：id=${id} prev_id=${prevId}") } catch (_: Exception) {}
                        Thread {
                            try {
                                val ok = SegmentSummaryManager.forceMergeSegmentById(this, id, prevId)
                                runOnUiThread { result.success(ok) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("force_merge_failed", e.message, null) }
                            }
                        }.start()
                    } catch (e: Exception) {
                        result.error("invalid_args", e.message, null)
                    }
                }
                "showSimpleNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Daily Summary"
                        val message = call.argument<String>("message") ?: ""
                        try { FileLogger.i(TAG, "显示简单通知：标题=${title} 长度=${message.length}") } catch (_: Exception) {}
                        val ok = DailySummaryNotifier.showSimple(this, title, message)
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error("notify_failed", e.message, null)
                    }
                }
                "showNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Daily Summary"
                        val message = call.argument<String>("message") ?: ""
                        try { FileLogger.i(TAG, "显示大文本通知：标题=${title} 长度=${message.length}") } catch (_: Exception) {}
                        val ok = DailySummaryNotifier.showBigText(this, title, message)
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error("notify_failed", e.message, null)
                    }
                }
                "scheduleDailySummaryNotification" -> {
                    try {
                        val hour = call.argument<Int>("hour") ?: 20
                        val minute = call.argument<Int>("minute") ?: 0
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val ok = if (enabled) {
                            DailySummaryScheduler.schedule(this, hour, minute)
                        } else {
                            DailySummaryScheduler.cancel(this)
                        }
                        try { FileLogger.i(TAG, "调度每日总结通知：启用=${enabled} 小时=${hour} 分钟=${minute} 结果=${ok}") } catch (_: Exception) {}
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error("schedule_failed", e.message, null)
                    }
                }
                "openAppNotificationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                putExtra("app_package", packageName)
                                putExtra("app_uid", applicationInfo.uid)
                            }
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("open_app_notify_failed", e2.message, null)
                        }
                    }
                }
                "openDailySummaryNotificationSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                            val high = nm.getNotificationChannel("daily_summary_high")
                            val channelId = if (high != null) "daily_summary_high" else "daily_summary"
                            val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra("app_package", packageName)
                                putExtra("app_uid", applicationInfo.uid)
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        try {
                            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("open_channel_notify_failed", e2.message, null)
                        }
                    }
                }
                "openExactAlarmSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        try {
                            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("open_exact_alarm_failed", e2.message, null)
                        }
                    }
                }
                "setDailyBrief" -> {
                    try {
                        val dateKey = call.argument<String>("dateKey") ?: ""
                        val brief = call.argument<String>("brief") ?: ""
                        val sp = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                        sp.edit()
                            .putString("daily_brief_$dateKey", brief)
                            .putString("daily_brief_last", brief)
                            .apply()
                        try { FileLogger.i(TAG, "设置通知简报：dateKey=$dateKey 长度=${brief.length}") } catch (_: Exception) {}
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("set_brief_failed", e.message, null)
                    }
                }
                "getDailyBrief" -> {
                    try {
                        val dateKey = call.argument<String>("dateKey") ?: ""
                        val sp = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                        val brief = sp.getString("daily_brief_$dateKey", null)
                        result.success(brief)
                    } catch (e: Exception) {
                        result.error("get_brief_failed", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 其余重任务延迟到首帧后执行
        FileLogger.d(TAG, "configureFlutterEngine：最小初始化完成，等待首帧")

        // 保留兼容：若是仅检查服务的启动，立即结束，避免叠加界面
        if (intent?.getBooleanExtra("check_service_only", false) == true) {
            FileLogger.e(TAG, "静默启动模式，仅检查服务")
            finish()
            return
        }

        FileLogger.d(TAG, "configureFlutterEngine：完成")
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // 使用预热的引擎以缩短首帧时间
        return FlutterEngineCache.getInstance().get(ScreenMemoApplication.ENGINE_ID)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        activityCreateTs = System.currentTimeMillis()
        super.onCreate(savedInstanceState)
        // 移除应用内开屏对话框，避免显示“屏幕无痕，记忆有痕”Slogan
        // showSplashDialog()
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        if (didRunPostFirstFrameInit) return
        didRunPostFirstFrameInit = true
        val delta = System.currentTimeMillis() - activityCreateTs
        FileLogger.d(TAG, "onFlutterUiDisplayed：首帧耗时(自onCreate)=${delta}毫秒；开始 runPostFirstFrameInit")
        try { FileLogger.e(TAG, "首帧耗时(自onCreate): ${delta}ms") } catch (_: Exception) {}
        // 已不再显示开屏对话框，无需关闭
        // dismissSplashDialog()
        runPostFirstFrameInit()
        try { handleLaunchFromNotification(intent) } catch (_: Exception) {}
    }

    private fun runPostFirstFrameInit() {
        val startMs = System.currentTimeMillis()
        try {
            FileLogger.e(TAG, "=== PostFirstFrame 初始化开始 ===")

            val t1 = System.currentTimeMillis()
            FileLogger.init(this)
            FileLogger.writeSystemInfo(this)
            FileLogger.e(TAG, "步骤：FileLogger.init + writeSystemInfo -> ${System.currentTimeMillis() - t1}毫秒")

            // 设置无障碍权限监听
            val t2 = System.currentTimeMillis()
            setupAccessibilityObserver()
            FileLogger.e(TAG, "步骤：setupAccessibilityObserver -> ${System.currentTimeMillis() - t2}毫秒")

            // 设置广播接收器
            val t3 = System.currentTimeMillis()
            setupMediaProjectionRequestReceiver()
            FileLogger.e(TAG, "步骤：setupMediaProjectionRequestReceiver -> ${System.currentTimeMillis() - t3}毫秒")
            val t4 = System.currentTimeMillis()
            setupScreenshotSavedReceiver()
            FileLogger.e(TAG, "步骤：setupScreenshotSavedReceiver -> ${System.currentTimeMillis() - t4}毫秒")

            // 启动辅助功能状态监听
            val t5 = System.currentTimeMillis()
            accessibilityStateMonitor = AccessibilityStateMonitor(this)
            accessibilityStateMonitor?.startMonitoring()
            FileLogger.e(TAG, "步骤：AccessibilityStateMonitor.startMonitoring -> ${System.currentTimeMillis() - t5}毫秒")

            // 调试监控与状态检查
            try {
                val t6 = System.currentTimeMillis()
                ServiceDebugHelper.performFullStatusCheck(this)
                FileLogger.e(TAG, "步骤：ServiceDebugHelper.performFullStatusCheck -> ${System.currentTimeMillis() - t6}毫秒")
            } catch (e: Exception) {
                FileLogger.e(TAG, "调试监控执行失败", e)
            }

            // 调度JobService保活
            val t7 = System.currentTimeMillis()
            scheduleKeepAliveJob()
            FileLogger.e(TAG, "步骤：scheduleKeepAliveJob -> ${System.currentTimeMillis() - t7}毫秒")

            // 已取消：守护服务前台通知会造成重复提示，仅保留前台截图服务通知
            // val t8 = System.currentTimeMillis()
            // startDaemonService()
            // FileLogger.e(TAG, "步骤: startDaemonService -> ${System.currentTimeMillis() - t8}ms")

            // 绑定AccessibilityService
            val t9 = System.currentTimeMillis()
            bindAccessibilityService()
            FileLogger.e(TAG, "步骤：bindAccessibilityService -> ${System.currentTimeMillis() - t9}毫秒")

            FileLogger.e(TAG, "=== PostFirstFrame 初始化完成，耗时: ${System.currentTimeMillis() - startMs}毫秒 ===")
        } catch (e: Exception) {
            FileLogger.e(TAG, "PostFirstFrame 初始化失败", e)
            try { FileLogger.e(TAG, "PostFirstFrame 初始化失败", e) } catch (_: Exception) {}
        }
    }
    
    private fun handleLaunchFromNotification(i: Intent?) {
        try {
            val it = i ?: return
            val from = it.getBooleanExtra("from_daily_summary_notification", false)
            if (from) {
                val dateKey = it.getStringExtra("daily_summary_date_key") ?: ""
                try { FileLogger.i(TAG, "通知启动：from=true dateKey=$dateKey") } catch (_: Exception) {}
                try {
                    methodChannel.invokeMethod("onDailySummaryNotificationTap", mapOf("dateKey" to dateKey))
                } catch (e: Exception) {
                    try { FileLogger.w(TAG, "调用 onDailySummaryNotificationTap 失败：${e.message}") } catch (_: Exception) {}
                }
                return
            }

            val fromDynamicRebuild = it.getBooleanExtra("from_dynamic_rebuild_notification", false)
            if (fromDynamicRebuild) {
                try { FileLogger.i(TAG, "通知启动：打开动态重建页面") } catch (_: Exception) {}
                try {
                    methodChannel.invokeMethod("onDynamicRebuildNotificationTap", null)
                } catch (e: Exception) {
                    try { FileLogger.w(TAG, "调用 onDynamicRebuildNotificationTap 失败：${e.message}") } catch (_: Exception) {}
                }
                return
            }

            val fromMemoryRebuild = it.getBooleanExtra("from_memory_rebuild_notification", false)
            if (fromMemoryRebuild) {
                try { FileLogger.i(TAG, "通知启动：打开记忆重建页面") } catch (_: Exception) {}
                try {
                    methodChannel.invokeMethod("onMemoryRebuildNotificationTap", null)
                } catch (e: Exception) {
                    try { FileLogger.w(TAG, "调用 onMemoryRebuildNotificationTap 失败：${e.message}") } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchFromNotification(intent)
    }
    
    // 移除额外日志输出，保留默认生命周期

    /**
     * 仅隐藏状态栏，保留底部导航栏；并启用 edge-to-edge，避免内容区域尺寸变化
     */
    private fun hideStatusBar() {
        try {
            // 透明状态栏，内容绘制到状态栏区域
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                window.statusBarColor = Color.TRANSPARENT
            }

            // 全屏时允许内容进入刘海区域
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val lp = window.attributes
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                window.attributes = lp
            }

            // 保持内容与系统栏重叠（edge-to-edge），避免布局高度变化
            WindowCompat.setDecorFitsSystemWindows(window, false)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.insetsController?.let { controller ->
                    controller.hide(WindowInsets.Type.statusBars())
                    controller.systemBarsBehavior =
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            } else {
                @Suppress("DEPRECATION")
                val flags = (
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_FULLSCREEN
                )
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = flags
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "隐藏状态栏失败", e)
        }
    }

    /**
     * 恢复状态栏显示，并恢复 decorFitsSystemWindows 以回到默认行为
     */
    private fun showStatusBar() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.insetsController?.show(WindowInsets.Type.statusBars())
            } else {
                @Suppress("DEPRECATION")
                val flags = (
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    // 不设置 LAYOUT_FULLSCREEN/ FULLSCREEN，恢复状态栏可见
                )
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = flags
            }

            // 退出全屏时恢复默认的刘海区域策略
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val lp = window.attributes
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                window.attributes = lp
            }

            // 恢复为系统默认：内容不与系统栏重叠
            WindowCompat.setDecorFitsSystemWindows(window, true)
        } catch (e: Exception) {
            FileLogger.e(TAG, "显示状态栏失败", e)
        }
    }

    // 调试日志已移除

    /**
     * 检查无障碍服务是否已启用
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        val accessibilityEnabled = try {
            Settings.Secure.getInt(
                contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED
            )
        } catch (e: Settings.SettingNotFoundException) {
            0
        }

        if (accessibilityEnabled == 1) {
            val services = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            // 简化版本，检查包名即可
            val serviceName = packageName
            return services?.contains(serviceName) == true
        }

        return false
    }

    /**
     * 请求无障碍服务权限
     */
    private fun requestAccessibilityPermission() {
        try {
            FileLogger.e(TAG, "=== 准备打开AccessibilityService设置页面 ===")
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            startActivityForResult(intent, REQUEST_ACCESSIBILITY_SETTINGS)
            FileLogger.e(TAG, "=== AccessibilityService设置页面已打开 ===")
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开AccessibilityService设置页面失败", e)
        }
    }

    /**
     * 请求媒体投影权限
     */
    private fun requestMediaProjectionPermission() {
        val intent = mediaProjectionManager?.createScreenCaptureIntent()
        if (intent != null) {
            startActivityForResult(intent, REQUEST_MEDIA_PROJECTION)
        }
    }

    /**
     * 启动前台服务
     */
    private fun startForegroundService() {
        FileLogger.d(TAG, "启动前台服务（简化版本）")
        // 简化版本，只记录日志
    }

    /**
     * 停止前台服务
     */
    private fun stopForegroundService() {
        FileLogger.d(TAG, "停止前台服务（简化版本）")
        // 简化版本，只记录日志
    }

    /**
     * 设置无障碍权限监听
     */
    private fun setupAccessibilityObserver() {
        accessibilityObserver = object : ContentObserver(mainHandler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                FileLogger.d(TAG, "检测到无障碍设置变化: $uri")

                // 延迟检查，确保设置已经生效
                mainHandler.postDelayed({
                    checkAndNotifyAccessibilityChange()
                }, 500)
            }
        }

        // 监听无障碍服务启用状态
        contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.ACCESSIBILITY_ENABLED),
            false,
            accessibilityObserver!!
        )

        // 监听启用的无障碍服务列表
        contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES),
            false,
            accessibilityObserver!!
        )

        FileLogger.d(TAG, "无障碍权限监听已设置")
    }

    /**
     * 检查并通知无障碍权限变化
     */
    private fun checkAndNotifyAccessibilityChange() {
        val currentEnabled = isAccessibilityServiceEnabled()
        val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
        val previousEnabled = sharedPrefs.getBoolean("accessibility_enabled", false)

        if (currentEnabled != previousEnabled) {
            FileLogger.d(TAG, "无障碍权限状态变化: $previousEnabled -> $currentEnabled")

            // 保存新状态
            sharedPrefs.edit().putBoolean("accessibility_enabled", currentEnabled).apply()

            // 通知Flutter端
            methodChannel.invokeMethod("onAccessibilityResult", mapOf(
                "enabled" to currentEnabled
            ))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQUEST_MEDIA_PROJECTION -> {
                FileLogger.d(TAG, "媒体投影权限结果: resultCode=$resultCode")
                if (resultCode == Activity.RESULT_OK && data != null) {
                    // 保存权限状态
                    val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                    sharedPrefs.edit().putBoolean("media_projection_granted", true).apply()

                    // 将权限数据传递给AccessibilityService
                    val service = ScreenCaptureAccessibilityService.instance
                    if (service != null) {
                        service.setMediaProjectionData(resultCode, data)
                        FileLogger.d(TAG, "媒体投影权限数据已传递给AccessibilityService")
                    } else {
                        FileLogger.w(TAG, "AccessibilityService未运行，无法传递媒体投影权限数据")
                    }

                    // 通知Flutter端
                    methodChannel.invokeMethod("onMediaProjectionResult", mapOf(
                        "granted" to true
                    ))
                } else {
                    methodChannel.invokeMethod("onMediaProjectionResult", mapOf(
                        "granted" to false
                    ))
                }
            }
            REQUEST_ACCESSIBILITY_SETTINGS -> {
                // 延迟检查，确保从设置页面返回后状态已更新
                mainHandler.postDelayed({
                    checkAndNotifyAccessibilityChange()
                }, 1000)
            }
        }
    }

    /**
     * 设置MediaProjection权限请求广播接收器
     */
    private fun setupMediaProjectionRequestReceiver() {
        try {
            mediaProjectionRequestReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "com.fqyw.screen_memo.REQUEST_MEDIA_PROJECTION") {
                        FileLogger.e(TAG, "收到MediaProjection权限请求广播，重新请求权限")
                        requestMediaProjectionPermission()
                    }
                }
            }
            
            val filter = IntentFilter("com.fqyw.screen_memo.REQUEST_MEDIA_PROJECTION")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(mediaProjectionRequestReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(mediaProjectionRequestReceiver, filter)
            }
            FileLogger.e(TAG, "MediaProjection权限请求广播接收器已注册")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置MediaProjection权限请求广播接收器失败", e)
        }
    }


    /**
     * 设置截图保存通知广播接收器
     */
    private fun setupScreenshotSavedReceiver() {
        try {
            screenshotSavedReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "com.fqyw.screen_memo.SCREENSHOT_SAVED") {
                        val packageName = intent.getStringExtra("packageName") ?: ""
                        val appName = intent.getStringExtra("appName") ?: ""
                        val filePath = intent.getStringExtra("filePath") ?: ""
                        val captureTime = intent.getLongExtra("captureTime", System.currentTimeMillis())
                        val pageUrl = intent.getStringExtra("pageUrl")
                        
                        FileLogger.i(TAG, "收到截图保存通知: $appName - $filePath")
                        if (!pageUrl.isNullOrBlank()) {
                            FileLogger.i(TAG, "收到URL: ${pageUrl}")
                        } else {
                            FileLogger.d(TAG, "本次通知未附带URL")
                        }
                        // 通知Flutter端更新数据库
                        methodChannel.invokeMethod("onScreenshotSaved", mapOf(
                            "packageName" to packageName,
                            "appName" to appName,
                            "filePath" to filePath,
                            "captureTime" to captureTime,
                            "pageUrl" to pageUrl
                        ))
                    }
                }
            }
            
            val filter = IntentFilter("com.fqyw.screen_memo.SCREENSHOT_SAVED")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenshotSavedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(screenshotSavedReceiver, filter)
            }
            FileLogger.e(TAG, "截图保存通知广播接收器已注册")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置截图保存通知广播接收器失败", e)
        }
    }

    /**
     * 测试自启动权限（通过尝试启动服务）
     */
    private fun testAutoStartPermission(): Boolean {
        return try {
            FileLogger.d(TAG, "测试自启动权限...")

            // 尝试启动无障碍服务来测试权限
            val intent = Intent(this, ScreenCaptureAccessibilityService::class.java)
            startService(intent)

            FileLogger.d(TAG, "服务启动命令已发送")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "测试自启动权限失败", e)
            false
        }
    }

    /**
     * 检查服务是否正在运行
     */
    private fun isServiceRunning(): Boolean {
        return try {
            // 先尝试通过AIDL检查
            val aidlRunning = try {
                accessibilityServiceBinder?.isServiceRunning() ?: false
            } catch (e: Exception) {
                FileLogger.w(TAG, "AIDL检查失败: ${e.message}")
                false
            }
            
            // 再检查本地实例（如果在同一进程）
            val instanceExists = ScreenCaptureAccessibilityService.instance != null
            val isServiceRunning = ScreenCaptureAccessibilityService.isServiceRunning
            val isAccessibilityEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(this)

            FileLogger.d(TAG, "服务状态检查:")
            FileLogger.d(TAG, "- AIDL服务运行: $aidlRunning")
            FileLogger.d(TAG, "- AccessibilityService实例存在: $instanceExists")
            FileLogger.d(TAG, "- 服务运行标志: $isServiceRunning")
            FileLogger.d(TAG, "- 系统中启用状态: $isAccessibilityEnabled")

            // 综合判断
            val result = aidlRunning || (instanceExists && isAccessibilityEnabled)
            FileLogger.d(TAG, "最终服务运行状态: $result")

            return result
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查服务状态失败", e)
            false
        }
    }

    /**
     * 验证MediaProjection权限是否真实有效
     */
    private fun validateMediaProjectionPermission(): Boolean {
        return try {
            // 检查SharedPreferences中的权限状态
            val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            val savedPermission = sharedPrefs.getBoolean("media_projection_granted", false)

            FileLogger.d(TAG, "MediaProjection权限验证:")
            FileLogger.d(TAG, "- SharedPreferences中的状态: $savedPermission")

            // MediaProjection权限是独立的，不依赖AccessibilityService的运行状态
            // 只要用户授予了权限，就认为是有效的
            if (savedPermission) {
                FileLogger.d(TAG, "MediaProjection权限验证通过")
                return true
            } else {
                FileLogger.d(TAG, "MediaProjection权限未授予")
                return false
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "验证MediaProjection权限失败", e)
            false
        }
    }

    /**
     * 开始屏幕截图
     */
    private fun startScreenCapture(): Boolean {
        return try {
            val service = ScreenCaptureAccessibilityService.instance
            if (service != null) {
                service.startScreenCapture()
            } else {
                FileLogger.e(TAG, "无障碍服务未运行")
                false
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "开始屏幕截图失败", e)
            false
        }
    }

    /**
     * 停止屏幕截图
     */
    private fun stopScreenCapture() {
        try {
            val service = ScreenCaptureAccessibilityService.instance
            service?.stopScreenCapture()
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止屏幕截图失败", e)
        }
    }

    /**
     * 启动定时截屏
     */
    private fun startTimedScreenshot(intervalSeconds: Int): Boolean {
        return try {
            FileLogger.e(TAG, "=== 开始定时截屏流程 ===")
            FileLogger.e(TAG, "截屏间隔: ${intervalSeconds}秒")

            // 检查服务状态
            val service = ScreenCaptureAccessibilityService.instance
            val isServiceRunning = service != null
            val isSystemEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(this)

            FileLogger.e(TAG, "服务状态检查:")
            FileLogger.e(TAG, "- AccessibilityService实例: ${if (service != null) "存在" else "不存在"}")
            FileLogger.e(TAG, "- 系统中启用状态: $isSystemEnabled")

            // 如果系统中已启用但实例不存在，等待服务启动
            if (isSystemEnabled && service == null) {
                FileLogger.e(TAG, "系统中已启用但服务实例不存在，等待服务启动...")
                
                // 等待服务实例可用，最多等待5秒
                var waitedService: ScreenCaptureAccessibilityService? = null
                for (i in 1..10) {
                    Thread.sleep(500) // 等待0.5秒
                    waitedService = ScreenCaptureAccessibilityService.instance
                    if (waitedService != null) {
                        FileLogger.e(TAG, "服务实例已可用，等待时间: ${i * 500}ms")
                        break
                    }
                    FileLogger.e(TAG, "等待服务实例，第${i}次检查...")
                }
                
                if (waitedService != null) {
                    FileLogger.e(TAG, "调用无障碍服务开始定时截屏")
                    val result = waitedService.startTimedScreenshot(intervalSeconds)
                    FileLogger.e(TAG, "无障碍服务开始定时截屏返回: $result")
                    return result
                } else {
                    FileLogger.e(TAG, "等待超时，服务实例仍不可用")
                    return false
                }
            }

            if (service != null) {
                FileLogger.e(TAG, "调用无障碍服务开始定时截屏")
                val result = service.startTimedScreenshot(intervalSeconds)
                FileLogger.e(TAG, "无障碍服务开始定时截屏返回: $result")
                return result
            } else {
                FileLogger.e(TAG, "无障碍服务未运行")
                if (!isSystemEnabled) {
                    FileLogger.e(TAG, "无障碍服务未在系统中启用，需要用户手动启用")
                }
                return false
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动定时截屏失败", e)
            false
        }
    }

    /**
     * 停止定时截屏
     */
    private fun stopTimedScreenshot() {
        try {
            val service = ScreenCaptureAccessibilityService.instance
            service?.stopTimedScreenshot()
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止定时截屏失败", e)
        }
    }

    /**
     * 手动截取屏幕
     */
    private fun captureScreen(): String? {
        return try {
            val service = ScreenCaptureAccessibilityService.instance
            if (service != null) {
                service.captureScreenSync()
            } else {
                FileLogger.e(TAG, "无障碍服务未运行")
                null
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "截取屏幕失败", e)
            null
        }
    }

    /**
     * 获取应用专用外部存储目录路径
     */
    private fun getExternalFilesDirPath(subDir: String?): String? {
        return try {
            val externalFilesDir = if (subDir != null) {
                getExternalFilesDir(subDir)
            } else {
                getExternalFilesDir(null)
            }

            externalFilesDir?.absolutePath
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取外部文件目录失败", e)
            null
        }
    }

    /**
     * 获取应用内部 files 目录路径
     */
    private fun getInternalFilesDirPath(subDir: String?): String? {
        return try {
            val baseDir = filesDir
            val target = if (subDir.isNullOrBlank()) {
                baseDir
            } else {
                val dir = File(baseDir, subDir)
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                dir
            }
            target.absolutePath
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取内部文件目录失败", e)
            null
        }
    }

    /**
     * 检查使用统计权限是否已授予
     */
    private fun isUsageStatsPermissionGranted(): Boolean {
        return try {
            val appOpsManager = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查使用统计权限失败", e)
            false
        }
    }

    /**
     * 请求使用统计权限
     */
    private fun requestUsageStatsPermission() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (e: Exception) {
            FileLogger.e(TAG, "请求使用统计权限失败", e)
            // 如果无法打开特定应用的设置页面，打开通用设置页面
            try {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                startActivity(intent)
            } catch (e2: Exception) {
                FileLogger.e(TAG, "打开使用统计设置页面失败", e2)
            }
        }
    }
    
    /**
     * 调度JobService保活任务
     */
    private fun scheduleKeepAliveJob() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                FileLogger.e(TAG, "准备调度JobService保活任务")
                
                val jobScheduler = getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
                val componentName = ComponentName(this, KeepAliveJobService::class.java)
                
                val jobInfo = JobInfo.Builder(KeepAliveJobService.JOB_ID, componentName).apply {
                    // 设置任务执行条件
                    setPeriodic(15 * 60 * 1000) // 每15分钟执行一次
                    setPersisted(true) // 设备重启后仍然执行
                    setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE) // 不需要网络
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setRequiresBatteryNotLow(false) // 电量低时也执行
                        setRequiresStorageNotLow(false) // 存储空间低时也执行
                    }
                }.build()
                
                val result = jobScheduler.schedule(jobInfo)
                if (result == JobScheduler.RESULT_SUCCESS) {
                    FileLogger.e(TAG, "JobService保活任务调度成功")
                } else {
                    FileLogger.e(TAG, "JobService保活任务调度失败")
                }
                
            } catch (e: Exception) {
                FileLogger.e(TAG, "调度JobService保活任务失败", e)
            }
        } else {
            FileLogger.w(TAG, "Android版本过低，不支持JobScheduler")
        }
    }
    
    private fun compressScreenshotFileInternal(
        filePath: String,
        format: String,
        targetBytes: Int,
        quality: Int,
        useTargetSize: Boolean,
    ): Map<String, Any?> {
        val file = File(filePath)
        if (!file.exists()) {
            return mapOf(
                "success" to false,
                "error" to "not_found",
            )
        }
        var bitmap: Bitmap? = null
        return try {
            bitmap = BitmapFactory.decodeFile(filePath)
            if (bitmap == null) {
                return mapOf(
                    "success" to false,
                    "error" to "decode_failed",
                )
            }
            val spec = resolveCompressFormat(format)
            val appliedQuality = quality.coerceIn(1, 100)
            val bytes = if (useTargetSize && spec.isLossy) {
                compressToTargetSize(bitmap, spec.compressFormat, targetBytes)
                    ?: compressOnce(bitmap, spec.compressFormat, appliedQuality)
            } else {
                compressOnce(
                    bitmap,
                    spec.compressFormat,
                    if (spec.isLossy) appliedQuality else 100,
                )
            }
            if (bytes == null) {
                return mapOf(
                    "success" to false,
                    "error" to "compress_failed",
                )
            }
            FileOutputStream(file, false).use { fos ->
                fos.write(bytes)
                fos.flush()
            }
            try {
                file.setLastModified(System.currentTimeMillis())
            } catch (_: Exception) {}
            mapOf(
                "success" to true,
                "newSize" to bytes.size,
                "format" to spec.extension,
            )
        } catch (e: Exception) {
            FileLogger.e(TAG, "压缩截图文件失败", e)
            mapOf(
                "success" to false,
                "error" to (e.message ?: "unknown"),
            )
        } finally {
            try { bitmap?.recycle() } catch (_: Exception) {}
        }
    }

    private fun compressScreenshotsBatch(
        tasksArg: List<Map<String, Any?>>,
        format: String,
        targetBytes: Int,
        quality: Int,
        useTargetSize: Boolean,
        parallelism: Int?,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                val parsedTasks = tasksArg.mapNotNull { map ->
                    val rawPath = map["filePath"] as? String ?: return@mapNotNull null
                    val filePath = rawPath.trim()
                    if (filePath.isEmpty()) return@mapNotNull null
                    val gid = when (val rawGid = map["gid"]) {
                        is Number -> rawGid.toLong()
                        is String -> rawGid.toLongOrNull() ?: 0L
                        else -> 0L
                    }
                    val originalSize = when (val rawSize = map["originalSize"]) {
                        is Number -> rawSize.toLong()
                        is String -> rawSize.toLongOrNull() ?: 0L
                        else -> 0L
                    }
                    ScreenshotCompressionTask(filePath, gid, originalSize)
                }

                if (parsedTasks.isEmpty()) {
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "total" to 0,
                                "handled" to 0,
                                "success" to 0,
                                "skipped" to 0,
                                "failed" to 0,
                                "savedBytes" to 0L,
                                "totalBeforeBytes" to 0L,
                                "totalAfterBytes" to 0L,
                                "durationMillis" to 0,
                                "successes" to emptyList<Map<String, Any?>>(),
                                "failures" to emptyList<Map<String, Any?>>(),
                                "skippedEntries" to emptyList<Map<String, Any?>>(),
                            ),
                        )
                    }
                    return@Thread
                }

                val total = parsedTasks.size
                emitCompressionProgress(total, 0, 0, 0, 0, 0L)

                val cpuCount = Runtime.getRuntime().availableProcessors()
                val desiredParallelism = parallelism ?: cpuCount
                val poolSize = max(1, min(8, max(2, desiredParallelism)))
                val executor = Executors.newFixedThreadPool(poolSize)
                val latch = CountDownLatch(total)

                val handledCount = AtomicInteger(0)
                val successCount = AtomicInteger(0)
                val skippedCount = AtomicInteger(0)
                val failedCount = AtomicInteger(0)
                val totalBefore = AtomicLong(0)
                val totalAfter = AtomicLong(0)

                val successes = Collections.synchronizedList(mutableListOf<Map<String, Any?>>())
                val failures = Collections.synchronizedList(mutableListOf<Map<String, Any?>>())
                val skipped = Collections.synchronizedList(mutableListOf<Map<String, Any?>>())

                val startTime = SystemClock.elapsedRealtime()
                val effectiveTargetBytes = if (targetBytes <= 0) 1024 else targetBytes

                parsedTasks.forEach { task ->
                    executor.execute {
                        try {
                            val file = File(task.filePath)
                            if (!file.exists()) {
                                failedCount.incrementAndGet()
                                failures.add(
                                    mapOf(
                                        "filePath" to task.filePath,
                                        "gid" to task.gid,
                                        "reason" to "not_found",
                                    ),
                                )
                            } else {
                                val currentSize = if (task.originalSize > 0) task.originalSize else file.length()
                                if (effectiveTargetBytes > 0 && currentSize <= effectiveTargetBytes.toLong()) {
                                    skippedCount.incrementAndGet()
                                    skipped.add(
                                        mapOf(
                                            "filePath" to task.filePath,
                                            "gid" to task.gid,
                                            "originalSize" to currentSize,
                                            "reason" to "already_small",
                                        ),
                                    )
                                } else {
                                    val outcome = compressScreenshotFileInternal(
                                        task.filePath,
                                        format,
                                        effectiveTargetBytes,
                                        quality,
                                        useTargetSize,
                                    )
                                    val success = outcome["success"] as? Boolean ?: false
                                    if (success) {
                                        val newSize = (
                                            (outcome["newSize"] as? Number)?.toLong()
                                                ?: File(task.filePath).length()
                                            ).coerceAtLeast(0L)
                                        val origin = if (currentSize > 0) currentSize else newSize
                                        successCount.incrementAndGet()
                                        totalBefore.addAndGet(origin)
                                    totalAfter.addAndGet(newSize)
                                    val effectiveSaved = (origin - newSize).coerceAtLeast(0L)
                                    val savedBytes = totalBefore.get() - totalAfter.get()
                                        successes.add(
                                            mapOf(
                                                "filePath" to task.filePath,
                                                "gid" to task.gid,
                                                "originalSize" to origin,
                                                "newSize" to newSize,
                                            "savedBytes" to effectiveSaved,
                                            ),
                                        )
                                    } else {
                                        failedCount.incrementAndGet()
                                        failures.add(
                                            mapOf(
                                                "filePath" to task.filePath,
                                                "gid" to task.gid,
                                                "reason" to (outcome["error"] ?: "compress_failed"),
                                            ),
                                        )
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            failedCount.incrementAndGet()
                            failures.add(
                                mapOf(
                                    "filePath" to task.filePath,
                                    "gid" to task.gid,
                                    "reason" to (e.message ?: "unknown"),
                                ),
                            )
                        } finally {
                            val handledNow = handledCount.incrementAndGet()
                            val savedBytes = totalBefore.get() - totalAfter.get()
                            emitCompressionProgress(
                                total,
                                handledNow,
                                successCount.get(),
                                skippedCount.get(),
                                failedCount.get(),
                                savedBytes,
                            )
                            latch.countDown()
                        }
                    }
                }

                executor.shutdown()
                latch.await()

                val duration = (SystemClock.elapsedRealtime() - startTime).toInt()
                val savedTotal = (totalBefore.get() - totalAfter.get()).coerceAtLeast(0L)
                val summary = mapOf(
                    "total" to total,
                    "handled" to handledCount.get(),
                    "success" to successCount.get(),
                    "skipped" to skippedCount.get(),
                    "failed" to failedCount.get(),
                    "savedBytes" to savedTotal,
                    "totalBeforeBytes" to totalBefore.get(),
                    "totalAfterBytes" to totalAfter.get(),
                    "durationMillis" to duration,
                    "successes" to ArrayList(successes),
                    "failures" to ArrayList(failures),
                    "skippedEntries" to ArrayList(skipped),
                )
                runOnUiThread { result.success(summary) }
            } catch (e: Exception) {
                runOnUiThread { result.error("compress_batch_failed", e.message, null) }
            }
        }.start()
    }

    private fun emitCompressionProgress(
        total: Int,
        handled: Int,
        success: Int,
        skipped: Int,
        failed: Int,
        savedBytes: Long,
    ) {
        val adjustedSaved = if (savedBytes < 0L) 0L else savedBytes
        try {
            runOnUiThread {
                try {
                    methodChannel.invokeMethod(
                        "onCompressionProgress",
                        mapOf(
                            "total" to total,
                            "handled" to handled,
                            "success" to success,
                            "skipped" to skipped,
                            "failed" to failed,
                            "savedBytes" to adjustedSaved,
                        ),
                    )
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
    }

    private data class ScreenshotCompressionTask(
        val filePath: String,
        val gid: Long,
        val originalSize: Long,
    )

    private data class FormatSpec(
        val compressFormat: Bitmap.CompressFormat,
        val isLossy: Boolean,
        val extension: String,
    )

    private fun resolveCompressFormat(name: String): FormatSpec {
        val lower = name.lowercase()
        return when (lower) {
            "jpeg", "jpg" -> FormatSpec(Bitmap.CompressFormat.JPEG, true, "jpg")
            "png" -> FormatSpec(Bitmap.CompressFormat.PNG, false, "png")
            "webp_lossless" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    FormatSpec(Bitmap.CompressFormat.WEBP_LOSSLESS, false, "webp")
                } else {
                    FormatSpec(Bitmap.CompressFormat.PNG, false, "png")
                }
            }
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    FormatSpec(Bitmap.CompressFormat.WEBP_LOSSY, true, "webp")
                } else {
                    FormatSpec(Bitmap.CompressFormat.WEBP, true, "webp")
                }
            }
        }
    }

    private fun compressOnce(
        bm: Bitmap,
        format: Bitmap.CompressFormat,
        quality: Int,
    ): ByteArray? {
        return try {
            val baos = ByteArrayOutputStream()
            bm.compress(format, quality.coerceIn(1, 100), baos)
            baos.toByteArray()
        } catch (e: Exception) {
            FileLogger.e(TAG, "压缩一次失败", e)
            null
        }
    }

    private fun compressToTargetSize(
        bm: Bitmap,
        format: Bitmap.CompressFormat,
        targetBytes: Int,
        minQ: Int = 1,
        maxQ: Int = 100,
        maxIterations: Int = 12,
    ): ByteArray? {
        var lo = minQ.coerceIn(1, 100)
        var hi = maxQ.coerceIn(lo, 100)
        var bestUnder: ByteArray? = null
        var bestOver: ByteArray? = null
        var iterations = 0
        while (lo <= hi && iterations < maxIterations) {
            iterations++
            val mid = (lo + hi) / 2
            val data = compressOnce(bm, format, mid) ?: return null
            if (data.size <= targetBytes) {
                if (bestUnder == null || data.size > bestUnder!!.size) {
                    bestUnder = data
                }
                lo = mid + 1
            } else {
                if (bestOver == null || data.size < bestOver!!.size) {
                    bestOver = data
                }
                hi = mid - 1
            }
        }
        return bestUnder ?: bestOver
    }

    /**
     * 触发AccessibilityService连接
     */
    private fun triggerAccessibilityServiceConnection() {
        try {
            FileLogger.e(TAG, "开始触发AccessibilityService连接")
            
            // 方法1: 启动前台服务
            try {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                FileLogger.e(TAG, "前台服务启动成功")
            } catch (e: Exception) {
                FileLogger.e(TAG, "启动前台服务失败", e)
            }
            
            // 方法2: 重新检查和更新状态
            ServiceDebugHelper.performFullStatusCheck(this)
            
            // 方法3: 尝试通过禁用/启用无障碍服务来触发连接
            // 注意：这需要系统权限，一般应用无法执行
            // val accessibilityManager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "触发AccessibilityService连接失败", e)
        }
    }
    
    /**
     * 启动守护服务
     */
    private fun startDaemonService() {
        try {
            val serviceIntent = Intent(this, DaemonService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            FileLogger.e(TAG, "守护服务启动成功")
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动守护服务失败", e)
        }
    }
    
    /**
     * 绑定AccessibilityService
     */
    private fun bindAccessibilityService() {
        try {
            val intent = Intent().apply {
                component = ComponentName(packageName, "$packageName.ScreenCaptureAccessibilityService")
            }
            bindService(intent, accessibilityServiceConnection, Context.BIND_AUTO_CREATE)
            FileLogger.e(TAG, "开始绑定AccessibilityService")
        } catch (e: Exception) {
            FileLogger.e(TAG, "绑定AccessibilityService失败", e)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // 尝试解绑AccessibilityService
        try {
            unbindService(accessibilityServiceConnection)
        } catch (e: Exception) {
            // 忽略解绑错误
        }
        
        // 调用原有的onDestroy逻辑
        onDestroyOriginal()
    }
    
    private fun onDestroyOriginal() {
        // 原有onDestroy代码
        // 取消注册ContentObserver
        accessibilityObserver?.let {
            contentResolver.unregisterContentObserver(it)
        }

        // 取消注册广播接收器
        mediaProjectionRequestReceiver?.let {
            try {
                unregisterReceiver(it)
                FileLogger.e(TAG, "MediaProjection权限请求广播接收器已取消注册")
            } catch (e: Exception) {
                FileLogger.e(TAG, "取消注册广播接收器失败", e)
            }
        }
        
        screenshotSavedReceiver?.let {
            try {
                unregisterReceiver(it)
                FileLogger.e(TAG, "截图保存通知广播接收器已取消注册")
            } catch (e: Exception) {
                FileLogger.e(TAG, "取消注册截图保存广播接收器失败", e)
            }
        }

        // 停止辅助功能状态监听
        accessibilityStateMonitor?.stopMonitoring()
    }

    private fun dp(value: Int): Int {
        return (resources.displayMetrics.density * value).toInt()
    }

    private fun showSplashDialog() {
        try {
            if (splashDialog?.isShowing == true) return
            val dialog = Dialog(this, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen)
            val root = FrameLayout(this).apply {
                setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.splash_background))
            }
            val container = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            }
            val logo = ImageView(this).apply {
                setImageResource(R.drawable.splash_logo)
                adjustViewBounds = true
                scaleType = ImageView.ScaleType.FIT_CENTER
                // 更保守的宽度，避免过大：屏宽的 32%
                val widthPx = (resources.displayMetrics.widthPixels * 0.32f).toInt()
                layoutParams = LinearLayout.LayoutParams(widthPx, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                }
            }
            val slogan = TextView(this).apply {
                text = "屏幕无痕，记忆有痕"
                setTextColor(ContextCompat.getColor(this@MainActivity, android.R.color.darker_gray))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                letterSpacing = 0.02f
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    topMargin = dp(12)
                    gravity = Gravity.CENTER_HORIZONTAL
                }
            }
            container.addView(logo)
            container.addView(slogan)
            root.addView(container)
            dialog.setContentView(root)
            dialog.setCancelable(false)
            dialog.show()
            splashDialog = dialog
        } catch (e: Exception) {
            FileLogger.e(TAG, "显示开屏对话框失败", e)
        }
    }

    private fun dismissSplashDialog() {
        try {
            val dialog = splashDialog ?: return
            dialog.window?.decorView?.animate()?.alpha(0f)?.setDuration(150)?.withEndAction {
                try { dialog.dismiss() } catch (_: Exception) {}
                splashDialog = null
            }?.start()
        } catch (e: Exception) {
            try { splashDialog?.dismiss() } catch (_: Exception) {}
            splashDialog = null
        }
    }

    /**
     * 将源文件复制到公共下载目录（Download/【subDir】/displayName）
     * 返回 Map，包括：contentUri、displayPath、absolutePath、fileName、size
     */
    private fun exportFileToDownloadsInternal(sourceFile: File, displayName: String, subDir: String?): Map<String, Any?> {
        val resolver = contentResolver
        val size = sourceFile.length()
        val targetSubDir = (subDir ?: "").trim('/').ifEmpty { "ScreenMemory" }
        val displayPath = if (targetSubDir.isNotEmpty()) "Download/$targetSubDir/$displayName" else "Download/$displayName"
        val copyBufferSize = 1024 * 1024

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                put(MediaStore.MediaColumns.RELATIVE_PATH, if (targetSubDir.isNotEmpty()) Environment.DIRECTORY_DOWNLOADS + "/" + targetSubDir else Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Failed to create item in MediaStore")
            try {
                resolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(sourceFile).use { input ->
                        input.copyTo(out, copyBufferSize)
                    }
                } ?: throw IllegalStateException("Failed to open output stream")

                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)

                @Suppress("DEPRECATION")
                val absDownloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val absolutePath = if (targetSubDir.isNotEmpty()) File(absDownloads, "$targetSubDir/$displayName").absolutePath else File(absDownloads, displayName).absolutePath

                mapOf(
                    "contentUri" to uri.toString(),
                    "displayPath" to displayPath,
                    "absolutePath" to absolutePath,
                    "fileName" to displayName,
                    "size" to size
                )
            } catch (e: Exception) {
                try {
                    resolver.delete(uri, null, null)
                } catch (_: Exception) {}
                throw e
            }
        } else {
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val targetDir = if (targetSubDir.isNotEmpty()) File(downloadsDir, targetSubDir) else downloadsDir
            if (!targetDir.exists()) targetDir.mkdirs()
            val dest = File(targetDir, displayName)

            try {
                FileInputStream(sourceFile).use { input ->
                    FileOutputStream(dest).use { output ->
                        input.copyTo(output, copyBufferSize)
                    }
                }
            } catch (e: Exception) {
                try {
                    if (dest.exists()) {
                        dest.delete()
                    }
                } catch (_: Exception) {}
                throw e
            }

            mapOf(
                "contentUri" to dest.absolutePath,
                "displayPath" to displayPath,
                "absolutePath" to dest.absolutePath,
                "fileName" to displayName,
                "size" to size
            )
        }
    }

    private fun deleteExportedArtifactInternal(contentUri: String?, absolutePath: String?): Boolean {
        var deleted = false
        if (!contentUri.isNullOrBlank() && contentUri.startsWith("content://")) {
            try {
                deleted = contentResolver.delete(Uri.parse(contentUri), null, null) > 0
            } catch (e: Exception) {
                FileLogger.e(TAG, "删除 MediaStore 导出项失败: $contentUri", e)
            }
        }
        if (!deleted && !absolutePath.isNullOrBlank()) {
            try {
                val file = File(absolutePath)
                if (file.exists()) {
                    deleted = file.delete()
                }
            } catch (e: Exception) {
                FileLogger.e(TAG, "删除导出目标文件失败: $absolutePath", e)
            }
        }
        return deleted
    }

    /**
     * 以原生 ZipOutputStream(BEST_SPEED) 直接压缩 output 目录并写入 Downloads/ScreenMemory（无中转临时文件）
     * - 极致速度：全局 Deflater.BEST_SPEED；仅复制字节，不做高开销压缩
     * - 直接写入 MediaStore OutputStream，省去“临时文件 -> 再复制到Downloads”的一步磁盘 I/O
     */
    private fun exportOutputToDownloadsNativeInternal(displayName: String, subDir: String?): Map<String, Any?> {
        val internalBase = filesDir
        val outputDir = File(internalBase, "output")
        if (!outputDir.exists() || !outputDir.isDirectory) {
            throw IllegalStateException("output directory not found: ${outputDir.absolutePath}")
        }

        val resolver = contentResolver
        val targetSubDir = (subDir ?: "ScreenMemory").trim('/').ifEmpty { "ScreenMemory" }
        val displayPath = if (targetSubDir.isNotEmpty()) "Download/$targetSubDir/$displayName" else "Download/$displayName"

        // Android 10+ 走 MediaStore
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/zip")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (targetSubDir.isNotEmpty()) Environment.DIRECTORY_DOWNLOADS + "/" + targetSubDir
                    else Environment.DIRECTORY_DOWNLOADS
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Failed to create item in MediaStore")

            var bytesWritten = 0L
            resolver.openOutputStream(uri)?.use { rawOut ->
                ZipOutputStream(rawOut).use { zipOut ->
                    zipOut.setLevel(Deflater.BEST_SPEED)
                    // 将根目录名包含为 "output/"
                    addDirectoryToZipNative(zipOut, outputDir, outputDir, "output/")
                }
                // 无法直接从 Uri 查询写入大小，按需要可忽略或额外统计
            } ?: throw IllegalStateException("Failed to open output stream")

            // 提交
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            @Suppress("DEPRECATION")
            val absDownloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val absolutePath = if (targetSubDir.isNotEmpty())
                File(absDownloads, "$targetSubDir/$displayName").absolutePath
            else
                File(absDownloads, displayName).absolutePath

            return mapOf(
                "contentUri" to uri.toString(),
                "displayPath" to displayPath,
                "absolutePath" to absolutePath,
                "fileName" to displayName,
                "size" to bytesWritten // 可能为0，Android Q+可选从 uri 查询实际大小，这里保持兼容
            )
        } else {
            // Android 9 及以下：直接写入公共下载目录文件
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val targetDir = if (targetSubDir.isNotEmpty()) File(downloadsDir, targetSubDir) else downloadsDir
            if (!targetDir.exists()) targetDir.mkdirs()
            val dest = File(targetDir, displayName)

            FileOutputStream(dest).use { fos ->
                ZipOutputStream(fos).use { zipOut ->
                    zipOut.setLevel(Deflater.BEST_SPEED)
                    addDirectoryToZipNative(zipOut, outputDir, outputDir, "output/")
                }
            }

            return mapOf(
                "contentUri" to dest.absolutePath,
                "displayPath" to displayPath,
                "absolutePath" to dest.absolutePath,
                "fileName" to displayName,
                "size" to dest.length()
            )
        }
    }

    /**
     * 原生导入：从 ZIP 文件解压到内部 files/output 目录
     */
    private fun importZipToOutputAsync(zipPath: String, overwrite: Boolean, result: MethodChannel.Result) {
        Thread {
            try {
                FileLogger.i(TAG, "原生导入：开始 importZipToOutput，path=$zipPath overwrite=$overwrite")
                val base = filesDir
                val outputDir = File(base, "output")
                if (overwrite && outputDir.exists()) {
                    outputDir.deleteRecursively()
                }
                if (!outputDir.exists()) {
                    outputDir.mkdirs()
                }

                val buffer = ByteArray(256 * 1024)
                ZipInputStream(FileInputStream(zipPath)).use { zis ->
                    while (true) {
                        val entry = zis.nextEntry ?: break
                        val rawName = entry.name.replace("\\", "/")
                        // 兼容导出时的 "output/..." 前缀
                        val rel = if (rawName.startsWith("output/")) {
                            rawName.substring("output/".length)
                        } else {
                            rawName
                        }
                        val normalized = normalizeImportRelativePath(rel)
                        if (normalized.isEmpty()) {
                            zis.closeEntry()
                            continue
                        }
                        val relLower = normalized.lowercase()
                        if (shouldSkipOutputCache(relLower)) {
                            FileLogger.i(TAG, "原生导入：跳过缓存条目 $normalized")
                            zis.closeEntry()
                            continue
                        }
                        val destFile = File(outputDir, normalized)
                        if (entry.isDirectory) {
                            if (!destFile.exists()) {
                                destFile.mkdirs()
                            }
                            zis.closeEntry()
                            continue
                        }
                        val parent = destFile.parentFile
                        if (parent != null && !parent.exists()) {
                            parent.mkdirs()
                        }
                        FileOutputStream(destFile).use { out ->
                            while (true) {
                                val read = zis.read(buffer)
                                if (read <= 0) break
                                out.write(buffer, 0, read)
                            }
                            out.flush()
                        }
                        zis.closeEntry()
                    }
                }

                try {
                    clearOutputCacheDirsNative(outputDir)
                } catch (e: Exception) {
                    FileLogger.e(TAG, "原生导入：清理缓存目录失败", e)
                }

                deleteImportZipIfCached(zipPath)

                FileLogger.i(TAG, "原生导入：importZipToOutput 完成，outputDir=${outputDir.absolutePath}")
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                FileLogger.e(TAG, "原生导入：importZipToOutput 失败", e)
                runOnUiThread { result.error("import_failed", e.message, null) }
            }
        }.start()
    }

    /**
     * 原生导入：从已解压的 output 目录复制到内部 files/output 目录
     */
    private fun importFromExtractedOutputDirAsync(srcRoot: String, overwrite: Boolean, result: MethodChannel.Result) {
        Thread {
            try {
                FileLogger.i(TAG, "原生导入：开始 importFromExtractedOutputDir，srcRoot=$srcRoot overwrite=$overwrite")
                val base = filesDir
                val targetOutput = File(base, "output")
                // 支持两种选择方式：
                // 1) 选择到包含 output 的父目录（此时使用 srcRoot/output）
                // 2) 直接选择到 output 目录本身
                var srcOutput = File(srcRoot, "output")
                if (!srcOutput.exists() || !srcOutput.isDirectory) {
                    val direct = File(srcRoot)
                    if (direct.exists() && direct.isDirectory && direct.name == "output") {
                        srcOutput = direct
                    } else {
                        FileLogger.e(TAG, "原生导入：源 output 目录不存在：${srcOutput.absolutePath}")
                        runOnUiThread {
                            result.error("import_src_not_found", "src output dir not found", srcOutput.absolutePath)
                        }
                        return@Thread
                    }
                }

                if (overwrite && targetOutput.exists()) {
                    targetOutput.deleteRecursively()
                }
                if (!targetOutput.exists()) {
                    targetOutput.mkdirs()
                }

                copyDirRecursively(srcOutput, targetOutput, srcOutput)

                clearOutputCacheDirsNative(targetOutput)

                FileLogger.i(TAG, "原生导入：importFromExtractedOutputDir 完成，target=${targetOutput.absolutePath}")
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                FileLogger.e(TAG, "原生导入：importFromExtractedOutputDir 失败", e)
                runOnUiThread { result.error("import_failed", e.message, null) }
            }
        }.start()
    }

    private fun shouldSkipOutputCache(relLower: String): Boolean {
        if (relLower.isEmpty()) return false
        val parts = relLower.split('/').filter { it.isNotEmpty() }
        for (part in parts) {
            if (part in outputCacheDirTokens) return true
            if (part.startsWith("cache") || part.startsWith("tmp") || part.startsWith("temp")) return true
            if (part.contains("thumbnail")) return true
        }
        return false
    }

    private fun copyDirRecursively(source: File, destination: File, root: File) {
        val relative = computeRelativePath(root, source)
        val relLower = relative.lowercase()
        if (relative.isNotEmpty() && shouldSkipOutputCache(relLower)) {
            FileLogger.i(TAG, "原生导入：跳过缓存条目 $relative")
            return
        }
        if (source.isDirectory) {
            if (!destination.exists()) {
                destination.mkdirs()
            }
            val children = source.listFiles() ?: return
            for (child in children) {
                val destChild = File(destination, child.name)
                copyDirRecursively(child, destChild, root)
            }
        } else {
            val parent = destination.parentFile
            if (parent != null && !parent.exists()) {
                parent.mkdirs()
            }
            val buffer = ByteArray(256 * 1024)
            FileInputStream(source).use { ins ->
                FileOutputStream(destination).use { out ->
                    while (true) {
                        val read = ins.read(buffer)
                        if (read <= 0) break
                        out.write(buffer, 0, read)
                    }
                    out.flush()
                }
            }
        }
    }

    private fun normalizeImportRelativePath(raw: String): String {
        val sanitized = raw.replace("\\", "/").trimStart('/')
        if (sanitized.isEmpty()) return ""
        val parts = sanitized.split('/')
        val segments = ArrayList<String>()
        for (part in parts) {
            when {
                part.isEmpty() || part == "." -> continue
                part == ".." -> return ""
                else -> segments.add(part)
            }
        }
        return segments.joinToString("/")
    }

    private fun computeRelativePath(root: File, node: File): String {
        val rootPath = root.absolutePath
        val nodePath = node.absolutePath
        if (!nodePath.startsWith(rootPath)) return ""
        var rel = nodePath.substring(rootPath.length)
        if (rel.startsWith(File.separator)) {
            rel = rel.substring(1)
        }
        return rel.replace("\\", "/")
    }

    private fun runImportOcrBatch(filePaths: List<String>): Map<String, Any> {
        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        var processed = 0
        var updated = 0
        var empty = 0
        var failed = 0
        var missingFiles = 0
        val failureSamples = ArrayList<String>()
        try {
            for (rawPath in filePaths) {
                val filePath = rawPath.trim()
                if (filePath.isEmpty()) continue
                processed++
                try {
                    val file = File(filePath)
                    if (!file.exists()) {
                        missingFiles++
                        if (failureSamples.size < 20) {
                            failureSamples.add("missing_file: $filePath")
                        }
                        continue
                    }
                    val text = recognizeImportOcrText(filePath, recognizer)
                    val finalText = text?.trim()?.takeIf { it.isNotEmpty() }
                    ScreenshotDatabaseHelper.updateOcrTextByFilePath(
                        this,
                        filePath,
                        finalText
                    )
                    if (finalText != null) {
                        updated++
                    } else {
                        empty++
                    }
                } catch (e: Exception) {
                    failed++
                    if (failureSamples.size < 20) {
                        failureSamples.add("ocr_failed: $filePath :: ${e.message ?: "unknown"}")
                    }
                }
            }
        } finally {
            try { recognizer.close() } catch (_: Exception) {}
        }
        return mapOf(
            "processed" to processed,
            "updated" to updated,
            "empty" to empty,
            "failed" to failed,
            "missingFiles" to missingFiles,
            "failureSamples" to failureSamples
        )
    }

    private fun recognizeImportOcrText(
        filePath: String,
        recognizer: com.google.mlkit.vision.text.TextRecognizer
    ): String? {
        val bmp = BitmapFactory.decodeFile(filePath) ?: return null
        return try {
            val image = InputImage.fromBitmap(bmp, 0)
            val visionText = Tasks.await(recognizer.process(image))
            visionText?.text?.trim()?.takeIf { it.isNotEmpty() }
        } finally {
            try { bmp.recycle() } catch (_: Exception) {}
        }
    }

    private fun clearOutputCacheDirsNative(root: File) {
        if (!root.exists()) return
        clearOutputCacheDirsRecursive(root, "")
    }

    private fun clearOutputCacheDirsRecursive(current: File, relative: String) {
        val files = current.listFiles() ?: return
        for (child in files) {
            val childRel = if (relative.isEmpty()) child.name else "$relative/${child.name}"
            val relLower = childRel.lowercase()
            if (child.isDirectory && shouldSkipOutputCache(relLower)) {
                if (child.deleteRecursively()) {
                    FileLogger.i(TAG, "原生导入：已清理缓存目录 $childRel")
                } else {
                    FileLogger.e(TAG, "原生导入：删除缓存目录失败 $childRel")
                }
                continue
            }
            if (child.isDirectory) {
                clearOutputCacheDirsRecursive(child, childRel)
            }
        }
    }

    private fun deleteImportZipIfCached(path: String) {
        try {
            val cacheDirPath = cacheDir?.absolutePath ?: return
            if (!path.startsWith(cacheDirPath)) return
            val zipFile = File(path)
            if (zipFile.exists()) {
                zipFile.delete()
            }
            var parent = zipFile.parentFile
            while (parent != null && parent.absolutePath.startsWith(cacheDirPath)) {
                val children = parent.listFiles()
                if (children != null && children.isNotEmpty()) break
                parent.delete()
                parent = parent.parentFile
            }
            FileLogger.i(TAG, "原生导入：已删除缓存导入 zip：$path")
        } catch (e: Exception) {
            FileLogger.e(TAG, "原生导入：删除缓存 zip 失败 path=$path", e)
        }
    }

    /**
     * 递归将目录加入 Zip（原生实现，极致速度）
     * - rootDir：用于计算相对路径
     * - prefix：用于包含顶层目录名（例如 "output/"）
     * - 忽略 cache/tmp/.thumbnails 以及 SQLite 日志文件以提速（可按需调整）
     */
    private fun addDirectoryToZipNative(zipOut: ZipOutputStream, rootDir: File, dir: File, prefix: String) {
        val files = dir.listFiles() ?: return
        val buffer = ByteArray(256 * 1024)
        for (f in files) {
            val rel = rootDir.toURI().relativize(f.toURI()).path.replace("\\", "/")
            val relLower = rel.lowercase()
            // 忽略低价值文件/目录
            val head = relLower.substringBefore('/', "")
            if (head == "cache" || head == "tmp" || head == "temp" || head == ".thumbnails") continue
            // 保留 SQLite WAL/SHM 辅助文件，确保 WAL 模式数据库导出完整
            if (relLower.endsWith(".db-journal")) continue

            if (f.isDirectory) {
                // 目录条目可选写入，常规解压工具不强制需要；这里显式写入更完整
                val entryName = prefix + rel.trimEnd('/') + "/"
                val entry = ZipEntry(entryName)
                entry.time = f.lastModified()
                zipOut.putNextEntry(entry)
                zipOut.closeEntry()
                addDirectoryToZipNative(zipOut, rootDir, f, prefix)
            } else {
                val entryName = prefix + rel
                val entry = ZipEntry(entryName)
                entry.time = f.lastModified()
                zipOut.putNextEntry(entry)
                FileInputStream(f).use { ins ->
                    var read: Int
                    while (true) {
                        read = ins.read(buffer)
                        if (read <= 0) break
                        zipOut.write(buffer, 0, read)
                    }
                }
                zipOut.closeEntry()
            }
        }
    }

    private fun switchLauncherAliasInternal(lang: String): Boolean {
        return try {
            val pm = packageManager
            val aliases = mapOf(
                "zh" to ComponentName(this, "$packageName.LauncherAliasZh"),
                "en" to ComponentName(this, "$packageName.LauncherAliasEn"),
                "ja" to ComponentName(this, "$packageName.LauncherAliasJa"),
                "ko" to ComponentName(this, "$packageName.LauncherAliasKo")
            )
            val langLower = lang.lowercase()
            val target = aliases[langLower] ?: aliases["en"]!!
            for ((code, component) in aliases) {
                val state = if (component == target)
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                pm.setComponentEnabledSetting(
                    component,
                    state,
                    android.content.pm.PackageManager.DONT_KILL_APP
                )
                try { FileLogger.i(TAG, "Launcher 别名状态已更新：lang=$code 启用=${component == target}") } catch (_: Exception) {}
            }
            true
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "切换Launcher别名异常", e) } catch (_: Exception) {}
            false
        }
    }

    private fun openDiagnosticFile(path: String, result: MethodChannel.Result) {
        try {
            val target = File(path)
            if (!target.exists()) {
                result.error("file_not_found", "File does not exist: $path", null)
                return
            }

            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                target,
            )
            val mimeType = when (target.extension.lowercase()) {
                "log", "txt", "json", "csv" -> "text/plain"
                "jpg", "jpeg" -> "image/jpeg"
                "png" -> "image/png"
                else -> "*/*"
            }

            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            try {
                startActivity(Intent.createChooser(viewIntent, "打开诊断文件"))
                result.success(true)
            } catch (_: Exception) {
                startActivity(Intent.createChooser(sendIntent, "分享诊断文件"))
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("open_diagnostic_file_failed", e.message, null)
        }
    }
}
