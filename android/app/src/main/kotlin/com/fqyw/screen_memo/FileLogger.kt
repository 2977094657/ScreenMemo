package com.fqyw.screen_memo

import android.content.Context
import android.os.Environment
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.*

/**
 * 文件日志记录器
 * 将日志同时输出到控制台和文件
 */
object FileLogger {
    
    private const val TAG = "FileLogger"
    private const val LOG_FILE_NAME = "screen_memo_debug.log"
    private var logFile: File? = null
    private var isInitialized = false
    // 日志级别：NONE(0) ERROR(1) WARN(2) INFO(3) DEBUG(4)
    private const val LEVEL_NONE = 0
    private const val LEVEL_ERROR = 1
    private const val LEVEL_WARNING = 2
    private const val LEVEL_INFO = 3
    private const val LEVEL_DEBUG = 4
    // 安全的 DEBUG 判定：基于构建类型/ro.build.type
    private val isDebugBuild: Boolean = try {
        val type = android.os.Build.TYPE?.lowercase(Locale.getDefault()) ?: ""
        type.contains("debug") || type.contains("eng")
    } catch (_: Exception) { false }
    private var logLevel = if (isDebugBuild) LEVEL_DEBUG else LEVEL_ERROR
    private var writeFileEnabled = isDebugBuild
    
    /**
     * 初始化文件日志
     */
    fun init(context: Context) {
        try {
            // 使用应用的外部文件目录
            val logDir = File(context.getExternalFilesDir(null), "logs")
            if (!logDir.exists()) {
                logDir.mkdirs()
            }
            
            logFile = File(logDir, LOG_FILE_NAME)
            
            // 如果文件太大，清空它
            if (logFile?.exists() == true && logFile?.length()!! > 5 * 1024 * 1024) { // 5MB
                logFile?.delete()
            }
            
            isInitialized = true
            
            // 写入初始化信息（仅在启用文件写入时）
            if (writeFileEnabled) {
                writeToFile("=== FileLogger 初始化成功 ===")
                writeToFile("日志文件路径: ${logFile?.absolutePath}")
                writeToFile("初始化时间: ${getCurrentTimestamp()}")
                writeToFile("进程ID: ${android.os.Process.myPid()}")
                writeToFile("===============================")
            }
            
            Log.e(TAG, "FileLogger 初始化成功，日志文件: ${logFile?.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "FileLogger 初始化失败", e)
        }
    }
    
    /**
     * 记录调试日志
     */
    fun d(tag: String, message: String) {
        if (logLevel < LEVEL_DEBUG) return
        Log.d(tag, message)
        writeLog("D", tag, message)
    }
    
    /**
     * 记录信息日志
     */
    fun i(tag: String, message: String) {
        if (logLevel < LEVEL_INFO) return
        Log.i(tag, message)
        writeLog("I", tag, message)
    }
    
    /**
     * 记录警告日志
     */
    fun w(tag: String, message: String) {
        if (logLevel < LEVEL_WARNING) return
        Log.w(tag, message)
        writeLog("W", tag, message)
    }
    
    /**
     * 记录错误日志
     */
    fun e(tag: String, message: String, throwable: Throwable? = null) {
        if (logLevel < LEVEL_ERROR) return
        Log.e(tag, message, throwable)
        val fullMessage = if (throwable != null) {
            "$message\n${Log.getStackTraceString(throwable)}"
        } else {
            message
        }
        writeLog("E", tag, fullMessage)
    }
    
    /**
     * 是否开启调试级别
     */
    fun isDebugEnabled(): Boolean {
        return logLevel >= LEVEL_DEBUG
    }
    
    /**
     * 设置日志级别
     */
    fun setLevel(level: Int) {
        logLevel = level
    }
    
    /**
     * 启用/禁用写入文件
     */
    fun enableFileLogging(enable: Boolean) {
        writeFileEnabled = enable
    }
    
    /**
     * 写入日志到文件
     */
    private fun writeLog(level: String, tag: String, message: String) {
        if (!isInitialized || !writeFileEnabled) return
        
        val timestamp = getCurrentTimestamp()
        val logEntry = "$timestamp [$level] $tag: $message"
        writeToFile(logEntry)
    }
    
    /**
     * 写入内容到文件
     */
    private fun writeToFile(content: String) {
        try {
            logFile?.let { file ->
                FileWriter(file, true).use { writer ->
                    writer.append(content)
                    writer.append("\n")
                    writer.flush()
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "写入日志文件失败", e)
        }
    }
    
    /**
     * 获取当前时间戳
     */
    private fun getCurrentTimestamp(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())
        return formatter.format(Date())
    }
    
    /**
     * 获取日志文件路径
     */
    fun getLogFilePath(): String? {
        return logFile?.absolutePath
    }
    
    /**
     * 清空日志文件
     */
    fun clearLog() {
        try {
            logFile?.delete()
            writeToFile("=== 日志已清空 ===")
            writeToFile("清空时间: ${getCurrentTimestamp()}")
            writeToFile("==================")
        } catch (e: Exception) {
            Log.e(TAG, "清空日志文件失败", e)
        }
    }
    
    /**
     * 写入分隔线
     */
    fun writeSeparator(title: String = "") {
        val separator = if (title.isNotEmpty()) {
            "=== $title ==="
        } else {
            "=========================="
        }
        writeToFile(separator)
    }
    
    /**
     * 写入系统信息
     */
    fun writeSystemInfo(context: Context) {
        writeSeparator("系统信息")
        writeToFile("应用包名: ${context.packageName}")
        writeToFile("进程ID: ${android.os.Process.myPid()}")
        writeToFile("Android版本: ${android.os.Build.VERSION.RELEASE}")
        writeToFile("设备型号: ${android.os.Build.MODEL}")
        writeToFile("设备厂商: ${android.os.Build.MANUFACTURER}")
        writeToFile("时间: ${getCurrentTimestamp()}")
        writeSeparator()
    }
}
