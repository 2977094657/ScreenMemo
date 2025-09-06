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
        val type = android.os.Build.TYPE?.lowercase(Locale.getDefault()) ?: ""
        type.contains("debug") || type.contains("eng")
    } catch (_: Exception) { false }

    private var logLevel = if (isDebugBuild) LEVEL_DEBUG else LEVEL_INFO
    private var writeFileEnabled = true

    fun init(context: Context) {
        // 仅标记初始化；输出文件由 OutputFileLogger 动态创建
        isInitialized = true
        try {
            OutputFileLogger.info(context, TAG, "FileLogger initialized")
        } catch (_: Exception) {}
    }

    fun d(tag: String, message: String) {
        if (logLevel < LEVEL_DEBUG) return
        Log.d(tag, message)
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.info(it, tag, message) }
        }
    }

    fun i(tag: String, message: String) {
        if (logLevel < LEVEL_INFO) return
        Log.i(tag, message)
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.info(it, tag, message) }
        }
    }

    fun w(tag: String, message: String) {
        if (logLevel < LEVEL_WARNING) return
        Log.w(tag, message)
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.info(it, tag, message) }
        }
    }

    fun e(tag: String, message: String, throwable: Throwable? = null) {
        if (logLevel < LEVEL_ERROR) return
        Log.e(tag, message, throwable)
        val full = if (throwable != null) "$message\n${Log.getStackTraceString(throwable)}" else message
        if (isInitialized && writeFileEnabled) {
            AppContextProvider.context()?.let { OutputFileLogger.error(it, tag, full) }
        }
    }

    fun isDebugEnabled(): Boolean = logLevel >= LEVEL_DEBUG
    fun setLevel(level: Int) { logLevel = level }
    fun enableFileLogging(enable: Boolean) { writeFileEnabled = enable }

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
        val line = if (title.isNotEmpty()) "=== $title ===" else "=========================="
        AppContextProvider.context()?.let { OutputFileLogger.info(it, TAG, line) }
    }

    fun writeSystemInfo(context: Context) {
        writeSeparator("系统信息")
        OutputFileLogger.info(context, TAG, "应用包名: ${context.packageName}")
        OutputFileLogger.info(context, TAG, "进程ID: ${android.os.Process.myPid()}")
        OutputFileLogger.info(context, TAG, "Android版本: ${android.os.Build.VERSION.RELEASE}")
        OutputFileLogger.info(context, TAG, "设备型号: ${android.os.Build.MODEL}")
        OutputFileLogger.info(context, TAG, "设备厂商: ${android.os.Build.MANUFACTURER}")
        writeSeparator()
    }
}

