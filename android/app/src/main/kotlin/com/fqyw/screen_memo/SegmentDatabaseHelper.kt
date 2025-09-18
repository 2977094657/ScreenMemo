package com.fqyw.screen_memo

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 段落与AI结果持久化（原生侧复用主库 screenshot_memo.db）
 * - 表结构：segments / segment_samples / segment_results
 * - 仅在主库中创建与维护，避免分库复杂度
 */
object SegmentDatabaseHelper {

    private const val TAG = "SegmentDB"
    private const val MASTER_DB_DIR_RELATIVE = "output/databases"
    private const val MASTER_DB_FILE_NAME = "screenshot_memo.db"

    data class Segment(
        val id: Long,
        val startTime: Long,
        val endTime: Long,
        val durationSec: Int,
        val sampleIntervalSec: Int,
        val status: String
    )

    data class Sample(
        val id: Long,
        val segmentId: Long,
        val captureTime: Long,
        val filePath: String,
        val appPackageName: String,
        val appName: String,
        val positionIndex: Int
    )

    data class ShotInfo(
        val filePath: String,
        val captureTime: Long,
        val appPackageName: String,
        val appName: String
    )

    // =============== 基础 ===============

    private fun resolveMasterDbPath(context: Context): String? {
        return try {
            val base = context.getExternalFilesDir(null)?.absolutePath ?: return null
            val dbDir = File(base, MASTER_DB_DIR_RELATIVE)
            if (!dbDir.exists()) dbDir.mkdirs()
            File(dbDir, MASTER_DB_FILE_NAME).absolutePath
        } catch (_: Exception) {
            try { context.getDatabasePath(MASTER_DB_FILE_NAME).absolutePath } catch (_: Exception) { null }
        }
    }

    private fun openMasterDb(context: Context, writable: Boolean = true): SQLiteDatabase? {
        return try {
            val path = resolveMasterDbPath(context) ?: return null
            val flags = if (writable) SQLiteDatabase.OPEN_READWRITE else SQLiteDatabase.OPEN_READONLY
            val db = SQLiteDatabase.openDatabase(path, null, flags or SQLiteDatabase.CREATE_IF_NECESSARY)
            ensureSchema(db)
            db
        } catch (e: Exception) {
            Log.w(TAG, "openMasterDb failed: ${e.message}")
            null
        }
    }

    private fun ensureSchema(db: SQLiteDatabase) {
        try {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS segments (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  start_time INTEGER NOT NULL,
                  end_time INTEGER NOT NULL,
                  duration_sec INTEGER NOT NULL,
                  sample_interval_sec INTEGER NOT NULL,
                  status TEXT NOT NULL,
                  app_packages TEXT,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
                  updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_segments_time ON segments(start_time, end_time)")
            // 强一致性：每个时间窗口仅允许一个段落
            db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS uniq_segments_window ON segments(start_time, end_time)")

            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS segment_samples (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  segment_id INTEGER NOT NULL,
                  capture_time INTEGER NOT NULL,
                  file_path TEXT NOT NULL,
                  app_package_name TEXT NOT NULL,
                  app_name TEXT NOT NULL,
                  position_index INTEGER NOT NULL,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
                  UNIQUE(segment_id, file_path)
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_segment_samples_seg ON segment_samples(segment_id, position_index)")

            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS segment_results (
                  segment_id INTEGER PRIMARY KEY,
                  ai_provider TEXT,
                  ai_model TEXT,
                  output_text TEXT,
                  structured_json TEXT,
                  categories TEXT,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
        } catch (_: Exception) {}
    }

    // =============== 段落 CRUD ===============

    fun createSegment(
        context: Context,
        startMillis: Long,
        endMillis: Long,
        durationSec: Int,
        sampleIntervalSec: Int,
        status: String
    ): Long {
        var db: SQLiteDatabase? = null
        return try {
            db = openMasterDb(context, writable = true) ?: return -1
            // 再次快速判重，降低并发窗口下的重复创建概率
            if (hasSegmentExact(context, startMillis, endMillis)) {
                return findSegmentIdByWindow(context, startMillis, endMillis)
            }
            val cv = ContentValues().apply {
                put("start_time", startMillis)
                put("end_time", endMillis)
                put("duration_sec", durationSec)
                put("sample_interval_sec", sampleIntervalSec)
                put("status", status)
            }
            // 唯一索引下的安全插入：冲突时忽略并回查 ID
            val rowId = db.insertWithOnConflict("segments", null, cv, SQLiteDatabase.CONFLICT_IGNORE)
            if (rowId > 0) rowId else findSegmentIdByWindow(context, startMillis, endMillis)
        } catch (e: Exception) {
            Log.w(TAG, "createSegment failed: ${e.message}")
            -1
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun updateSegmentStatus(context: Context, segmentId: Long, status: String, appPackagesJson: String? = null) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            val cv = ContentValues().apply {
                put("status", status)
                put("updated_at", System.currentTimeMillis())
                if (!appPackagesJson.isNullOrBlank()) put("app_packages", appPackagesJson)
            }
            db.update("segments", cv, "id = ?", arrayOf(segmentId.toString()))
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun getCollectingSegment(context: Context): Segment? {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return null
            cursor = db.query(
                "segments",
                arrayOf("id","start_time","end_time","duration_sec","sample_interval_sec","status"),
                "status = ?",
                arrayOf("collecting"),
                null, null,
                "id DESC",
                "1"
            )
            if (cursor.moveToFirst()) {
                Segment(
                    id = cursor.getLong(0),
                    startTime = cursor.getLong(1),
                    endTime = cursor.getLong(2),
                    durationSec = cursor.getInt(3),
                    sampleIntervalSec = cursor.getInt(4),
                    status = cursor.getString(5)
                )
            } else null
        } catch (_: Exception) {
            null
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    fun saveSamples(context: Context, segmentId: Long, samples: List<Sample>) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            db.beginTransaction()
            try {
                // 先清空该段落的旧样本，避免多次采样导致样本数叠加
                db.delete("segment_samples", "segment_id = ?", arrayOf(segmentId.toString()))
                for (s in samples) {
                    val cv = ContentValues().apply {
                        put("segment_id", segmentId)
                        put("capture_time", s.captureTime)
                        put("file_path", s.filePath)
                        put("app_package_name", s.appPackageName)
                        put("app_name", s.appName)
                        put("position_index", s.positionIndex)
                    }
                    db.insertWithOnConflict("segment_samples", null, cv, SQLiteDatabase.CONFLICT_IGNORE)
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun saveResult(
        context: Context,
        segmentId: Long,
        provider: String,
        model: String,
        outputText: String,
        structuredJson: String?,
        categories: String?
    ) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            val cv = ContentValues().apply {
                put("segment_id", segmentId)
                put("ai_provider", provider)
                put("ai_model", model)
                put("output_text", outputText)
                if (!structuredJson.isNullOrBlank()) put("structured_json", structuredJson)
                if (!categories.isNullOrBlank()) put("categories", categories)
            }
            db.insertWithOnConflict("segment_results", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    // =============== 查询截图（跨分库月表） ===============

    /**
     * 查询指定时间范围内的所有截图（全局，按时间升序）。
     */
    fun listShotsBetween(context: Context, startMillis: Long, endMillis: Long, perTableLimit: Int = 2000): List<ShotInfo> {
        val result = ArrayList<ShotInfo>()
        var master: SQLiteDatabase? = null
        try {
            master = openMasterDb(context, writable = false) ?: return emptyList()

            // 预读 app 名称
            val appNameMap = HashMap<String, String>()
            try {
                val c = master.query("app_registry", arrayOf("app_package_name","app_name"), null, null, null, null, null)
                c.use { cur ->
                    while (cur.moveToNext()) {
                        appNameMap[cur.getString(0)] = cur.getString(1) ?: cur.getString(0)
                    }
                }
            } catch (_: Exception) {}

            // 需要涉及的 (package, year)
            val shards = master.query("shard_registry", arrayOf("app_package_name","year","db_path"), null, null, null, null, "year DESC")
            shards.use { cur ->
                while (cur.moveToNext()) {
                    val pkg = cur.getString(0)
                    val year = cur.getInt(1)
                    val dbPath = cur.getString(2)
                    // 仅处理范围涉及的年份
                    val sy = java.util.Calendar.getInstance().apply { timeInMillis = startMillis }.get(java.util.Calendar.YEAR)
                    val ey = java.util.Calendar.getInstance().apply { timeInMillis = endMillis }.get(java.util.Calendar.YEAR)
                    if (year < sy || year > ey) continue

                    var shard: SQLiteDatabase? = null
                    try {
                        shard = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY)
                        // 遍历所有月份
                        for (m in 1..12) {
                            val table = monthTableName(year, m)
                            if (!tableExists(shard, table)) continue
                            try {
                                val rows = shard.query(
                                    table,
                                    arrayOf("file_path","capture_time"),
                                    "capture_time >= ? AND capture_time <= ? AND is_deleted = 0",
                                    arrayOf(startMillis.toString(), endMillis.toString()),
                                    null, null,
                                    "capture_time ASC",
                                    perTableLimit.toString()
                                )
                                rows.use { rc ->
                                    while (rc.moveToNext()) {
                                        val path = rc.getString(0)
                                        val ts = rc.getLong(1)
                                        val appName = appNameMap[pkg] ?: pkg
                                        result.add(ShotInfo(path, ts, pkg, appName))
                                    }
                                }
                            } catch (_: Exception) {}
                        }
                    } catch (_: Exception) {
                    } finally { try { shard?.close() } catch (_: Exception) {} }
                }
            }
        } catch (_: Exception) {
        } finally { try { master?.close() } catch (_: Exception) {} }
        result.sortBy { it.captureTime }
        return result
    }

    /**
     * 查询某时间范围内，最新一个段落的 end_time（降序取第一）。
     * 若不存在则返回 null。
     */
    fun getLastSegmentEndTimeInRange(context: Context, startMillis: Long, endMillis: Long): Long? {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return null
            cursor = db.query(
                "segments",
                arrayOf("end_time"),
                "start_time >= ? AND start_time <= ?",
                arrayOf(startMillis.toString(), endMillis.toString()),
                null, null,
                "end_time DESC",
                "1"
            )
            if (cursor.moveToFirst()) cursor.getLong(0) else null
        } catch (_: Exception) {
            null
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 判断是否已存在起止时间完全一致的段落，避免重复创建。
     */
    fun hasSegmentExact(context: Context, startMillis: Long, endMillis: Long): Boolean {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return false
            cursor = db.query(
                "segments",
                arrayOf("id"),
                "start_time = ? AND end_time = ?",
                arrayOf(startMillis.toString(), endMillis.toString()),
                null, null,
                null,
                "1"
            )
            cursor.moveToFirst()
        } catch (_: Exception) {
            false
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 列出当前 status=collecting 的段落（按 end_time 升序）。
     */
    fun listCollectingSegments(context: Context, limit: Int = 100): List<Segment> {
        val list = ArrayList<Segment>()
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            cursor = db.query(
                "segments",
                arrayOf("id","start_time","end_time","duration_sec","sample_interval_sec","status"),
                "status = ?",
                arrayOf("collecting"),
                null, null,
                "end_time ASC",
                limit.toString()
            )
            while (cursor.moveToNext()) {
                list.add(
                    Segment(
                        id = cursor.getLong(0),
                        startTime = cursor.getLong(1),
                        endTime = cursor.getLong(2),
                        durationSec = cursor.getInt(3),
                        sampleIntervalSec = cursor.getInt(4),
                        status = cursor.getString(5)
                    )
                )
            }
        } catch (_: Exception) {
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
        return list
    }

    /**
     * 查询：给定时间窗口的 segment 是否已有任一结果（用于跳过重复总结）。
     */
    fun hasAnyResultForWindow(context: Context, startMillis: Long, endMillis: Long): Boolean {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return false
            cursor = db.rawQuery(
                """
                SELECT 1
                FROM segments s
                JOIN segment_results r ON r.segment_id = s.id
                WHERE s.start_time = ? AND s.end_time = ?
                LIMIT 1
                """.trimIndent(),
                arrayOf(startMillis.toString(), endMillis.toString())
            )
            cursor.moveToFirst()
        } catch (_: Exception) { false } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 查询：某个 segment 是否已经有结果。
     */
    fun hasResultForSegment(context: Context, segmentId: Long): Boolean {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return false
            cursor = db.query(
                "segment_results",
                arrayOf("segment_id"),
                "segment_id = ?",
                arrayOf(segmentId.toString()),
                null, null,
                null,
                "1"
            )
            cursor.moveToFirst()
        } catch (_: Exception) { false } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 根据时间窗口查找已存在的 segment ID，找不到返回 -1。
     */
    fun findSegmentIdByWindow(context: Context, startMillis: Long, endMillis: Long): Long {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return -1
            cursor = db.query(
                "segments",
                arrayOf("id"),
                "start_time = ? AND end_time = ?",
                arrayOf(startMillis.toString(), endMillis.toString()),
                null, null,
                "id DESC",
                "1"
            )
            if (cursor.moveToFirst()) cursor.getLong(0) else -1
        } catch (_: Exception) { -1 } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 清理历史重复段（同一窗口存在多个段）。
     * 策略：优先保留“已有结果”的段；若都无结果则保留最小ID。
     * 返回删除数量。
     */
    fun cleanupDuplicateSegments(context: Context, limitGroups: Int = 50): Int {
        var db: SQLiteDatabase? = null
        var totalDeleted = 0
        try {
            db = openMasterDb(context, writable = true) ?: return 0
            // 找出重复窗口（分组，限制一次处理数量）
            val sql = """
                SELECT start_time, end_time, COUNT(*) as c
                FROM segments
                GROUP BY start_time, end_time
                HAVING c > 1
                ORDER BY start_time DESC
                LIMIT ?
            """.trimIndent()
            val cur = db.rawQuery(sql, arrayOf(limitGroups.toString()))
            cur.use { gcur ->
                while (gcur.moveToNext()) {
                    val s = gcur.getLong(0)
                    val e = gcur.getLong(1)
                    // 列出该窗口的所有段，并标注是否有结果
                    val list = ArrayList<Pair<Long, Boolean>>()
                    val cur2 = db.rawQuery(
                        """
                        SELECT s.id, CASE WHEN r.segment_id IS NULL THEN 0 ELSE 1 END AS has_result
                        FROM segments s
                        LEFT JOIN segment_results r ON r.segment_id = s.id
                        WHERE s.start_time = ? AND s.end_time = ?
                        ORDER BY has_result DESC, s.id ASC
                        """.trimIndent(),
                        arrayOf(s.toString(), e.toString())
                    )
                    cur2.use { c2 ->
                        while (c2.moveToNext()) {
                            list.add(Pair(c2.getLong(0), c2.getInt(1) == 1))
                        }
                    }
                    if (list.size <= 1) continue
                    val keepId = list.first().first
                    // 删除其他 ID 的样本与结果、段
                    for (i in 1 until list.size) {
                        val delId = list[i].first
                        try {
                            db.beginTransaction()
                            db.delete("segment_results", "segment_id = ?", arrayOf(delId.toString()))
                            db.delete("segment_samples", "segment_id = ?", arrayOf(delId.toString()))
                            val cnt = db.delete("segments", "id = ?", arrayOf(delId.toString()))
                            db.setTransactionSuccessful()
                            totalDeleted += cnt
                        } finally {
                            try { db.endTransaction() } catch (_: Exception) {}
                        }
                    }
                }
            }
        } catch (_: Exception) {
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
        return totalDeleted
    }

    private fun tableExists(db: SQLiteDatabase, table: String): Boolean {
        var c: Cursor? = null
        return try {
            c = db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?", arrayOf(table))
            c.moveToFirst()
        } catch (_: Exception) { false } finally { try { c?.close() } catch (_: Exception) {} }
    }

    private fun monthTableName(year: Int, month: Int): String {
        val mm = if (month < 10) "0$month" else month.toString()
        return "shots_${year}${mm}"
    }
}


