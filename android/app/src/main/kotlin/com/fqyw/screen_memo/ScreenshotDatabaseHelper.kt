package com.fqyw.screen_memo

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
 
import java.io.File
import java.util.Locale

/**
 * 轻量级的原生端数据库助手
 * 目的：在 Flutter 端尚未就绪或异步延迟时，原生侧也能将截图元数据实时写入数据库。
 * 注意：路径与表结构需与 Flutter 端保持一致（分表结构）。
 */
object ScreenshotDatabaseHelper {

    private const val TAG = "ScreenshotDBHelper"
    private const val MASTER_DB_DIR_RELATIVE = "output/databases"
    private const val MASTER_DB_FILE_NAME = "screenshot_memo.db"
    private const val SHARDS_DIR_RELATIVE = "output/databases/shards"
    
    fun insertIfNotExists(
        context: Context,
        appPackageName: String,
        appName: String,
        absoluteFilePath: String,
        captureTimeMillis: Long,
        pageUrl: String?
    ) {
        var db: SQLiteDatabase? = null
        var shardDb: SQLiteDatabase? = null
        try {
            FileLogger.i(TAG, "insertIfNotExists 开始：包名=${appPackageName} 时间=${captureTimeMillis} 路径=${absoluteFilePath}")
            val masterDbPath = resolveMasterDbPath(context) ?: return
            db = SQLiteDatabase.openDatabase(masterDbPath, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY)
            ensureSchema(db)
            registerAppIfNeeded(db, appPackageName, appName)

            val cal = java.util.Calendar.getInstance().apply { timeInMillis = captureTimeMillis }
            val year = cal.get(java.util.Calendar.YEAR)
            val month = cal.get(java.util.Calendar.MONTH) + 1
            shardDb = openShardDb(context, appPackageName, year)
            if (shardDb == null) return
            ensureMonthTable(shardDb!!, year, month)
            val tableName = monthTableName(year, month)

            // 已存在则返回
            if (isFilePathExists(shardDb!!, tableName, absoluteFilePath)) return

            val fileSize = getFileSizeSafe(absoluteFilePath)
            val values = ContentValues().apply {
                put("file_path", absoluteFilePath)
                put("capture_time", captureTimeMillis)
                put("file_size", fileSize)
                put("is_deleted", 0)
                if (!pageUrl.isNullOrBlank()) put("page_url", pageUrl)
            }
            val rowId = shardDb!!.insert(tableName, null, values)
            FileLogger.i(TAG, "插入成功：table=${tableName} rowId=${rowId}")

            // 维护聚合统计（写主库）
            upsertAppStatsOnInsert(db, appPackageName, appName, fileSize, captureTimeMillis)
            FileLogger.i(TAG, "更新 app_stats 成功：包名=${appPackageName} last=${captureTimeMillis}")
        } catch (e: Exception) {
            FileLogger.w(TAG, "原生 insertIfNotExists 失败：${e.message}")
            // 忽略原生侧入库异常，不影响截屏主流程
        } finally {
            try { db?.close() } catch (_: Exception) {}
            try { shardDb?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 更新指定文件的 OCR 文本（按绝对路径定位）。
     * 路径格式示例：.../output/screen/<package>/<yyyy-MM>/<dd>/<filename>
     * 通过路径解析出包名与年月，直接定位到对应的分库月表进行更新。
     */
    fun updateOcrTextByFilePath(context: Context, absoluteFilePath: String, ocrText: String?) {
        var shardDb: SQLiteDatabase? = null
        try {
            val pkg = extractPackageFromPath(absoluteFilePath) ?: return
            val ym = extractYearMonthFromPath(absoluteFilePath) ?: return
            val year = ym.first
            val month = ym.second

            shardDb = openShardDb(context, pkg, year)
            if (shardDb == null) return
            val table = monthTableName(year, month)
            ensureMonthTable(shardDb!!, year, month)
            // 幂等添加列（老表可能缺列）
            try { shardDb!!.execSQL("ALTER TABLE $table ADD COLUMN ocr_text TEXT") } catch (_: Exception) {}
            try { shardDb!!.execSQL("ALTER TABLE $table ADD COLUMN updated_at INTEGER") } catch (_: Exception) {}

            val cv = ContentValues().apply {
                put("ocr_text", ocrText)
                put("updated_at", System.currentTimeMillis())
            }
            shardDb!!.update(table, cv, "file_path = ?", arrayOf(absoluteFilePath))
        } catch (_: Exception) {
        } finally {
            try { shardDb?.close() } catch (_: Exception) {}
        }
    }

    private fun extractPackageFromPath(path: String): String? {
        // 适配新旧结构：.../output/screen/<package>/... 或 .../<package>/screenshots/...
        val parts = path.replace('\\', '/').split('/')
        for (i in 0 until parts.size - 1) {
            val seg = parts[i]
            if (seg == "output" && i + 2 < parts.size && parts[i + 1] == "screen") {
                return parts[i + 2]
            }
            if (i + 1 < parts.size && parts[i + 1] == "screenshots") {
                return seg
            }
        }
        return null
    }

    private fun extractYearMonthFromPath(path: String): Pair<Int, Int>? {
        // 解析 yyyy-MM 片段
        val normalized = path.replace('\\', '/')
        val regex = Regex("/(\\d{4})-(\\d{2})/")
        val m = regex.find(normalized) ?: return null
        val year = m.groupValues[1].toIntOrNull() ?: return null
        val month = m.groupValues[2].toIntOrNull() ?: return null
        return Pair(year, month)
    }

    fun resolveMasterDbPath(context: Context): String? {
        return try {
            val base = context.filesDir.absolutePath
            val dbDir = File(base, MASTER_DB_DIR_RELATIVE)
            if (!dbDir.exists()) {
                dbDir.mkdirs()
            }
            File(dbDir, MASTER_DB_FILE_NAME).absolutePath
        } catch (_: Exception) {
            try {
                // 退化：使用应用内部数据库路径（与 Flutter 端备选一致）
                context.getDatabasePath(MASTER_DB_FILE_NAME).absolutePath
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
                  last_capture_time INTEGER,
                  last_dhash INTEGER
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_app_stats_last ON app_stats(last_capture_time)")
            // 分库注册表
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS shard_registry (
                  app_package_name TEXT NOT NULL,
                  year INTEGER NOT NULL,
                  db_path TEXT NOT NULL,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
                  PRIMARY KEY (app_package_name, year)
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS user_settings (
                  key TEXT PRIMARY KEY,
                  value TEXT,
                  updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_user_settings_updated_at ON user_settings(updated_at)")
        } catch (_: Exception) {
            // 忽略
        }
    }

    private fun sanitizePackageName(packageName: String): String {
        // 仅保留 \w，其他转为下划线
        return packageName.replace(Regex("[^\\w]"), "_")
    }

    fun resolveExpectedShardDbPath(context: Context, packageName: String, year: Int): String? {
        return try {
            val base = context.filesDir.absolutePath
            val shardsRoot = File(base, SHARDS_DIR_RELATIVE)
            val sanitized = sanitizePackageName(packageName)
            File(
                File(File(shardsRoot, sanitized), "$year"),
                "smm_${sanitized}_${year}.db"
            ).absolutePath
        } catch (_: Exception) {
            null
        }
    }

    fun resolveExistingShardDbPath(
        context: Context,
        packageName: String,
        year: Int,
        registryDbPath: String?
    ): String? {
        val candidates = ArrayList<String>(2)
        val registryPath = registryDbPath?.trim().orEmpty()
        if (registryPath.isNotEmpty()) {
            candidates.add(registryPath)
        }
        val expectedPath = resolveExpectedShardDbPath(context, packageName, year)
        if (!expectedPath.isNullOrBlank() && expectedPath != registryPath) {
            candidates.add(expectedPath)
        }
        for (path in candidates) {
            try {
                val file = File(path)
                if (file.exists() && file.isFile) {
                    return path
                }
            } catch (_: Exception) {}
        }
        return null
    }

    private fun openShardDb(context: Context, packageName: String, year: Int): SQLiteDatabase? {
        return try {
            val base = context.filesDir.absolutePath
            val shardsRoot = File(base, SHARDS_DIR_RELATIVE)
            val pkgDir = File(File(shardsRoot, sanitizePackageName(packageName)), "$year")
            if (!pkgDir.exists()) pkgDir.mkdirs()
            val file = File(pkgDir, "smm_${sanitizePackageName(packageName)}_${year}.db")
            val db = SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY)
            // 注册分库到主库
            try {
                val masterPath = resolveMasterDbPath(context)
                if (masterPath != null) {
                    val master = SQLiteDatabase.openDatabase(masterPath, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY)
                    ensureSchema(master)
                    master.execSQL(
                        "INSERT OR REPLACE INTO shard_registry(app_package_name, year, db_path) VALUES(?, ?, ?)",
                        arrayOf(packageName, year, file.absolutePath)
                    )
                    master.close()
                }
            } catch (_: Exception) {}
            db
        } catch (_: Exception) { null }
    }

    private fun monthTableName(year: Int, month: Int): String {
        val mm = if (month < 10) "0$month" else month.toString()
        return "shots_${year}${mm}"
    }

    private fun ensureMonthTable(db: SQLiteDatabase, year: Int, month: Int) {
        val table = monthTableName(year, month)
        try {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $table (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  file_path TEXT NOT NULL UNIQUE,
                  capture_time INTEGER NOT NULL,
                  file_size INTEGER NOT NULL DEFAULT 0,
                  page_url TEXT,
                  ocr_text TEXT,
                  is_deleted INTEGER NOT NULL DEFAULT 0,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
                  updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_${table}_capture_time ON $table(capture_time)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_${table}_file_path ON $table(file_path)")
            // 兜底为旧表添加缺失列
            try { db.execSQL("ALTER TABLE $table ADD COLUMN ocr_text TEXT") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE $table ADD COLUMN updated_at INTEGER") } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    private fun registerAppIfNeeded(db: SQLiteDatabase, packageName: String, appName: String) {
        try {
            db.execSQL(
                "INSERT OR REPLACE INTO app_registry(app_package_name, app_name, table_name) VALUES(?, ?, ?)",
                arrayOf(packageName, appName, "sharded")
            )
        } catch (_: Exception) {}
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
                  last_capture_time=CASE WHEN app_stats.last_capture_time IS NULL OR excluded.last_capture_time > app_stats.last_capture_time THEN excluded.last_capture_time ELSE app_stats.last_capture_time END
                """.trimIndent(),
                arrayOf(packageName, appName, fileSize, captureTime)
            )
        } catch (_: Exception) {
            // 回退：全量重算该应用的聚合统计
            recomputeAppStatForPackage(db, packageName)
        }
    }

    /**
     * 读取指定应用的裁剪画面签名（可能为 null）。
     */
    fun getLastSignature(context: Context, packageName: String): String? {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            val dbPath = resolveMasterDbPath(context) ?: return null
            db = SQLiteDatabase.openDatabase(
                dbPath,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY
            )
            ensureSchema(db)
            cursor = db.rawQuery("SELECT last_dhash FROM app_stats WHERE app_package_name = ? LIMIT 1", arrayOf(packageName))
            if (cursor.moveToFirst()) {
                if (cursor.isNull(0)) {
                    null
                } else {
                    when (cursor.getType(0)) {
                        Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(0).toString()
                        Cursor.FIELD_TYPE_STRING -> cursor.getString(0)
                        Cursor.FIELD_TYPE_BLOB -> {
                            val bytes = cursor.getBlob(0)
                            bytes?.joinToString(separator = "") { String.format(Locale.US, "%02x", it) }
                        }
                        else -> cursor.getString(0)
                    }
                }
            } else null
        } catch (_: Exception) {
            null
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 设置/更新指定应用的裁剪画面签名；若记录不存在将插入一条记录（保持其他聚合列为默认值）
     */
    fun setLastSignature(context: Context, packageName: String, appNameOrNull: String?, value: String) {
        var db: SQLiteDatabase? = null
        try {
            val dbPath = resolveMasterDbPath(context) ?: return
            db = SQLiteDatabase.openDatabase(
                dbPath,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY
            )
            ensureSchema(db)

            val appName = appNameOrNull ?: packageName

            // 尝试 UPDATE；若影响行数为0则 INSERT
            val cv = ContentValues().apply { put("last_dhash", value) }
            val updated = db.update("app_stats", cv, "app_package_name = ?", arrayOf(packageName))
            if (updated <= 0) {
                val values = ContentValues().apply {
                    put("app_package_name", packageName)
                    put("app_name", appName)
                    put("total_count", 0)
                    put("total_size", 0)
                    put("last_capture_time", null as Long?)
                    put("last_dhash", value)
                }
                db.insert("app_stats", null, values)
            }
        } catch (_: Exception) {
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    private fun recomputeAppStatForPackage(db: SQLiteDatabase, packageName: String) {
        try {
            var totalCount = 0L
            var totalSize = 0L
            var lastCapture = 0L

            // 从主库读取该应用的所有年库路径
            val years = db.rawQuery(
                "SELECT year, db_path FROM shard_registry WHERE app_package_name = ?",
                arrayOf(packageName)
            )
            years.use { yCur ->
                while (yCur.moveToNext()) {
                    val year = yCur.getInt(0)
                    val path = yCur.getString(1)
                    try {
                        val shard = SQLiteDatabase.openDatabase(
                            path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY
                        )
                        // 遍历 12 个月表进行聚合
                        for (m in 1..12) {
                            val table = monthTableName(year, m)
                            try {
                                // 检查表是否存在
                                val chk = shard.rawQuery(
                                    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                                    arrayOf(table)
                                )
                                val exists = chk.use { it.moveToFirst() }
                                if (!exists) continue

                                val rows = shard.rawQuery(
                                    "SELECT COUNT(*) as c, COALESCE(SUM(file_size),0) as s, COALESCE(MAX(capture_time),0) as t FROM $table",
                                    emptyArray()
                                )
                                rows.use { r ->
                                    if (r.moveToFirst()) {
                                        totalCount += r.getLong(0)
                                        totalSize += r.getLong(1)
                                        val tmax = r.getLong(2)
                                        if (tmax > lastCapture) lastCapture = tmax
                                    }
                                }
                            } catch (_: Exception) {
                                // 忽略单表异常
                            }
                        }
                        try { shard.close() } catch (_: Exception) {}
                    } catch (_: Exception) {
                        // 忽略单年库异常
                    }
                }
            }

            if (totalCount <= 0L) {
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
                arrayOf(packageName, appName, totalCount, totalSize, lastCapture)
            )
        } catch (e: Exception) {
            FileLogger.w(TAG, "重算应用统计失败：${e.message}")
        }
    }

    private fun getFileSizeSafe(path: String): Long {
        return try {
            val f = File(path)
            if (f.exists()) f.length() else 0L
        } catch (_: Exception) { 0L }
    }
}
