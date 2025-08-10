package com.fqyw.screen_memo

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * 轻量级的原生端数据库助手
 * 目的：在 Flutter 引擎未就绪时，原生侧也能将截图元数据实时写入数据库。
 * 注意：路径与表结构需与 Flutter 端保持一致。
 */
object ScreenshotDatabaseHelper {

    private const val DB_DIR_RELATIVE = "output/databases"
    private const val DB_NAME = "screenshot_memo.db"

    private fun getDatabasePath(context: Context): String? {
        return try {
            val baseDir = context.getExternalFilesDir(null) ?: return null
            val dbDir = File(baseDir, DB_DIR_RELATIVE)
            if (!dbDir.exists()) {
                dbDir.mkdirs()
            }
            File(dbDir, DB_NAME).absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun ensureSchema(db: SQLiteDatabase) {
        // 与 lib/services/screenshot_database.dart 保持一致
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS screenshots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              app_package_name TEXT NOT NULL,
              app_name TEXT NOT NULL,
              file_path TEXT NOT NULL UNIQUE,
              capture_time INTEGER NOT NULL,
              file_size INTEGER NOT NULL DEFAULT 0,
              is_deleted INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
              updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_app_package_name ON screenshots(app_package_name)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_capture_time ON screenshots(capture_time)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_is_deleted ON screenshots(is_deleted)")
    }

    private fun isFilePathExists(db: SQLiteDatabase, filePath: String): Boolean {
        var cursor: Cursor? = null
        return try {
            cursor = db.query(
                "screenshots",
                arrayOf("id"),
                "file_path = ?",
                arrayOf(filePath),
                null, null, null, "1"
            )
            cursor.moveToFirst()
        } catch (_: Exception) {
            false
        } finally {
            cursor?.close()
        }
    }

    fun insertIfNotExists(
        context: Context,
        appPackageName: String,
        appName: String,
        absoluteFilePath: String,
        captureTimeMillis: Long
    ) {
        try {
            val dbPath = getDatabasePath(context) ?: return
            val db = SQLiteDatabase.openOrCreateDatabase(dbPath, null)
            ensureSchema(db)

            if (isFilePathExists(db, absoluteFilePath)) {
                db.close()
                return
            }

            val file = File(absoluteFilePath)
            val fileSize = if (file.exists()) file.length() else 0L

            val values = ContentValues().apply {
                put("app_package_name", appPackageName)
                put("app_name", appName)
                put("file_path", absoluteFilePath)
                put("capture_time", captureTimeMillis)
                put("file_size", fileSize)
                put("is_deleted", 0)
                // created_at / updated_at 由默认值填充
            }

            db.insert("screenshots", null, values)
            db.close()
        } catch (_: Exception) {
            // 忽略原生侧入库异常，不影响截屏主流程
        }
    }
}

