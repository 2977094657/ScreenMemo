package com.fqyw.screen_memo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

object MemoryRebuildNotifier {
    private const val CHANNEL_ID = "memory_rebuild_channel"
    private const val NOTIFICATION_ID = 1038

    fun show(
        context: Context,
        status: String,
        processed: Int,
        failed: Int,
        total: Int,
        currentPosition: Int,
        currentSegmentId: Int,
        segmentSampleCursor: Int,
        segmentSampleTotal: Int,
        pauseReason: String?,
        lastError: String?,
    ): Boolean {
        return try {
            ensureChannel(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val pending = launchAppPendingIntent(context)
            val safeTotal = total.coerceAtLeast(1)
            val scope = buildScope(context, currentSegmentId, segmentSampleCursor, segmentSampleTotal)

            val title: String
            val detail: String
            when (status.trim()) {
                "preparing" -> {
                    title = context.getString(R.string.memory_rebuild_notif_preparing_title)
                    detail = context.getString(R.string.memory_rebuild_notif_preparing_text)
                }
                "completed" -> {
                    title = context.getString(R.string.memory_rebuild_notif_done_title)
                    detail = context.getString(
                        R.string.memory_rebuild_notif_done_text,
                        processed,
                    )
                }
                "stopped" -> {
                    title = context.getString(R.string.memory_rebuild_notif_cancelled_title)
                    detail = context.getString(
                        R.string.memory_rebuild_notif_cancelled_text,
                        currentPosition.coerceAtLeast(0),
                        safeTotal,
                    )
                }
                "paused" -> {
                    title = context.getString(R.string.memory_rebuild_notif_paused_title)
                    detail = context.getString(
                        R.string.memory_rebuild_notif_paused_text,
                        currentPosition.coerceAtLeast(0),
                        safeTotal,
                    )
                }
                else -> {
                    title = context.getString(R.string.memory_rebuild_notif_running_title)
                    detail = context.getString(
                        R.string.memory_rebuild_notif_running_text,
                        currentPosition.coerceAtLeast(1),
                        safeTotal,
                        scope,
                    )
                }
            }

            val extra = buildString {
                if (failed > 0) {
                    append("失败: ")
                    append(failed)
                }
                if (!pauseReason.isNullOrBlank()) {
                    if (isNotEmpty()) append("\n")
                    append("状态: ")
                    append(pauseReason)
                }
                if (!lastError.isNullOrBlank()) {
                    if (isNotEmpty()) append("\n")
                    append(lastError.trim())
                }
            }.trim()
            val bigText = if (extra.isEmpty()) detail else "$detail\n$extra"

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(detail.lineSequence().firstOrNull() ?: detail)
                .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
                .setContentIntent(pending)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

            when (status.trim()) {
                "preparing" -> {
                    builder.setOngoing(true)
                    builder.setProgress(0, 0, true)
                }
                "running" -> {
                    builder.setOngoing(true)
                    builder.setProgress(
                        safeTotal,
                        currentPosition.coerceAtMost(safeTotal),
                        false,
                    )
                }
                else -> {
                    builder.setOngoing(false)
                    builder.setAutoCancel(true)
                }
            }

            nm.notify(NOTIFICATION_ID, builder.build())
            true
        } catch (_: Exception) {
            false
        }
    }

    fun cancel(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}
    }

    private fun buildScope(
        context: Context,
        currentSegmentId: Int,
        segmentSampleCursor: Int,
        segmentSampleTotal: Int,
    ): String {
        val defaultText = context.getString(R.string.memory_rebuild_notif_running_scope_default)
        if (currentSegmentId <= 0 && segmentSampleTotal <= 0) return defaultText
        val sb = StringBuilder()
        if (currentSegmentId > 0) {
            sb.append("段落 #")
            sb.append(currentSegmentId)
        }
        if (segmentSampleTotal > 0) {
            if (sb.isNotEmpty()) sb.append(" · ")
            sb.append(segmentSampleCursor.coerceAtLeast(0))
            sb.append("/")
            sb.append(segmentSampleTotal)
            sb.append(" 张")
        }
        return if (sb.isEmpty()) defaultText else sb.toString()
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.memory_rebuild_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.memory_rebuild_channel_desc)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    private fun launchAppPendingIntent(context: Context): PendingIntent {
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_memory_rebuild_notification", true)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(context, 2003, launch, flags)
    }
}
