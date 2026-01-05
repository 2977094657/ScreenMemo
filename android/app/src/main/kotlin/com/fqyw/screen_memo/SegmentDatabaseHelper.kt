package com.fqyw.screen_memo

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
 
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
        val status: String,
        val appPackages: String? = null,
        val createdAt: Long? = null,
        val updatedAt: Long? = null
    )
    data class SegmentResult(
        val segmentId: Long,
        val aiProvider: String?,
        val aiModel: String?,
        val outputText: String?,
        val structuredJson: String?,
        val categories: String?
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

    private data class AiImageMeta(
        var tagsJson: String? = null,
        var nsfw: Int? = null,
        var description: String? = null,
        var descriptionRange: String? = null
    )

    private fun Cursor.getStringOrNull(index: Int): String? = if (isNull(index)) null else getString(index)
    private fun Cursor.getLongOrNull(index: Int): Long? = if (isNull(index)) null else getLong(index)
    private fun Cursor.getDoubleOrNull(index: Int): Double? = if (isNull(index)) null else getDouble(index)

    // =============== 基础 ===============

    private fun resolveMasterDbPath(context: Context): String? {
        return try {
            val base = context.filesDir.absolutePath
            val dbDir = File(base, MASTER_DB_DIR_RELATIVE)
            if (!dbDir.exists()) dbDir.mkdirs()
            File(dbDir, MASTER_DB_FILE_NAME).absolutePath
        } catch (_: Exception) {
            try { context.getDatabasePath(MASTER_DB_FILE_NAME).absolutePath } catch (_: Exception) { null }
        }
    }

    // Debug/diagnostic helper: expose resolved master DB path for Flutter.
    fun debugResolveMasterDbPath(context: Context): String? = resolveMasterDbPath(context)

    /** 按ID读取段落 */
    fun getSegmentById(context: Context, id: Long): Segment? {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return null
            cursor = db.query(
                "segments",
                arrayOf("id","start_time","end_time","duration_sec","sample_interval_sec","status","app_packages","created_at","updated_at"),
                "id = ?",
                arrayOf(id.toString()),
                null,null,
                null,
                "1"
            )
            if (cursor.moveToFirst()) Segment(
                id = cursor.getLong(0),
                startTime = cursor.getLong(1),
                endTime = cursor.getLong(2),
                durationSec = cursor.getInt(3),
                sampleIntervalSec = cursor.getInt(4),
                status = cursor.getString(5),
                appPackages = cursor.getStringOrNull(6),
                createdAt = cursor.getLongOrNull(7),
                updatedAt = cursor.getLongOrNull(8)
            ) else null
        } catch (_: Exception) { null } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
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
            FileLogger.w(TAG, "打开主库失败：${e.message}")
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
                  segment_kind TEXT NOT NULL DEFAULT 'global',
                  app_packages TEXT,
                  merge_attempted INTEGER NOT NULL DEFAULT 0,
                  merged_flag INTEGER NOT NULL DEFAULT 0,
                  merged_into_id INTEGER,
                  merge_prev_id INTEGER,
                  merge_decision_json TEXT,
                  merge_decision_reason TEXT,
                  merge_forced INTEGER NOT NULL DEFAULT 0,
                  merge_decision_at INTEGER,
                  created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
                  updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_segments_time ON segments(start_time, end_time)")
            // 幂等增加新列
            try { db.execSQL("ALTER TABLE segments ADD COLUMN segment_kind TEXT NOT NULL DEFAULT 'global'") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merge_attempted INTEGER NOT NULL DEFAULT 0") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merged_flag INTEGER NOT NULL DEFAULT 0") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merged_into_id INTEGER") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merge_prev_id INTEGER") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merge_decision_json TEXT") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merge_decision_reason TEXT") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merge_forced INTEGER NOT NULL DEFAULT 0") } catch (_: Exception) {}
            try { db.execSQL("ALTER TABLE segments ADD COLUMN merge_decision_at INTEGER") } catch (_: Exception) {}
            try { db.execSQL("CREATE INDEX IF NOT EXISTS idx_segments_merged_into ON segments(merged_into_id)") } catch (_: Exception) {}
            // 兼容：旧版本曾创建“全局唯一窗口”索引，会阻止单应用段落与全局段落时间窗重叠。
            // 这里改为按 segment_kind 的部分唯一约束。
            try { db.execSQL("DROP INDEX IF EXISTS uniq_segments_window") } catch (_: Exception) {}
            try { db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS uniq_segments_window_global ON segments(start_time, end_time) WHERE segment_kind = 'global'") } catch (_: Exception) {}
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
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_segment_samples_app_seg ON segment_samples(app_package_name, segment_id)")

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

            // AI 图片元数据表：按 file_path 存储标签/自然语言描述（可跨页面复用）
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS ai_image_meta (
                  file_path TEXT PRIMARY KEY,
                  tags_json TEXT,
                  description TEXT,
                  description_range TEXT,
                  nsfw INTEGER NOT NULL DEFAULT 0,
                  segment_id INTEGER,
                  capture_time INTEGER,
                  lang TEXT,
                  updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                )
                """.trimIndent()
            )
            try { db.execSQL("CREATE INDEX IF NOT EXISTS idx_ai_image_meta_nsfw ON ai_image_meta(nsfw, updated_at DESC)") } catch (_: Exception) {}
            try { db.execSQL("CREATE INDEX IF NOT EXISTS idx_ai_image_meta_updated ON ai_image_meta(updated_at DESC)") } catch (_: Exception) {}
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
                // 兼容：segment_kind 默认 global，但这里显式写入便于旧库/回填一致
                put("segment_kind", "global")
            }
            // 唯一索引下的安全插入：冲突时忽略并回查 ID
            val rowId = db.insertWithOnConflict("segments", null, cv, SQLiteDatabase.CONFLICT_IGNORE)
            if (rowId > 0) rowId else findSegmentIdByWindow(context, startMillis, endMillis)
        } catch (e: Exception) {
            FileLogger.w(TAG, "创建段落失败：${e.message}")
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
                arrayOf("id","start_time","end_time","duration_sec","sample_interval_sec","status","app_packages","created_at","updated_at"),
                "status = ? AND (segment_kind IS NULL OR segment_kind = 'global')",
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
                    status = cursor.getString(5),
                    appPackages = cursor.getStringOrNull(6),
                    createdAt = cursor.getLongOrNull(7),
                    updatedAt = cursor.getLongOrNull(8)
                )
            } else null
        } catch (_: Exception) {
            null
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 将最新的采样间隔同步到所有 collecting 段落，确保在设置里修改后无需等待“下一段落创建”即可生效。
     *
     * @return 受影响的段落数量
     */
    fun updateCollectingSegmentsSampleInterval(context: Context, sampleIntervalSec: Int): Int {
        val v = if (sampleIntervalSec < 5) 5 else sampleIntervalSec
        var db: SQLiteDatabase? = null
        return try {
            db = openMasterDb(context, writable = true) ?: return 0
            val cv = ContentValues().apply {
                put("sample_interval_sec", v)
                put("updated_at", System.currentTimeMillis())
            }
            val n = db.update(
                "segments",
                cv,
                "status = ? AND (segment_kind IS NULL OR segment_kind = 'global')",
                arrayOf("collecting")
            )
            try { FileLogger.i(TAG, "更新采样间隔：间隔=${v}秒，更新行数=${n}") } catch (_: Exception) {}
            n
        } catch (e: Exception) {
            try { FileLogger.w(TAG, "更新采样间隔失败：${e.message}") } catch (_: Exception) {}
            0
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    fun listSegmentsAscending(context: Context, limit: Int, offset: Int): List<Segment> {
        val segments = ArrayList<Segment>()
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            val limitClause = if (offset > 0) "$offset,$limit" else limit.toString()
            cursor = db.query(
                "segments",
                arrayOf(
                    "id",
                    "start_time",
                    "end_time",
                    "duration_sec",
                    "sample_interval_sec",
                    "status",
                    "app_packages",
                    "created_at",
                    "updated_at"
                ),
                "(segment_kind IS NULL OR segment_kind = 'global')",
                null,
                null,
                null,
                "start_time ASC",
                limitClause
            )
            while (cursor.moveToNext()) {
                segments.add(
                    Segment(
                        id = cursor.getLong(0),
                        startTime = cursor.getLong(1),
                        endTime = cursor.getLong(2),
                        durationSec = cursor.getInt(3),
                        sampleIntervalSec = cursor.getInt(4),
                        status = cursor.getString(5),
                        appPackages = cursor.getStringOrNull(6),
                        createdAt = cursor.getLongOrNull(7),
                        updatedAt = cursor.getLongOrNull(8)
                    )
                )
            }
        } catch (_: Exception) {
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
        return segments
    }

    fun getSegmentSamples(context: Context, segmentId: Long): List<Sample> {
        val samples = ArrayList<Sample>()
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            cursor = db.query(
                "segment_samples",
                arrayOf("id","segment_id","capture_time","file_path","app_package_name","app_name","position_index"),
                "segment_id = ?",
                arrayOf(segmentId.toString()),
                null,
                null,
                "capture_time ASC"
            )
            while (cursor.moveToNext()) {
                samples.add(
                    Sample(
                        id = cursor.getLong(0),
                        segmentId = cursor.getLong(1),
                        captureTime = cursor.getLong(2),
                        filePath = cursor.getString(3),
                        appPackageName = cursor.getString(4),
                        appName = cursor.getString(5),
                        positionIndex = cursor.getInt(6)
                    )
                )
            }
        } catch (_: Exception) {
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
        return samples
    }

    fun getSegmentResult(context: Context, segmentId: Long): SegmentResult? {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return null
            cursor = db.query(
                "segment_results",
                arrayOf("segment_id","ai_provider","ai_model","output_text","structured_json","categories"),
                "segment_id = ?",
                arrayOf(segmentId.toString()),
                null,
                null,
                null,
                "1"
            )
            if (cursor.moveToFirst()) {
                SegmentResult(
                    segmentId = cursor.getLong(0),
                    aiProvider = cursor.getStringOrNull(1),
                    aiModel = cursor.getStringOrNull(2),
                    outputText = cursor.getStringOrNull(3),
                    structuredJson = cursor.getStringOrNull(4),
                    categories = cursor.getStringOrNull(5)
                )
            } else null
        } catch (_: Exception) {
            null
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    fun countSegments(context: Context): Int {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return 0
            cursor = db.rawQuery("SELECT COUNT(*) FROM segments", null)
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        } catch (_: Exception) {
            0
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
            // 若文本与结构化结果都为空或为字符串"null"，视为“无内容”，不保存
            val ot = outputText.trim()
            val sj = structuredJson?.trim()
            val otEmpty = ot.isEmpty() || ot.equals("null", ignoreCase = true)
            val sjEmpty = sj.isNullOrEmpty() || sj.equals("null", ignoreCase = true)
            if (otEmpty && sjEmpty) {
                return
            }
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

    /**
     * 将段落 AI 的图片标签/描述写入主库，供全局页面复用（按 file_path 作为唯一键）。
     *
     * - structuredJson 来自 segment_results.structured_json（JSON 字符串）
     * - samples 必须与本次送入模型的图片一致（filename 基于 File(filePath).name）
     */
    fun upsertAiImageMetaFromStructuredJson(
        context: Context,
        segmentId: Long,
        samples: List<Sample>,
        structuredJson: String?,
        lang: String? = null
    ) {
        val sj = structuredJson?.trim()
        if (sj.isNullOrEmpty() || sj.equals("null", ignoreCase = true)) return
        if (samples.isEmpty()) return

        val ordered = samples.sortedBy { it.captureTime }
        val files = ArrayList<String>(ordered.size)
        val indexByFile = HashMap<String, Int>(ordered.size * 2)
        val sampleByFile = HashMap<String, Sample>(ordered.size * 2)
        for ((i, s) in ordered.withIndex()) {
            val name = try { File(s.filePath).name } catch (_: Exception) { "" }
            if (name.isEmpty()) continue
            files.add(name)
            indexByFile.putIfAbsent(name, i)
            sampleByFile.putIfAbsent(name, s)
        }
        if (files.isEmpty()) return

        val metaByFile = HashMap<String, AiImageMeta>(files.size * 2)
        fun meta(file: String): AiImageMeta = metaByFile.getOrPut(file) { AiImageMeta() }

        try {
            val root = JSONObject(sj)

            // 1) image_tags[]
            val tagArr = root.optJSONArray("image_tags")
            if (tagArr != null) {
                for (i in 0 until tagArr.length()) {
                    val obj = tagArr.optJSONObject(i) ?: continue
                    val file = obj.optString("file", "").trim()
                    if (file.isEmpty()) continue
                    val raw = obj.opt("tags")
                    val tags = ArrayList<String>()
                    when (raw) {
                        is JSONArray -> {
                            for (j in 0 until raw.length()) {
                                val t = raw.optString(j, "").trim()
                                if (t.isNotEmpty()) tags.add(t)
                            }
                        }
                        is String -> {
                            raw.split(Regex("[，,;；\\s]+"))
                                .map { it.trim() }
                                .filter { it.isNotEmpty() }
                                .forEach { tags.add(it) }
                        }
                    }
                    if (tags.isEmpty()) continue
                    val nsfw = tags.any { it.trim().equals("nsfw", ignoreCase = true) }
                    val tagsJson = JSONArray().apply { tags.forEach { put(it) } }.toString()
                    val m = meta(file)
                    m.tagsJson = tagsJson
                    m.nsfw = if (nsfw) 1 else 0
                }
            }

            // 2) image_descriptions[]（range 合并）
            val descArr = root.optJSONArray("image_descriptions")
            if (descArr != null) {
                for (i in 0 until descArr.length()) {
                    val obj = descArr.optJSONObject(i) ?: continue
                    val from = obj.optString("from_file", obj.optString("from", obj.optString("start", ""))).trim()
                    val to = obj.optString("to_file", obj.optString("to", obj.optString("end", ""))).trim()
                    val desc = obj.optString("description", obj.optString("desc", "")).trim()
                    if (desc.isEmpty()) continue
                    val a = if (from.isNotEmpty()) from else to
                    val b = if (to.isNotEmpty()) to else from
                    if (a.isEmpty() || b.isEmpty()) continue
                    val ia = indexByFile[a]
                    val ib = indexByFile[b]
                    if (ia == null || ib == null) continue

                    var start = ia
                    var end = ib
                    if (start > end) {
                        val tmp = start
                        start = end
                        end = tmp
                    }
                    val rangeLabel = if (a != b) "${a}-${b}" else a
                    for (k in start..end) {
                        if (k < 0 || k >= files.size) continue
                        val f = files[k]
                        val m = meta(f)
                        m.description = desc
                        m.descriptionRange = rangeLabel
                    }
                }
            }

            // 3) described_images[]（单图描述兜底：历史版本仅输出 described_images）
            val describedArr = root.optJSONArray("described_images")
            if (describedArr != null) {
                for (i in 0 until describedArr.length()) {
                    val obj = describedArr.optJSONObject(i) ?: continue
                    val file = obj.optString("file", "").trim()
                    if (file.isEmpty()) continue
                    val desc = obj.optString(
                        "summary",
                        obj.optString("summary_md", obj.optString("desc", ""))
                    ).trim()
                    if (desc.isEmpty()) continue
                    if (!indexByFile.containsKey(file)) continue
                    val m = meta(file)
                    if (m.description.isNullOrBlank()) {
                        m.description = desc
                        m.descriptionRange = file
                    }
                }
            }
        } catch (_: Exception) {
            return
        }

        if (metaByFile.isEmpty()) return

        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            db.beginTransaction()
            try {
                val now = System.currentTimeMillis()
                for ((file, m) in metaByFile) {
                    val sample = sampleByFile[file] ?: continue
                    val filePath = sample.filePath
                    if (filePath.isBlank()) continue

                    // 先确保行存在（避免 update 0 行）
                    val insertCv = ContentValues().apply {
                        put("file_path", filePath)
                        put("updated_at", now)
                        put("segment_id", segmentId)
                        put("capture_time", sample.captureTime)
                        if (!lang.isNullOrBlank()) put("lang", lang)
                    }
                    db.insertWithOnConflict("ai_image_meta", null, insertCv, SQLiteDatabase.CONFLICT_IGNORE)

                    val updateCv = ContentValues().apply {
                        put("updated_at", now)
                        put("segment_id", segmentId)
                        put("capture_time", sample.captureTime)
                        if (!lang.isNullOrBlank()) put("lang", lang)
                        if (!m.tagsJson.isNullOrBlank()) {
                            put("tags_json", m.tagsJson)
                            if (m.nsfw != null) put("nsfw", m.nsfw)
                        }
                        if (!m.description.isNullOrBlank()) {
                            put("description", m.description)
                            if (!m.descriptionRange.isNullOrBlank()) {
                                put("description_range", m.descriptionRange)
                            }
                        }
                    }
                    db.update("ai_image_meta", updateCv, "file_path = ?", arrayOf(filePath))
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
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
     * 查询指定时间范围内某个应用的所有截图（按时间升序）。
     * - 仅扫描该 app 的 shard 库，避免全量遍历所有包。
     */
    fun listShotsBetweenForApp(
        context: Context,
        appPackageName: String,
        startMillis: Long,
        endMillis: Long,
        perTableLimit: Int? = 2000
    ): List<ShotInfo> {
        val pkg = appPackageName.trim()
        if (pkg.isEmpty()) return emptyList()
        val result = ArrayList<ShotInfo>()
        var master: SQLiteDatabase? = null
        try {
            master = openMasterDb(context, writable = false) ?: return emptyList()
            var appName = pkg
            try {
                val c = master.query(
                    "app_registry",
                    arrayOf("app_name"),
                    "app_package_name = ?",
                    arrayOf(pkg),
                    null,
                    null,
                    null,
                    "1"
                )
                c.use { cur ->
                    if (cur.moveToFirst()) {
                        val name = cur.getStringOrNull(0)
                        if (!name.isNullOrBlank()) appName = name
                    }
                }
            } catch (_: Exception) {}

            val sy = java.util.Calendar.getInstance().apply { timeInMillis = startMillis }
                .get(java.util.Calendar.YEAR)
            val ey = java.util.Calendar.getInstance().apply { timeInMillis = endMillis }
                .get(java.util.Calendar.YEAR)

            val shards = master.query(
                "shard_registry",
                arrayOf("year", "db_path"),
                "app_package_name = ?",
                arrayOf(pkg),
                null,
                null,
                "year DESC"
            )
            shards.use { cur ->
                while (cur.moveToNext()) {
                    val year = cur.getInt(0)
                    val dbPath = cur.getString(1)
                    if (year < sy || year > ey) continue

                    var shard: SQLiteDatabase? = null
                    try {
                        shard = SQLiteDatabase.openDatabase(
                            dbPath,
                            null,
                            SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY
                        )
                        for (m in 1..12) {
                            val table = monthTableName(year, m)
                            if (!tableExists(shard, table)) continue
                            try {
                                val limitStr = perTableLimit?.takeIf { it > 0 }?.toString()
                                val rows = shard.query(
                                    table,
                                    arrayOf("file_path", "capture_time"),
                                    "capture_time >= ? AND capture_time <= ? AND is_deleted = 0",
                                    arrayOf(startMillis.toString(), endMillis.toString()),
                                    null,
                                    null,
                                    "capture_time ASC",
                                    limitStr
                                )
                                rows.use { rc ->
                                    while (rc.moveToNext()) {
                                        val path = rc.getString(0)
                                        val ts = rc.getLong(1)
                                        result.add(ShotInfo(path, ts, pkg, appName))
                                    }
                                }
                            } catch (_: Exception) {}
                        }
                    } catch (_: Exception) {
                    } finally {
                        try { shard?.close() } catch (_: Exception) {}
                    }
                }
            }
        } catch (_: Exception) {
        } finally {
            try { master?.close() } catch (_: Exception) {}
        }
        result.sortBy { it.captureTime }
        return result
    }

    /**
     * 获取某个应用在分库截图中的最早一张截图时间（capture_time）。
     * - 用于“全历史回填单应用段落”时确定起点
     * - 只扫描该 app 的 shard 库
     */
    fun getEarliestShotTimeForApp(context: Context, appPackageName: String): Long? {
        val pkg = appPackageName.trim()
        if (pkg.isEmpty()) return null
        var master: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            master = openMasterDb(context, writable = false) ?: return null
            cursor = master.query(
                "shard_registry",
                arrayOf("year", "db_path"),
                "app_package_name = ?",
                arrayOf(pkg),
                null,
                null,
                "year ASC"
            )
            cursor.use { cur ->
                while (cur.moveToNext()) {
                    val year = cur.getInt(0)
                    val dbPath = cur.getString(1)
                    var shard: SQLiteDatabase? = null
                    try {
                        shard = SQLiteDatabase.openDatabase(
                            dbPath,
                            null,
                            SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY
                        )
                        var yearMin: Long? = null
                        for (m in 1..12) {
                            val table = monthTableName(year, m)
                            if (!tableExists(shard, table)) continue
                            try {
                                val c = shard.rawQuery(
                                    "SELECT MIN(capture_time) FROM $table WHERE is_deleted = 0",
                                    null
                                )
                                c.use { rc ->
                                    if (!rc.moveToFirst()) return@use
                                    val v = rc.getLongOrNull(0)
                                    if (v != null && v > 0L) {
                                        yearMin = if (yearMin == null) v else kotlin.math.min(yearMin!!, v)
                                    }
                                }
                            } catch (_: Exception) {}
                        }
                        if (yearMin != null) return yearMin
                    } catch (_: Exception) {
                    } finally {
                        try { shard?.close() } catch (_: Exception) {}
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { master?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 统计指定时间范围内的截图总数（全局，包含边界）。
     * - 为性能考虑提供 hardLimit，计数超过该值时提前返回（用于合并上限判断）。
     */
    fun countShotsBetween(context: Context, startMillis: Long, endMillis: Long, hardLimit: Int = Int.MAX_VALUE): Int {
        var master: SQLiteDatabase? = null
        var total = 0
        try {
            master = openMasterDb(context, writable = false) ?: return 0

            // 需要涉及的 (package, year)
            val shards = master.query("shard_registry", arrayOf("app_package_name","year","db_path"), null, null, null, null, "year DESC")
            shards.use { cur ->
                // 年份范围
                val sy = java.util.Calendar.getInstance().apply { timeInMillis = startMillis }.get(java.util.Calendar.YEAR)
                val ey = java.util.Calendar.getInstance().apply { timeInMillis = endMillis }.get(java.util.Calendar.YEAR)
                while (cur.moveToNext()) {
                    val year = cur.getInt(1)
                    if (year < sy || year > ey) continue
                    val dbPath = cur.getString(2)
                    var shard: SQLiteDatabase? = null
                    try {
                        shard = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY)
                        // 遍历所有月份
                        for (m in 1..12) {
                            val table = monthTableName(year, m)
                            if (!tableExists(shard, table)) continue
                            try {
                                val rows = shard.rawQuery(
                                    "SELECT COUNT(*) as c FROM $table WHERE capture_time >= ? AND capture_time <= ? AND is_deleted = 0",
                                    arrayOf(startMillis.toString(), endMillis.toString())
                                )
                                rows.use { rc ->
                                    if (rc.moveToFirst()) total += (rc.getLong(0)).toInt()
                                }
                                if (total >= hardLimit) return total
                            } catch (_: Exception) {}
                        }
                    } catch (_: Exception) {
                    } finally { try { shard?.close() } catch (_: Exception) {} }
                    if (total >= hardLimit) return total
                }
            }
        } catch (_: Exception) {
        } finally { try { master?.close() } catch (_: Exception) {} }
        return total
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
                "(segment_kind IS NULL OR segment_kind = 'global') AND start_time >= ? AND start_time <= ?",
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
     * 查询某时间范围内所有“全局段落”的 start_time（按时间升序）。
     * 用于快速对比“有截图的日期”与“已生成动态的日期”，从而发现被删空的日期并触发重建。
     */
    fun listGlobalSegmentStartTimesBetween(
        context: Context,
        startMillis: Long,
        endMillis: Long,
        limit: Int? = null,
    ): List<Long> {
        val out = ArrayList<Long>()
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            val lim = if (limit != null && limit > 0) limit.toString() else null
            cursor = db.query(
                "segments",
                arrayOf("start_time"),
                "(segment_kind IS NULL OR segment_kind = 'global') AND start_time >= ? AND start_time <= ?",
                arrayOf(startMillis.toString(), endMillis.toString()),
                null,
                null,
                "start_time ASC",
                lim,
            )
            while (cursor.moveToNext()) {
                out.add(cursor.getLong(0))
            }
        } catch (_: Exception) {
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
        return out
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
                "(segment_kind IS NULL OR segment_kind = 'global') AND start_time = ? AND end_time = ?",
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
                "status = ? AND (segment_kind IS NULL OR segment_kind = 'global')",
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
                WHERE (s.segment_kind IS NULL OR s.segment_kind = 'global')
                  AND s.start_time = ? AND s.end_time = ?
                  AND (
                    (r.output_text IS NOT NULL AND LOWER(TRIM(r.output_text)) NOT IN ('', 'null'))
                    OR (r.structured_json IS NOT NULL AND LOWER(TRIM(r.structured_json)) NOT IN ('', 'null'))
                  )
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
            cursor = db.rawQuery(
                """
                SELECT 1 FROM segment_results
                WHERE segment_id = ?
                  AND (
                    (output_text IS NOT NULL AND LOWER(TRIM(output_text)) NOT IN ('', 'null'))
                    OR (structured_json IS NOT NULL AND LOWER(TRIM(structured_json)) NOT IN ('', 'null'))
                  )
                LIMIT 1
                """.trimIndent(),
                arrayOf(segmentId.toString())
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
                "(segment_kind IS NULL OR segment_kind = 'global') AND start_time = ? AND end_time = ?",
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

    /** 更新段落时间窗口与时长 */
    fun updateSegmentWindow(context: Context, segmentId: Long, newStart: Long, newEnd: Long) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            val dur = (((newEnd - newStart) / 1000L).toInt()).coerceAtLeast(1)
            val cv = ContentValues().apply {
                put("start_time", newStart)
                put("end_time", newEnd)
                put("duration_sec", dur)
                put("updated_at", System.currentTimeMillis())
            }
            db.update("segments", cv, "id = ?", arrayOf(segmentId.toString()))
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    /** 级联删除段落（结果、样本、段自身） */
    fun deleteSegmentCascade(context: Context, segmentId: Long) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            db.beginTransaction()
            try {
                db.delete("segment_results", "segment_id = ?", arrayOf(segmentId.toString()))
                db.delete("segment_samples", "segment_id = ?", arrayOf(segmentId.toString()))
                db.delete("segments", "id = ?", arrayOf(segmentId.toString()))
                db.setTransactionSuccessful()
            } finally { try { db.endTransaction() } catch (_: Exception) {} }
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    /** 最近完成且已有结果的段落列表（按 end_time 升序或降序由参数决定） */
    fun listRecentCompletedWithResult(context: Context, limit: Int = 20, ascending: Boolean = true): List<Segment> {
        val list = ArrayList<Segment>()
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            val effLimit = limit.coerceAtLeast(1)
            val order = if (ascending) "end_time ASC" else "end_time DESC"
            cursor = db.rawQuery(
                """
                SELECT s.id, s.start_time, s.end_time, s.duration_sec, s.sample_interval_sec, s.status
                FROM segments s
                JOIN segment_results r ON r.segment_id = s.id
                WHERE (s.segment_kind IS NULL OR s.segment_kind = 'global')
                  AND s.status = 'completed' AND (s.merged_into_id IS NULL) AND (
                  (r.output_text IS NOT NULL AND LOWER(TRIM(r.output_text)) NOT IN ('', 'null'))
                  OR (r.structured_json IS NOT NULL AND LOWER(TRIM(r.structured_json)) NOT IN ('', 'null'))
                )
                ORDER BY $order
                LIMIT ?
                """.trimIndent(),
                arrayOf(effLimit.toString())
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

    /** 标记某段落已尝试合并 */
    fun setMergeAttempted(context: Context, segmentId: Long, attempted: Boolean = true) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            val cv = ContentValues().apply {
                put("merge_attempted", if (attempted) 1 else 0)
                put("updated_at", System.currentTimeMillis())
            }
            db.update("segments", cv, "id = ?", arrayOf(segmentId.toString()))
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }
 
    /** 标记某段落为“已合并” */
    fun setMergedFlag(context: Context, segmentId: Long, merged: Boolean = true) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            val cv = ContentValues().apply {
                put("merged_flag", if (merged) 1 else 0)
                put("updated_at", System.currentTimeMillis())
            }
            db.update("segments", cv, "id = ?", arrayOf(segmentId.toString()))
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    /** 查询：某段落是否为“合并事件”（merged_flag=1） */
    fun isMergedSegment(context: Context, segmentId: Long): Boolean {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return false
            cursor = db.query(
                "segments",
                arrayOf("merged_flag"),
                "id = ?",
                arrayOf(segmentId.toString()),
                null,
                null,
                null,
                "1"
            )
            if (!cursor.moveToFirst()) return false
            cursor.getInt(0) == 1
        } catch (_: Exception) {
            false
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 记录最近一次“向后合并判定/合并尝试”的信息，供前端展示。
     *
     * - merge_prev_id: 本次尝试的上一事件ID（可为空）
     * - merge_decision_json: AI 判定 JSON（或系统生成的 JSON / 为空）
     * - merge_decision_reason: 展示用原因（AI reason / 系统原因）
     * - merge_forced: 是否为用户强制合并
     * - merge_decision_at: 记录时间戳（ms）
     */
    fun updateMergeDecisionInfo(
        context: Context,
        segmentId: Long,
        prevSegmentId: Long? = null,
        decisionJson: String? = null,
        reason: String? = null,
        forced: Boolean = false
    ) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            val now = System.currentTimeMillis()
            val cv = ContentValues().apply {
                if (prevSegmentId != null && prevSegmentId > 0) {
                    put("merge_prev_id", prevSegmentId)
                } else {
                    putNull("merge_prev_id")
                }
                if (!decisionJson.isNullOrBlank()) {
                    put("merge_decision_json", decisionJson)
                } else {
                    putNull("merge_decision_json")
                }
                if (!reason.isNullOrBlank()) {
                    put("merge_decision_reason", reason)
                } else {
                    putNull("merge_decision_reason")
                }
                put("merge_forced", if (forced) 1 else 0)
                put("merge_decision_at", now)
                put("updated_at", now)
            }
            db.update("segments", cv, "id = ?", arrayOf(segmentId.toString()))
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    /**
     * 将某段落标记为“已被合并到 mergedIntoId”，并扁平化其所有已合并子段，避免产生链式引用。
     *
     * - segments.merged_into_id: 被合并段指向“当前根段落”的 id
     * - 同时将 merged_into_id = segmentId 的所有行更新为 mergedIntoId（扁平化）
     */
    fun markMergedInto(context: Context, segmentId: Long, mergedIntoId: Long) {
        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(context, writable = true) ?: return
            val now = System.currentTimeMillis()
            db.beginTransaction()
            try {
                // 1) 标记自身
                val cv = ContentValues().apply {
                    put("merged_into_id", mergedIntoId)
                    put("updated_at", now)
                }
                db.update("segments", cv, "id = ?", arrayOf(segmentId.toString()))

                // 2) 扁平化：所有已合并到 segmentId 的子段，直接指向 mergedIntoId
                val cv2 = ContentValues().apply {
                    put("merged_into_id", mergedIntoId)
                    put("updated_at", now)
                }
                db.update("segments", cv2, "merged_into_id = ?", arrayOf(segmentId.toString()))

                db.setTransactionSuccessful()
            } finally { try { db.endTransaction() } catch (_: Exception) {} }
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun isMergeAttempted(context: Context, segmentId: Long): Boolean {
        var db: SQLiteDatabase? = null
        var c: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return false
            c = db.query("segments", arrayOf("merge_attempted"), "id = ?", arrayOf(segmentId.toString()), null, null, null, "1")
            if (c.moveToFirst()) (c.getInt(0) == 1) else false
        } catch (_: Exception) { false } finally { try { c?.close() } catch (_: Exception) {}; try { db?.close() } catch (_: Exception) {} }
    }

    /** 当天已完成但尚未尝试合并的段落（排除第一段） */
    fun listUnattemptedCompletedSince(context: Context, sinceMillis: Long, limit: Int = 100): List<Segment> {
        val list = ArrayList<Segment>()
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            val effLimit = limit.coerceAtLeast(1)
            cursor = db.rawQuery(
                """
                SELECT id, start_time, end_time, duration_sec, sample_interval_sec, status
                FROM segments
                WHERE (segment_kind IS NULL OR segment_kind = 'global')
                  AND status = 'completed' AND (merged_into_id IS NULL) AND start_time >= ? AND merge_attempted = 0
                ORDER BY end_time ASC
                LIMIT ?
                """.trimIndent(),
                arrayOf(sinceMillis.toString(), effLimit.toString())
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
        } finally { try { cursor?.close() } catch (_: Exception) {}; try { db?.close() } catch (_: Exception) {} }
        return list
    }

    /**
     * 获取在指定 start 之前、最近的一个且已有 AI 结果的已完成段落。
     */
    fun getPreviousCompletedSegmentWithResult(context: Context, beforeStart: Long): Segment? {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return null
            cursor = db.rawQuery(
                """
                SELECT s.id, s.start_time, s.end_time, s.duration_sec, s.sample_interval_sec, s.status
                FROM segments s
                JOIN segment_results r ON r.segment_id = s.id
                WHERE (s.segment_kind IS NULL OR s.segment_kind = 'global')
                  AND s.end_time <= ? AND (s.merged_into_id IS NULL) AND s.status = 'completed' AND (
                  (r.output_text IS NOT NULL AND LOWER(TRIM(r.output_text)) NOT IN ('', 'null'))
                  OR (r.structured_json IS NOT NULL AND LOWER(TRIM(r.structured_json)) NOT IN ('', 'null'))
                )
                ORDER BY s.end_time DESC
                LIMIT 1
                """.trimIndent(),
                arrayOf(beforeStart.toString())
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
        } catch (_: Exception) { null } finally {
            try { cursor?.close() } catch (_: Exception) {}
            try { db?.close() } catch (_: Exception) {}
        }
    }
 
    /** 读取某段落的样本列表（按 position_index 升序） */
    fun getSamplesForSegment(context: Context, segmentId: Long): List<Sample> {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        val list = ArrayList<Sample>()
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            cursor = db.query(
                "segment_samples",
                arrayOf("id","segment_id","capture_time","file_path","app_package_name","app_name","position_index"),
                "segment_id = ?",
                arrayOf(segmentId.toString()),
                null,null,
                "position_index ASC"
            )
            while (cursor.moveToNext()) {
                list.add(
                    Sample(
                        id = cursor.getLong(0),
                        segmentId = cursor.getLong(1),
                        captureTime = cursor.getLong(2),
                        filePath = cursor.getString(3),
                        appPackageName = cursor.getString(4),
                        appName = cursor.getString(5),
                        positionIndex = cursor.getInt(6)
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

    /** 返回段落结果（output_text, structured_json） */
    fun getResultForSegment(context: Context, segmentId: Long): Pair<String?, String?> {
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        return try {
            db = openMasterDb(context, writable = false) ?: return Pair(null, null)
            cursor = db.query(
                "segment_results",
                arrayOf("output_text","structured_json"),
                "segment_id = ?",
                arrayOf(segmentId.toString()),
                null,null,
                null,
                "1"
            )
            if (cursor.moveToFirst()) {
                Pair(cursor.getString(0), cursor.getString(1))
            } else Pair(null, null)
        } catch (_: Exception) { Pair(null, null) } finally {
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
                WHERE (segment_kind IS NULL OR segment_kind = 'global')
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
                        SELECT s.id,
                               CASE WHEN r.segment_id IS NOT NULL AND (
                                         (r.output_text IS NOT NULL AND LOWER(TRIM(r.output_text)) NOT IN ('', 'null')) OR
                                         (r.structured_json IS NOT NULL AND LOWER(TRIM(r.structured_json)) NOT IN ('', 'null'))
                                     ) THEN 1 ELSE 0 END AS has_result
                        FROM segments s
                        LEFT JOIN segment_results r ON r.segment_id = s.id
                        WHERE (s.segment_kind IS NULL OR s.segment_kind = 'global')
                          AND s.start_time = ? AND s.end_time = ?
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

    /**
     * 列出需要补救总结的段落（已完成、无结果但有样本），可按起始时间筛选并限制数量。
     */
    fun listSegmentsNeedingSummary(context: Context, limit: Int = 5, sinceMillis: Long? = null): List<Segment> {
        val list = ArrayList<Segment>()
        var db: SQLiteDatabase? = null
        var cursor: Cursor? = null
        try {
            db = openMasterDb(context, writable = false) ?: return emptyList()
            val effLimit = limit.coerceAtLeast(1)
            val where = StringBuilder(
                "(s.segment_kind IS NULL OR s.segment_kind = 'global') AND s.status = 'completed' AND (r.segment_id IS NULL OR ((r.output_text IS NULL OR LOWER(TRIM(r.output_text)) IN ('', 'null')) AND (r.structured_json IS NULL OR LOWER(TRIM(r.structured_json)) IN ('', 'null'))))"
            )
            val args = ArrayList<String>()
            if (sinceMillis != null) {
                where.append(" AND s.start_time >= ?")
                args.add(sinceMillis.toString())
            }
            args.add(effLimit.toString())
            cursor = db.rawQuery(
                """
                SELECT s.id, s.start_time, s.end_time, s.duration_sec, s.sample_interval_sec, s.status
                FROM segments s
                LEFT JOIN segment_results r ON r.segment_id = s.id
                WHERE ${where.toString()}
                ORDER BY s.start_time ASC, s.id ASC
                LIMIT ?
                """.trimIndent(),
                args.toTypedArray()
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
        // 不再强制要求“必须已有样本”，直接返回待补救段落
        return list
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
