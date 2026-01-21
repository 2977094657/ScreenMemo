package com.fqyw.screen_memo.memory.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.sqlite.db.SupportSQLiteDatabase
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
                // Create FTS indexes for hybrid lexical search (best-effort; safe on older installs).
                .addCallback(
                    object : RoomDatabase.Callback() {
                        override fun onOpen(db: SupportSQLiteDatabase) {
                            super.onOpen(db)
                            ensureSearchFts(db)
                        }
                    }
                )
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

        private fun ensureSearchFts(db: SupportSQLiteDatabase) {
            // Note: FTS is a best-effort optimization. If any statement fails, we keep the DB usable and
            // fall back to LIKE-based search in repository code.
            try {
                val initialized = queryMetadataValue(db, METADATA_FTS_INIT_KEY)
                val shouldRebuild = initialized != METADATA_FTS_INIT_VALUE

                ensureEntitiesFts(db)
                ensureEventsFts(db)
                ensureEdgeEvidenceFts(db)

                if (shouldRebuild) {
                    tryRebuildFts(db, "memory_entities_fts")
                    tryRebuildFts(db, "memory_events_fts")
                    tryRebuildFts(db, "memory_edge_evidence_fts")
                    upsertMetadataValue(db, METADATA_FTS_INIT_KEY, METADATA_FTS_INIT_VALUE)
                }
            } catch (t: Throwable) {
                FileLogger.e(TAG, "ensureSearchFts failed", t)
            }
        }

        private fun ensureEntitiesFts(db: SupportSQLiteDatabase) {
            val table = "memory_entities_fts"
            if (!createFts4TableIfNeeded(
                    db,
                    tableName = table,
                    columns = "entity_key, name",
                    contentTable = "memory_entities",
                    contentRowId = "id"
                )
            ) {
                return
            }
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_entities_fts_ai")
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_entities_fts_ad")
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_entities_fts_au")
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_entities_fts_ai
                AFTER INSERT ON memory_entities
                BEGIN
                  INSERT INTO $table(rowid, entity_key, name)
                  VALUES (new.id, new.entity_key, new.name);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_entities_fts_ad
                AFTER DELETE ON memory_entities
                BEGIN
                  INSERT INTO $table($table, rowid, entity_key, name)
                  VALUES ('delete', old.id, old.entity_key, old.name);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_entities_fts_au
                AFTER UPDATE ON memory_entities
                BEGIN
                  INSERT INTO $table($table, rowid, entity_key, name)
                  VALUES ('delete', old.id, old.entity_key, old.name);
                  INSERT INTO $table(rowid, entity_key, name)
                  VALUES (new.id, new.entity_key, new.name);
                END
                """.trimIndent()
            )
        }

        private fun ensureEventsFts(db: SupportSQLiteDatabase) {
            val table = "memory_events_fts"
            if (!createFts4TableIfNeeded(
                    db,
                    tableName = table,
                    columns = "content",
                    contentTable = "memory_events",
                    contentRowId = "id"
                )
            ) {
                return
            }
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_events_fts_ai")
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_events_fts_ad")
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_events_fts_au")
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_events_fts_ai
                AFTER INSERT ON memory_events
                BEGIN
                  INSERT INTO $table(rowid, content)
                  VALUES (new.id, new.content);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_events_fts_ad
                AFTER DELETE ON memory_events
                BEGIN
                  INSERT INTO $table($table, rowid, content)
                  VALUES ('delete', old.id, old.content);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_events_fts_au
                AFTER UPDATE ON memory_events
                BEGIN
                  INSERT INTO $table($table, rowid, content)
                  VALUES ('delete', old.id, old.content);
                  INSERT INTO $table(rowid, content)
                  VALUES (new.id, new.content);
                END
                """.trimIndent()
            )
        }

        private fun ensureEdgeEvidenceFts(db: SupportSQLiteDatabase) {
            val table = "memory_edge_evidence_fts"
            if (!createFts4TableIfNeeded(
                    db,
                    tableName = table,
                    columns = "excerpt",
                    contentTable = "memory_edge_evidence",
                    contentRowId = "id"
                )
            ) {
                return
            }
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_edge_evidence_fts_ai")
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_edge_evidence_fts_ad")
            db.execSQL("DROP TRIGGER IF EXISTS trg_memory_edge_evidence_fts_au")
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_edge_evidence_fts_ai
                AFTER INSERT ON memory_edge_evidence
                BEGIN
                  INSERT INTO $table(rowid, excerpt)
                  VALUES (new.id, new.excerpt);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_edge_evidence_fts_ad
                AFTER DELETE ON memory_edge_evidence
                BEGIN
                  INSERT INTO $table($table, rowid, excerpt)
                  VALUES ('delete', old.id, old.excerpt);
                END
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TRIGGER IF NOT EXISTS trg_memory_edge_evidence_fts_au
                AFTER UPDATE ON memory_edge_evidence
                BEGIN
                  INSERT INTO $table($table, rowid, excerpt)
                  VALUES ('delete', old.id, old.excerpt);
                  INSERT INTO $table(rowid, excerpt)
                  VALUES (new.id, new.excerpt);
                END
                """.trimIndent()
            )
        }

        private fun createFts4TableIfNeeded(
            db: SupportSQLiteDatabase,
            tableName: String,
            columns: String,
            contentTable: String,
            contentRowId: String
        ): Boolean {
            // Prefer unicode61 tokenizer + small prefix indexes for better CJK prefix matching.
            val variants = listOf(
                "CREATE VIRTUAL TABLE IF NOT EXISTS $tableName USING fts4($columns, content='$contentTable', content_rowid='$contentRowId', tokenize=unicode61, prefix='2,3,4')",
                "CREATE VIRTUAL TABLE IF NOT EXISTS $tableName USING fts4($columns, content='$contentTable', content_rowid='$contentRowId')",
            )
            for (sql in variants) {
                try {
                    db.execSQL(sql)
                    return true
                } catch (t: Throwable) {
                    FileLogger.e(TAG, "createFts4Table failed table=$tableName sql=$sql", t)
                }
            }
            return false
        }

        private fun tryRebuildFts(db: SupportSQLiteDatabase, tableName: String) {
            try {
                db.execSQL("INSERT INTO $tableName($tableName) VALUES('rebuild')")
            } catch (t: Throwable) {
                FileLogger.e(TAG, "rebuild fts failed table=$tableName", t)
            }
        }

        private fun queryMetadataValue(db: SupportSQLiteDatabase, key: String): String? {
            try {
                db.query("SELECT value FROM memory_metadata WHERE `key` = ? LIMIT 1", arrayOf(key)).use { c ->
                    return if (c.moveToFirst()) c.getString(0) else null
                }
            } catch (_: Throwable) {
                return null
            }
        }

        private fun upsertMetadataValue(db: SupportSQLiteDatabase, key: String, value: String) {
            try {
                db.execSQL(
                    "INSERT OR REPLACE INTO memory_metadata(`key`, value) VALUES(?, ?)",
                    arrayOf(key, value)
                )
            } catch (_: Throwable) {
            }
        }

        private const val METADATA_FTS_INIT_KEY = "fts_init_v1"
        private const val METADATA_FTS_INIT_VALUE = "1"
        private const val TAG = "MemoryDatabase"
    }
}
