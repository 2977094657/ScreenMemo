package com.fqyw.screen_memo.memory.service

import com.fqyw.screen_memo.AppContextProvider
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 专用于记忆后端的独立日志文件（output/logs/memory_backend_yyyyMMdd.log）。
 * 记录 LLM 请求 / 响应等调试信息，避免与通用日志混淆。
 */
object MemoryBackendLogger {
    private val dayFormatter = SimpleDateFormat("yyyyMMdd", Locale.getDefault())
    private val tsFormatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())

    private val lock = Any()

    fun log(message: String) {
        val context = AppContextProvider.context() ?: return
        val base = context.getExternalFilesDir(null) ?: return
        val dir = File(base, "output/logs")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        val day = dayFormatter.format(Date())
        val file = File(dir, "memory_backend_$day.log")
        val line = "${tsFormatter.format(Date())} $message\n"
        synchronized(lock) {
            try {
                FileOutputStream(file, true).use { fos ->
                    OutputStreamWriter(fos, Charsets.UTF_8).use { writer ->
                        writer.write(line)
                        writer.flush()
                    }
                }
            } catch (_: Exception) {
            }
        }
    }
}

