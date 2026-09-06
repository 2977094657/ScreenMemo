package com.fqyw.screen_memo.backup

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import com.fqyw.screen_memo.R
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import java.io.File
import java.util.UUID

class CloudBackupWorker(appContext: Context, params: WorkerParameters) : Worker(appContext, params) {
    private var lastProgressStage = ""
    private var lastProgressPercent = -1
    private var lastProgressWriteAt = 0L

    override fun doWork(): Result {
        try {
            FileLogger.init(applicationContext)
        } catch (_: Exception) {
        }
        val backupDir = File(applicationContext.cacheDir, NativeFullBackupBuilder.TEMP_DIR_NAME)
        val lock = try {
            NativeFullBackupBuilder.tryAcquireRunLock(backupDir)
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取云备份互斥锁失败", e)
            return Result.failure()
        }
        if (lock == null) {
            FileLogger.i(TAG, "已有云备份任务运行，跳过重复任务：workId=$id")
            return Result.success()
        }
        return lock.use {
            if (!NativeFullBackupBuilder.cleanupTempArtifacts(backupDir)) {
                FileLogger.e(TAG, "遗留云备份缓存无法清理，取消本次构建")
                return@use Result.failure()
            }
            doWorkLocked()
        }
    }

    private fun doWorkLocked(): Result {
        val force = inputData.getBoolean(CloudBackupScheduler.KEY_FORCE, false)
        if (force && runAttemptCount > 0) {
            recordStatus("failed:interrupted_retry_suppressed")
            recordProgress("failed", 100, "interrupted_retry_suppressed", active = false)
            FileLogger.w(TAG, "跳过被系统恢复的立即备份，等待用户重新发起：workId=$id")
            return Result.failure()
        }
        val now = System.currentTimeMillis()
        recordProgress("checking", 1, active = true)
        return try {
            val enabled = UserSettingsStorage.getBoolean(
                applicationContext,
                UserSettingsKeysNative.CLOUD_BACKUP_ENABLED,
                false,
            )
            val frequencyDays = UserSettingsStorage.getInt(
                applicationContext,
                UserSettingsKeysNative.CLOUD_BACKUP_FREQUENCY_DAYS,
                30,
            ).coerceAtLeast(1)
            val lastSuccessAt = UserSettingsStorage.getString(
                applicationContext,
                UserSettingsKeysNative.CLOUD_BACKUP_LAST_SUCCESS_AT,
                "0",
            )?.toLongOrNull() ?: 0L
            val lastAttemptAt = UserSettingsStorage.getString(
                applicationContext,
                UserSettingsKeysNative.CLOUD_BACKUP_LAST_ATTEMPT_AT,
                "0",
            )?.toLongOrNull() ?: 0L
            val lastRunAt = maxOf(lastSuccessAt, lastAttemptAt)
            if (!CloudBackupPolicy.isDue(enabled, force, lastRunAt, now, frequencyDays)) {
                recordStatus("skipped:not_due")
                recordProgress("skipped", 0, "not_due", active = false)
                FileLogger.i(TAG, "云备份未到期，跳过")
                return Result.success()
            }
            recordAttempt(now, "running")
            recordProgress("preparing", 5)
            ensureCredentialsPresent()
            setForegroundAsync(createForegroundInfo()).get()
            val deviceId = ensureDeviceId()
            val keepLatest = UserSettingsStorage.getInt(
                applicationContext,
                UserSettingsKeysNative.CLOUD_BACKUP_KEEP_LATEST_COUNT,
                3,
            ).coerceAtLeast(1)

            FileLogger.i(
                TAG,
                "开始构建自动云备份 ZIP：deviceId=$deviceId workId=$id force=$force attempt=$runAttemptCount",
            )
            recordProgress("zipping", 10)
            val backup = NativeFullBackupBuilder(applicationContext).build(deviceId) { processed, total, currentEntry ->
                if (isStopped) throw InterruptedException("cloud_backup_stopped")
                val ratio = if (total > 0) processed.toDouble() / total.toDouble() else 0.0
                val percent = (10 + ratio * 30).toInt().coerceIn(10, 40)
                recordProgress("zipping", percent, currentEntry)
            }
            try {
                recordProgress(
                    stage = "uploading",
                    percent = 42,
                    detail = backup.archiveFileName,
                    bytesDone = 0L,
                    bytesTotal = backup.file.length(),
                )
                val uploadResult = BaiduNetdiskClient(applicationContext)
                    .uploadBackup(backup.file, deviceId, keepLatest) { progress ->
                        if (isStopped) throw InterruptedException("cloud_backup_stopped")
                        recordUploadProgress(progress)
                    }
                val successAt = System.currentTimeMillis()
                UserSettingsStorage.putString(
                    applicationContext,
                    UserSettingsKeysNative.CLOUD_BACKUP_LAST_SUCCESS_AT,
                    successAt.toString(),
                )
                recordStatus("success:${uploadResult["remotePath"] ?: backup.archiveFileName}")
                recordProgress("finished", 100, uploadResult["remotePath"]?.toString().orEmpty(), active = false)
                FileLogger.i(TAG, "自动云备份完成：${uploadResult["remotePath"]}")
                Result.success()
            } catch (e: Exception) {
                FileLogger.e(TAG, "自动云备份上传失败", e)
                recordStatus("failed:${e.message ?: e.javaClass.simpleName}")
                recordProgress("failed", 100, e.message ?: e.javaClass.simpleName, active = false)
                Result.failure()
            } finally {
                try {
                    if (backup.file.exists() && !backup.file.delete()) {
                        FileLogger.w(TAG, "自动云备份临时 ZIP 删除失败：${backup.file.absolutePath}")
                    }
                } catch (e: Exception) {
                    FileLogger.w(TAG, "自动云备份临时 ZIP 删除异常：${e.message}")
                }
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "自动云备份执行失败", e)
            recordStatus("failed:${e.message ?: e.javaClass.simpleName}")
            recordProgress("failed", 100, e.message ?: e.javaClass.simpleName, active = false)
            Result.failure()
        }
    }

    private fun createForegroundInfo(): ForegroundInfo {
        ensureNotificationChannel()
        val cancelIntent = WorkManager.getInstance(applicationContext).createCancelPendingIntent(id)
        val notification = NotificationCompat.Builder(applicationContext, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(applicationContext.getString(R.string.cloud_backup_notification_title))
            .setContentText(applicationContext.getString(R.string.cloud_backup_notification_text))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                android.R.drawable.ic_delete,
                applicationContext.getString(android.R.string.cancel),
                cancelIntent,
            )
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                applicationContext.getString(R.string.cloud_backup_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = applicationContext.getString(R.string.cloud_backup_notification_text)
                setSound(null, null)
                enableVibration(false)
            },
        )
    }

    private fun ensureCredentialsPresent() {
        val appKey = UserSettingsStorage.getString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_BAIDU_APP_KEY,
            "",
        ).orEmpty()
        val secret = UserSettingsStorage.getString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_BAIDU_SECRET_KEY,
            "",
        ).orEmpty()
        val access = UserSettingsStorage.getString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_BAIDU_ACCESS_TOKEN,
            "",
        ).orEmpty()
        val refresh = UserSettingsStorage.getString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_BAIDU_REFRESH_TOKEN,
            "",
        ).orEmpty()
        if (appKey.isBlank() || secret.isBlank()) {
            throw IllegalStateException("AppKey and SecretKey are required.")
        }
        if (access.isBlank() && refresh.isBlank()) {
            throw IllegalStateException("Authorization is required.")
        }
    }

    private fun ensureDeviceId(): String {
        val existing = UserSettingsStorage.getString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_DEVICE_ID,
            "",
        ).orEmpty()
        if (existing.isNotBlank()) return existing
        val androidId = try {
            Settings.Secure.getString(applicationContext.contentResolver, Settings.Secure.ANDROID_ID)
        } catch (_: Exception) {
            null
        }
        val generated = "android_" + (androidId?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString())
        UserSettingsStorage.putString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_DEVICE_ID,
            generated,
        )
        return generated
    }

    private fun recordAttempt(now: Long, status: String) {
        UserSettingsStorage.putString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_LAST_ATTEMPT_AT,
            now.toString(),
        )
        recordStatus(status)
    }

    private fun recordStatus(status: String) {
        UserSettingsStorage.putString(
            applicationContext,
            UserSettingsKeysNative.CLOUD_BACKUP_LAST_STATUS,
            status.take(500),
        )
    }

    private fun recordUploadProgress(progress: BaiduUploadProgress) {
        when (progress.stage) {
            "remote_folder" -> recordProgress("remote_folder", 41, progress.detail)
            "preparing_upload" -> recordProgress(
                stage = "preparing_upload",
                percent = 43,
                detail = progress.detail,
                bytesDone = 0L,
                bytesTotal = progress.bytesTotal,
            )
            "precreate" -> recordProgress(
                stage = "precreate",
                percent = 45,
                detail = progress.detail,
                bytesDone = 0L,
                bytesTotal = progress.bytesTotal,
            )
            "uploading" -> {
                val ratio = if (progress.bytesTotal > 0L) {
                    progress.bytesDone.toDouble() / progress.bytesTotal.toDouble()
                } else {
                    0.0
                }
                val percent = (45 + ratio * 45).toInt().coerceIn(45, 90)
                recordProgress(
                    stage = "uploading",
                    percent = percent,
                    detail = progress.detail,
                    bytesDone = progress.bytesDone,
                    bytesTotal = progress.bytesTotal,
                )
            }
            "create" -> recordProgress(
                stage = "creating_remote_file",
                percent = 92,
                detail = progress.detail,
                bytesDone = progress.bytesDone,
                bytesTotal = progress.bytesTotal,
            )
            "cleanup" -> recordProgress("cleanup", 96, progress.detail)
            else -> recordProgress(progress.stage, 45, progress.detail)
        }
    }

    private fun recordProgress(
        stage: String,
        percent: Int,
        detail: String = "",
        bytesDone: Long = 0L,
        bytesTotal: Long = 0L,
        active: Boolean = true,
    ) {
        val now = System.currentTimeMillis()
        val safePercent = percent.coerceIn(0, 100)
        val shouldWrite = !active ||
            stage != lastProgressStage ||
            safePercent != lastProgressPercent ||
            now - lastProgressWriteAt >= PROGRESS_WRITE_MIN_INTERVAL_MS ||
            safePercent >= 100
        if (!shouldWrite) return
        lastProgressStage = stage
        lastProgressPercent = safePercent
        lastProgressWriteAt = now
        CloudBackupProgressStore.record(
            applicationContext,
            stage = stage,
            percent = safePercent,
            detail = detail,
            bytesDone = bytesDone,
            bytesTotal = bytesTotal,
            active = active,
        )
    }

    companion object {
        private const val TAG = "CloudBackupWorker"
        private const val PROGRESS_WRITE_MIN_INTERVAL_MS = 1000L
        private const val NOTIFICATION_CHANNEL_ID = "cloud_backup"
        private const val NOTIFICATION_ID = 1042
    }
}
