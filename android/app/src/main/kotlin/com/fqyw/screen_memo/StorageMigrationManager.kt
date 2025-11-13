package com.fqyw.screen_memo

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicLong

object StorageMigrationManager {

    private const val TAG = "StorageMigration"
    private const val PREF_NAME = "storage_migration"
    private const val PREF_KEY_COMPLETED = "v1_completed"

    data class MigrationStatus(
        val needsMigration: Boolean,
        val legacyBase: String?,
        val internalBase: String?,
        val totalBytes: Long,
        val totalFiles: Long,
        val pendingItems: Int
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "needsMigration" to needsMigration,
            "legacyBase" to legacyBase,
            "internalBase" to internalBase,
            "totalBytes" to totalBytes,
            "totalFiles" to totalFiles,
            "pendingItems" to pendingItems
        )
    }

    data class MigrationResult(
        val success: Boolean,
        val migratedBytes: Long,
        val migratedFiles: Long,
        val skippedItems: Int,
        val durationMillis: Long,
        val errors: List<String>
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "migratedBytes" to migratedBytes,
            "migratedFiles" to migratedFiles,
            "skippedItems" to skippedItems,
            "durationMillis" to durationMillis,
            "errors" to errors
        )
    }

    data class MigrationProgress(
        val totalBytes: Long,
        val migratedBytes: Long,
        val totalFiles: Long,
        val migratedFiles: Long
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "totalBytes" to totalBytes,
            "migratedBytes" to migratedBytes,
            "totalFiles" to totalFiles,
            "migratedFiles" to migratedFiles,
            "ratio" to if (totalBytes > 0) {
                migratedBytes.toDouble() / totalBytes.toDouble()
            } else if (totalFiles > 0) {
                migratedFiles.toDouble() / totalFiles.toDouble()
            } else {
                0.0
            }
        )
    }

    private data class MigrationTask(val source: File, val dest: File)

    private data class Counters(
        val bytes: AtomicLong = AtomicLong(0L),
        val files: AtomicLong = AtomicLong(0L),
        @Volatile var skipped: Int = 0
    )

    fun getStatus(context: Context): MigrationStatus {
        val legacyBase = context.getExternalFilesDir(null)
        val internalBase = context.filesDir

        if (legacyBase == null) {
            return MigrationStatus(
                needsMigration = false,
                legacyBase = null,
                internalBase = internalBase.absolutePath,
                totalBytes = 0,
                totalFiles = 0,
                pendingItems = 0
            )
        }

        if (legacyBase.absolutePath == internalBase.absolutePath) {
            return MigrationStatus(
                needsMigration = false,
                legacyBase = legacyBase.absolutePath,
                internalBase = internalBase.absolutePath,
                totalBytes = 0,
                totalFiles = 0,
                pendingItems = 0
            )
        }

        val tasks = collectTasks(legacyBase, internalBase)
        var totalBytes = 0L
        var totalFiles = 0L
        for (task in tasks) {
            val (bytes, files) = measure(task.source)
            totalBytes += bytes
            totalFiles += files
        }

        val needsMigration = tasks.isNotEmpty() && (totalBytes > 0 || hasDirStructure(tasks))
        val pendingItems = tasks.size

        return MigrationStatus(
            needsMigration = needsMigration,
            legacyBase = legacyBase.absolutePath,
            internalBase = internalBase.absolutePath,
            totalBytes = totalBytes,
            totalFiles = totalFiles,
            pendingItems = pendingItems
        )
    }

    fun migrate(
        context: Context,
        progressCallback: ((MigrationProgress) -> Unit)? = null
    ): MigrationResult {
        val start = System.currentTimeMillis()
        val status = getStatus(context)
        if (!status.needsMigration) {
            FileLogger.i(TAG, "No migration required")
            progressCallback?.invoke(
                MigrationProgress(
                    status.totalBytes,
                    status.totalBytes,
                    status.totalFiles,
                    status.totalFiles
                )
            )
            return MigrationResult(
                success = true,
                migratedBytes = 0,
                migratedFiles = 0,
                skippedItems = status.pendingItems,
                durationMillis = System.currentTimeMillis() - start,
                errors = emptyList()
            )
        }

        val legacyBase = context.getExternalFilesDir(null)
        val internalBase = context.filesDir
        if (legacyBase == null) {
            return MigrationResult(
                success = false,
                migratedBytes = 0,
                migratedFiles = 0,
                skippedItems = 0,
                durationMillis = System.currentTimeMillis() - start,
                errors = listOf("legacy base directory not available")
            )
        }

        val tasks = collectTasks(legacyBase, internalBase)
        val totals = computeTotals(tasks)
        val totalBytes = totals.first
        val totalFiles = totals.second
        val counters = Counters()
        val errors = mutableListOf<String>()

        if (totalBytes > 0 || totalFiles > 0) {
            progressCallback?.invoke(
                MigrationProgress(
                    totalBytes,
                    counters.bytes.get(),
                    totalFiles,
                    counters.files.get()
                )
            )
        }

        for (task in tasks) {
            val beforeErrors = errors.size
            copyRecursively(
                task.source,
                task.dest,
                counters,
                errors,
                totalBytes,
                totalFiles,
                progressCallback
            )
            if (errors.size == beforeErrors) {
                deleteQuietly(task.source)
            } else {
                errors.add("skip delete due to errors: ${task.source.absolutePath}")
            }
        }

        val duration = System.currentTimeMillis() - start
        val success = errors.isEmpty()

        progressCallback?.invoke(
            MigrationProgress(
                totalBytes,
                counters.bytes.get(),
                totalFiles,
                counters.files.get()
            )
        )

        if (success) {
            try {
                val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean(PREF_KEY_COMPLETED, true).apply()
            } catch (_: Exception) {}
            FileLogger.i(TAG, "Migration completed: bytes=${counters.bytes.get()} files=${counters.files.get()} duration=${duration}ms")
        } else {
            FileLogger.w(TAG, "Migration completed with errors: ${errors.size}")
        }

        return MigrationResult(
            success = success,
            migratedBytes = counters.bytes.get(),
            migratedFiles = counters.files.get(),
            skippedItems = counters.skipped,
            durationMillis = duration,
            errors = errors
        )
    }

    private fun collectTasks(legacyBase: File, internalBase: File): List<MigrationTask> {
        val tasks = mutableListOf<MigrationTask>()
        val children = legacyBase.listFiles() ?: return tasks
        for (child in children) {
            if (child.name.equals("logs", ignoreCase = true)) {
                continue
            }
            if (child.name == "output" && child.isDirectory) {
                val outputChildren = child.listFiles() ?: continue
                for (outChild in outputChildren) {
                    if (outChild.name.equals("logs", ignoreCase = true)) continue
                    val dest = File(internalBase, "output/${outChild.name}")
                    tasks.add(MigrationTask(outChild, dest))
                }
            } else {
                val dest = File(internalBase, child.name)
                tasks.add(MigrationTask(child, dest))
            }
        }
        return tasks
    }

    private fun measure(file: File): Pair<Long, Long> {
        if (!file.exists()) return 0L to 0L
        if (file.isFile) return file.length() to 1L
        var bytes = 0L
        var count = 0L
        val stack = ArrayDeque<File>()
        stack.add(file)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast()
            val list = current.listFiles() ?: continue
            for (child in list) {
                if (!child.exists()) continue
                if (child.isFile) {
                    bytes += child.length()
                    count++
                } else if (child.isDirectory) {
                    stack.add(child)
                }
            }
        }
        return bytes to count
    }

    private fun hasDirStructure(tasks: List<MigrationTask>): Boolean {
        for (task in tasks) {
            if (task.source.isDirectory) return true
        }
        return false
    }

    private fun copyRecursively(
        source: File,
        dest: File,
        counters: Counters,
        errors: MutableList<String>,
        totalBytes: Long,
        totalFiles: Long,
        progressCallback: ((MigrationProgress) -> Unit)?
    ) {
        if (!source.exists()) {
            return
        }
        try {
            if (source.isDirectory) {
                if (dest.exists() && dest.isFile) {
                    dest.delete()
                }
                if (!dest.exists()) {
                    if (!dest.mkdirs()) {
                        errors.add("failed to create directory: ${dest.absolutePath}")
                        counters.skipped++
                        return
                    }
                }
                val children = source.listFiles()
                if (children == null) {
                    counters.skipped++
                    return
                }
                for (child in children) {
                    val destChild = File(dest, child.name)
                    copyRecursively(
                        child,
                        destChild,
                        counters,
                        errors,
                        totalBytes,
                        totalFiles,
                        progressCallback
                    )
                }
            } else {
                val parent = dest.parentFile
                if (parent != null && !parent.exists()) {
                    if (!parent.mkdirs()) {
                        errors.add("failed to create parent directory: ${parent.absolutePath}")
                        counters.skipped++
                        return
                    }
                }
                if (dest.exists() && dest.isDirectory) {
                    dest.deleteRecursively()
                }
                FileInputStream(source).use { input ->
                    FileOutputStream(dest, false).use { output ->
                        input.copyTo(output)
                    }
                }
                dest.setLastModified(source.lastModified())
                counters.bytes.addAndGet(source.length())
                counters.files.incrementAndGet()
                progressCallback?.invoke(
                    MigrationProgress(
                        totalBytes,
                        counters.bytes.get(),
                        totalFiles,
                        counters.files.get()
                    )
                )
            }
        } catch (e: Exception) {
            errors.add("copy failed: ${source.absolutePath} -> ${dest.absolutePath}: ${e.message}")
        }
    }

    private fun deleteQuietly(file: File) {
        try {
            if (!file.exists()) return
            if (file.isDirectory) {
                file.deleteRecursively()
            } else {
                file.delete()
            }
        } catch (_: Exception) {
        }
    }

    private fun computeTotals(tasks: List<MigrationTask>): Pair<Long, Long> {
        var totalBytes = 0L
        var totalFiles = 0L
        for (task in tasks) {
            val (bytes, files) = measure(task.source)
            totalBytes += bytes
            totalFiles += files
        }
        return totalBytes to totalFiles
    }
}

