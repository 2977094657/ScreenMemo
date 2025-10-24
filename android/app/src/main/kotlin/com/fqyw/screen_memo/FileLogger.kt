package com.fqyw.screen_memo

import android.content.Context
import android.util.Log
import java.io.File
import java.util.Locale

/**
 * 统一日志入口：控制台 + 本地文件（output/logs/yyyy/MM/dd/dd_info.log / dd_error.log）。
 */
object FileLogger {

    private const val TAG = "FileLogger"
    private var isInitialized = false

    // 日志级别：NONE(0) ERROR(1) WARN(2) INFO(3) DEBUG(4)
    private const val LEVEL_NONE = 0
    private const val LEVEL_ERROR = 1
    private const val LEVEL_WARNING = 2
    private const val LEVEL_INFO = 3
    private const val LEVEL_DEBUG = 4

    private val isDebugBuild: Boolean = try {
        // 优先使用应用 debuggable 标志；若不可用则回退到 Build.TYPE
        val flags = AppContextProvider.context()?.applicationInfo?.flags ?: 0
        (flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    } catch (_: Exception) {
        try {
            val type = android.os.Build.TYPE?.lowercase(Locale.getDefault()) ?: ""
            type.contains("debug") || type.contains("eng")
        } catch (_: Exception) { false }
    }

    // Debug 构建：DEBUG 级别并落盘；Release 构建：仅 ERROR 级别，且不落盘
    private var logLevel = if (isDebugBuild) LEVEL_DEBUG else LEVEL_ERROR
    private var writeFileEnabled = isDebugBuild

    // 模块化分类：general/ai/screenshot
    private const val CAT_GENERAL = "general"
    private const val CAT_AI = "ai"
    private const val CAT_SCREENSHOT = "screenshot"

    // 通过 tag -> category 的推断（尽量无侵入）
    private val aiTags = setOf("SegmentSummaryManager")
    private val screenshotTags = setOf("ScreenCaptureAccessibilityService", "ScreenCaptureService")

    // 分类开关（默认 false = 关闭；依赖 UI 开启）
    @Volatile private var categoryEnabled: MutableMap<String, Boolean> = mutableMapOf(
        CAT_AI to false,
        CAT_SCREENSHOT to false
    )

    fun init(context: Context) {
        // 仅标记初始化；输出文件由 OutputFileLogger 动态创建
        isInitialized = true
        try {
            OutputFileLogger.info(context, TAG, "FileLogger initialized")
        } catch (_: Exception) {}
    }

    fun d(tag: String, message: String) {
        if (!isAllowed(LEVEL_DEBUG, tag)) return
        Log.d(tag, message)
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.info(it, tag, message) }
        }
    }

    fun i(tag: String, message: String) {
        if (!isAllowed(LEVEL_INFO, tag)) return
        Log.i(tag, message)
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.info(it, tag, message) }
        }
    }

    fun w(tag: String, message: String) {
        if (!isAllowed(LEVEL_WARNING, tag)) return
        Log.w(tag, message)
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.info(it, tag, message) }
        }
    }

    fun e(tag: String, message: String, throwable: Throwable? = null) {
        if (!isAllowed(LEVEL_ERROR, tag)) return
        Log.e(tag, message, throwable)
        val full = if (throwable != null) "$message\n${Log.getStackTraceString(throwable)}" else message
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.error(it, tag, full) }
        }
    }

    fun isDebugEnabled(): Boolean = logLevel >= LEVEL_DEBUG
    fun setLevel(level: Int) { logLevel = level }
    fun enableFileLogging(enable: Boolean) { writeFileEnabled = enable }

    private fun inferCategory(tag: String): String {
        return when {
            aiTags.contains(tag) -> CAT_AI
            screenshotTags.contains(tag) -> CAT_SCREENSHOT
            else -> CAT_GENERAL
        }
    }

    private fun isAllowed(level: Int, tag: String): Boolean {
        if (logLevel < level) return false
        val cat = inferCategory(tag)
        // 分类已知时由分类开关决定；未知走全局文件开关
        val known = (cat == CAT_AI || cat == CAT_SCREENSHOT)
        val catOn = categoryEnabled[cat] == true
        return if (known) catOn else true
    }

    // 提供给 OutputFileLogger 的只读判定
    fun shouldWriteInfo(tag: String): Boolean = isAllowed(LEVEL_INFO, tag)
    fun shouldWriteError(tag: String): Boolean = isAllowed(LEVEL_ERROR, tag)

    fun syncFromFlutterPrefs(context: Context) {
        try {
            val sp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val any = sp.all["logging_enabled"]
            val enabled = when (any) {
                is Boolean -> any
                is String -> any.equals("true", ignoreCase = true)
                is Int -> any != 0
                is Long -> any != 0L
                else -> sp.getBoolean("logging_enabled", true)
            }
            enableFileLogging(enabled)
            setLevel(if (enabled) LEVEL_DEBUG else LEVEL_NONE)
            // 分类开关
            val ai = sp.getBoolean("logging_ai_enabled", false)
            val shot = sp.getBoolean("logging_screenshot_enabled", false)
            categoryEnabled[CAT_AI] = ai
            categoryEnabled[CAT_SCREENSHOT] = shot
            try { OutputFileLogger.setEnabled(enabled) } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    fun setCategoryEnabled(context: Context, category: String, enabled: Boolean) {
        try {
            when (category) {
                CAT_AI -> categoryEnabled[CAT_AI] = enabled
                CAT_SCREENSHOT -> categoryEnabled[CAT_SCREENSHOT] = enabled
            }
            val sp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            when (category) {
                CAT_AI -> sp.edit().putBoolean("logging_ai_enabled", enabled).apply()
                CAT_SCREENSHOT -> sp.edit().putBoolean("logging_screenshot_enabled", enabled).apply()
            }
        } catch (_: Exception) {}
    }

    fun getLogFilePath(): String? {
        // 返回今日 info 文件路径，便于兼容旧接口
        val dir = AppContextProvider.context()?.let { OutputFileLogger.getTodayDir(it) } ?: return null
        val day = java.text.SimpleDateFormat("dd", java.util.Locale.getDefault()).format(java.util.Date())
        return File(dir, "${day}_info.log").absolutePath
    }

    fun clearLog() {
        try {
            val ctx = AppContextProvider.context() ?: return
            val dir = OutputFileLogger.getTodayDir(ctx) ?: return
            val day = java.text.SimpleDateFormat("dd", java.util.Locale.getDefault()).format(java.util.Date())
            listOf("${day}_info.log", "${day}_error.log").forEach { name ->
                try { File(dir, name).delete() } catch (_: Exception) {}
            }
            OutputFileLogger.info(ctx, TAG, "logs cleared for today")
        } catch (e: Exception) {
            Log.e(TAG, "clearLog failed", e)
        }
    }

    fun writeSeparator(title: String = "") {
        if (!writeFileEnabled) return
        val line = if (title.isNotEmpty()) "=== $title ===" else "=========================="
        AppContextProvider.context()?.let { OutputFileLogger.info(it, TAG, line) }
    }

    fun writeSystemInfo(context: Context) {
        if (!writeFileEnabled) return
        writeSeparator("系统信息")
        OutputFileLogger.info(context, TAG, "应用包名: ${context.packageName}")
        OutputFileLogger.info(context, TAG, "进程ID: ${android.os.Process.myPid()}")
        OutputFileLogger.info(context, TAG, "Android版本: ${android.os.Build.VERSION.RELEASE}")
        OutputFileLogger.info(context, TAG, "设备型号: ${android.os.Build.MODEL}")
        OutputFileLogger.info(context, TAG, "设备厂商: ${android.os.Build.MANUFACTURER}")
        writeSeparator()
    }
}

