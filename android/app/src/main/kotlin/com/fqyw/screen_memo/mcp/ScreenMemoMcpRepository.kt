package com.fqyw.screen_memo.mcp

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Base64
import com.fqyw.screen_memo.logging.FileLogger
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class ScreenMemoMcpRepository(private val context: Context) {
    companion object {
        private const val TAG = "ScreenMemoMcpRepo"
        private const val MASTER_DB_DIR_RELATIVE = "output/databases"
        private const val MASTER_DB_FILE_NAME = "screenshot_memo.db"
        private const val SHARDS_DIR_RELATIVE = "output/databases/shards"
        private const val DEFAULT_LIMIT = 20
        private const val MAX_LIMIT = 100
        private const val MAX_IMAGE_LIMIT = 5
        private const val SUMMARY_LIMIT = 3000
        private const val OUTPUT_LIMIT = 8000
        private const val STRUCTURED_LIMIT = 65536
        private const val OCR_LIMIT_PER_SAMPLE = 1500
        private const val OCR_LIMIT_TOTAL = 8000
        private const val SEARCH_DOC_CONTENT_LIMIT = 8000
        private const val SCREENSHOT_OCR_PREVIEW_LIMIT = 220
        private const val SCREENSHOT_OCR_FULL_LIMIT = 3000
        private const val MAX_IMAGE_BYTES = 8L * 1024L * 1024L
    }

    fun status(serviceStatus: Map<String, Any?>): JSONObject {
        val dbPath = resolveMasterDbPath()
        val dbFile = dbPath?.let { File(it) }
        val out = JSONObject()
            .put("service", mapToJson(serviceStatus))
            .put(
                "database",
                JSONObject()
                    .put("path", dbPath ?: JSONObject.NULL)
                    .put("exists", dbFile?.exists() == true)
                    .put("readable", dbFile?.canRead() == true),
            )

        val db = openMasterDb()
        if (db == null) {
            out.getJSONObject("database").put("ok", false)
            return out
        }
        db.use { conn ->
            val database = out.getJSONObject("database").put("ok", true)
            database.put("segment_count", queryLong(conn, "SELECT COUNT(*) FROM segments"))
            database.put(
                "dynamic_count",
                queryLong(
                    conn,
                    """
                    SELECT COUNT(*)
                    FROM segments s
                    JOIN segment_results r ON r.segment_id = s.id
                    WHERE ${rootSegmentWhere("s")}
                      AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
                    """.trimIndent(),
                ),
            )
            database.put("search_docs_count", safeCount(conn, "search_docs"))
            database.put("shard_count", safeCount(conn, "shard_registry"))
            database.put("screenshot_count", queryLong(conn, "SELECT COALESCE(SUM(total_count), 0) FROM app_stats"))
            database.put("first_dynamic_time", queryLongOrNull(conn, "SELECT MIN(start_time) FROM segments"))
            database.put("last_dynamic_time", queryLongOrNull(conn, "SELECT MAX(end_time) FROM segments"))
            database.put("first_screenshot_time", queryLongOrNull(conn, "SELECT MIN(first_capture_time) FROM day_stats"))
            database.put("last_screenshot_time", queryLongOrNull(conn, "SELECT MAX(last_capture_time) FROM day_stats"))
        }
        return out
    }

    fun listRecentDynamics(args: JSONObject): JSONObject {
        val limit = limit(args)
        val offset = offset(args)
        val includeOcr = args.optBoolean("include_ocr", false)
        val db = requireMasterDb()
        db.use { conn ->
            val rows = queryDynamics(
                db = conn,
                limit = limit,
                offset = offset,
                includeSamples = includeOcr,
                includeOcr = includeOcr,
            )
            return JSONObject()
                .put("items", rows)
                .put("limit", limit)
                .put("offset", offset)
                .put("include_ocr", includeOcr)
        }
    }

    fun searchDynamics(args: JSONObject): JSONObject {
        val query = args.optString("query", "").trim()
        if (query.isEmpty()) throw IllegalArgumentException("query is required")
        val limit = limit(args)
        val offset = offset(args)
        val includeOcr = args.optBoolean("include_ocr", false)
        val start = optLong(args, "start_time")
        val end = optLong(args, "end_time")
        val db = requireMasterDb()
        db.use { conn ->
            val rows = searchDynamicsInternal(conn, query, limit, offset, start, end, includeOcr)
            return JSONObject()
                .put("query", query)
                .put("items", rows)
                .put("limit", limit)
                .put("offset", offset)
                .put("include_ocr", includeOcr)
        }
    }

    fun getDynamicContext(args: JSONObject): JSONObject {
        val start = requireLong(args, "start_time")
        val end = requireLong(args, "end_time")
        if (end < start) throw IllegalArgumentException("end_time must be greater than or equal to start_time")
        val limit = limit(args)
        val includeOcr = args.optBoolean("include_ocr", false)
        val db = requireMasterDb()
        db.use { conn ->
            val rows = queryDynamics(
                db = conn,
                limit = limit,
                offset = 0,
                startTime = start,
                endTime = end,
                ascending = true,
                includeSamples = includeOcr,
                includeOcr = includeOcr,
                overlapWindow = true,
            )
            val contextText = buildContextText(rows)
            return JSONObject()
                .put("start_time", start)
                .put("end_time", end)
                .put("items", rows)
                .put("context_text", contextText)
                .put("include_ocr", includeOcr)
        }
    }

    fun getSegment(args: JSONObject): JSONObject {
        val segmentId = requireLong(args, "segment_id")
        val includeOcr = args.optBoolean("include_ocr", false)
        val includeImages = args.optBoolean("include_images", false)
        val db = requireMasterDb()
        db.use { conn ->
            val row = querySegment(conn, segmentId)
                ?: throw IllegalArgumentException("segment not found: $segmentId")
            if (includeImages || includeOcr) {
                row.put("samples", getSamples(conn, segmentId, includeOcr))
            }
            return JSONObject()
                .put("segment", row)
                .put("include_ocr", includeOcr)
                .put("include_images", includeImages)
        }
    }

    fun searchDocs(args: JSONObject): JSONObject {
        val query = args.optString("query", "").trim()
        if (query.isEmpty()) throw IllegalArgumentException("query is required")
        val limit = limit(args)
        val offset = offset(args)
        val docType = args.optString("doc_type", "").trim().takeIf { it.isNotEmpty() }
        val start = optLong(args, "start_time")
        val end = optLong(args, "end_time")
        val db = requireMasterDb()
        db.use { conn ->
            if (!tableExists(conn, "search_docs")) {
                return JSONObject()
                    .put("query", query)
                    .put("items", JSONArray())
                    .put("warning", "search_docs table does not exist")
            }
            val rows = searchDocsInternal(conn, query, docType, limit, offset, start, end)
            return JSONObject()
                .put("query", query)
                .put("doc_type", docType ?: JSONObject.NULL)
                .put("items", rows)
                .put("limit", limit)
                .put("offset", offset)
        }
    }

    fun searchScreenshots(args: JSONObject): JSONObject {
        val query = args.optString("query", "").trim()
        if (query.isEmpty()) throw IllegalArgumentException("query is required")
        val limit = limit(args)
        val offset = offset(args)
        val includeOcr = args.optBoolean("include_ocr", false)
        val start = optLong(args, "start_time")
        val end = optLong(args, "end_time")
        val db = requireMasterDb()
        db.use { conn ->
            val rows = searchScreenshotsInternal(conn, query, limit, offset, start, end, includeOcr)
            return JSONObject()
                .put("query", query)
                .put("items", rows)
                .put("limit", limit)
                .put("offset", offset)
                .put("include_ocr", includeOcr)
        }
    }

    fun getEvidenceImages(args: JSONObject): JSONObject {
        val limit = imageLimit(args)
        val paths = LinkedHashSet<String>()
        val refs = args.optJSONArray("image_refs")
        if (refs != null) {
            for (i in 0 until refs.length()) {
                decodeImageRef(refs.optString(i, ""))?.let { paths.add(it) }
                if (paths.size >= limit) break
            }
        }
        val segmentId = optLong(args, "segment_id")
        if (segmentId != null && paths.size < limit) {
            val db = requireMasterDb()
            db.use { conn ->
                val samples = getSamples(conn, segmentId, includeOcr = false, maxSamples = limit)
                for (i in 0 until samples.length()) {
                    val path = samples.getJSONObject(i).optString("file_path", "")
                    if (path.isNotBlank()) paths.add(path)
                    if (paths.size >= limit) break
                }
            }
        }
        if (paths.isEmpty()) {
            return JSONObject()
                .put(
                    "content",
                    JSONArray().put(JSONObject().put("type", "text").put("text", "No image references found.")),
                )
                .put("isError", true)
        }

        val imageContent = JSONArray()
        val images = JSONArray()
        for (path in paths.take(limit)) {
            val file = File(path)
            val ref = encodeImageRef(path)
            if (!file.exists() || !file.isFile) {
                images.put(JSONObject().put("image_ref", ref).put("error", "file_not_found"))
                continue
            }
            if (file.length() > MAX_IMAGE_BYTES) {
                images.put(JSONObject().put("image_ref", ref).put("error", "file_too_large").put("size_bytes", file.length()))
                continue
            }
            val bytes = try {
                file.readBytes()
            } catch (e: Exception) {
                images.put(JSONObject().put("image_ref", ref).put("error", e.message ?: "read_failed"))
                continue
            }
            val mime = mimeType(path)
            val imageMeta = JSONObject()
                .put("image_ref", ref)
                .put("file_path", path)
                .put("mime_type", mime)
                .put("size_bytes", bytes.size)
            images.put(imageMeta)
            imageContent.put(
                JSONObject()
                    .put("type", "image")
                    .put("data", Base64.encodeToString(bytes, Base64.NO_WRAP))
                    .put("mimeType", mime),
            )
        }
        val structured = JSONObject()
            .put("images", images)
            .put("limit", limit)
        val content = JSONArray()
            .put(
            JSONObject()
                .put("type", "text")
                .put("text", structured.toString(2)),
            )
        for (i in 0 until imageContent.length()) {
            content.put(imageContent.getJSONObject(i))
        }
        return JSONObject()
            .put("content", content)
            .put("structuredContent", structured)
            .put("isError", false)
    }

    private fun queryDynamics(
        db: SQLiteDatabase,
        limit: Int,
        offset: Int,
        startTime: Long? = null,
        endTime: Long? = null,
        ascending: Boolean = false,
        includeSamples: Boolean = false,
        includeOcr: Boolean = false,
        overlapWindow: Boolean = false,
    ): JSONArray {
        val where = mutableListOf(
            rootSegmentWhere("s"),
            "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
            "(r.segment_id IS NOT NULL)",
            "((r.output_text IS NOT NULL AND LENGTH(TRIM(r.output_text)) > 0) OR (r.structured_json IS NOT NULL AND LENGTH(TRIM(r.structured_json)) > 0))",
        )
        val params = ArrayList<String>()
        if (startTime != null && endTime != null && overlapWindow) {
            where.add("s.end_time >= ? AND s.start_time <= ?")
            params.add(startTime.toString())
            params.add(endTime.toString())
        } else {
            if (startTime != null) {
                where.add("s.start_time >= ?")
                params.add(startTime.toString())
            }
            if (endTime != null) {
                where.add("s.start_time <= ?")
                params.add(endTime.toString())
            }
        }
        params.add(limit.toString())
        params.add(offset.toString())
        val order = if (ascending) "ASC" else "DESC"
        val sql =
            """
            SELECT
              s.id, s.start_time, s.end_time, s.duration_sec, s.sample_interval_sec,
              s.status, s.app_packages, s.created_at, s.updated_at,
              r.ai_provider, r.ai_model,
              SUBSTR(r.output_text, 1, $OUTPUT_LIMIT) AS output_text,
              CASE
                WHEN r.structured_json IS NULL THEN NULL
                WHEN LENGTH(r.structured_json) <= $STRUCTURED_LIMIT THEN r.structured_json
                ELSE SUBSTR(r.structured_json, MAX(1, INSTR(r.structured_json, '"overall_summary"')), $STRUCTURED_LIMIT)
              END AS structured_json,
              SUBSTR(r.categories, 1, 4096) AS categories,
              (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count
            FROM segments s
            JOIN segment_results r ON r.segment_id = s.id
            WHERE ${where.joinToString(" AND ")}
            ORDER BY s.start_time $order, s.id $order
            LIMIT ? OFFSET ?
            """.trimIndent()
        return rawDynamicQuery(db, sql, params, includeSamples, includeOcr)
    }

    private fun searchDynamicsInternal(
        db: SQLiteDatabase,
        query: String,
        limit: Int,
        offset: Int,
        startTime: Long?,
        endTime: Long?,
        includeOcr: Boolean,
    ): JSONArray {
        val terms = queryTerms(query)
        val baseFilters = mutableListOf(
            rootSegmentWhere("s"),
            "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
        )
        val baseArgs = ArrayList<String>()
        if (startTime != null) {
            baseFilters.add("s.start_time >= ?")
            baseArgs.add(startTime.toString())
        }
        if (endTime != null) {
            baseFilters.add("s.start_time <= ?")
            baseArgs.add(endTime.toString())
        }

        val likeFilters = mutableListOf<String>()
        val likeArgs = ArrayList<String>()
        for (term in terms) {
            likeFilters.add("(r.output_text LIKE ? OR r.categories LIKE ? OR r.structured_json LIKE ?)")
            val like = "%$term%"
            likeArgs.add(like)
            likeArgs.add(like)
            likeArgs.add(like)
        }
        val where = (likeFilters + baseFilters).joinToString(" AND ")
        val params = ArrayList<String>()
        params.addAll(likeArgs)
        params.addAll(baseArgs)
        params.add(limit.toString())
        params.add(offset.toString())
        val sql =
            """
            SELECT
              s.id, s.start_time, s.end_time, s.duration_sec, s.sample_interval_sec,
              s.status, s.app_packages, s.created_at, s.updated_at,
              r.ai_provider, r.ai_model,
              SUBSTR(r.output_text, 1, $OUTPUT_LIMIT) AS output_text,
              CASE
                WHEN r.structured_json IS NULL THEN NULL
                WHEN LENGTH(r.structured_json) <= $STRUCTURED_LIMIT THEN r.structured_json
                ELSE SUBSTR(r.structured_json, MAX(1, INSTR(r.structured_json, '"overall_summary"')), $STRUCTURED_LIMIT)
              END AS structured_json,
              SUBSTR(r.categories, 1, 4096) AS categories,
              (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count
            FROM segments s
            JOIN segment_results r ON r.segment_id = s.id
            WHERE $where
            ORDER BY s.start_time DESC, s.id DESC
            LIMIT ? OFFSET ?
            """.trimIndent()
        return rawDynamicQuery(db, sql, params, includeSamples = includeOcr, includeOcr = includeOcr)
    }

    private fun rawDynamicQuery(
        db: SQLiteDatabase,
        sql: String,
        params: List<String>,
        includeSamples: Boolean,
        includeOcr: Boolean,
    ): JSONArray {
        val out = JSONArray()
        db.rawQuery(sql, params.toTypedArray()).use { c ->
            while (c.moveToNext()) {
                val item = dynamicRowToJson(c)
                if (includeSamples) {
                    item.put("samples", getSamples(db, item.getLong("segment_id"), includeOcr))
                }
                out.put(item)
            }
        }
        return out
    }

    private fun querySegment(db: SQLiteDatabase, segmentId: Long): JSONObject? {
        val sql =
            """
            SELECT
              s.id, s.start_time, s.end_time, s.duration_sec, s.sample_interval_sec,
              s.status, s.app_packages, s.created_at, s.updated_at,
              r.ai_provider, r.ai_model,
              r.output_text,
              r.structured_json,
              r.categories,
              (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count
            FROM segments s
            LEFT JOIN segment_results r ON r.segment_id = s.id
            WHERE s.id = ?
            LIMIT 1
            """.trimIndent()
        db.rawQuery(sql, arrayOf(segmentId.toString())).use { c ->
            if (!c.moveToFirst()) return null
            return dynamicRowToJson(c, fullResult = true)
        }
    }

    private fun dynamicRowToJson(c: Cursor, fullResult: Boolean = false): JSONObject {
        val segmentId = c.getLong(0)
        val start = c.getLong(1)
        val end = c.getLong(2)
        val outputText = c.getStringOrNull(11)
        val structuredJson = c.getStringOrNull(12)
        val categories = c.getStringOrNull(13)
        val summary = extractOverallSummary(structuredJson, outputText)
        val item = JSONObject()
            .put("segment_id", segmentId)
            .put("start_time", start)
            .put("end_time", end)
            .put("start_time_text", formatMillis(start))
            .put("end_time_text", formatMillis(end))
            .put("duration_sec", c.getInt(3))
            .put("sample_interval_sec", c.getInt(4))
            .put("status", c.getStringOrNull(5) ?: "")
            .put("app_packages", c.getStringOrNull(6) ?: "")
            .put("created_at", c.getLongOrNull(7) ?: JSONObject.NULL)
            .put("updated_at", c.getLongOrNull(8) ?: JSONObject.NULL)
            .put("ai_provider", c.getStringOrNull(9) ?: JSONObject.NULL)
            .put("ai_model", c.getStringOrNull(10) ?: JSONObject.NULL)
            .put("summary", truncate(summary, SUMMARY_LIMIT))
            .put("categories", parseJsonOrString(categories))
            .put("structured_json", structuredPreview(structuredJson))
            .put("sample_count", c.getInt(14))
        if (fullResult) {
            item.put("output_text", truncate(outputText.orEmpty(), OUTPUT_LIMIT))
        }
        return item
    }

    private fun getSamples(
        db: SQLiteDatabase,
        segmentId: Long,
        includeOcr: Boolean,
        maxSamples: Int = 20,
    ): JSONArray {
        val samples = JSONArray()
        val rows = ArrayList<SampleRow>()
        val sql =
            """
            SELECT id, segment_id, capture_time, file_path, app_package_name, app_name, position_index
            FROM segment_samples
            WHERE segment_id = ?
            ORDER BY position_index ASC, id ASC
            LIMIT ?
            """.trimIndent()
        db.rawQuery(sql, arrayOf(segmentId.toString(), maxSamples.toString())).use { c ->
            while (c.moveToNext()) {
                rows.add(
                    SampleRow(
                        id = c.getLong(0),
                        segmentId = c.getLong(1),
                        captureTime = c.getLong(2),
                        filePath = c.getStringOrNull(3).orEmpty(),
                        appPackageName = c.getStringOrNull(4).orEmpty(),
                        appName = c.getStringOrNull(5).orEmpty(),
                        positionIndex = c.getInt(6),
                    ),
                )
            }
        }
        val ocrByPath = if (includeOcr) loadOcrForSamples(db, rows) else emptyMap()
        var ocrBudget = OCR_LIMIT_TOTAL
        for (row in rows) {
            val obj = JSONObject()
                .put("sample_id", row.id)
                .put("segment_id", row.segmentId)
                .put("capture_time", row.captureTime)
                .put("capture_time_text", formatMillis(row.captureTime))
                .put("file_path", row.filePath)
                .put("image_ref", encodeImageRef(row.filePath))
                .put("app_package_name", row.appPackageName)
                .put("app_name", row.appName)
                .put("position_index", row.positionIndex)
            if (includeOcr && ocrBudget > 0) {
                val text = ocrByPath[row.filePath].orEmpty()
                val clipped = truncate(text, minOf(OCR_LIMIT_PER_SAMPLE, ocrBudget))
                ocrBudget -= clipped.length
                obj.put("ocr_text", clipped)
                obj.put("ocr_truncated", text.length > clipped.length)
            }
            samples.put(obj)
        }
        return samples
    }

    private fun loadOcrForSamples(db: SQLiteDatabase, samples: List<SampleRow>): Map<String, String> {
        if (samples.isEmpty()) return emptyMap()
        val out = LinkedHashMap<String, String>()
        val grouped = samples.groupBy { sample ->
            val cal = Calendar.getInstance().apply { timeInMillis = sample.captureTime }
            Triple(sample.appPackageName, cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)
        }
        for ((key, group) in grouped) {
            val (pkg, year, month) = key
            if (pkg.isBlank() || year <= 1970 || month !in 1..12) continue
            val shard = openShardDbReadOnly(db, pkg, year) ?: continue
            shard.use { shardDb ->
                val table = monthTableName(year, month)
                if (!tableExists(shardDb, table)) return@use
                val paths = group.map { it.filePath }.filter { it.isNotBlank() }.distinct()
                for (chunk in paths.chunked(300)) {
                    val placeholders = List(chunk.size) { "?" }.joinToString(",")
                    val sql = "SELECT file_path, ocr_text FROM $table WHERE file_path IN ($placeholders) AND ocr_text IS NOT NULL AND LENGTH(ocr_text) > 0"
                    try {
                        shardDb.rawQuery(sql, chunk.toTypedArray()).use { c ->
                            while (c.moveToNext()) {
                                val path = c.getStringOrNull(0).orEmpty()
                                val text = c.getStringOrNull(1).orEmpty().trim()
                                if (path.isNotBlank() && text.isNotBlank()) out[path] = text
                            }
                        }
                    } catch (e: Exception) {
                        FileLogger.w(TAG, "load OCR failed: ${e.message}")
                    }
                }
            }
        }
        return out
    }

    private fun searchDocsInternal(
        db: SQLiteDatabase,
        query: String,
        docType: String?,
        limit: Int,
        offset: Int,
        startTime: Long?,
        endTime: Long?,
    ): JSONArray {
        val terms = queryTerms(query)
        val filters = mutableListOf<String>()
        val args = ArrayList<String>()
        for (term in terms) {
            filters.add("(d.title LIKE ? OR d.content LIKE ? OR d.tags LIKE ? OR d.app_name LIKE ?)")
            val like = "%$term%"
            repeat(4) { args.add(like) }
        }
        if (docType != null) {
            filters.add("d.doc_type = ?")
            args.add(docType)
        }
        if (startTime != null) {
            filters.add("(d.start_time IS NULL OR d.start_time >= ?)")
            args.add(startTime.toString())
        }
        if (endTime != null) {
            filters.add("(d.start_time IS NULL OR d.start_time <= ?)")
            args.add(endTime.toString())
        }
        args.add(limit.toString())
        args.add(offset.toString())
        val sql =
            """
            SELECT doc_key, doc_type, title, content, tags, app_package_name, app_name,
                   file_path, screenshot_id, segment_id, date_key, start_time, end_time, nsfw, updated_at
            FROM search_docs d
            WHERE ${filters.joinToString(" AND ")}
            ORDER BY d.updated_at DESC
            LIMIT ? OFFSET ?
            """.trimIndent()
        val out = JSONArray()
        db.rawQuery(sql, args.toTypedArray()).use { c ->
            while (c.moveToNext()) {
                out.put(
                    JSONObject()
                        .put("doc_key", c.getStringOrNull(0) ?: "")
                        .put("doc_type", c.getStringOrNull(1) ?: "")
                        .put("title", c.getStringOrNull(2) ?: "")
                        .put("content", truncate(c.getStringOrNull(3).orEmpty(), SEARCH_DOC_CONTENT_LIMIT))
                        .put("tags", c.getStringOrNull(4) ?: JSONObject.NULL)
                        .put("app_package_name", c.getStringOrNull(5) ?: JSONObject.NULL)
                        .put("app_name", c.getStringOrNull(6) ?: JSONObject.NULL)
                        .put("file_path", c.getStringOrNull(7) ?: JSONObject.NULL)
                        .put("screenshot_id", c.getLongOrNull(8) ?: JSONObject.NULL)
                        .put("segment_id", c.getLongOrNull(9) ?: JSONObject.NULL)
                        .put("date_key", c.getStringOrNull(10) ?: JSONObject.NULL)
                        .put("start_time", c.getLongOrNull(11) ?: JSONObject.NULL)
                        .put("end_time", c.getLongOrNull(12) ?: JSONObject.NULL)
                        .put("nsfw", c.getInt(13) != 0)
                        .put("updated_at", c.getLongOrNull(14) ?: JSONObject.NULL),
                )
            }
        }
        return out
    }

    private fun searchScreenshotsInternal(
        db: SQLiteDatabase,
        query: String,
        limit: Int,
        offset: Int,
        startTime: Long?,
        endTime: Long?,
        includeOcr: Boolean,
    ): JSONArray {
        val refs = loadShardRefs(db)
        if (refs.isEmpty()) return JSONArray()
        val terms = queryTerms(query)
        val targetCount = limit + offset
        val results = ArrayList<JSONObject>()
        for (ref in refs) {
            val shard = openShardDbReadOnly(db, ref.packageName, ref.year, ref.dbPath) ?: continue
            shard.use { shardDb ->
                for (month in 1..12) {
                    val table = monthTableName(ref.year, month)
                    if (!tableExists(shardDb, table)) continue
                    val filters = mutableListOf("COALESCE(is_deleted, 0) = 0")
                    val args = ArrayList<String>()
                    if (startTime != null) {
                        filters.add("capture_time >= ?")
                        args.add(startTime.toString())
                    }
                    if (endTime != null) {
                        filters.add("capture_time <= ?")
                        args.add(endTime.toString())
                    }
                    for (term in terms) {
                        filters.add("(ocr_text LIKE ? OR page_url LIKE ? OR file_path LIKE ?)")
                        val like = "%$term%"
                        args.add(like)
                        args.add(like)
                        args.add(like)
                    }
                    args.add(targetCount.coerceAtLeast(limit).toString())
                    val sql =
                        """
                        SELECT file_path, capture_time, file_size, page_url, ocr_text
                        FROM $table
                        WHERE ${filters.joinToString(" AND ")}
                        ORDER BY capture_time DESC
                        LIMIT ?
                        """.trimIndent()
                    try {
                        shardDb.rawQuery(sql, args.toTypedArray()).use { c ->
                            while (c.moveToNext()) {
                                val path = c.getStringOrNull(0).orEmpty()
                                val ocr = c.getStringOrNull(4).orEmpty()
                                val hiddenOcrSummary = if (ocr.isBlank()) {
                                    ""
                                } else {
                                    "OCR match found. Text is hidden by default; set include_ocr=true to return truncated OCR text."
                                }
                                results.add(
                                    JSONObject()
                                        .put("image_ref", encodeImageRef(path))
                                        .put("file_path", path)
                                        .put("capture_time", c.getLong(1))
                                        .put("capture_time_text", formatMillis(c.getLong(1)))
                                        .put("file_size", c.getLong(2))
                                        .put("page_url", c.getStringOrNull(3) ?: JSONObject.NULL)
                                        .put("app_package_name", ref.packageName)
                                        .put("app_name", ref.appName)
                                        .put("summary", hiddenOcrSummary)
                                        .put(
                                            "ocr_preview",
                                            if (includeOcr) {
                                                buildSnippet(ocr, terms, SCREENSHOT_OCR_PREVIEW_LIMIT)
                                            } else {
                                                JSONObject.NULL
                                            },
                                        )
                                        .put("ocr_text", if (includeOcr) truncate(ocr, SCREENSHOT_OCR_FULL_LIMIT) else JSONObject.NULL)
                                        .put("ocr_truncated", includeOcr && ocr.length > SCREENSHOT_OCR_FULL_LIMIT),
                                )
                            }
                        }
                    } catch (e: Exception) {
                        FileLogger.w(TAG, "search screenshot table failed: ${e.message}")
                    }
                }
            }
        }
        results.sortByDescending { it.optLong("capture_time", 0L) }
        val out = JSONArray()
        results.drop(offset).take(limit).forEach { out.put(it) }
        return out
    }

    private fun loadShardRefs(db: SQLiteDatabase): List<ShardRef> {
        if (!tableExists(db, "shard_registry")) return emptyList()
        val out = ArrayList<ShardRef>()
        val sql =
            """
            SELECT sr.app_package_name, sr.year, sr.db_path, COALESCE(ar.app_name, sr.app_package_name) AS app_name
            FROM shard_registry sr
            LEFT JOIN app_registry ar ON ar.app_package_name = sr.app_package_name
            ORDER BY sr.year DESC, sr.app_package_name ASC
            """.trimIndent()
        db.rawQuery(sql, emptyArray()).use { c ->
            while (c.moveToNext()) {
                out.add(
                    ShardRef(
                        packageName = c.getStringOrNull(0).orEmpty(),
                        year = c.getInt(1),
                        dbPath = c.getStringOrNull(2),
                        appName = c.getStringOrNull(3).orEmpty(),
                    ),
                )
            }
        }
        return out
    }

    private fun openShardDbReadOnly(
        masterDb: SQLiteDatabase,
        packageName: String,
        year: Int,
        registryDbPath: String? = lookupShardPath(masterDb, packageName, year),
    ): SQLiteDatabase? {
        val candidates = ArrayList<String>()
        val reg = registryDbPath?.trim().orEmpty()
        if (reg.isNotBlank()) candidates.add(reg)
        expectedShardPath(packageName, year)?.let {
            if (it !in candidates) candidates.add(it)
        }
        for (path in candidates) {
            try {
                val file = File(path)
                if (!file.exists() || !file.isFile) continue
                return SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun lookupShardPath(db: SQLiteDatabase, packageName: String, year: Int): String? {
        if (!tableExists(db, "shard_registry")) return null
        db.rawQuery(
            "SELECT db_path FROM shard_registry WHERE app_package_name = ? AND year = ? LIMIT 1",
            arrayOf(packageName, year.toString()),
        ).use { c ->
            return if (c.moveToFirst()) c.getStringOrNull(0) else null
        }
    }

    private fun expectedShardPath(packageName: String, year: Int): String? {
        return try {
            val sanitized = sanitizePackageName(packageName)
            File(
                File(File(File(context.filesDir, SHARDS_DIR_RELATIVE), sanitized), year.toString()),
                "smm_${sanitized}_${year}.db",
            ).absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun buildContextText(items: JSONArray): String {
        val sb = StringBuilder()
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            sb.append("[")
                .append(item.optLong("segment_id"))
                .append("] ")
                .append(item.optString("start_time_text"))
                .append(" - ")
                .append(item.optString("end_time_text"))
                .append("\n")
                .append(item.optString("summary"))
                .append("\n\n")
        }
        return truncate(sb.toString().trim(), 24000)
    }

    private fun structuredPreview(raw: String?): Any {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty() || text.equals("null", ignoreCase = true)) return JSONObject.NULL
        return try {
            val obj = JSONObject(text)
            val preview = JSONObject()
            for (key in listOf("apps", "categories", "timeline", "key_actions", "content_groups", "overall_summary")) {
                if (obj.has(key)) preview.put(key, obj.opt(key))
            }
            preview
        } catch (_: Exception) {
            JSONObject()
                .put("parse_error", true)
                .put("raw_preview", truncate(text, 4000))
        }
    }

    private fun extractOverallSummary(structuredJson: String?, outputText: String?): String {
        val raw = structuredJson?.trim().orEmpty()
        if (raw.isNotEmpty() && !raw.equals("null", ignoreCase = true)) {
            try {
                val obj = JSONObject(raw)
                val summary = obj.optString("overall_summary", "").trim()
                if (summary.isNotEmpty()) return summary
            } catch (_: Exception) {
            }
        }
        return outputText?.trim().orEmpty()
    }

    private fun parseJsonOrString(raw: String?): Any {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty() || value.equals("null", ignoreCase = true)) return JSONObject.NULL
        return try {
            when {
                value.startsWith("[") -> JSONArray(value)
                value.startsWith("{") -> JSONObject(value)
                else -> value
            }
        } catch (_: Exception) {
            value
        }
    }

    private fun buildSnippet(text: String, terms: List<String>, maxLen: Int): String {
        if (text.isBlank()) return ""
        val lower = text.lowercase(Locale.getDefault())
        val idx = terms.asSequence()
            .map { lower.indexOf(it.lowercase(Locale.getDefault())) }
            .filter { it >= 0 }
            .minOrNull() ?: 0
        val start = (idx - maxLen / 3).coerceAtLeast(0)
        val end = (start + maxLen).coerceAtMost(text.length)
        val prefix = if (start > 0) "..." else ""
        val suffix = if (end < text.length) "..." else ""
        return prefix + text.substring(start, end) + suffix
    }

    private fun queryTerms(query: String): List<String> {
        val parts = query.split(Regex("\\s+")).map { it.trim() }.filter { it.isNotEmpty() }
        return (if (parts.isEmpty()) listOf(query.trim()) else parts).take(5)
    }

    private fun requireMasterDb(): SQLiteDatabase {
        return openMasterDb() ?: throw IllegalArgumentException("master database is not available")
    }

    private fun openMasterDb(): SQLiteDatabase? {
        val path = resolveMasterDbPath() ?: return null
        val file = File(path)
        if (!file.exists() || !file.isFile) return null
        return try {
            SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
        } catch (e: Exception) {
            FileLogger.w(TAG, "open master db failed: ${e.message}")
            null
        }
    }

    private fun resolveMasterDbPath(): String? {
        return try {
            val primary = File(File(context.filesDir, MASTER_DB_DIR_RELATIVE), MASTER_DB_FILE_NAME)
            if (primary.exists()) return primary.absolutePath
            val fallback = context.getDatabasePath(MASTER_DB_FILE_NAME)
            if (fallback.exists()) fallback.absolutePath else primary.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun tableExists(db: SQLiteDatabase, table: String): Boolean {
        db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
            arrayOf(table),
        ).use { c ->
            return c.moveToFirst()
        }
    }

    private fun safeCount(db: SQLiteDatabase, table: String): Long {
        if (!tableExists(db, table)) return 0L
        return queryLong(db, "SELECT COUNT(*) FROM $table")
    }

    private fun queryLong(db: SQLiteDatabase, sql: String): Long {
        return queryLongOrNull(db, sql) ?: 0L
    }

    private fun queryLongOrNull(db: SQLiteDatabase, sql: String): Long? {
        return try {
            db.rawQuery(sql, emptyArray()).use { c ->
                if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun rootSegmentWhere(alias: String): String {
        val prefix = if (alias.isBlank()) "" else "$alias."
        return "(${prefix}merged_into_id IS NULL OR ${prefix}merged_into_id <= 0 OR NOT EXISTS (SELECT 1 FROM segments root WHERE root.id = ${prefix}merged_into_id))"
    }

    private fun limit(args: JSONObject): Int {
        val raw = if (args.has("limit")) args.optInt("limit", DEFAULT_LIMIT) else DEFAULT_LIMIT
        return raw.coerceIn(1, MAX_LIMIT)
    }

    private fun imageLimit(args: JSONObject): Int {
        val raw = if (args.has("limit")) args.optInt("limit", 3) else 3
        return raw.coerceIn(1, MAX_IMAGE_LIMIT)
    }

    private fun offset(args: JSONObject): Int {
        return if (args.has("offset")) args.optInt("offset", 0).coerceAtLeast(0) else 0
    }

    private fun requireLong(args: JSONObject, key: String): Long {
        return optLong(args, key) ?: throw IllegalArgumentException("$key is required")
    }

    private fun optLong(args: JSONObject, key: String): Long? {
        if (!args.has(key) || args.isNull(key)) return null
        val value = args.opt(key)
        return when (value) {
            is Number -> value.toLong()
            is String -> value.trim().toLongOrNull()
            else -> null
        }
    }

    private fun encodeImageRef(path: String): String {
        val encoded = Base64.encodeToString(path.toByteArray(Charsets.UTF_8), Base64.NO_WRAP or Base64.URL_SAFE)
        return "shot:$encoded"
    }

    private fun decodeImageRef(ref: String): String? {
        val value = ref.trim()
        if (!value.startsWith("shot:")) return null
        return try {
            String(Base64.decode(value.substringAfter("shot:"), Base64.NO_WRAP or Base64.URL_SAFE), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun mimeType(path: String): String {
        return when (path.substringAfterLast('.', "").lowercase(Locale.US)) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
    }

    private fun monthTableName(year: Int, month: Int): String {
        return "shots_${year}${month.toString().padStart(2, '0')}"
    }

    private fun sanitizePackageName(packageName: String): String {
        return packageName.replace(Regex("[^\\w]"), "_")
    }

    private fun formatMillis(value: Long): String {
        if (value <= 0L) return ""
        return try {
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(value))
        } catch (_: Exception) {
            value.toString()
        }
    }

    private fun truncate(value: String, max: Int): String {
        if (value.length <= max) return value
        if (max <= 3) return value.take(max)
        return value.take(max - 3) + "..."
    }

    private fun mapToJson(map: Map<String, Any?>): JSONObject {
        val out = JSONObject()
        for ((key, value) in map) {
            out.put(key, toJsonValue(value))
        }
        return out
    }

    private fun toJsonValue(value: Any?): Any {
        return when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> {
                val obj = JSONObject()
                value.forEach { (k, v) -> obj.put(k?.toString() ?: "", toJsonValue(v)) }
                obj
            }
            is Iterable<*> -> {
                val arr = JSONArray()
                value.forEach { arr.put(toJsonValue(it)) }
                arr
            }
            else -> value
        }
    }

    private fun Cursor.getStringOrNull(index: Int): String? = if (isNull(index)) null else getString(index)
    private fun Cursor.getLongOrNull(index: Int): Long? = if (isNull(index)) null else getLong(index)

    private data class SampleRow(
        val id: Long,
        val segmentId: Long,
        val captureTime: Long,
        val filePath: String,
        val appPackageName: String,
        val appName: String,
        val positionIndex: Int,
    )

    private data class ShardRef(
        val packageName: String,
        val year: Int,
        val dbPath: String?,
        val appName: String,
    )
}
