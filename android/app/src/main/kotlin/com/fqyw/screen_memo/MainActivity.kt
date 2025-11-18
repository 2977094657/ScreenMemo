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
import android.util.TypedValue
import android.app.Dialog
import android.graphics.BitmapFactory
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipOutputStream
import java.util.zip.ZipEntry
import java.util.zip.Deflater
import com.fqyw.screen_memo.OutputFileLogger
import com.fqyw.screen_memo.memory.bridge.MemoryBridge
import com.fqyw.screen_memo.memory.service.MemoryBackendService

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
    private var memoryBridge: MemoryBridge? = null
    
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
        FileLogger.d(TAG, "configureFlutterEngine: minimal init start")

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
                    FileLogger.e(TAG, "=== 收到startScreenCapture请求 ===")
                    val success = startScreenCapture()
                    FileLogger.e(TAG, "=== startScreenCapture结果: $success ===")
                    result.success(success)
                }
                "stopScreenCapture" -> {
                    FileLogger.e(TAG, "=== 收到stopScreenCapture请求 ===")
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
                    FileLogger.e(TAG, "=== 收到startTimedScreenshot请求，间隔: ${interval}秒 ===")
                    val success = startTimedScreenshot(interval)
                    FileLogger.e(TAG, "=== startTimedScreenshot结果: $success ===")
                    result.success(success)
                }
                "stopTimedScreenshot" -> {
                    FileLogger.e(TAG, "=== 收到stopTimedScreenshot请求 ===")
                    stopTimedScreenshot()
                    result.success(null)
                }
                "captureScreen" -> {
                    FileLogger.e(TAG, "=== 收到captureScreen请求 ===")
                    val filePath = captureScreen()
                    FileLogger.e(TAG, "=== captureScreen结果: $filePath ===")
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
                    try {
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
                        val exportResult = exportFileToDownloadsInternal(src, name, subDir)
                        result.success(exportResult)
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "导出文件到下载目录失败", e)
                        result.error("export_failed", e.message, null)
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
                "insertScreenshotRecord" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: ""
                    val filePath = call.argument<String>("filePath") ?: ""
                    val captureTime = call.argument<Long>("captureTime") ?: System.currentTimeMillis()
                    
                    FileLogger.i(TAG, "收到截图记录插入请求: $appName - $filePath")
                    
                    // 通知Flutter端插入数据库记录
                    methodChannel.invokeMethod("onScreenshotSaved", mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "filePath" to filePath,
                        "captureTime" to captureTime
                    ))
                    
                    result.success(true)
                }
                "testAutoStartPermission" -> {
                    result.success(testAutoStartPermission())
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
                "triggerSegmentTick" -> {
                    try {
                        Thread {
                            try {
                                SegmentSummaryManager.tick(this)
                            } catch (e: Exception) {
                                FileLogger.w(TAG, "manual tick failed: ${e.message}")
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
                        try { FileLogger.i(TAG, "retrySegments: ids=${ids} force=${force}") } catch (_: Exception) {}
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
                "showSimpleNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Daily Summary"
                        val message = call.argument<String>("message") ?: ""
                        try { FileLogger.i(TAG, "showSimpleNotification: title=${title}, len=${message.length}") } catch (_: Exception) {}
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
                        try { FileLogger.i(TAG, "showNotification(bigText): title=${title}, len=${message.length}") } catch (_: Exception) {}
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
                        try { FileLogger.i(TAG, "scheduleDailySummaryNotification: enabled=${enabled} hour=${hour} minute=${minute} result=${ok}") } catch (_: Exception) {}
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
                        try { FileLogger.i(TAG, "setDailyBrief: dateKey=$dateKey len=${brief.length}") } catch (_: Exception) {}
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

        // 启用原生记忆系统桥接，提供 MethodChannel/EventChannel
        memoryBridge?.dispose()
        memoryBridge = MemoryBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        // 其余重任务延迟到首帧后执行
        FileLogger.d(TAG, "configureFlutterEngine: minimal init done, waiting first frame")

        // 保留兼容：若是仅检查服务的启动，立即结束，避免叠加界面
        if (intent?.getBooleanExtra("check_service_only", false) == true) {
            FileLogger.e(TAG, "静默启动模式，仅检查服务")
            finish()
            return
        }

        FileLogger.d(TAG, "configureFlutterEngine: completed")
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
        FileLogger.d(TAG, "onFlutterUiDisplayed: first frame delta since onCreate = ${delta}ms; runPostFirstFrameInit start")
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

            // 启动本地记忆后端服务，确保事件解析在原生层运行
            try {
                MemoryBackendService.start(applicationContext)
            } catch (e: Exception) {
                FileLogger.w(TAG, "启动 MemoryBackendService 失败: ${e.message}")
            }

            val t1 = System.currentTimeMillis()
            FileLogger.init(this)
            FileLogger.writeSystemInfo(this)
            FileLogger.e(TAG, "步骤: FileLogger.init + writeSystemInfo -> ${System.currentTimeMillis() - t1}ms")

            // 设置无障碍权限监听
            val t2 = System.currentTimeMillis()
            setupAccessibilityObserver()
            FileLogger.e(TAG, "步骤: setupAccessibilityObserver -> ${System.currentTimeMillis() - t2}ms")

            // 设置广播接收器
            val t3 = System.currentTimeMillis()
            setupMediaProjectionRequestReceiver()
            FileLogger.e(TAG, "步骤: setupMediaProjectionRequestReceiver -> ${System.currentTimeMillis() - t3}ms")
            val t4 = System.currentTimeMillis()
            setupScreenshotSavedReceiver()
            FileLogger.e(TAG, "步骤: setupScreenshotSavedReceiver -> ${System.currentTimeMillis() - t4}ms")

            // 启动辅助功能状态监听
            val t5 = System.currentTimeMillis()
            accessibilityStateMonitor = AccessibilityStateMonitor(this)
            accessibilityStateMonitor?.startMonitoring()
            FileLogger.e(TAG, "步骤: AccessibilityStateMonitor.startMonitoring -> ${System.currentTimeMillis() - t5}ms")

            // 调试监控与状态检查
            try {
                val t6 = System.currentTimeMillis()
                ServiceDebugHelper.performFullStatusCheck(this)
                FileLogger.e(TAG, "步骤: ServiceDebugHelper.performFullStatusCheck -> ${System.currentTimeMillis() - t6}ms")
            } catch (e: Exception) {
                FileLogger.e(TAG, "调试监控执行失败", e)
            }

            // 调度JobService保活
            val t7 = System.currentTimeMillis()
            scheduleKeepAliveJob()
            FileLogger.e(TAG, "步骤: scheduleKeepAliveJob -> ${System.currentTimeMillis() - t7}ms")

            // 已取消：守护服务前台通知会造成重复提示，仅保留前台截图服务通知
            // val t8 = System.currentTimeMillis()
            // startDaemonService()
            // FileLogger.e(TAG, "步骤: startDaemonService -> ${System.currentTimeMillis() - t8}ms")

            // 绑定AccessibilityService
            val t9 = System.currentTimeMillis()
            bindAccessibilityService()
            FileLogger.e(TAG, "步骤: bindAccessibilityService -> ${System.currentTimeMillis() - t9}ms")

            FileLogger.e(TAG, "=== PostFirstFrame 初始化完成，耗时: ${System.currentTimeMillis() - startMs}ms ===")
        } catch (e: Exception) {
            FileLogger.e(TAG, "PostFirstFrame 初始化失败", e)
            try { FileLogger.e(TAG, "PostFirstFrame 初始化失败", e) } catch (_: Exception) {}
        }
    }
    
    private fun handleLaunchFromNotification(i: Intent?) {
        try {
            val it = i ?: return
            val from = it.getBooleanExtra("from_daily_summary_notification", false)
            if (!from) return
            val dateKey = it.getStringExtra("daily_summary_date_key") ?: ""
            try { FileLogger.i(TAG, "handleLaunchFromNotification: from=true dateKey=$dateKey") } catch (_: Exception) {}
            try {
                methodChannel.invokeMethod("onDailySummaryNotificationTap", mapOf("dateKey" to dateKey))
            } catch (e: Exception) {
                try { FileLogger.w(TAG, "invoke onDailySummaryNotificationTap failed: ${e.message}") } catch (_: Exception) {}
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
                    FileLogger.e(TAG, "调用AccessibilityService.startTimedScreenshot")
                    val result = waitedService.startTimedScreenshot(intervalSeconds)
                    FileLogger.e(TAG, "AccessibilityService.startTimedScreenshot返回: $result")
                    return result
                } else {
                    FileLogger.e(TAG, "等待超时，服务实例仍不可用")
                    return false
                }
            }

            if (service != null) {
                FileLogger.e(TAG, "调用AccessibilityService.startTimedScreenshot")
                val result = service.startTimedScreenshot(intervalSeconds)
                FileLogger.e(TAG, "AccessibilityService.startTimedScreenshot返回: $result")
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

        memoryBridge?.dispose()
        memoryBridge = null
        
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

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                put(MediaStore.MediaColumns.RELATIVE_PATH, if (targetSubDir.isNotEmpty()) Environment.DIRECTORY_DOWNLOADS + "/" + targetSubDir else Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Failed to create item in MediaStore")

            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(sourceFile).use { input -> input.copyTo(out) }
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
        } else {
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val targetDir = if (targetSubDir.isNotEmpty()) File(downloadsDir, targetSubDir) else downloadsDir
            if (!targetDir.exists()) targetDir.mkdirs()
            val dest = File(targetDir, displayName)

            FileInputStream(sourceFile).use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
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
            if (relLower.endsWith(".db-wal") || relLower.endsWith(".db-shm") || relLower.endsWith(".db-journal")) continue

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
                try { FileLogger.i(TAG, "Launcher alias state updated lang=$code enabled=${component == target}") } catch (_: Exception) {}
            }
            true
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "切换Launcher别名异常", e) } catch (_: Exception) {}
            false
        }
    }
}
