package com.fqyw.screen_memo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.media.RingtoneManager
import android.media.AudioAttributes
import androidx.core.app.NotificationCompat
import java.util.Calendar
import java.util.Locale

/**
 * 每日总结提醒：通知显示 + 每日闹钟调度 + 广播接收
 * - 日志统一通过 FileLogger + OutputFileLogger
 * - Channel: "daily_summary"
 * - Alarm Action: "com.fqyw.screen_memo.ACTION_DAILY_SUMMARY"
 */
object DailySummaryNotifier {
    private const val TAG = "DailySummaryNotifier"
    private const val CHANNEL_ID = "daily_summary"
    private const val CHANNEL_ID_HIGH = "daily_summary_high"
    private const val CHANNEL_NAME = "每日总结提醒"
    private const val CHANNEL_DESC = "每天固定时间提醒查看/生成当日总结"
    private const val NOTIFICATION_ID = 20001

    fun showSimple(context: Context, title: String, message: String): Boolean {
        return try {
            val channelId = ensureChannelAndGetId(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val dk = try {
                val cal = Calendar.getInstance()
                String.format(
                    "%04d-%02d-%02d",
                    cal.get(Calendar.YEAR),
                    cal.get(Calendar.MONTH) + 1,
                    cal.get(Calendar.DAY_OF_MONTH)
                )
            } catch (e: Exception) { null }
            val pending = launchAppPendingIntent(context, dk)
            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setWhen(System.currentTimeMillis())
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                // heads-up 要素（O 以下）
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
            // 尝试提升为 heads-up（部分机型需要 fullScreenIntent 才弹横幅）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.setFullScreenIntent(pending, true)
            }
            nm.notify(NOTIFICATION_ID, builder.build())
            try { FileLogger.i(TAG, "showSimple: title=$title, len=${message.length}, channel=$channelId") } catch (_: Exception) {}
            true
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "showSimple failed: ${e.message}", e) } catch (_: Exception) {}
            false
        }
    }

    fun showBigText(context: Context, title: String, message: String): Boolean {
        return try {
            val channelId = ensureChannelAndGetId(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val dk = try {
                val cal = Calendar.getInstance()
                String.format(
                    "%04d-%02d-%02d",
                    cal.get(Calendar.YEAR),
                    cal.get(Calendar.MONTH) + 1,
                    cal.get(Calendar.DAY_OF_MONTH)
                )
            } catch (e: Exception) { null }
            val pending = launchAppPendingIntent(context, dk)
            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setContentTitle(title)
                .setContentText(message.take(80))
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setWhen(System.currentTimeMillis())
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.setFullScreenIntent(pending, true)
            }
            nm.notify(NOTIFICATION_ID, builder.build())
            try { FileLogger.i(TAG, "showBigText: title=$title, len=${message.length}, channel=$channelId") } catch (_: Exception) {}
            true
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "showBigText failed: ${e.message}", e) } catch (_: Exception) {}
            false
        }
    }

    /**
     * 确保存在高重要性渠道，并返回实际使用的渠道ID。
     * 若已有旧渠道且重要性不足，则创建一个新的高优先级渠道（daily_summary_high）用于 heads-up。
     */
    private fun ensureChannelAndGetId(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return CHANNEL_ID
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing == null) {
            createHighChannel(nm, CHANNEL_ID, CHANNEL_NAME)
            return CHANNEL_ID
        }
        return if (existing.importance < NotificationManager.IMPORTANCE_HIGH) {
            // 不能修改已存在渠道的重要性，创建新的高优先级渠道
            val alt = nm.getNotificationChannel(CHANNEL_ID_HIGH)
            if (alt == null) {
                createHighChannel(nm, CHANNEL_ID_HIGH, "$CHANNEL_NAME(高优先级)")
            }
            CHANNEL_ID_HIGH
        } else {
            CHANNEL_ID
        }
    }

    private fun createHighChannel(nm: NotificationManager, id: String, name: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH)
            ch.description = CHANNEL_DESC
            ch.enableLights(true)
            ch.lightColor = Color.BLUE
            ch.enableVibration(true)
            ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            try {
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                ch.setSound(soundUri, attrs)
                ch.vibrationPattern = longArrayOf(0, 250, 150, 250)
            } catch (_: Exception) {}
            nm.createNotificationChannel(ch)
            try { FileLogger.i(TAG, "create channel id=$id importance=HIGH") } catch (_: Exception) {}
        }
    }

    private fun launchAppPendingIntent(context: Context, dateKey: String?): PendingIntent {
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_daily_summary_notification", true)
            if (!dateKey.isNullOrBlank()) {
                putExtra("daily_summary_date_key", dateKey)
            }
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        return PendingIntent.getActivity(context, 2001, launch, flags)
    }
}

/**
 * 每日调度器：保存配置到 SharedPreferences，并用 AlarmManager 调度；
 * - setExactAndAllowWhileIdle 若不可用/失败则回退 setAndAllowWhileIdle
 * - 下次触发时机：若已过今日时刻，则安排明日
 */
object DailySummaryScheduler {
    private const val TAG = "DailySummaryScheduler"
    private const val PREF = "screen_memo_prefs"
    private const val KEY_ENABLED = "daily_summary_enabled"
    private const val KEY_HOUR = "daily_summary_hour"
    private const val KEY_MINUTE = "daily_summary_minute"
    const val ACTION_ALARM = "com.fqyw.screen_memo.ACTION_DAILY_SUMMARY"
    private const val REQUEST_CODE_SINGLE = 3001
    private const val REQUEST_CODE_SLOT_BASE = 3100
    const val EXTRA_SLOT_TYPE = "daily_slot_type"
    const val EXTRA_SLOT_INDEX = "daily_slot_index"
    const val SLOT_TYPE_USER = 0
    const val SLOT_TYPE_FIXED = 1
    private val FIXED_SLOTS = arrayOf(
        intArrayOf(8, 0),
        intArrayOf(12, 0),
        intArrayOf(17, 0),
        intArrayOf(22, 0),
    )

    fun schedule(context: Context, hour: Int, minute: Int): Boolean {
        return try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = buildBroadcastPendingIntent(context, REQUEST_CODE_SINGLE)

            val cal = Calendar.getInstance().apply {
                timeInMillis = System.currentTimeMillis()
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
                set(Calendar.MINUTE, minute.coerceIn(0, 59))
            }
            val trigger = if (cal.timeInMillis <= System.currentTimeMillis()) {
                cal.add(Calendar.DAY_OF_YEAR, 1); cal.timeInMillis
            } else cal.timeInMillis

            // 先取消再设定
            am.cancel(pi)

            var ok = false
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    am.setExact(AlarmManager.RTC_WAKEUP, trigger, pi)
                } else {
                    am.set(AlarmManager.RTC_WAKEUP, trigger, pi)
                }
                ok = true
            } catch (e: Exception) {
                try { FileLogger.w(TAG, "setExact failed, fallback setAndAllowWhileIdle: ${e.message}") } catch (_: Exception) {}
                try { am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi); ok = true } catch (_: Exception) {}
            }

            // 持久化
            try {
                val sp = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
                sp.edit()
                    .putBoolean(KEY_ENABLED, true)
                    .putInt(KEY_HOUR, hour)
                    .putInt(KEY_MINUTE, minute)
                    .apply()
            } catch (_: Exception) {}

            try { FileLogger.i(TAG, "schedule ok=$ok at ${fmt(trigger)} (hour=$hour, minute=$minute)") } catch (_: Exception) {}
            ok
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "schedule failed: ${e.message}", e) } catch (_: Exception) {}
            false
        }
    }

    fun cancel(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = buildBroadcastPendingIntent(context, REQUEST_CODE_SINGLE)
            am.cancel(pi)
            try {
                val sp = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
                sp.edit().putBoolean(KEY_ENABLED, false).apply()
            } catch (_: Exception) {}
            try { FileLogger.i(TAG, "cancel: daily summary alarm cancelled") } catch (_: Exception) {}
            true
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "cancel failed: ${e.message}", e) } catch (_: Exception) {}
            false
        }
    }

    /**
     * 额外固定时段调度：08:00、12:00、17:00、22:00
     * - 与单次用户自选时间并存；便于一天多次提醒和预热
     */
    fun scheduleFixedSlots(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // 先全部取消再重设，避免重复
            cancelFixedSlots(context)

            var anyOk = false
            val now = System.currentTimeMillis()
            val cal = Calendar.getInstance()
            for ((idx, hm) in FIXED_SLOTS.withIndex()) {
                val h = hm[0]
                val m = hm[1]
                cal.timeInMillis = now
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                cal.set(Calendar.HOUR_OF_DAY, h.coerceIn(0, 23))
                cal.set(Calendar.MINUTE, m.coerceIn(0, 59))
                val trigger = if (cal.timeInMillis <= now) {
                    cal.add(Calendar.DAY_OF_YEAR, 1); cal.timeInMillis
                } else cal.timeInMillis

                val pi = buildBroadcastPendingIntent(context, REQUEST_CODE_SLOT_BASE + idx)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        am.setExact(AlarmManager.RTC_WAKEUP, trigger, pi)
                    } else {
                        am.set(AlarmManager.RTC_WAKEUP, trigger, pi)
                    }
                    anyOk = true
                } catch (e: Exception) {
                    try { FileLogger.w(TAG, "slot $idx setExact failed: ${e.message}") } catch (_: Exception) {}
                    try {
                        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
                        anyOk = true
                    } catch (_: Exception) {}
                }

                try { FileLogger.i(TAG, "scheduleFixedSlots: slot=$idx time=${fmt(trigger)}") } catch (_: Exception) {}
            }
            anyOk
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "scheduleFixedSlots failed: ${e.message}", e) } catch (_: Exception) {}
            false
        }
    }

    fun cancelFixedSlots(context: Context) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (idx in FIXED_SLOTS.indices) {
                val pi = buildBroadcastPendingIntent(context, REQUEST_CODE_SLOT_BASE + idx)
                am.cancel(pi)
            }
            try { FileLogger.i(TAG, "cancelFixedSlots: all fixed slots cancelled") } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    fun restore(context: Context) {
        try {
            val sp = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            val enabled = sp.getBoolean(KEY_ENABLED, false)
            val hour = sp.getInt(KEY_HOUR, 20)
            val minute = sp.getInt(KEY_MINUTE, 0)
            if (enabled) {
                val ok = schedule(context, hour, minute)
                try { FileLogger.i(TAG, "restore: enabled=true, schedule result=$ok ($hour:$minute)") } catch (_: Exception) {}
                // 同步安排固定时段
                val ok2 = scheduleFixedSlots(context)
                try { FileLogger.i(TAG, "restore: fixed slots schedule result=$ok2") } catch (_: Exception) {}
            } else {
                cancelFixedSlots(context)
                try { FileLogger.i(TAG, "restore: enabled=false, cancel fixed slots & skip schedule") } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "restore failed: ${e.message}", e) } catch (_: Exception) {}
        }
    }

    private fun buildBroadcastPendingIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, DailySummaryAlarmReceiver::class.java).apply {
            action = ACTION_ALARM
            putExtra(
                EXTRA_SLOT_TYPE,
                if (requestCode == REQUEST_CODE_SINGLE) SLOT_TYPE_USER else SLOT_TYPE_FIXED
            )
            if (requestCode >= REQUEST_CODE_SLOT_BASE) {
                putExtra(EXTRA_SLOT_INDEX, requestCode - REQUEST_CODE_SLOT_BASE)
            }
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_CANCEL_CURRENT
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    private fun fmt(ts: Long): String {
        val cal = Calendar.getInstance().apply { timeInMillis = ts }
        return String.format("%04d-%02d-%02d %02d:%02d:%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE),
            cal.get(Calendar.SECOND)
        )
    }
}

/**
 * 每日提醒广播接收器：到点后展示一条可点击进入应用的通知。
 * 注：为保证在应用未启动时也能提示，这里直接使用原生通知，文案为兜底提示。
 * 更丰富的内容由用户进入应用后，由 Flutter 侧计算并可再次调用 showNotification 覆盖。
 */
class DailySummaryAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "DailySummaryReceiver"

        private fun resolveSlotTexts(
            context: Context,
            slotType: Int,
            slotIndex: Int,
            dateKey: String
        ): Pair<String, String> {
            val locale = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.resources.configuration.locales.get(0)
            } else {
                @Suppress("DEPRECATION")
                context.resources.configuration.locale
            }
            val lang = locale?.language?.lowercase(Locale.ROOT) ?: "en"
            val isZh = lang.startsWith("zh")

            val title = when {
                slotType == DailySummaryScheduler.SLOT_TYPE_USER ->
                    if (isZh) "每日总结 $dateKey" else "Daily Summary $dateKey"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 0 ->
                    if (isZh) "晨间速览 $dateKey" else "Morning Briefing $dateKey"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 1 ->
                    if (isZh) "午间速览 $dateKey" else "Midday Briefing $dateKey"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 2 ->
                    if (isZh) "傍晚速览 $dateKey" else "Evening Briefing $dateKey"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 3 ->
                    if (isZh) "夜间速览 $dateKey" else "Nightly Briefing $dateKey"
                else -> if (isZh) "每日总结 $dateKey" else "Daily Summary $dateKey"
            }

            val fallback = when {
                slotType == DailySummaryScheduler.SLOT_TYPE_USER ->
                    if (isZh) "点击打开查看今日总结" else "Tap to open today's summary"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 0 ->
                    if (isZh) "点击查看晨间速览" else "Open the morning briefing"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 1 ->
                    if (isZh) "点击查看午间速览" else "Open the midday briefing"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 2 ->
                    if (isZh) "点击查看傍晚速览" else "Open the evening briefing"
                slotType == DailySummaryScheduler.SLOT_TYPE_FIXED && slotIndex == 3 ->
                    if (isZh) "点击查看夜间速览" else "Open the nightly briefing"
                else -> if (isZh) "点击打开查看今日总结" else "Tap to open today's summary"
            }

            return Pair(title, fallback)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        FileLogger.init(context)
        val action = intent.action ?: ""
        try { FileLogger.i(TAG, "onReceive action=$action") } catch (_: Exception) {}
        if (action == DailySummaryScheduler.ACTION_ALARM) {
            // 到点展示兜底通知
            val cal = Calendar.getInstance()
            val dateKey = String.format(
                "%04d-%02d-%02d",
                cal.get(Calendar.YEAR),
                cal.get(Calendar.MONTH) + 1,
                cal.get(Calendar.DAY_OF_MONTH)
            )
            val slotType = intent.getIntExtra(DailySummaryScheduler.EXTRA_SLOT_TYPE, DailySummaryScheduler.SLOT_TYPE_FIXED)
            val slotIndex = intent.getIntExtra(DailySummaryScheduler.EXTRA_SLOT_INDEX, -1)
            val (title, fallbackMessage) = resolveSlotTexts(context, slotType, slotIndex, dateKey)
            val sp = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            val brief = sp.getString("daily_brief_$dateKey", null)
            val message = brief ?: fallbackMessage
            val ok = DailySummaryNotifier.showBigText(context, title, message)
            try { FileLogger.i(TAG, "fired: show notification ok=$ok, briefLen=${message.length}") } catch (_: Exception) {}

            // 异步触发真实后台生成（WorkManager），以便在应用未运行时也生成当日总结
            try {
                DailySummaryWorker.enqueueOnce(context.applicationContext, dateKey)
            } catch (_: Exception) {}

            // 立即安排下一天
            try {
                val sp = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                val enabled = sp.getBoolean("daily_summary_enabled", false)
                val hour = sp.getInt("daily_summary_hour", 20)
                val minute = sp.getInt("daily_summary_minute", 0)
                if (enabled) {
                    DailySummaryScheduler.schedule(context, hour, minute)
                }
            } catch (_: Exception) {}
        }
    }
}