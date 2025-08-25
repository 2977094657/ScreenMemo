package com.fqyw.screen_memo

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File

/**
 * 轻量级的原生端数据库助手
 * 目的：在 Flutter 端尚未就绪或异步延迟时，原生侧也能将截图元数据实时写入数据库。
 * 注意：路径与表结构需与 Flutter 端保持一致（分表结构）。
 */
object ScreenshotDatabaseHelper {

    private const val TAG = "ScreenshotDBHelper"
    private const val DB_DIR_RELATIVE = "output/databases"
    private const val DB_FILE_NAME = "screenshot_memo.db"
    
    fun insertIfNotExists(
        context: Context,
        appPackageName: String,
        appName: String,
        absoluteFilePath: String,
        captureTimeMillis: Long
    ) {
        var db: SQLiteDatabase? = null
        try {
            val dbPath = resolveDatabasePath(context) ?: return
            db = SQLiteDatabase.openDatabase(
                dbPath,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY
            )

            // 确保基础表与应用分表存在
            ensureSchema(db)
            ensureAppTableExists(db, appPackageName, appName)

            val tableName = getAppTableName(appPackageName)

            // 已存在则返回
            if (isFilePathExists(db, tableName, absoluteFilePath)) {
                return
            }

            val fileSize = getFileSizeSafe(absoluteFilePath)

            // 插入分表记录（app字段在分表中不再重复存储）
            val values = ContentValues().apply {
                put("file_path", absoluteFilePath)
                put("capture_time", captureTimeMillis)
                put("file_size", fileSize)
                put("is_deleted", 0)
                // created_at / updated_at 交由默认值填充
            }
            db.insert(tableName, null, values)

            // 维护聚合统计
            upsertAppStatsOnInsert(db, appPackageName, appName, fileSize, captureTimeMillis)
        } catch (e: Exception) {
            Log.w(TAG, "Native insertIfNotExists failed: ${e.message}")
            // 忽略原生侧入库异常，不影响截屏主流程
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    private fun resolveDatabasePath(context: Context): String? {
        return try {
            val base = context.getExternalFilesDir(null)?.absolutePath ?: return null
            val dbDir = File(base, DB_DIR_RELATIVE)
            if (!dbDir.exists()) {
                dbDir.mkdirs()
            }
            File(dbDir, DB_FILE_NAME).absolutePath
        } catch (_: Exception) {
            try {
                // 退化：使用应用内部数据库路径（与 Flutter 端备选一致）
                context.getDatabasePath(DB_FILE_NAME).absolutePath
            } catch (_: Exception) {
                null
            }
        }
    }

    // 与 lib/services/screenshot_database.dart 保持一致的基础表结构
    private fun ensureSchema(db: SQLiteDatabase) {
        try {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS app_registry (
                  app_package_name TEXT PRIMARY KEY,
                  app_name TEXT NOT NULL,
                  table_name TEXT NOT NULL,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS app_stats (
                  app_package_name TEXT PRIMARY KEY,
                  app_name TEXT NOT NULL,
                  total_count INTEGER NOT NULL DEFAULT 0,
                  total_size INTEGER NOT NULL DEFAULT 0,
                  last_capture_time INTEGER
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_app_stats_last ON app_stats(last_capture_time)")
        } catch (_: Exception) {
            // 忽略
        }
    }

    private fun sanitizePackageName(packageName: String): String {
        // 仅保留 \w，其他转为下划线
        return packageName.replace(Regex("[^\\w]"), "_")
    }

    private fun getAppTableName(packageName: String): String {
        return "screenshots_${sanitizePackageName(packageName)}"
    }

    private fun ensureAppTableExists(db: SQLiteDatabase, packageName: String, appName: String) {
        val tableName = getAppTableName(packageName)
        try {
            // 分表结构，与 lib/services/screenshot_database.dart 保持一致
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $tableName (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  file_path TEXT NOT NULL UNIQUE,
                  capture_time INTEGER NOT NULL,
                  file_size INTEGER NOT NULL DEFAULT 0,
                  is_deleted INTEGER NOT NULL DEFAULT 0,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
                  updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_${tableName}_capture_time ON $tableName(capture_time)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_${tableName}_file_path ON $tableName(file_path)")

            // 注册到 app_registry
            db.execSQL(
                "INSERT OR REPLACE INTO app_registry(app_package_name, app_name, table_name) VALUES(?, ?, ?)",
                arrayOf(packageName, appName, tableName)
            )
        } catch (_: Exception) {
            // 忽略
        }
    }

    private fun isFilePathExists(db: SQLiteDatabase, tableName: String, filePath: String): Boolean {
        var cursor: Cursor? = null
        return try {
            cursor = db.query(
                tableName,
                arrayOf("id"),
                "file_path = ?",
                arrayOf(filePath),
                null,
                null,
                null,
                "1"
            )
            cursor.moveToFirst()
        } catch (_: Exception) {
            false
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
        }
    }

    private fun upsertAppStatsOnInsert(
        db: SQLiteDatabase,
        packageName: String,
        appName: String,
        fileSize: Long,
        captureTime: Long
    ) {
        try {
            // 优先尝试 UPSERT（SQLite 3.24+）。老设备若不支持将抛异常并回退到重算。
            db.execSQL(
                """
                INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time)
                VALUES (?, ?, 1, ?, ?)
                ON CONFLICT(app_package_name) DO UPDATE SET
                  app_name=excluded.app_name,
                  total_count=app_stats.total_count + 1,
                  total_size=app_stats.total_size + excluded.total_size,
                  last_capture_time=CASE
                    WHEN excluded.last_capture_time > app_stats.last_capture_time THEN excluded.last_capture_time
                    ELSE app_stats.last_capture_time
                  END
                """.trimIndent(),
                arrayOf(packageName, appName, fileSize, captureTime)
            )
        } catch (_: Exception) {
            // 回退：全量重算该应用的聚合统计
            recomputeAppStatForPackage(db, packageName)
        }
    }

    private fun recomputeAppStatForPackage(db: SQLiteDatabase, packageName: String) {
        val tableName = getAppTableName(packageName)
        try {
            val cursor = db.rawQuery(
                "SELECT COUNT(*) as c, COALESCE(SUM(file_size),0) as s, MAX(capture_time) as t FROM $tableName",
                emptyArray()
            )
            cursor.use {
                if (it.moveToFirst()) {
                    val count = it.getLong(it.getColumnIndexOrThrow("c"))
                    val size = it.getLong(it.getColumnIndexOrThrow("s"))
                    val last = if (it.isNull(it.getColumnIndexOrThrow("t"))) null else it.getLong(it.getColumnIndexOrThrow("t"))

                    if (count <= 0L) {
                        db.delete("app_stats", "app_package_name = ?", arrayOf(packageName))
                        return
                    }

                    // 从 app_registry 取 app_name（若无则回退为包名）
                    val appName = try {
                        val c2 = db.query(
                            "app_registry",
                            arrayOf("app_name"),
                            "app_package_name = ?",
                            arrayOf(packageName),
                            null, null, null, "1"
                        )
                        c2.use { if (it.moveToFirst()) it.getString(0) else packageName }
                    } catch (_: Exception) { packageName }

                    db.execSQL(
                        """
                        INSERT INTO app_stats(app_package_name, app_name, total_count, total_size, last_capture_time)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(app_package_name) DO UPDATE SET
                          app_name=excluded.app_name,
                          total_count=excluded.total_count,
                          total_size=excluded.total_size,
                          last_capture_time=excluded.last_capture_time
                        """.trimIndent(),
                        arrayOf(packageName, appName, count, size, last)
                    )
                } else {
                    db.delete("app_stats", "app_package_name = ?", arrayOf(packageName))
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "recomputeAppStatForPackage failed: ${e.message}")
        }
    }

    private fun getFileSizeSafe(path: String): Long {
        return try {
            val f = File(path)
            if (f.exists()) f.length() else 0L
        } catch (_: Exception) { 0L }
    }
}