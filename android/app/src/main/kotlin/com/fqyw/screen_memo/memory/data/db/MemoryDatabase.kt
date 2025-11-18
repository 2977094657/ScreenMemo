package com.fqyw.screen_memo.memory.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.fqyw.screen_memo.FileLogger
import java.io.File

@Database(
    entities = [
        MemoryEventEntity::class,
        MemoryTagEntity::class,
        MemoryTagEvidenceEntity::class,
        MemoryMetadataEntity::class
    ],
    version = 3,
    exportSchema = true
)
@TypeConverters(MemoryTypeConverters::class)
abstract class MemoryDatabase : RoomDatabase() {

    abstract fun memoryDao(): MemoryDao

    companion object {
        private const val DATABASE_NAME = "memory_backend.db"

        @Volatile
        private var instance: MemoryDatabase? = null

        fun getInstance(context: Context): MemoryDatabase {
            return instance ?: synchronized(this) {
                instance ?: buildDatabase(context.applicationContext).also { instance = it }
            }
        }

        private fun buildDatabase(appContext: Context): MemoryDatabase {
            val storageContext = MemoryDatabaseContext(appContext)
            migrateLegacyDatabaseIfNeeded(appContext, storageContext)
            return Room.databaseBuilder(storageContext, MemoryDatabase::class.java, DATABASE_NAME)
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                // 允许版本降级时清空旧数据，避免迁移路径缺失导致崩溃
                .fallbackToDestructiveMigrationOnDowngrade()
                .build()
        }

        private val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE memory_tags ADD COLUMN level1 TEXT NOT NULL DEFAULT ''")
                database.execSQL("ALTER TABLE memory_tags ADD COLUMN level2 TEXT NOT NULL DEFAULT ''")
                database.execSQL("ALTER TABLE memory_tags ADD COLUMN level3 TEXT NOT NULL DEFAULT ''")
                database.execSQL("ALTER TABLE memory_tags ADD COLUMN level4 TEXT NOT NULL DEFAULT ''")
                database.execSQL("ALTER TABLE memory_tags ADD COLUMN full_path TEXT NOT NULL DEFAULT ''")
            }
        }

        private val MIGRATION_2_3 = object : androidx.room.migration.Migration(2, 3) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS memory_metadata (
                        key TEXT NOT NULL PRIMARY KEY,
                        value TEXT NOT NULL
                    )
                    """.trimIndent()
                )
            }
        }

        private fun migrateLegacyDatabaseIfNeeded(
            appContext: Context,
            storageContext: MemoryDatabaseContext
        ) {
            try {
                val targetDb = storageContext.getDatabasePath(DATABASE_NAME)
                val candidates = mutableListOf<File>()

                appContext.getDatabasePath(DATABASE_NAME)?.let { candidates.add(it) }
                appContext.getExternalFilesDir(null)?.let { externalRoot ->
                    val externalDb = File(
                        externalRoot,
                        "${MemoryDatabaseContext.OUTPUT_RELATIVE_PATH}/$DATABASE_NAME"
                    )
                    candidates.add(externalDb)
                }

                for (candidate in candidates) {
                    if (candidate == targetDb) continue
                    if (!candidate.exists()) continue

                    targetDb.parentFile?.let { parent ->
                        if (!parent.exists()) {
                            parent.mkdirs()
                        }
                    }

                    if (!targetDb.exists()) {
                        candidate.copyTo(targetDb, overwrite = true)
                        copySidecarFile(candidate, targetDb, "-wal")
                        copySidecarFile(candidate, targetDb, "-shm")
                        FileLogger.i(
                            TAG,
                            "migrated memory database from ${candidate.absolutePath} to ${targetDb.absolutePath}"
                        )
                    }

                    if (candidate.exists()) {
                        deleteIfExists(candidate)
                    }
                    deleteIfExists(File(candidate.path + "-wal"))
                    deleteIfExists(File(candidate.path + "-shm"))

                    if (targetDb.exists()) {
                        break
                    }
                }
            } catch (t: Throwable) {
                FileLogger.e(TAG, "迁移旧版记忆数据库失败", t)
            }
        }

        private fun copySidecarFile(
            legacyDb: File,
            targetDb: File,
            suffix: String
        ) {
            val legacy = File(legacyDb.path + suffix)
            if (!legacy.exists()) return
            val target = File(targetDb.path + suffix)
            target.parentFile?.let { parent ->
                if (!parent.exists()) {
                    parent.mkdirs()
                }
            }
            legacy.copyTo(target, overwrite = true)
        }

        private fun deleteIfExists(file: File) {
            if (file.exists()) {
                try {
                    file.delete()
                } catch (_: Throwable) {
                }
            }
        }

        private const val TAG = "MemoryDatabase"
    }
}

