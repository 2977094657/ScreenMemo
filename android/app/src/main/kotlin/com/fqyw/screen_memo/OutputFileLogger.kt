package com.fqyw.screen_memo

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue

/**
 * 将日志输出到 app 外部私有目录（异步落盘）：
 * 路径：<externalFiles>/output/logs/yyyy/MM/dd/{dd}_info.log 与 {dd}_error.log
 *
 * 变更点：
 * - 改为单线程后台写入，主线程仅入队，避免冷启动/首帧阶段 I/O 阻塞造成“无法点击/ANR”
 * - 有界队列 + 丢弃限流，防止异常场景下内存膨胀
 */
object OutputFileLogger {
    private const val TAG = "OutputFileLogger"

    private val dateDirFmt = SimpleDateFormat("yyyy/MM/dd", Locale.getDefault())
    private val dayFmt = SimpleDateFormat("dd", Locale.getDefault())
    private val tsFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())

    private const val MAX_QUEUE_CAPACITY = 4096
    private val queue = LinkedBlockingQueue<LogItem>(MAX_QUEUE_CAPACITY)

    @Volatile
    private var workerStarted = false

    @Volatile
    private var lastDropWarnAt = 0L

    private data class LogItem(
        val appContext: Context,
        val isError: Boolean,
        val tag: String,
        val message: String,
        val ts: Long = System.currentTimeMillis()
    )

    fun info(context: Context, tag: String, message: String) {
        enqueue(context, false, tag, message)
    }

    fun error(context: Context, tag: String, message: String) {
        enqueue(context, true, tag, message)
    }

    /**
     * 获取“今天”的日志目录（按 yyyy/MM/dd 分桶）
     */
    fun getTodayDir(context: Context): File? {
        return try {
            val base = context.getExternalFilesDir(null) ?: return null
            val dir = File(base, "output/logs/" + dateDirFmt.format(Date()))
            if (!dir.exists()) dir.mkdirs()
            dir
        } catch (_: Exception) { null }
    }

    /**
     * 入队一条日志，主线程快速返回；若队列已满，将节流输出一次丢弃告警。
     */
    private fun enqueue(context: Context, isError: Boolean, tag: String, message: String) {
        try {
            ensureWorker()
            val appCtx = context.applicationContext
            val offered = queue.offer(LogItem(appCtx, isError, tag, message))
            if (!offered) {
                val now = System.currentTimeMillis()
                if (now - lastDropWarnAt >= 5000) {
                    lastDropWarnAt = now
                    Log.w(TAG, "log queue is full, dropping incoming logs")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "enqueue failed", e)
        }
    }

    /**
     * 启动单线程后台写入循环
     */
    @Synchronized
    private fun ensureWorker() {
        if (workerStarted) return
        val t = Thread({ writerLoop() }, "OutputFileLogger-Worker")
        t.isDaemon = true
        t.start()
        workerStarted = true
    }

    /**
     * 从队列批量取出日志并落盘；批处理可显著降低文件句柄开销
     */
    private fun writerLoop() {
        while (true) {
            try {
                // 阻塞等待至少一条
                val first = queue.take()
                val batch = mutableListOf(first)
                // 再尽量批量提取，单批最多 512 条
                queue.drainTo(batch, 512)
                writeBatch(batch)
            } catch (ie: InterruptedException) {
                // 保持为守护线程，忽略中断持续工作
                Thread.currentThread().interrupt()
            } catch (e: Exception) {
                Log.w(TAG, "writer loop error", e)
            }
        }
    }

    /**
     * 批量写入，按 info/error 分文件
     */
    private fun writeBatch(batch: List<LogItem>) {
        if (batch.isEmpty()) return

        // 使用首条的应用上下文获取目录（同包名、同私有区）
        val ctx = batch[0].appContext
        val dir = getTodayDir(ctx) ?: return

        val day = dayFmt.format(Date())
        val infoFile = File(dir, "${day}_info.log")
        val errorFile = File(dir, "${day}_error.log")

        var infoWriter: FileWriter? = null
        var errorWriter: FileWriter? = null
        try {
            for (item in batch) {
                val line = "${tsFmt.format(Date(item.ts))} [${if (item.isError) "E" else "I"}] ${item.tag}: ${item.message}\n"
                if (item.isError) {
                    if (errorWriter == null) errorWriter = FileWriter(errorFile, true)
                    errorWriter!!.write(line)
                } else {
                    if (infoWriter == null) infoWriter = FileWriter(infoFile, true)
                    infoWriter!!.write(line)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "write batch failed", e)
        } finally {
            try { infoWriter?.flush(); infoWriter?.close() } catch (_: Exception) {}
            try { errorWriter?.flush(); errorWriter?.close() } catch (_: Exception) {}
        }
    }
}

