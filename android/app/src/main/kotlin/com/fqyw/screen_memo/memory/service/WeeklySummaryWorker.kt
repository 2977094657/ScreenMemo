package com.fqyw.screen_memo.memory.service

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.fqyw.screen_memo.AISettingsNative
import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.OkHttpClientFactory
import com.fqyw.screen_memo.OutputFileLogger
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.min

/**
 * 原生周总结 Worker：在后台读取过去一周的每日总结与分段摘要，调用文本模型生成周总结并写入 weekly_summaries。
 * 触发入口：MemoryProcessingReceiver.enqueueWeeklySummaryIfDue -> WorkManager
 */
class WeeklySummaryWorker(appContext: Context, params: WorkerParameters) :
    Worker(appContext, params) {

    override fun doWork(): Result {
        try {
            FileLogger.init(applicationContext)
        } catch (_: Exception) {}

        val zone = ZoneId.systemDefault()
        val weekStartKey = inputData.getString(KEY_WEEK_START)
            ?: run {
                try { OutputFileLogger.errorForce(applicationContext, TAG, "doWork 缺少输入参数 weekStartKey") } catch (_: Exception) {}
                return Result.failure()
            }

        try { OutputFileLogger.infoForce(applicationContext, TAG, "doWork 开始 weekStartKey=$weekStartKey") } catch (_: Exception) {}

        val weekStart = try {
            LocalDate.parse(weekStartKey, DATE_FMT)
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "weekStartKey 无效：$weekStartKey") } catch (_: Exception) {}
            try { OutputFileLogger.errorForce(applicationContext, TAG, "weekStartKey 无效：$weekStartKey") } catch (_: Exception) {}
            return Result.failure()
        }
        val weekEnd = weekStart.plusDays(6)
        val startMillis = weekStart.atStartOfDay(zone).toInstant().toEpochMilli()
        val endMillis = weekEnd.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() - 1

        var db: SQLiteDatabase? = null
        try {
            db = openMasterDb(applicationContext, writable = true)
            if (db == null) {
                try { OutputFileLogger.errorForce(applicationContext, TAG, "打开主库返回 null；将重试") } catch (_: Exception) {}
                return Result.retry()
            }

            // 若已存在则直接成功
            if (hasWeeklySummary(db, weekStartKey)) {
                try { FileLogger.i(TAG, "周总结已存在：$weekStartKey") } catch (_: Exception) {}
                try { setLastGeneratedWeek(applicationContext, weekStartKey) } catch (_: Exception) {}
                try { OutputFileLogger.infoForce(applicationContext, TAG, "周总结已存在：$weekStartKey") } catch (_: Exception) {}
                return Result.success()
            }

            val dailySummaries = loadDailySummaries(db, weekStart, weekEnd)
            val segmentSummaries = loadSegmentSummaries(db, startMillis, endMillis)

            val lang = detectLang(applicationContext)
            val prompt = buildPrompt(lang, weekStartKey, weekEnd.format(DATE_FMT), dailySummaries, segmentSummaries)

            val (model, content) = callTextModel(applicationContext, prompt, lang)
            val (outputText, structuredJson) = extractStructured(content)

            upsertWeeklySummary(
                db = db,
                weekStart = weekStartKey,
                weekEnd = weekEnd.format(DATE_FMT),
                aiModel = model,
                outputText = outputText,
                structuredJson = structuredJson
            )

            try { setLastGeneratedWeek(applicationContext, weekStartKey) } catch (_: Exception) {}

            try { FileLogger.i(TAG, "周总结已生成：weekStartKey=$weekStartKey 模型=$model 长度=${outputText.length}") } catch (_: Exception) {}
            try { OutputFileLogger.infoForce(applicationContext, TAG, "周总结已生成：weekStartKey=$weekStartKey 模型=$model 长度=${outputText.length}") } catch (_: Exception) {}
            return Result.success()
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "周总结 Worker 执行失败：${e.message}", e) } catch (_: Exception) {}
            try { OutputFileLogger.errorForce(applicationContext, TAG, "周总结 Worker 执行失败：${e.message}\n${e.stackTraceToString()}") } catch (_: Exception) {}
            return Result.retry()
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    // ---------- Data loading ----------

    private fun loadDailySummaries(db: SQLiteDatabase, start: LocalDate, end: LocalDate): List<DaySummary> {
        val res = ArrayList<DaySummary>()
        val startKey = start.format(DATE_FMT)
        val endKey = end.format(DATE_FMT)
        val cursor: Cursor? = try {
            db.query(
                "daily_summaries",
                arrayOf("date_key", "output_text", "structured_json"),
                "date_key >= ? AND date_key <= ?",
                arrayOf(startKey, endKey),
                null, null,
                "date_key ASC"
            )
        } catch (_: Exception) { null }
        cursor?.use { c ->
            while (c.moveToNext()) {
                val dateKey = c.getString(0) ?: continue
                val outText = c.getString(1) ?: ""
                val structured = c.getString(2)
                val overall = structured?.let { tryExtractJsonField(it, "overall_summary") } ?: outText
                res.add(DaySummary(dateKey, overall ?: outText))
            }
        }
        return res
    }

    private fun loadSegmentSummaries(db: SQLiteDatabase, startMillis: Long, endMillis: Long): List<SegmentSummary> {
        val res = ArrayList<SegmentSummary>()
        val sql = """
            SELECT s.start_time, s.end_time, s.app_packages, sr.output_text, sr.structured_json
            FROM segments s
            LEFT JOIN segment_results sr ON sr.segment_id = s.id
            WHERE s.start_time >= ? AND s.end_time <= ?
            ORDER BY s.start_time ASC
            LIMIT 160
        """.trimIndent()
        val cursor = try {
            db.rawQuery(sql, arrayOf(startMillis.toString(), endMillis.toString()))
        } catch (_: Exception) { null }
        cursor?.use { c ->
            while (c.moveToNext()) {
                val st = c.getLong(0)
                val et = c.getLong(1)
                val apps = c.getString(2) ?: ""
                val outText = c.getString(3) ?: ""
                val structured = c.getString(4)
                val summary = structured?.let { tryExtractJsonField(it, "overall_summary") } ?: outText
                if (!summary.isNullOrBlank()) {
                    res.add(SegmentSummary(st, et, apps, summary.trim()))
                }
                if (res.size >= 120) break // 再次兜底
            }
        }
        return res
    }

    // ---------- Prompt & AI ----------

    private fun buildPrompt(
        lang: String,
        weekStart: String,
        weekEnd: String,
        daily: List<DaySummary>,
        segments: List<SegmentSummary>
    ): String {
        val isZh = lang.startsWith("zh")
        val header = if (isZh) ZH_HEADER else EN_HEADER
        val sb = StringBuilder()
        sb.append(header).append("\n\n")
        sb.append(if (isZh) "周起始: " else "Week start: ").append(weekStart).append('\n')
        sb.append(if (isZh) "周结束: " else "Week end: ").append(weekEnd).append("\n\n")

        sb.append(if (isZh) "【每日总结】\n" else "[Daily summaries]\n")
        if (daily.isEmpty()) {
            sb.append(if (isZh) "- 本周暂无每日总结\n" else "- No daily summaries this week\n")
        } else {
            for (d in daily) {
                val text = d.summary.take(600)
                sb.append("- ").append(d.dateKey).append(": ").append(text).append('\n')
            }
        }

        sb.append("\n").append(if (isZh) "【分段摘要（最多120条）】\n" else "[Segment snippets (up to 120)]\n")
        if (segments.isEmpty()) {
            sb.append(if (isZh) "- 无分段摘要\n" else "- No segment snippets\n")
        } else {
            for (s in segments) {
                val range = formatRange(s.start, s.end)
                val appLabel = if (s.apps.isBlank()) "" else " (${s.apps})"
                val text = s.summary.take(400)
                sb.append("- ").append(range).append(appLabel).append(": ").append(text).append('\n')
            }
        }

        sb.append("\n").append(if (isZh) OUTPUT_SPEC_ZH else OUTPUT_SPEC_EN)
        return sb.toString()
    }

    private fun callTextModel(ctx: Context, prompt: String, lang: String): Pair<String, String> {
        val cfg = try {
            AISettingsNative.readConfig(ctx, "weekly")
        } catch (_: Exception) {
            AISettingsNative.readConfig(ctx)
        }
        val client = OkHttpClientFactory.newBuilder(ctx)
            .connectTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
            .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
            .writeTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            .build()
        val systemMsg = if (lang.startsWith("zh")) ZH_SYSTEM else EN_SYSTEM

        val baseUrl = resolveBaseUrl(cfg.baseUrl)
        val host = try { baseUrl.host.lowercase() } catch (_: Exception) { "" }
        val typeLower = (cfg.providerType ?: "").trim().lowercase()
        val isGoogle = typeLower == "gemini" || host.contains("googleapis.com") || host.contains("generativelanguage")
        val isAzure = typeLower == "azure_openai"

        return if (isGoogle) {
            val url = resolveEndpointUrl(baseUrl, "/v1beta/models/${cfg.model}:generateContent").toString()
            val body = JSONObject().put(
                "contents",
                JSONArray().put(
                    JSONObject().put(
                        "parts",
                        JSONArray()
                            .put(JSONObject().put("text", systemMsg))
                            .put(JSONObject().put("text", prompt))
                    )
                )
            )
            val reqBody = body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())
            val req = Request.Builder()
                .url(url)
                .addHeader("x-goog-api-key", cfg.apiKey)
                .post(reqBody)
                .build()
            val resp = client.newCall(req).execute()
            val respText = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IllegalStateException("Request failed: ${resp.code} $respText")
            var content = ""
            try {
                val obj = JSONObject(respText)
                val candidates = obj.optJSONArray("candidates")
                if (candidates != null && candidates.length() > 0) {
                    val c0 = candidates.getJSONObject(0)
                    val ct = c0.optJSONObject("content")
                    val parts = ct?.optJSONArray("parts")
                    if (parts != null && parts.length() > 0) {
                        content = parts.getJSONObject(0).optString("text", "")
                    }
                }
            } catch (_: Exception) {}
            if (content.isBlank()) throw IllegalStateException("Empty content: $respText")
            Pair(cfg.model, content)
        } else {
            val chatPath = cfg.chatPath?.trim().takeIf { !it.isNullOrEmpty() } ?: "/v1/chat/completions"
            val url = resolveEndpointUrl(baseUrl, chatPath).toString()
            val messages = JSONArray()
                .put(JSONObject().put("role", "system").put("content", systemMsg))
                .put(JSONObject().put("role", "user").put("content", prompt))
            val body = JSONObject()
                .put("messages", messages)
                .put("temperature", 0.2)
                .put("stream", false)
            if (!isAzure) {
                body.put("model", cfg.model)
            }
            val reqBody = body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())
            val reqBuilder = Request.Builder()
                .url(url)
                .post(reqBody)
                .addHeader("Content-Type", "application/json")
            if (isAzure) {
                reqBuilder.addHeader("api-key", cfg.apiKey)
            } else {
                reqBuilder.addHeader("Authorization", "Bearer ${cfg.apiKey}")
            }
            val req = reqBuilder.build()
            val resp = client.newCall(req).execute()
            val respText = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IllegalStateException("Request failed: ${resp.code} $respText")
            var content = ""
            try {
                val obj = JSONObject(respText)
                val choices = obj.optJSONArray("choices")
                if (choices != null && choices.length() > 0) {
                    val c0 = choices.getJSONObject(0)
                    val msg = c0.optJSONObject("message")
                    content = msg?.optString("content", "") ?: ""
                }
            } catch (_: Exception) {}
            if (content.isBlank()) throw IllegalStateException("Empty content: $respText")
            Pair(cfg.model, content)
        }
    }

    private fun resolveBaseUrl(raw: String): HttpUrl {
        val candidate = raw.trim()
        candidate.toHttpUrlOrNull()?.let { return it }
        val httpsCandidate = "https://$candidate"
        httpsCandidate.toHttpUrlOrNull()?.let { return it }
        throw IllegalStateException("Invalid base URL: $candidate")
    }

    private fun resolveEndpointUrl(base: HttpUrl, rawPath: String): HttpUrl {
        val candidate = rawPath.trim()
        if (candidate.startsWith("http", ignoreCase = true)) {
            return candidate.toHttpUrlOrNull() ?: throw IllegalStateException("Invalid endpoint URL: $candidate")
        }
        val normalized = if (candidate.startsWith("/")) candidate else "/$candidate"
        return base.resolve(normalized) ?: throw IllegalStateException("Invalid endpoint path: $candidate")
    }

    // ---------- Persistence ----------

    private fun hasWeeklySummary(db: SQLiteDatabase, weekStart: String): Boolean {
        val cursor = try {
            db.query(
                "weekly_summaries",
                arrayOf("week_start_date"),
                "week_start_date = ?",
                arrayOf(weekStart),
                null, null, null, "1"
            )
        } catch (_: Exception) { null }
        cursor?.use { if (it.moveToFirst()) return true }
        return false
    }

    private fun upsertWeeklySummary(
        db: SQLiteDatabase,
        weekStart: String,
        weekEnd: String,
        aiModel: String,
        outputText: String,
        structuredJson: String?
    ) {
        val cv = android.content.ContentValues().apply {
            put("week_start_date", weekStart)
            put("week_end_date", weekEnd)
            put("ai_provider", aiProviderName(aiModel))
            put("ai_model", aiModel)
            put("output_text", outputText)
            if (!structuredJson.isNullOrBlank()) put("structured_json", structuredJson)
            put("created_at", System.currentTimeMillis())
        }
        db.insertWithOnConflict("weekly_summaries", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun setLastGeneratedWeek(context: Context, weekStartKey: String) {
        try {
            val prefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            prefs.edit().putString("weekly_summary_last_generated_week", weekStartKey).apply()
        } catch (_: Exception) {}
    }

    private fun aiProviderName(model: String): String =
        when {
            model.contains("gpt", true) -> "openai"
            model.contains("gemini", true) -> "google"
            else -> "segments"
        }

    // ---------- Helpers ----------

    private fun openMasterDb(context: Context, writable: Boolean): SQLiteDatabase? {
        return try {
            val base = context.filesDir.absolutePath
            val dbDir = File(base, MASTER_DB_DIR_RELATIVE)
            if (!dbDir.exists()) dbDir.mkdirs()
            val path = File(dbDir, MASTER_DB_FILE_NAME).absolutePath
            if (writable) {
                SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY)
            } else {
                SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY)
            }
        } catch (e: Exception) {
            try { FileLogger.w(TAG, "打开主库失败：${e.message}") } catch (_: Exception) {}
            null
        }
    }

    private fun tryExtractJsonField(json: String, field: String): String? {
        return try {
            val obj = JSONObject(json)
            obj.optString(field, null)?.takeIf { it.isNotBlank() }
        } catch (_: Exception) { null }
    }

    private fun extractStructured(content: String): Pair<String, String?> {
        // 若可解析 JSON 则存 structured_json，同时 outputText 选用 weekly_overview 或原文
        var output = content.trim()
        var structured: String? = null
        try {
            val obj = JSONObject(content)
            structured = obj.toString()
            val overview = obj.optString("weekly_overview", null)
            if (!overview.isNullOrBlank()) output = overview.trim()
        } catch (_: Exception) {
            // ignore
        }
        return Pair(output, structured)
    }

    private fun formatRange(st: Long, et: Long): String {
        return try {
            val zone = ZoneId.systemDefault()
            val s = java.time.Instant.ofEpochMilli(st).atZone(zone)
            val e = java.time.Instant.ofEpochMilli(et).atZone(zone)
            String.format("%02d:%02d-%02d:%02d", s.hour, s.minute, e.hour, e.minute)
        } catch (_: Exception) {
            "$st-$et"
        }
    }

    private fun detectLang(ctx: Context): String {
        val pref = try {
            ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.locale_option", "system")
        } catch (_: Exception) { "system" }
        val sys = try { java.util.Locale.getDefault().language?.lowercase() } catch (_: Exception) { "en" } ?: "en"
        return when (pref) {
            "zh", "en", "ja", "ko" -> pref
            else -> if (sys.startsWith("zh")) "zh" else sys
        }
    }

    data class DaySummary(val dateKey: String, val summary: String)
    data class SegmentSummary(val start: Long, val end: Long, val apps: String, val summary: String)

    companion object {
        private const val TAG = "WeeklySummaryWorker"
        private const val KEY_WEEK_START = "weekStartKey"
        private const val MASTER_DB_DIR_RELATIVE = "output/databases"
        private const val MASTER_DB_FILE_NAME = "screenshot_memo.db"
        private val DATE_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

        private const val ZH_HEADER = "你是一名严谨的周总结助手。请基于提供的每日总结与分段摘要，生成结构化的周总结。"
        private const val EN_HEADER = "You are a disciplined weekly review assistant. Use the provided daily summaries and segment snippets to produce a structured weekly report."
        private const val OUTPUT_SPEC_ZH = "输出JSON，字段：weekly_overview(使用Markdown)、daily_breakdowns[{date_key,headline,highlights>=3}]、action_items(4-6条，动词开头)、notification_brief(1-2句，不含Markdown)。如果信息不足，也要给出可行动或提醒性的内容。"
        private const val OUTPUT_SPEC_EN = "Return JSON with fields: weekly_overview (Markdown), daily_breakdowns[{date_key,headline,highlights>=3}], action_items(4-6, start with verbs), notification_brief(1-2 sentences, plain). Provide actionable or cautionary items even when evidence is thin."
        private const val ZH_SYSTEM = "始终使用中文回答。"
        private const val EN_SYSTEM = "Always respond in English unless the user language is specified otherwise."

        fun enqueueOnce(ctx: Context, weekStartKey: String) {
            try {
                val data = Data.Builder().putString(KEY_WEEK_START, weekStartKey).build()
                val constraints = Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
                val req: OneTimeWorkRequest = OneTimeWorkRequestBuilder<WeeklySummaryWorker>()
                    .setInputData(data)
                    .setConstraints(constraints)
                    .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                    .build()
                val uniqueName = "weekly_summary_$weekStartKey"
                WorkManager.getInstance(ctx).enqueueUniqueWork(uniqueName, ExistingWorkPolicy.KEEP, req)
                try { FileLogger.i(TAG, "周总结已入队：$weekStartKey") } catch (_: Exception) {}
                try { OutputFileLogger.infoForce(ctx, TAG, "提交唯一任务：name=$uniqueName") } catch (_: Exception) {}
            } catch (e: Exception) {
                try { FileLogger.e(TAG, "入队失败：${e.message}", e) } catch (_: Exception) {}
                try { OutputFileLogger.errorForce(ctx, TAG, "入队失败：${e.message}\n${e.stackTraceToString()}") } catch (_: Exception) {}
            }
        }
    }
}
