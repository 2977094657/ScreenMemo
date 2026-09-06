package com.fqyw.screen_memo.backup

import androidx.work.NetworkType

data class RemoteBackupFile(
    val path: String,
    val name: String,
    val mtime: Long,
    val isDir: Boolean = false,
)

object CloudBackupPolicy {
    private const val DAY_MS = 24L * 60L * 60L * 1000L

    fun isDue(
        enabled: Boolean,
        force: Boolean,
        lastRunAt: Long,
        nowMillis: Long,
        frequencyDays: Int,
    ): Boolean {
        if (force) return true
        if (!enabled) return false
        if (lastRunAt <= 0L) return true
        val days = frequencyDays.coerceAtLeast(1)
        return nowMillis - lastRunAt >= days * DAY_MS
    }

    fun requiredNetworkType(allowMobileData: Boolean): NetworkType {
        return if (allowMobileData) NetworkType.CONNECTED else NetworkType.UNMETERED
    }

    fun selectBackupsToDelete(
        files: List<RemoteBackupFile>,
        keepLatestCount: Int,
    ): List<RemoteBackupFile> {
        val keep = keepLatestCount.coerceAtLeast(1)
        return files
            .filter { !it.isDir && it.name.endsWith(".zip", ignoreCase = true) }
            .sortedWith(
                compareByDescending<RemoteBackupFile> { it.mtime }
                    .thenByDescending { it.name }
            )
            .drop(keep)
    }
}
