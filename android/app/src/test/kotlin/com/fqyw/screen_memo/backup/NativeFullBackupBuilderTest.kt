package com.fqyw.screen_memo.backup

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class NativeFullBackupBuilderTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun cleanupTempArtifacts_deletesOnlyCloudBackupArtifacts() {
        val root = temporaryFolder.newFolder("cloud_backup")
        val stage = File(root, "stage_20260818_133354").apply { mkdirs() }
        File(stage, "partial.db").writeText("partial")
        val archive = File(root, "screen_memo_full_device_20260818_133354.zip").apply {
            writeText("partial")
        }
        val lock = File(root, ".worker.lock").apply { writeText("lock") }
        val unrelated = File(root, "keep.txt").apply { writeText("keep") }

        assertTrue(NativeFullBackupBuilder.cleanupTempArtifacts(root))

        assertFalse(stage.exists())
        assertFalse(archive.exists())
        assertTrue(lock.exists())
        assertTrue(unrelated.exists())
    }

    @Test
    fun tryAcquireRunLock_allowsOnlyOneOwner() {
        val root = temporaryFolder.newFolder("cloud_backup_lock")
        val first = NativeFullBackupBuilder.tryAcquireRunLock(root)

        assertNotNull(first)
        assertNull(NativeFullBackupBuilder.tryAcquireRunLock(root))

        first!!.close()
        val third = NativeFullBackupBuilder.tryAcquireRunLock(root)
        assertNotNull(third)
        third!!.close()
    }
}
