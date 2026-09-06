package com.fqyw.screen_memo.backup

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import com.fqyw.screen_memo.database.ScreenshotDatabaseHelper
import com.fqyw.screen_memo.logging.FileLogger
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

data class NativeBackupFile(
    val source: File,
    val archivePath: String,
    val bytes: Long,
    val categoryId: String,
)

data class NativeBackupResult(
    val file: File,
    val archiveFileName: String,
    val totalBytes: Long,
    val totalFiles: Int,
)

class NativeFullBackupBuilder(private val context: Context) {
    private val appContext = context.applicationContext

    fun build(
        deviceId: String,
        onProgress: ((processedFiles: Int, totalFiles: Int, currentEntry: String) -> Unit)? = null,
    ): NativeBackupResult {
        val now = Date()
        val timestamp = fileTimestamp(now)
        val safeDeviceId = sanitizeDeviceId(deviceId)
        val fileName = "screen_memo_full_${safeDeviceId}_$timestamp.zip"
        val backupDir = File(appContext.cacheDir, TEMP_DIR_NAME).apply { mkdirs() }
        val zipFile = File(backupDir, fileName)
        if (zipFile.exists()) zipFile.delete()

        val stageDir = File(backupDir, "stage_$timestamp")
        if (stageDir.exists()) stageDir.deleteRecursively()
        stageDir.mkdirs()

        var completed = false
        try {
            val inventory = scanInventory(stageDir)
            if (inventory.isEmpty()) {
                throw IllegalStateException("backup_inventory_empty")
            }
            val manifest = buildManifest(inventory, now, fileName)
            onProgress?.invoke(0, inventory.size, MANIFEST_FILE_NAME)
            ZipOutputStream(BufferedOutputStream(FileOutputStream(zipFile))).use { zip ->
                zip.setLevel(java.util.zip.Deflater.BEST_SPEED)
                zip.putNextEntry(ZipEntry(MANIFEST_FILE_NAME))
                zip.write(manifest.toByteArray(Charsets.UTF_8))
                zip.closeEntry()
                for ((index, entry) in inventory.withIndex()) {
                    addFile(zip, entry.source, entry.archivePath)
                    onProgress?.invoke(index + 1, inventory.size, entry.archivePath)
                }
            }
            val totalBytes = inventory.sumOf { it.bytes }
            completed = true
            return NativeBackupResult(
                file = zipFile,
                archiveFileName = fileName,
                totalBytes = totalBytes,
                totalFiles = inventory.size,
            )
        } finally {
            if (!completed) {
                try {
                    zipFile.delete()
                } catch (_: Exception) {
                }
            }
            try {
                stageDir.deleteRecursively()
            } catch (_: Exception) {
            }
        }
    }

    private fun scanInventory(stageDir: File): List<NativeBackupFile> {
        val files = mutableListOf<NativeBackupFile>()
        val seen = linkedSetOf<String>()
        val filesDir = appContext.filesDir
        val dataRoot = filesDir.parentFile
        val outputDir = File(filesDir, "output")
        val stagedMaster = stageMasterDatabase(stageDir)
        val skipArchivePaths = if (stagedMaster.isNotEmpty()) {
            setOf(
                "output/databases/screenshot_memo.db-wal",
                "output/databases/screenshot_memo.db-shm",
            )
        } else {
            emptySet()
        }

        scanRoot(
            root = outputDir,
            archiveRoot = "output",
            files = files,
            seen = seen,
            ignoredTopLevel = OUTPUT_IGNORED_DIRS,
            replacementByArchivePath = stagedMaster,
            skipArchivePaths = skipArchivePaths,
        )
        scanRoot(
            root = filesDir,
            archiveRoot = "files",
            files = files,
            seen = seen,
            ignoredTopLevel = setOf("output"),
        )
        scanRoot(
            root = dataRoot?.resolve("shared_prefs"),
            archiveRoot = "shared_prefs",
            files = files,
            seen = seen,
        )
        scanRoot(
            root = dataRoot?.resolve("app_flutter"),
            archiveRoot = "app_flutter",
            files = files,
            seen = seen,
        )
        scanRoot(
            root = appContext.noBackupFilesDir,
            archiveRoot = "no_backup",
            files = files,
            seen = seen,
        )
        scanRoot(
            root = File(dataRoot, "databases"),
            archiveRoot = "databases",
            files = files,
            seen = seen,
        )
        files.sortBy { it.archivePath }
        return files
    }

    private fun stageMasterDatabase(stageDir: File): Map<String, File> {
        val sourcePath = ScreenshotDatabaseHelper.resolveMasterDbPath(appContext)
            ?: return emptyMap()
        val source = File(sourcePath)
        if (!source.exists() || !source.isFile) return emptyMap()
        val snapshot = File(stageDir, MASTER_DB_ARCHIVE_PATH)
        snapshot.parentFile?.mkdirs()
        try {
            SQLiteDatabase.openDatabase(
                source.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY,
            ).use { db ->
                try {
                    db.rawQuery("PRAGMA wal_checkpoint(PASSIVE)", null).use { }
                } catch (_: Exception) {
                }
            }
            SQLiteDatabase.openDatabase(
                source.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE,
            ).use { db ->
                db.execSQL("VACUUM INTO '${escapeSql(snapshot.absolutePath)}'")
            }
            if (snapshot.exists() && snapshot.length() > 0L) {
                FileLogger.i(TAG, "主库快照完成：${snapshot.absolutePath}")
                return mapOf(MASTER_DB_ARCHIVE_PATH to snapshot)
            }
        } catch (e: Exception) {
            FileLogger.w(TAG, "主库 VACUUM 快照失败，回退到文件复制：${e.message}")
            try {
                source.copyTo(snapshot, overwrite = true)
                if (snapshot.exists() && snapshot.length() > 0L) {
                    return mapOf(MASTER_DB_ARCHIVE_PATH to snapshot)
                }
            } catch (copyError: Exception) {
                FileLogger.w(TAG, "主库文件复制快照失败：${copyError.message}")
            }
        }
        return emptyMap()
    }

    private fun scanRoot(
        root: File?,
        archiveRoot: String,
        files: MutableList<NativeBackupFile>,
        seen: MutableSet<String>,
        ignoredTopLevel: Set<String> = emptySet(),
        replacementByArchivePath: Map<String, File> = emptyMap(),
        skipArchivePaths: Set<String> = emptySet(),
    ) {
        if (root == null || !root.exists() || !root.isDirectory) return
        val stack = ArrayDeque<File>()
        stack.add(root)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast()
            val children = current.listFiles()?.sortedBy { it.absolutePath } ?: continue
            for (child in children) {
                val rel = child.relativeTo(root).invariantSeparatorsPath
                if (rel.isBlank() || rel == ".") continue
                val head = rel.substringBefore('/').lowercase()
                val archivePath = "$archiveRoot/$rel"
                if (child.isDirectory) {
                    if (ignoredTopLevel.contains(head)) continue
                    if (archiveRoot != "output" && TOP_LEVEL_IGNORED_DIRS.contains(head)) continue
                    stack.add(child)
                    continue
                }
                if (!child.isFile) continue
                if (archivePath.endsWith(".db-journal", ignoreCase = true)) continue
                if (skipArchivePaths.contains(archivePath)) continue
                if (archiveRoot == "output" && shouldSkipOutputRelativePath(rel)) continue

                val source = replacementByArchivePath[archivePath] ?: child
                val canonical = try {
                    source.canonicalPath
                } catch (_: Exception) {
                    source.absolutePath
                }
                if (!seen.add(canonical)) continue
                files.add(
                    NativeBackupFile(
                        source = source,
                        archivePath = archivePath,
                        bytes = source.length(),
                        categoryId = categorize(archivePath),
                    ),
                )
            }
        }
    }

    private fun buildManifest(
        files: List<NativeBackupFile>,
        createdAt: Date,
        archiveFileName: String,
    ): String {
        val categories = CATEGORY_ORDER.mapNotNull { id ->
            val categoryFiles = files.filter { it.categoryId == id }
            if (categoryFiles.isEmpty()) return@mapNotNull null
            JSONObject()
                .put("id", id)
                .put("totalBytes", categoryFiles.sumOf { it.bytes })
                .put("fileCount", categoryFiles.size)
        }
        val totalBytes = files.sumOf { it.bytes }
        val rootEntries = files.map { it.archivePath.substringBefore('/') }.toSet()
        val requiresRestart = rootEntries.any {
            it == "shared_prefs" ||
                it == "app_flutter" ||
                it == "no_backup" ||
                it == "databases" ||
                it == "files"
        }
        val excluded = JSONArray()
            .put(
                JSONObject()
                    .put("id", "cache")
                    .put("reason", "Cache directory is temporary and can be rebuilt.")
                    .put("bytes", measureDir(File(appContext.dataDir, "cache"))),
            )
            .put(
                JSONObject()
                    .put("id", "code_cache")
                    .put("reason", "Code cache is regenerated automatically after launch.")
                    .put("bytes", measureDir(File(appContext.dataDir, "code_cache"))),
            )
            .put(
                JSONObject()
                    .put("id", "output_temp")
                    .put("reason", "Temporary output cache and thumbnails are excluded.")
                    .put("bytes", 0),
            )
            .put(
                JSONObject()
                    .put("id", "external_logs")
                    .put("reason", "External logs are intentionally excluded from backups."),
            )

        return JSONObject()
            .put("format", "screen_memo_backup")
            .put("version", 2)
            .put("createdAt", isoTimestamp(createdAt))
            .put("archiveFileName", archiveFileName)
            .put("totalBytes", totalBytes)
            .put("totalFiles", files.size)
            .put("requiresRestartAfterImport", requiresRestart)
            .put("categories", JSONArray(categories))
            .put("excluded", excluded)
            .put("warnings", JSONArray())
            .toString(2)
    }

    private fun addFile(zip: ZipOutputStream, source: File, archivePath: String) {
        val entry = ZipEntry(archivePath).apply {
            time = source.lastModified()
        }
        zip.putNextEntry(entry)
        BufferedInputStream(FileInputStream(source)).use { input ->
            input.copyTo(zip)
        }
        zip.closeEntry()
    }

    private fun shouldSkipOutputRelativePath(relativePath: String): Boolean {
        val lower = relativePath.replace('\\', '/').lowercase()
        if (lower.endsWith(".db-journal")) return true
        val parts = lower.split('/')
        if (parts.any { OUTPUT_IGNORED_DIRS.contains(it) || it.contains("thumbnail") }) {
            return true
        }
        return false
    }

    private fun categorize(archivePath: String): String {
        val lower = archivePath.replace('\\', '/').lowercase()
        val name = lower.substringAfterLast('/')
        return when {
            lower.startsWith("output/screen/") -> "screenshots"
            lower == MASTER_DB_ARCHIVE_PATH ||
                lower == "output/databases/screenshot_memo.db-wal" ||
                lower == "output/databases/screenshot_memo.db-shm" -> "main_database"
            lower.startsWith("output/databases/shards/") &&
                (name == "settings.db" || name == "settings.db-wal" || name == "settings.db-shm") -> "per_app_settings"
            lower.startsWith("output/databases/shards/") &&
                name.startsWith("smm_") &&
                (name.endsWith(".db") || name.endsWith(".db-wal") || name.endsWith(".db-shm")) -> "shard_databases"
            lower.startsWith("output/") -> "other_output"
            lower.startsWith("shared_prefs/") -> "shared_prefs"
            lower.startsWith("app_flutter/") -> "app_flutter"
            lower.startsWith("no_backup/") -> "no_backup"
            lower.startsWith("databases/") -> "app_databases"
            lower.startsWith("files/") -> "app_files"
            else -> "other_output"
        }
    }

    private fun measureDir(dir: File): Long {
        if (!dir.exists()) return 0L
        var total = 0L
        val stack = ArrayDeque<File>()
        stack.add(dir)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast()
            current.listFiles()?.forEach { child ->
                if (child.isDirectory) stack.add(child) else if (child.isFile) total += child.length()
            }
        }
        return total
    }

    private fun sanitizeDeviceId(raw: String): String {
        return raw.replace(Regex("[^A-Za-z0-9_.-]"), "_").ifBlank { "device" }
    }

    private fun escapeSql(raw: String): String = raw.replace("'", "''")

    private fun fileTimestamp(date: Date): String {
        return SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(date)
    }

    private fun isoTimestamp(date: Date): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(date)
    }

    companion object {
        private const val TAG = "NativeFullBackupBuilder"
        internal const val TEMP_DIR_NAME = "cloud_backup"
        private const val LOCK_FILE_NAME = ".worker.lock"
        private const val MANIFEST_FILE_NAME = "backup_manifest.json"
        private const val MASTER_DB_ARCHIVE_PATH = "output/databases/screenshot_memo.db"
        private val OUTPUT_IGNORED_DIRS = setOf("cache", "tmp", "temp", ".thumbnails")
        private val TOP_LEVEL_IGNORED_DIRS = setOf("cache", "code_cache")
        private val CATEGORY_ORDER = listOf(
            "screenshots",
            "main_database",
            "shard_databases",
            "per_app_settings",
            "other_output",
            "shared_prefs",
            "app_flutter",
            "no_backup",
            "app_databases",
            "app_files",
        )

        internal fun cleanupTempArtifacts(dir: File): Boolean {
            var success = true
            dir.listFiles()?.forEach { file ->
                val isStage = file.isDirectory && file.name.startsWith("stage_")
                val isArchive = file.isFile &&
                    file.name.startsWith("screen_memo_full_") &&
                    file.name.endsWith(".zip", ignoreCase = true)
                if (!isStage && !isArchive) return@forEach
                try {
                    val deleted = if (file.isDirectory) file.deleteRecursively() else file.delete()
                    if (!deleted && file.exists()) success = false
                } catch (_: Exception) {
                    success = false
                }
            }
            return success
        }

        internal fun tryAcquireRunLock(dir: File): Closeable? {
            dir.mkdirs()
            val handle = RandomAccessFile(File(dir, LOCK_FILE_NAME), "rw")
            try {
                val lock = try {
                    handle.channel.tryLock()
                } catch (_: OverlappingFileLockException) {
                    null
                }
                if (lock == null) {
                    handle.close()
                    return null
                }
                return Closeable {
                    try {
                        lock.release()
                    } finally {
                        handle.close()
                    }
                }
            } catch (e: Exception) {
                handle.close()
                throw e
            }
        }
    }
}
