package com.fqyw.screen_memo.memory.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

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
            return Room.databaseBuilder(appContext, MemoryDatabase::class.java, DATABASE_NAME)
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
    }
}

