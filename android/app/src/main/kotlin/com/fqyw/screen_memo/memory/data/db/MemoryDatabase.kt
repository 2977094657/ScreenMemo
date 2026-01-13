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
        MemoryMetadataEntity::class,
        MemoryEntityEntity::class,
        MemoryEdgeEntity::class,
        MemoryEdgeEvidenceEntity::class,
        MemoryEntityAliasEntity::class
    ],
    version = 6,
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
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6)
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

        private val MIGRATION_3_4 = object : androidx.room.migration.Migration(3, 4) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS memory_entities (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        entity_key TEXT NOT NULL,
                        type TEXT NOT NULL,
                        name TEXT NOT NULL,
                        aliases TEXT,
                        metadata TEXT,
                        created_at INTEGER NOT NULL,
                        last_modified_at INTEGER NOT NULL
                    )
                    """.trimIndent()
                )
                database.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_entities_key ON memory_entities(entity_key)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_entities_type ON memory_entities(type)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_entities_name ON memory_entities(name)")

                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS memory_edges (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        subject_entity_id INTEGER NOT NULL,
                        predicate TEXT NOT NULL,
                        object_entity_id INTEGER,
                        object_value TEXT,
                        qualifiers TEXT,
                        valid_from INTEGER NOT NULL,
                        valid_to INTEGER,
                        confidence REAL NOT NULL,
                        created_at INTEGER NOT NULL,
                        last_modified_at INTEGER NOT NULL,
                        FOREIGN KEY(subject_entity_id) REFERENCES memory_entities(id) ON DELETE CASCADE,
                        FOREIGN KEY(object_entity_id) REFERENCES memory_entities(id) ON DELETE SET NULL
                    )
                    """.trimIndent()
                )
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_edges_subject ON memory_edges(subject_entity_id)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_edges_object ON memory_edges(object_entity_id)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_edges_predicate ON memory_edges(predicate)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_edges_valid_from ON memory_edges(valid_from)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_edges_valid_to ON memory_edges(valid_to)")

                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS memory_edge_evidence (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        edge_id INTEGER NOT NULL,
                        event_id INTEGER NOT NULL,
                        excerpt TEXT NOT NULL,
                        confidence REAL NOT NULL,
                        created_at INTEGER NOT NULL,
                        last_modified_at INTEGER NOT NULL,
                        is_user_edited INTEGER NOT NULL DEFAULT 0,
                        notes TEXT,
                        FOREIGN KEY(edge_id) REFERENCES memory_edges(id) ON DELETE CASCADE,
                        FOREIGN KEY(event_id) REFERENCES memory_events(id) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                database.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_edge_evidence_pair ON memory_edge_evidence(edge_id, event_id)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_edge_evidence_edge ON memory_edge_evidence(edge_id)")
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_edge_evidence_event ON memory_edge_evidence(event_id)")
            }
        }

        private val MIGRATION_4_5 = object : androidx.room.migration.Migration(4, 5) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS memory_tag_aliases (
                        alias_key TEXT NOT NULL PRIMARY KEY,
                        tag_id INTEGER NOT NULL,
                        created_at INTEGER NOT NULL,
                        FOREIGN KEY(tag_id) REFERENCES memory_tags(id) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                database.execSQL("CREATE INDEX IF NOT EXISTS idx_memory_tag_aliases_tag ON memory_tag_aliases(tag_id)")

                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS memory_entity_aliases (
                        alias_key TEXT NOT NULL PRIMARY KEY,
                        entity_id INTEGER NOT NULL,
                        created_at INTEGER NOT NULL,
                        FOREIGN KEY(entity_id) REFERENCES memory_entities(id) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                database.execSQL(
                    "CREATE INDEX IF NOT EXISTS idx_memory_entity_aliases_entity ON memory_entity_aliases(entity_id)"
                )
            }
        }

        private val MIGRATION_5_6 = object : androidx.room.migration.Migration(5, 6) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                // v6 removes tag-related tables entirely.
                database.execSQL("DROP TABLE IF EXISTS memory_tag_aliases")
                database.execSQL("DROP TABLE IF EXISTS memory_tag_evidence")
                database.execSQL("DROP TABLE IF EXISTS memory_tags")
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
