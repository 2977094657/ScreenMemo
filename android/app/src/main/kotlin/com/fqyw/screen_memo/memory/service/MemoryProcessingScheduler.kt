package com.fqyw.screen_memo.memory.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.OutputFileLogger
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

            try { OutputFileLogger.infoForce(context, TAG, "scheduleNext：当前=$nowMillis 触发时间=$triggerAt") } catch (_: Exception) {}

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
            } catch (e: Exception) {
                FileLogger.w(TAG, "精确闹钟调度失败：${e.message}")
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                    } else {
                        alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                    }
                    scheduled = true
                } catch (ignored: Exception) {
                    FileLogger.e(TAG, "兜底调度失败：${ignored.message}", ignored)
                }
            }

            if (scheduled) {
                FileLogger.i(TAG, "下一次记忆处理已安排于 ${logTime(triggerAt)}")
                try { OutputFileLogger.infoForce(context, TAG, "下一次记忆处理已安排于 ${logTime(triggerAt)}") } catch (_: Exception) {}
            }
            scheduled
        } catch (e: Exception) {
            FileLogger.e(TAG, "scheduleNext 遇到异常：${e.message}", e)
            try { OutputFileLogger.errorForce(context, TAG, "scheduleNext 遇到异常：${e.message}\n${e.stackTraceToString()}") } catch (_: Exception) {}
            false
        }
    }

    fun cancel(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val pendingIntent = buildPendingIntent(context)
            alarmManager.cancel(pendingIntent)
            FileLogger.i(TAG, "记忆处理闹钟已取消")
        } catch (e: Exception) {
            FileLogger.w(TAG, "取消失败：${e.message}")
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

