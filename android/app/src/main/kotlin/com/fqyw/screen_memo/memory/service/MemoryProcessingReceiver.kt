package com.fqyw.screen_memo.memory.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.fqyw.screen_memo.FileLogger
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.Calendar

class MemoryProcessingReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        FileLogger.init(context)
        val action = intent?.action
        if (action != MemoryProcessingScheduler.ACTION_MEMORY_PROCESSING) {
            FileLogger.w(TAG, "Ignored action: $action")
            return
        }

        val appContext = context.applicationContext ?: context
        val cutoffMillis = resolveCutoffMillis()
        FileLogger.i(TAG, "Trigger memory processing cutoff=$cutoffMillis")

        try {
            MemoryBackendService.startHistoricalProcessing(
                appContext,
                forceReprocess = false,
                targetEndExclusiveMillis = cutoffMillis
            )
        } catch (e: Exception) {
            FileLogger.e(TAG, "Failed to trigger historical processing: ${e.message}", e)
        }

        // 额外：若上周周总结尚未生成，则在每日调度时触发一轮周总结（原生执行，避免 Dart 定时器失效）
        try {
            enqueueWeeklySummaryIfDue(appContext)
        } catch (e: Exception) {
            FileLogger.e(TAG, "Failed to enqueue weekly summary: ${e.message}", e)
        }

        try {
            MemoryProcessingScheduler.scheduleNext(appContext)
        } catch (e: Exception) {
            FileLogger.e(TAG, "Failed to schedule next memory processing: ${e.message}", e)
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

    /**
     * 计算“刚刚结束的周”的起始日（周一）并触发原生周总结 Worker。
     * - 若已生成则跳过（SharedPreferences: weekly_summary_last_generated_week）
     * - 以昨日所属周为基准，确保即便错过周一0点也能在后续日子补生成
     */
    private fun enqueueWeeklySummaryIfDue(context: Context) {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val yesterday = today.minusDays(1)
        // 昨日所在周的周一
        val weekStart = yesterday.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val weekEnd = weekStart.plusDays(6)

        // 若昨日还未结束一周，则无需生成
        if (yesterday.isBefore(weekEnd)) return

        val weekStartKey = String.format("%04d-%02d-%02d", weekStart.year, weekStart.month.value, weekStart.dayOfMonth)
        val prefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
        val lastGenerated = prefs.getString("weekly_summary_last_generated_week", null)
        if (lastGenerated != null && lastGenerated == weekStartKey) {
            FileLogger.i(TAG, "Weekly summary already generated for $weekStartKey, skip")
            return
        }

        WeeklySummaryWorker.enqueueOnce(context.applicationContext, weekStartKey)
        prefs.edit().putString("weekly_summary_last_generated_week", weekStartKey).apply()
        FileLogger.i(TAG, "Weekly summary enqueued for weekStart=$weekStartKey (end=${String.format("%04d-%02d-%02d", weekEnd.year, weekEnd.month.value, weekEnd.dayOfMonth)})")
    }

    companion object {
        private const val TAG = "MemoryProcessingReceiver"
    }
}

