package com.fqyw.screen_memo.backup

import android.content.Context
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import java.util.concurrent.TimeUnit

object CloudBackupScheduler {
    private const val TAG = "CloudBackupScheduler"
    private const val PERIODIC_WORK_NAME = "baidu_cloud_backup_periodic"
    private const val RUN_NOW_WORK_NAME = "baidu_cloud_backup_run_now"
    const val KEY_FORCE = "force"

    fun reschedule(context: Context): Map<String, Any?> {
        val appContext = context.applicationContext
        val enabled = UserSettingsStorage.getBoolean(
            appContext,
            UserSettingsKeysNative.CLOUD_BACKUP_ENABLED,
            false,
        )
        val frequencyDays = UserSettingsStorage.getInt(
            appContext,
            UserSettingsKeysNative.CLOUD_BACKUP_FREQUENCY_DAYS,
            30,
        ).coerceAtLeast(1)
        val allowMobileData = UserSettingsStorage.getBoolean(
            appContext,
            UserSettingsKeysNative.CLOUD_BACKUP_ALLOW_MOBILE_DATA,
            false,
        )
        val wm = WorkManager.getInstance(appContext)
        if (!enabled) {
            wm.cancelUniqueWork(PERIODIC_WORK_NAME)
            CloudBackupProgressStore.markInactive(appContext, "disabled", 0, "")
            FileLogger.i(TAG, "自动云备份已关闭，取消周期任务")
            return mapOf("ok" to true, "enabled" to false)
        }

        val request = PeriodicWorkRequestBuilder<CloudBackupWorker>(
            frequencyDays.toLong(),
            TimeUnit.DAYS,
        )
            .setConstraints(buildConstraints(allowMobileData))
            .build()
        wm.enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
        FileLogger.i(
            TAG,
            "已调度自动云备份：frequencyDays=$frequencyDays allowMobileData=$allowMobileData",
        )
        return mapOf(
            "ok" to true,
            "enabled" to true,
            "frequencyDays" to frequencyDays,
            "allowMobileData" to allowMobileData,
        )
    }

    fun enqueueRunNow(context: Context): Map<String, Any?> {
        val appContext = context.applicationContext
        val allowMobileData = UserSettingsStorage.getBoolean(
            appContext,
            UserSettingsKeysNative.CLOUD_BACKUP_ALLOW_MOBILE_DATA,
            false,
        )
        val data = Data.Builder().putBoolean(KEY_FORCE, true).build()
        val request = OneTimeWorkRequestBuilder<CloudBackupWorker>()
            .setInputData(data)
            .setConstraints(buildConstraints(allowMobileData))
            .build()
        CloudBackupProgressStore.record(
            appContext,
            stage = "queued",
            percent = 0,
            detail = "run_now",
            active = true,
        )
        WorkManager.getInstance(appContext).enqueueUniqueWork(
            RUN_NOW_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request,
        )
        FileLogger.i(TAG, "已入队立即云备份任务")
        return mapOf("ok" to true, "workId" to request.id.toString())
    }

    private fun buildConstraints(allowMobileData: Boolean): Constraints {
        return Constraints.Builder()
            .setRequiredNetworkType(
                CloudBackupPolicy.requiredNetworkType(allowMobileData),
            )
            .build()
    }
}
