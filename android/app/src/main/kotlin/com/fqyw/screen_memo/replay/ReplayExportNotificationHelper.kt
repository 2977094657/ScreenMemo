package com.fqyw.screen_memo.replay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.fqyw.screen_memo.MainActivity
import com.fqyw.screen_memo.R
import kotlin.math.max
import kotlin.math.roundToInt

object ReplayExportNotificationHelper {
    private const val CHANNEL_ID = "replay_export_channel"
    private const val NOTIFICATION_ID = 1041

    fun showPreparing(context: Context) {
        notify(
            context,
            buildNotification(
                context = context,
                title = context.getString(R.string.replay_export_notif_preparing_title),
                detail = context.getString(R.string.replay_export_notif_preparing_text),
                ongoing = true,
                indeterminate = true,
            ),
        )
    }

    fun updateProgress(context: Context, processed: Int, total: Int) {
        val safeTotal = total.coerceAtLeast(1)
        val safeProcessed = processed.coerceIn(0, safeTotal)
        val percent = "${((safeProcessed * 100f) / max(1, safeTotal)).roundToInt()}%"
        notify(
            context,
            buildNotification(
                context = context,
                title = context.getString(R.string.replay_export_notif_running_title),
                detail = context.getString(
                    R.string.replay_export_notif_running_text,
                    safeProcessed,
                    safeTotal,
                    percent,
                ),
                ongoing = true,
                progressMax = safeTotal,
                progress = safeProcessed,
            ),
        )
    }

    fun showCompleted(context: Context) {
        notify(
            context,
            buildNotification(
                context = context,
                title = context.getString(R.string.replay_export_notif_done_title),
                detail = context.getString(R.string.replay_export_notif_done_text),
                ongoing = false,
                autoCancel = true,
            ),
        )
    }

    fun showFailed(context: Context, detail: String?) {
        notify(
            context,
            buildNotification(
                context = context,
                title = context.getString(R.string.replay_export_notif_failed_title),
                detail = detail?.takeIf { it.isNotBlank() }
                    ?: context.getString(R.string.replay_export_notif_failed_generic),
                ongoing = false,
                autoCancel = true,
            ),
        )
    }

    private fun buildNotification(
        context: Context,
        title: String,
        detail: String,
        ongoing: Boolean,
        autoCancel: Boolean = false,
        indeterminate: Boolean = false,
        progressMax: Int = 0,
        progress: Int = 0,
    ): Notification {
        ensureChannel(context)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("from_replay_export_notification", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(detail.lineSequence().firstOrNull() ?: detail)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(ongoing)
            .setAutoCancel(autoCancel)
        when {
            indeterminate -> builder.setProgress(0, 0, true)
            progressMax > 0 -> builder.setProgress(progressMax, progress, false)
            else -> builder.setProgress(0, 0, false)
        }
        return builder.build()
    }

    private fun notify(context: Context, notification: Notification) {
        ensureChannel(context)
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.replay_export_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.replay_export_channel_desc)
            setShowBadge(false)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }
}
