package com.fqyw.screen_memo.memory.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.fqyw.screen_memo.FileLogger
import java.time.ZoneId
import java.time.LocalDate
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

    companion object {
        private const val TAG = "MemoryProcessingReceiver"
    }
}

