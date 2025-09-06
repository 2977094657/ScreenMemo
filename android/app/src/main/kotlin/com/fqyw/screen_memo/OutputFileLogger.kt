package com.fqyw.screen_memo

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 将日志输出到 app 外部私有目录：
 * <externalFiles>/output/logs/yyyy/MM/dd/{dd}_info.log 与 {dd}_error.log
 */
object OutputFileLogger {
    private const val TAG = "OutputFileLogger"

    private val dateDirFmt = SimpleDateFormat("yyyy/MM/dd", Locale.getDefault())
    private val dayFmt = SimpleDateFormat("dd", Locale.getDefault())
    private val tsFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())

    fun info(context: Context, tag: String, message: String) {
        write(context, false, tag, message)
    }

    fun error(context: Context, tag: String, message: String) {
        write(context, true, tag, message)
    }

    fun getTodayDir(context: Context): File? {
        return try {
            val base = context.getExternalFilesDir(null) ?: return null
            val dir = File(base, "output/logs/" + dateDirFmt.format(Date()))
            if (!dir.exists()) dir.mkdirs()
            dir
        } catch (_: Exception) { null }
    }

    private fun write(context: Context, isError: Boolean, tag: String, message: String) {
        try {
            val dir = getTodayDir(context) ?: return
            val day = dayFmt.format(Date())
            val name = if (isError) "${day}_error.log" else "${day}_info.log"
            val file = File(dir, name)
            val line = "${tsFmt.format(Date())} [${if (isError) "E" else "I"}] $tag: $message\n"
            FileWriter(file, true).use { it.write(line) }
        } catch (e: Exception) {
            Log.w(TAG, "write failed", e)
        }
    }
}

