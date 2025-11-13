package com.fqyw.screen_memo.memory.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.fqyw.screen_memo.FileLogger
import java.time.Instant
import java.time.ZoneId

object MemoryProcessingScheduler {

    private const val TAG = "MemoryProcessingScheduler"
    const val ACTION_MEMORY_PROCESSING = "com.fqyw.screen_memo.memory.ACTION_PROCESS_DAILY"
    private const val REQUEST_CODE = 4101
    private const val TRIGGER_DELAY_MILLIS = 60_000L

    fun scheduleNext(context: Context, nowMillis: Long = System.currentTimeMillis()): Boolean {
        return try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return false
            val triggerAt = computeNextTrigger(nowMillis)
            val pendingIntent = buildPendingIntent(context)

            alarmManager.cancel(pendingIntent)

            var scheduled = false
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pendingIntent
                    )
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                }
                scheduled = true
            } catch (e: SecurityException) {
                FileLogger.w(TAG, "Exact alarm scheduling denied: ${e.message}")
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                    } else {
                        alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                    }
                    scheduled = true
                } catch (ignored: Exception) {
                    FileLogger.e(TAG, "Fallback scheduling failed: ${ignored.message}", ignored)
                }
            } catch (e: Exception) {
                FileLogger.e(TAG, "scheduleNext failed: ${e.message}", e)
            }

            if (scheduled) {
                FileLogger.i(TAG, "Next memory processing scheduled at ${logTime(triggerAt)}")
            }
            scheduled
        } catch (e: Exception) {
            FileLogger.e(TAG, "scheduleNext encountered error: ${e.message}", e)
            false
        }
    }

    fun cancel(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val pendingIntent = buildPendingIntent(context)
            alarmManager.cancel(pendingIntent)
            FileLogger.i(TAG, "Memory processing alarm cancelled")
        } catch (e: Exception) {
            FileLogger.w(TAG, "cancel failed: ${e.message}")
        }
    }

    private fun computeNextTrigger(nowMillis: Long): Long {
        val zone = ZoneId.systemDefault()
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val nextDay = now.toLocalDate().plusDays(1)
        val nextMidnight = nextDay.atStartOfDay(zone).toInstant().toEpochMilli()
        return nextMidnight + TRIGGER_DELAY_MILLIS
    }

    private fun buildPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MemoryProcessingReceiver::class.java).apply {
            action = ACTION_MEMORY_PROCESSING
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_CANCEL_CURRENT
        }
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }

    private fun logTime(triggerAt: Long): String {
        return try {
            val zone = ZoneId.systemDefault()
            Instant.ofEpochMilli(triggerAt).atZone(zone).toString()
        } catch (_: Exception) {
            triggerAt.toString()
        }
    }
}

