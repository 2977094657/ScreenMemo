package com.fqyw.screen_memo.memory.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.OutputFileLogger
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Calendar
import java.io.File

class MemoryProcessingReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        FileLogger.init(context)
        val action = intent?.action
        try { OutputFileLogger.infoForce(context, TAG, "收到广播 action=$action") } catch (_: Exception) {}
        if (action != MemoryProcessingScheduler.ACTION_MEMORY_PROCESSING) {
            FileLogger.w(TAG, "忽略 action：$action")
            try { OutputFileLogger.infoForce(context, TAG, "忽略 action：$action") } catch (_: Exception) {}
            return
        }

        val appContext = context.applicationContext ?: context
        val cutoffMillis = resolveCutoffMillis()
        FileLogger.i(TAG, "触发记忆处理 截止=$cutoffMillis")
        try { OutputFileLogger.infoForce(appContext, TAG, "触发记忆处理 截止=$cutoffMillis") } catch (_: Exception) {}

        try {
            MemoryBackendService.startHistoricalProcessing(
                appContext,
                forceReprocess = false,
                targetEndExclusiveMillis = cutoffMillis
            )
        } catch (e: Exception) {
            FileLogger.e(TAG, "触发历史处理失败：${e.message}", e)
            try { OutputFileLogger.errorForce(appContext, TAG, "触发历史处理失败：${e.message}\n${e.stackTraceToString()}") } catch (_: Exception) {}
        }

        // 额外：若上周周总结尚未生成，则在每日调度时触发一轮周总结（原生执行，避免 Dart 定时器失效）
        try {
            enqueueWeeklySummaryIfDue(appContext)
        } catch (e: Exception) {
            FileLogger.e(TAG, "加入周总结队列失败：${e.message}", e)
            try { OutputFileLogger.errorForce(appContext, TAG, "加入周总结队列失败：${e.message}\n${e.stackTraceToString()}") } catch (_: Exception) {}
        }

        try {
            MemoryProcessingScheduler.scheduleNext(appContext)
        } catch (e: Exception) {
            FileLogger.e(TAG, "安排下一次记忆处理失败：${e.message}", e)
            try { OutputFileLogger.errorForce(appContext, TAG, "安排下一次记忆处理失败：${e.message}\n${e.stackTraceToString()}") } catch (_: Exception) {}
        }
    }

    private fun resolveCutoffMillis(): Long =
        try {
            val zone = ZoneId.systemDefault()
            val today = LocalDate.now(zone)
            today.atStartOfDay(zone).toInstant().toEpochMilli()
        } catch (_: Exception) {
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            cal.timeInMillis
        }

    companion object {
        private const val TAG = "MemoryProcessingReceiver"
        private const val MASTER_DB_DIR_RELATIVE = "output/databases"
        private const val MASTER_DB_FILE_NAME = "screenshot_memo.db"
        private val DATE_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

        /**
         * 计算“刚刚结束的周”的起始日（周一）并触发原生周总结 Worker。
         * - 若已生成则跳过（SharedPreferences: weekly_summary_last_generated_week）
         * - 以昨日所属周为基准，确保即便错过周一0点也能在后续日子补生成
         */
        @JvmStatic
        fun enqueueWeeklySummaryIfDue(context: Context) {
            val zone = ZoneId.systemDefault()
            val today = LocalDate.now(zone)

            var db: SQLiteDatabase? = null
            try {
                db = openMasterDb(context, writable = false)
                if (db == null) {
                    try { OutputFileLogger.errorForce(context, TAG, "openMasterDb 返回 null；跳过周总结") } catch (_: Exception) {}
                    return
                }

                val anchor = resolveWeeklyAnchor(db, zone)
                if (anchor == null) {
                    try { OutputFileLogger.infoForce(context, TAG, "未找到周总结锚点；跳过") } catch (_: Exception) {}
                    return
                }

                val daysFromAnchorToToday = ChronoUnit.DAYS.between(anchor, today)
                if (daysFromAnchorToToday < 7) {
                    return
                }
                val completedBlocks = (daysFromAnchorToToday / 7)
                if (completedBlocks <= 0) {
                    return
                }
                val weekStart = anchor.plusDays((completedBlocks - 1) * 7)
                val weekEnd = weekStart.plusDays(6)
                val weekStartKey = weekStart.format(DATE_FMT)

                val prefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                val lastGenerated = prefs.getString("weekly_summary_last_generated_week", null)
                if (lastGenerated != null && lastGenerated == weekStartKey) {
                    return
                }

                WeeklySummaryWorker.enqueueOnce(context.applicationContext, weekStartKey)
                FileLogger.i(TAG, "周总结已入队 weekStart=$weekStartKey (end=${weekEnd.format(DATE_FMT)})")
                try { OutputFileLogger.infoForce(context, TAG, "周总结已入队 weekStart=$weekStartKey") } catch (_: Exception) {}
            } catch (e: Exception) {
                FileLogger.e(TAG, "计算需要生成的周总结失败：${e.message}", e)
                try { OutputFileLogger.errorForce(context, TAG, "计算需要生成的周总结失败：${e.message}\n${e.stackTraceToString()}") } catch (_: Exception) {}
            } finally {
                try { db?.close() } catch (_: Exception) {}
            }
        }

        private fun openMasterDb(context: Context, writable: Boolean): SQLiteDatabase? {
            return try {
                val base = context.filesDir.absolutePath
                val dbDir = File(base, MASTER_DB_DIR_RELATIVE)
                if (!dbDir.exists()) dbDir.mkdirs()
                val path = File(dbDir, MASTER_DB_FILE_NAME).absolutePath
                if (writable) {
                    SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY)
                } else {
                    SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY)
                }
            } catch (e: Exception) {
                try { FileLogger.w(TAG, "openMasterDb 失败：${e.message}") } catch (_: Exception) {}
                null
            }
        }

        private fun resolveWeeklyAnchor(db: SQLiteDatabase, zone: ZoneId): LocalDate? {
            try {
                db.rawQuery("SELECT MIN(week_start_date) FROM weekly_summaries", null)?.use { c ->
                    if (c.moveToFirst()) {
                        val key = c.getString(0)
                        if (!key.isNullOrBlank()) {
                            return try { LocalDate.parse(key, DATE_FMT) } catch (_: Exception) { null }
                        }
                    }
                }
            } catch (_: Exception) {}

            try {
                db.rawQuery("SELECT MIN(date_key) FROM daily_summaries", null)?.use { c ->
                    if (c.moveToFirst()) {
                        val key = c.getString(0)
                        if (!key.isNullOrBlank()) {
                            return try { LocalDate.parse(key, DATE_FMT) } catch (_: Exception) { null }
                        }
                    }
                }
            } catch (_: Exception) {}

            try {
                db.rawQuery("SELECT MIN(start_time) FROM segments", null)?.use { c ->
                    if (c.moveToFirst()) {
                        val millis = if (c.isNull(0)) null else c.getLong(0)
                        if (millis != null && millis > 0) {
                            return try {
                                java.time.Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
                            } catch (_: Exception) {
                                null
                            }
                        }
                    }
                }
            } catch (_: Exception) {}

            return null
        }
    }
}

