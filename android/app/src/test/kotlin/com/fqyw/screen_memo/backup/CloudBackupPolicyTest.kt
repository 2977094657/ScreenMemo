package com.fqyw.screen_memo.backup

import androidx.work.NetworkType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudBackupPolicyTest {
    @Test
    fun isDue_respectsEnabledAndFrequency() {
        val now = 10L * 24L * 60L * 60L * 1000L
        val last = 5L * 24L * 60L * 60L * 1000L

        assertFalse(
            CloudBackupPolicy.isDue(
                enabled = false,
                force = false,
                lastRunAt = 0L,
                nowMillis = now,
                frequencyDays = 1,
            ),
        )
        assertTrue(
            CloudBackupPolicy.isDue(
                enabled = false,
                force = true,
                lastRunAt = now,
                nowMillis = now,
                frequencyDays = 30,
            ),
        )
        assertTrue(
            CloudBackupPolicy.isDue(
                enabled = true,
                force = false,
                lastRunAt = 0L,
                nowMillis = now,
                frequencyDays = 30,
            ),
        )
        assertTrue(
            CloudBackupPolicy.isDue(
                enabled = true,
                force = false,
                lastRunAt = last,
                nowMillis = now,
                frequencyDays = 5,
            ),
        )
        assertFalse(
            CloudBackupPolicy.isDue(
                enabled = true,
                force = false,
                lastRunAt = last,
                nowMillis = now,
                frequencyDays = 6,
            ),
        )
    }

    @Test
    fun requiredNetworkType_usesUnmeteredUnlessMobileDataAllowed() {
        assertEquals(NetworkType.UNMETERED, CloudBackupPolicy.requiredNetworkType(false))
        assertEquals(NetworkType.CONNECTED, CloudBackupPolicy.requiredNetworkType(true))
    }

    @Test
    fun selectBackupsToDelete_keepsLatestZipFilesOnly() {
        val files = listOf(
            RemoteBackupFile("/d/a.zip", "a.zip", 10),
            RemoteBackupFile("/d/b.zip", "b.zip", 40),
            RemoteBackupFile("/d/c.zip", "c.zip", 30),
            RemoteBackupFile("/d/readme.txt", "readme.txt", 50),
            RemoteBackupFile("/d/sub", "sub", 60, isDir = true),
            RemoteBackupFile("/d/d.zip", "d.zip", 20),
        )

        val delete = CloudBackupPolicy.selectBackupsToDelete(files, keepLatestCount = 3)

        assertEquals(listOf("/d/a.zip"), delete.map { it.path })
    }
}
