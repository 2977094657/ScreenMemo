package com.fqyw.screen_memo.logging
import android.content.Context
import android.util.Log
import com.elvishew.xlog.XLog
import com.elvishew.xlog.LogLevel
import com.elvishew.xlog.printer.file.FilePrinter
import com.elvishew.xlog.printer.file.backup.NeverBackupStrategy
import com.elvishew.xlog.printer.file.naming.FileNameGenerator
import com.elvishew.xlog.flattener.PatternFlattener
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
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
    private val yearDirRegex = Regex("^\\d{4}$")
    private val monthDayDirRegex = Regex("^\\d{2}$")

    private const val MAX_QUEUE_CAPACITY = 4096
    private const val DEFAULT_RETENTION_DAYS = 30
    private const val CLEANUP_INTERVAL_MS = 12L * 60L * 60L * 1000L
    private val queue = LinkedBlockingQueue<LogItem>(MAX_QUEUE_CAPACITY)

    @Volatile
    private var workerStarted = false

    @Volatile
    private var lastDropWarnAt = 0L

    @Volatile
    private var enabled = true

    @Volatile
    private var lastCleanupAt = 0L

    private val directWriteLock = Any()

    fun setEnabled(enable: Boolean) {
        enabled = enable
    }

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

    fun infoForce(context: Context, tag: String, message: String) {
        try { writeDirect(context, false, tag, message) } catch (_: Exception) {}
        enqueueForce(context, false, tag, message)
    }

    fun errorForce(context: Context, tag: String, message: String) {
        try { writeDirect(context, true, tag, message) } catch (_: Exception) {}
        enqueueForce(context, true, tag, message)
    }

    fun infoDiagnostic(context: Context, tag: String, message: String) {
        try { writeDirect(context, false, tag, message) } catch (_: Exception) {}
    }

    private fun writeDirect(context: Context, isError: Boolean, tag: String, message: String) {
        cleanupExpiredLogsIfNeeded(context)
        val ts = System.currentTimeMillis()
        val base = context.getExternalFilesDir(null) ?: return
        val dayKey = dateDirFmt.format(Date(ts))
        val dir = File(base, "output/logs/$dayKey")
        if (!dir.exists()) dir.mkdirs()

        val day = dayFmt.format(Date(ts))
        val suffix = if (isError) "error" else "info"
        val file = File(dir, "${day}_${suffix}.log")
        val level = if (isError) "ERROR" else "INFO"
        val line = "${tsFmt.format(Date(ts))} [$level] $tag: $message\n"
        synchronized(directWriteLock) {
            try {
                file.appendText(line, Charsets.UTF_8)
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    /**
     * 获取“今天”的日志目录（按 yyyy/MM/dd 分桶）
     */
    fun getTodayDir(context: Context): File? {
        return try {
            cleanupExpiredLogsIfNeeded(context)
            val base = context.getExternalFilesDir(null) ?: return null
            val dir = File(base, "output/logs/" + dateDirFmt.format(Date()))
            if (!dir.exists()) dir.mkdirs()
            dir
        } catch (_: Exception) { null }
    }

    fun cleanupExpiredLogsIfNeeded(
        context: Context,
        retentionDays: Int? = null,
        force: Boolean = false
    ) {
        try {
            val appCtx = safeAppContext(context)
            val now = System.currentTimeMillis()
            if (!force && now - lastCleanupAt < CLEANUP_INTERVAL_MS) return
            lastCleanupAt = now
            Thread(
                {
                    try {
                        cleanupExpiredLogs(appCtx, retentionDays)
                    } catch (t: Throwable) {
                        Log.w(TAG, "日志清理线程异常", t)
                    }
                },
                "OutputFileLogger-Cleanup"
            ).apply {
                isDaemon = true
                start()
            }
        } catch (e: Exception) {
            Log.w(TAG, "日志清理启动失败", e)
        }
    }

    /**
     * 入队一条日志，主线程快速返回；若队列已满，将节流输出一次丢弃告警。
     */
    private fun enqueue(context: Context, isError: Boolean, tag: String, message: String) {
        try {
            cleanupExpiredLogsIfNeeded(context)
            if (!enabled) return
            // 分类/级别门控：未放行则不入队
            try {
                val allowed = if (isError) FileLogger.shouldWriteError(tag) else FileLogger.shouldWriteInfo(tag)
                if (!allowed) return
            } catch (_: Exception) {}
            ensureWorker()
            val appCtx = safeAppContext(context)
            val offered = queue.offer(LogItem(appCtx, isError, tag, message))
            if (!offered) {
                val now = System.currentTimeMillis()
                if (now - lastDropWarnAt >= 5000) {
                    lastDropWarnAt = now
                    Log.w(TAG, "日志队列已满，丢弃新日志")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "入队失败", e)
        }
    }

    private fun enqueueForce(context: Context, isError: Boolean, tag: String, message: String) {
        try {
            ensureWorker()
            val appCtx = safeAppContext(context)
            val offered = queue.offer(LogItem(appCtx, isError, tag, message))
            if (!offered) {
                val now = System.currentTimeMillis()
                if (now - lastDropWarnAt >= 5000) {
                    lastDropWarnAt = now
                    Log.w(TAG, "日志队列已满，丢弃新日志")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "强制入队失败", e)
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
                Log.w(TAG, "写入线程异常", e)
            }
        }
    }

    /**
     * 批量写入，按 info/error 分文件
     */
    private fun writeBatch(batch: List<LogItem>) {
        if (batch.isEmpty()) return
        try {
            for (item in batch) {
                val filePrinter = ensureFilePrinter(item.appContext, item.ts)
                val level = if (item.isError) LogLevel.ERROR else LogLevel.INFO
                try { filePrinter.println(level, item.tag, item.message) } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            Log.w(TAG, "批量写入失败", e)
        }
    }

    @Volatile
    private var currentDayKey: String? = null
    @Volatile
    private var currentPrinter: FilePrinter? = null

    private fun ensureFilePrinter(context: Context, timestamp: Long): FilePrinter {
        cleanupExpiredLogsIfNeeded(context)
        val dayKey = dateDirFmt.format(Date(timestamp)) // yyyy/MM/dd
        val existing = currentPrinter
        if (existing != null && currentDayKey == dayKey) return existing

        // 构建按天目录：<externalFiles>/output/logs/yyyy/MM/dd
        val base = context.getExternalFilesDir(null) ?: throw IllegalStateException("no external files dir")
        val dir = File(base, "output/logs/$dayKey")
        if (!dir.exists()) dir.mkdirs()

        val printer = FilePrinter.Builder(dir.absolutePath)
            .fileNameGenerator(object : FileNameGenerator {
                override fun generateFileName(logLevel: Int, timestamp: Long): String {
                    val day = dayFmt.format(Date(timestamp))
                    val suffix = if (logLevel >= LogLevel.ERROR) "error" else "info"
                    return "${day}_${suffix}.log"
                }
                override fun isFileNameChangeable(): Boolean {
                    // 文件名依赖于时间戳（按天）与级别，属于可变
                    return true
                }
            })
            .backupStrategy(NeverBackupStrategy())
            .flattener(PatternFlattener("{d yyyy-MM-dd HH:mm:ss.SSS} [{l}] {t}: {m}"))
            .build()

        currentDayKey = dayKey
        currentPrinter = printer
        return printer
    }

    private fun cleanupExpiredLogs(context: Context, retentionDays: Int?) {
        try {
            val days = (retentionDays ?: UserSettingsStorage.getInt(
                context,
                UserSettingsKeysNative.LOG_RETENTION_DAYS,
                DEFAULT_RETENTION_DAYS
            )).coerceAtLeast(1)
            val base = context.getExternalFilesDir(null) ?: return
            val logsRoot = File(base, "output/logs")
            if (!logsRoot.exists() || !logsRoot.isDirectory) return
            val cutoff = startOfTodayMillis() - (days.toLong() * 24L * 60L * 60L * 1000L)

            logsRoot.listFiles()
                ?.filter { it.isDirectory && yearDirRegex.matches(it.name) }
                ?.forEach { yearDir ->
                    yearDir.listFiles()
                        ?.filter { it.isDirectory && monthDayDirRegex.matches(it.name) }
                        ?.forEach { monthDir ->
                            monthDir.listFiles()
                                ?.filter { it.isDirectory && monthDayDirRegex.matches(it.name) }
                                ?.forEach { dayDir ->
                                    val dayStart = parseDayStartMillis(
                                        yearDir.name,
                                        monthDir.name,
                                        dayDir.name
                                    ) ?: return@forEach
                                    if (dayStart < cutoff) {
                                        try {
                                            dayDir.deleteRecursively()
                                        } catch (e: Exception) {
                                            Log.w(TAG, "删除过期日志目录失败: ${dayDir.absolutePath}", e)
                                        }
                                    }
                                }
                            deleteIfEmpty(monthDir)
                        }
                    deleteIfEmpty(yearDir)
                }
        } catch (e: Exception) {
            Log.w(TAG, "日志清理失败", e)
        }
    }

    private fun startOfTodayMillis(): Long {
        return Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    private fun parseDayStartMillis(year: String, month: String, day: String): Long? {
        val y = year.toIntOrNull() ?: return null
        val m = month.toIntOrNull() ?: return null
        val d = day.toIntOrNull() ?: return null
        return try {
            Calendar.getInstance().apply {
                isLenient = false
                clear()
                set(Calendar.YEAR, y)
                set(Calendar.MONTH, m - 1)
                set(Calendar.DAY_OF_MONTH, d)
            }.timeInMillis
        } catch (_: Exception) {
            null
        }
    }

    private fun deleteIfEmpty(dir: File) {
        try {
            if (dir.isDirectory && dir.listFiles()?.isEmpty() == true) {
                dir.delete()
            }
        } catch (_: Exception) {}
    }

    private fun safeAppContext(context: Context): Context {
        return try {
            context.applicationContext ?: context
        } catch (_: Exception) {
            context
        }
    }
}
