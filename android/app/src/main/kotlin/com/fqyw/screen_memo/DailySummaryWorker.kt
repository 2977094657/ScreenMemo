package com.fqyw.screen_memo

import android.content.Context
import android.database.sqlite.SQLiteDatabase
 
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkRequest
import androidx.work.Worker
import androidx.work.WorkerParameters
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.Calendar

data class MorningInsightsRecord(
    val dateKey: String,
    val sourceDateKey: String,
    val tips: List<String>,
    val raw: String?,
    val createdAt: Long
)

/**
 * 原生每日总结 Worker：在后台读取当天的段落结果聚合后，调用文本模型生成“每日总结”，
 * 并写入主库 daily_summaries 表，同时把通知简报写入 SharedPreferences。
 */
class DailySummaryWorker(appContext: Context, params: WorkerParameters) : Worker(appContext, params) {

    override fun doWork(): Result {
        try {
            FileLogger.init(applicationContext)
        } catch (_: Exception) {}
        val dateKey = inputData.getString(KEY_DATE) ?: todayKey()
        try { FileLogger.i(TAG, "doWork: date=$dateKey") } catch (_: Exception) {}
        return try {
            val ok = generateForDate(applicationContext, dateKey)
            if (ok) Result.success() else Result.retry()
        } catch (e: Exception) {
            try { FileLogger.e(TAG, "daily worker failed: ${e.message}", e) } catch (_: Exception) {}
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "DailySummaryWorker"
        private const val KEY_DATE = "dateKey"
        private const val MASTER_DB_DIR_RELATIVE = "output/databases"
        private const val MASTER_DB_FILE_NAME = "screenshot_memo.db"
        private const val TABLE_MORNING_INSIGHTS = "morning_insights"

        fun enqueueOnce(ctx: Context, dateKey: String) {
            try {
                val data = Data.Builder().putString(KEY_DATE, dateKey).build()
                val constraints = Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
                val req: WorkRequest = OneTimeWorkRequestBuilder<DailySummaryWorker>()
                    .setInputData(data)
                    .setConstraints(constraints)
                    .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                    .build()
                WorkManager.getInstance(ctx).enqueue(req)
                try { FileLogger.i(TAG, "enqueueOnce: date=$dateKey enqueued") } catch (_: Exception) {}
            } catch (_: Exception) {}
        }

        private fun todayKey(): String {
            val cal = Calendar.getInstance()
            val y = cal.get(Calendar.YEAR)
            val m = cal.get(Calendar.MONTH) + 1
            val d = cal.get(Calendar.DAY_OF_MONTH)
            return String.format("%04d-%02d-%02d", y, m, d)
        }

        private fun resolveMasterDbPath(context: Context): String? {
            return try {
                val base = context.filesDir.absolutePath
                val dbDir = java.io.File(base, MASTER_DB_DIR_RELATIVE)
                if (!dbDir.exists()) dbDir.mkdirs()
                java.io.File(dbDir, MASTER_DB_FILE_NAME).absolutePath
            } catch (_: Exception) {
                try { context.getDatabasePath(MASTER_DB_FILE_NAME).absolutePath } catch (_: Exception) { null }
            }
        }

        private fun openDbRW(context: Context): SQLiteDatabase? {
            return try {
                val path = resolveMasterDbPath(context) ?: return null
                SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY)
            } catch (e: Exception) {
                FileLogger.w(TAG, "openDbRW failed: ${e.message}")
                null
            }
        }

        private fun ensureMorningInsightsTable(db: SQLiteDatabase) {
            try {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS $TABLE_MORNING_INSIGHTS (
                        date_key TEXT PRIMARY KEY,
                        source_date_key TEXT NOT NULL,
                        tips_json TEXT NOT NULL,
                        raw_response TEXT,
                        created_at INTEGER DEFAULT (strftime('%s','now') * 1000)
                    )
                    """.trimIndent()
                )
            } catch (e: Exception) {
                try { FileLogger.w(TAG, "ensureMorningInsightsTable failed: ${e.message}") } catch (_: Exception) {}
            }
        }

        private fun fetchMorningInsights(db: SQLiteDatabase, dateKey: String): MorningInsightsRecord? {
            var cursor: android.database.Cursor? = null
            return try {
                cursor = db.rawQuery(
                    "SELECT source_date_key, tips_json, raw_response, created_at FROM $TABLE_MORNING_INSIGHTS WHERE date_key = ? LIMIT 1",
                    arrayOf(dateKey)
                )
                if (!cursor.moveToFirst()) return null
                val sourceDate = cursor.getString(0) ?: return null
                val tipsJson = cursor.getString(1) ?: "[]"
                val raw = cursor.getString(2)
                val createdAt = cursor.getLong(3)
                val tips = parseTipsJson(tipsJson)
                if (tips.isEmpty()) return null
                MorningInsightsRecord(dateKey, sourceDate, tips, raw, createdAt)
            } catch (e: Exception) {
                try { FileLogger.w(TAG, "fetchMorningInsights failed: ${e.message}") } catch (_: Exception) {}
                null
            } finally {
                cursor?.close()
            }
        }

        private fun saveMorningInsights(db: SQLiteDatabase, record: MorningInsightsRecord) {
            try {
                val json = org.json.JSONArray(record.tips).toString()
                db.execSQL(
                    """
                    INSERT OR REPLACE INTO $TABLE_MORNING_INSIGHTS(date_key, source_date_key, tips_json, raw_response, created_at)
                    VALUES(?, ?, ?, ?, ?)
                    """.trimIndent(),
                    arrayOf(record.dateKey, record.sourceDateKey, json, record.raw, record.createdAt)
                )
            } catch (e: Exception) {
                try { FileLogger.e(TAG, "saveMorningInsights failed: ${e.message}", e) } catch (_: Exception) {}
            }
        }

        private fun parseTipsJson(json: String): List<String> {
            return try {
                val arr = org.json.JSONArray(json)
                val list = mutableListOf<String>()
                for (i in 0 until arr.length()) {
                    val raw = arr.optString(i, "").trim()
                    val cleaned = cleanupTip(raw)
                    if (cleaned.isNotEmpty()) list.add(cleaned)
                }
                list
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun dayRange(dateKey: String): Pair<Long, Long>? {
            return try {
                val parts = dateKey.split('-')
                if (parts.size != 3) return null
                val y = parts[0].toInt()
                val m = parts[1].toInt()
                val d = parts[2].toInt()
                val start = Calendar.getInstance().apply { set(y, m - 1, d, 0, 0, 0); set(Calendar.MILLISECOND, 0) }.timeInMillis
                val end = Calendar.getInstance().apply { set(y, m - 1, d, 23, 59, 59); set(Calendar.MILLISECOND, 999) }.timeInMillis
                Pair(start, end)
            } catch (_: Exception) { null }
        }

        private fun fmtHms(ms: Long): String {
            val cal = Calendar.getInstance().apply { timeInMillis = ms }
            val h = cal.get(Calendar.HOUR_OF_DAY)
            val mi = cal.get(Calendar.MINUTE)
            val s = cal.get(Calendar.SECOND)
            return String.format("%02d:%02d:%02d", h, mi, s)
        }

        fun generateForDate(ctx: Context, dateKey: String): Boolean {
            val range = dayRange(dateKey) ?: return false
            var db: SQLiteDatabase? = null
            return try {
                db = openDbRW(ctx)
                if (db == null) return false
                // 读取当天有结果的段落，仅取 structured_json.overall_summary 作为上下文
                val rows = db!!.rawQuery(
                    """
                    SELECT s.start_time, s.end_time, r.structured_json
                    FROM segments s
                    JOIN segment_results r ON r.segment_id = s.id
                    WHERE s.start_time >= ? AND s.start_time <= ?
                    ORDER BY s.start_time ASC
                    """.trimIndent(),
                    arrayOf(range.first.toString(), range.second.toString())
                )
                val sb = StringBuilder()
                val effectiveLang = try {
                    val langOpt = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.locale_option", "system") ?: "system"
                    val sys = java.util.Locale.getDefault().language?.lowercase() ?: "en"
                    when (langOpt) {
                        "zh", "en", "ja", "ko" -> langOpt
                        "system" -> when {
                            sys.startsWith("zh") -> "zh"
                            sys.startsWith("ja") -> "ja"
                            sys.startsWith("ko") -> "ko"
                            else -> "en"
                        }
                        else -> "en"
                    }
                } catch (_: Exception) { "zh" }
                val languagePolicy = when (effectiveLang) {
                    "zh" -> ctx.getString(R.string.ai_language_policy_zh)
                    "ja" -> ctx.getString(R.string.ai_language_policy_ja)
                    "ko" -> ctx.getString(R.string.ai_language_policy_ko)
                    else -> ctx.getString(R.string.ai_language_policy_en)
                }
                val extraKey = when (effectiveLang) {
                    "zh" -> "prompt_daily_extra_zh"
                    else -> "prompt_daily_extra_en"
                }
                val legacyKey = when (effectiveLang) {
                    "zh" -> "prompt_daily_zh"
                    else -> "prompt_daily_en"
                }
                val extra = try { AISettingsNative.readSettingValue(ctx, extraKey) } catch (_: Exception) { null }
                val legacyLang = try { AISettingsNative.readSettingValue(ctx, legacyKey) } catch (_: Exception) { null }
                val legacy = try { AISettingsNative.readSettingValue(ctx, "prompt_daily") } catch (_: Exception) { null }
                val addon = sequenceOf(extra, legacyLang, legacy)
                    .firstOrNull { it != null && it.trim().isNotEmpty() }
                    ?.trim()
                val headerBuilder = StringBuilder()
                headerBuilder.append(languagePolicy).append("\n\n")
                val defaultTemplate = when (effectiveLang) {
                    "zh" -> DEFAULT_PROMPT_ZH
                    "ja" -> DEFAULT_PROMPT_JA
                    "ko" -> DEFAULT_PROMPT_KO
                    else -> DEFAULT_PROMPT_EN
                }
                if (!addon.isNullOrEmpty()) {
                    val beginMarker = when (effectiveLang) {
                        "zh" -> "【重要附加说明（开始）】"
                        "ja" -> "【重要な追加指示（開始）】"
                        "ko" -> "***중요 추가 지침 (시작)***"
                        else -> "***IMPORTANT EXTRA INSTRUCTIONS (BEGIN)***"
                    }
                    val endMarker = when (effectiveLang) {
                        "zh" -> "【重要附加说明（结束）】"
                        "ja" -> "【重要な追加指示（終了）】"
                        "ko" -> "***중요 추가 지침 (종료)***"
                        else -> "***IMPORTANT EXTRA INSTRUCTIONS (END)***"
                    }
                    headerBuilder.append(beginMarker).append('\n').append(addon).append("\n\n")
                    headerBuilder.append(defaultTemplate).append("\n\n")
                    headerBuilder.append(endMarker).append('\n').append(addon)
                } else {
                    headerBuilder.append(defaultTemplate)
                }
                val header = headerBuilder.toString()
                sb.append(header).append('\n').append('\n')
                sb.append("日期: ").append(dateKey).append('\n')
                sb.append("上下文（仅用于总结的 overall_summary，禁止逐句复述原文）：\n")
                var count = 0
                rows.use { c ->
                    while (c.moveToNext()) {
                        val st = c.getLong(0)
                        val et = c.getLong(1)
                        val raw = c.getString(2) ?: ""
                        if (raw.isBlank()) continue
                        val ov = try {
                            val j = JSONObject(raw)
                            val s = (j.optString("overall_summary", "").trim())
                            if (s.isNotEmpty()) s else ""
                        } catch (_: Exception) { "" }
                        if (ov.isBlank()) continue
                        val clipped = if (ov.length > 800) ov.substring(0, 800) + "…" else ov
                        sb.append("- [").append(fmtHms(st)).append('-').append(fmtHms(et)).append("] ").append(clipped).append('\n')
                        count++
                        if (count >= 200) break
                    }
                }
                val prompt = sb.toString()
                val (model, content) = callTextModel(ctx, prompt, effectiveLang)
                val stripped = stripFences(content.trim())
                var structured: String? = null
                var outputText: String = stripped
                try {
                    val jo = JSONObject(stripped)
                    structured = jo.toString()
                    val ov = jo.optString("overall_summary", "").trim()
                    if (ov.isNotEmpty()) outputText = ov
                } catch (_: Exception) { /* 非 JSON，尝试容错提取 */
                    // 先尝试修复未转义引号，再次解析
                    var parsed = false
                    try {
                        val repaired = repairJsonUnescapedQuotes(stripped, arrayOf("overall_summary", "notification_brief"))
                        val jo2 = JSONObject(repaired)
                        structured = jo2.toString()
                        val ov2 = jo2.optString("overall_summary", "").trim()
                        if (ov2.isNotEmpty()) outputText = ov2
                        parsed = true
                    } catch (_: Exception) {}
                    if (!parsed) {
                        try {
                            val ov = extractLooseField(stripped, "overall_summary", nextKeyHint = "\"timeline\"")
                            val nb = extractLooseField(stripped, "notification_brief", nextKeyHint = null)
                            if (!ov.isNullOrBlank()) {
                                val ov2 = unescapeJsonStringCandidate(ov.trim())
                                val nb2 = if (nb.isNullOrBlank()) null else unescapeJsonStringCandidate(nb!!.trim())
                                outputText = ov2
                                val jo = JSONObject()
                                jo.put("overall_summary", outputText)
                                if (!nb2.isNullOrBlank()) jo.put("notification_brief", nb2!!.trim())
                                structured = jo.toString()
                                parsed = true
                            }
                        } catch (_: Exception) {}
                    }
                    if (!parsed) {
                        try {
                            val ov = extractJsonStringValue(stripped, "overall_summary")
                            val nb = extractJsonStringValue(stripped, "notification_brief")
                            if (!ov.isNullOrBlank()) {
                                outputText = ov.trim()
                                val jo = JSONObject()
                                jo.put("overall_summary", outputText)
                                if (!nb.isNullOrBlank()) jo.put("notification_brief", nb.trim())
                                structured = jo.toString()
                            }
                        } catch (_: Exception) {}
                    }
                }

                // 写入 daily_summaries
                db!!.execSQL(
                    """
                    INSERT OR REPLACE INTO daily_summaries(date_key, ai_provider, ai_model, output_text, structured_json, created_at)
                    VALUES(?, ?, ?, ?, ?, strftime('%s','now') * 1000)
                    """.trimIndent(),
                    arrayOf(dateKey, providerName(ctx), model, outputText, structured)
                )

                // 写入通知简报（优先 structured_json.notification_brief，其次 overall_summary 首句）
                val brief = try {
                    if (structured != null) {
                        val j = JSONObject(structured!!)
                        val nb = j.optString("notification_brief", "").trim()
                        if (nb.isNotEmpty()) nb else firstSentence(j.optString("overall_summary", outputText))
                    } else firstSentence(outputText)
                } catch (_: Exception) { firstSentence(outputText) }
                try {
                    val sp = ctx.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                    sp.edit().putString("daily_brief_$dateKey", brief).apply()
                    try { FileLogger.i(TAG, "brief saved: len=${brief.length}") } catch (_: Exception) {}
                } catch (_: Exception) {}
                true
            } catch (e: Exception) {
                try { FileLogger.e(TAG, "generateForDate failed: ${e.message}", e) } catch (_: Exception) {}
                false
            } finally { try { db?.close() } catch (_: Exception) {} }
        }

        private fun providerName(ctx: Context): String {
            return try {
                val cfg = AISettingsNative.readConfig(ctx)
                val base = cfg.baseUrl.lowercase()
                when {
                    base.contains("googleapis.com") || base.contains("generativelanguage") -> "gemini"
                    else -> "openai-compatible"
                }
            } catch (_: Exception) { "openai-compatible" }
        }

        private fun stripFences(s: String): String {
            val t = s.trim()
            if (!t.startsWith("```") ) return t
            val idx = t.indexOf('\n')
            val rest = if (idx >= 0) t.substring(idx + 1) else t
            val end = rest.lastIndexOf("```")
            return if (end >= 0) rest.substring(0, end).trim() else rest.trim()
        }

        private fun firstSentence(s: String): String {
            if (s.isBlank()) return s
            val re = Regex("[。.!?！？]")
            val m = re.find(s)
            return if (m != null) s.substring(0, m.range.last + 1) else if (s.length > 120) s.substring(0, 120) + "…" else s
        }

        private fun extractJsonStringValue(text: String, key: String): String? {
            return try {
                val pattern = Regex("\"" + Regex.escape(key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", setOf(RegexOption.DOT_MATCHES_ALL))
                val m = pattern.find(text) ?: return null
                val captured = m.groupValues.getOrNull(1) ?: return null
                val wrapped = "{\"x\":\"$captured\"}"
                try {
                    JSONObject(wrapped).optString("x", captured).trim()
                } catch (_: Exception) {
                    captured.trim()
                }
            } catch (_: Exception) { null }
        }

        private fun repairJsonUnescapedQuotes(s: String, keys: Array<String>): String {
            var out = s
            for (k in keys) {
                out = repairOneField(out, k, nextKeyHint = if (k == "overall_summary") "\"timeline\"" else null)
            }
            return out
        }

        private fun repairOneField(s: String, key: String, nextKeyHint: String?): String {
            return try {
                val keyIdx = s.indexOf("\"$key\"")
                if (keyIdx < 0) return s
                val colon = s.indexOf(':', keyIdx)
                if (colon < 0) return s
                val firstQuote = s.indexOf('"', colon)
                if (firstQuote < 0) return s
                val endQuote: Int = if (nextKeyHint != null) {
                    val nextIdx = s.indexOf(nextKeyHint, firstQuote + 1)
                    if (nextIdx < 0) return s
                    s.lastIndexOf('"', nextIdx - 1)
                } else {
                    val brace = s.indexOf('}', firstQuote + 1)
                    if (brace < 0) return s
                    s.lastIndexOf('"', brace)
                }
                if (endQuote <= firstQuote) return s
                val value = s.substring(firstQuote + 1, endQuote)
                val escaped = value.replace(Regex("(?<!\\)\""), "\\\"")
                s.substring(0, firstQuote + 1) + escaped + s.substring(endQuote)
            } catch (_: Exception) { s }
        }

        private fun extractLooseField(s: String, key: String, nextKeyHint: String?): String? {
            return try {
                val keyIdx = s.indexOf("\"$key\"")
                if (keyIdx < 0) return null
                val colon = s.indexOf(':', keyIdx)
                if (colon < 0) return null
                val firstQuote = s.indexOf('"', colon)
                if (firstQuote < 0) return null
                val endQuote: Int = if (nextKeyHint != null) {
                    val nextIdx = s.indexOf(nextKeyHint, firstQuote + 1)
                    if (nextIdx < 0) return null
                    s.lastIndexOf('"', nextIdx - 1)
                } else {
                    val brace = s.indexOf('}', firstQuote + 1)
                    if (brace < 0) return null
                    s.lastIndexOf('"', brace)
                }
                if (endQuote <= firstQuote) return null
                s.substring(firstQuote + 1, endQuote).trim()
            } catch (_: Exception) { null }
        }

        private fun unescapeJsonStringCandidate(s: String): String {
            return try {
                val wrapped = "{\"x\":\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"}"
                val obj = JSONObject(wrapped)
                obj.optString("x", s)
            } catch (_: Exception) { s }
        }

        private fun callTextModel(ctx: Context, prompt: String, lang: String): Pair<String, String> {
            val cfg = AISettingsNative.readConfig(ctx)
            val client = OkHttpClient.Builder()
                .connectTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
                .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
                .writeTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
                .retryOnConnectionFailure(true)
                .build()
            val base = if (cfg.baseUrl.endsWith('/')) cfg.baseUrl.dropLast(1) else cfg.baseUrl
            val systemMsg = when (lang) {
                "zh" -> ctx.getString(R.string.ai_language_policy_zh)
                "ja" -> ctx.getString(R.string.ai_language_policy_ja)
                "ko" -> ctx.getString(R.string.ai_language_policy_ko)
                else -> ctx.getString(R.string.ai_language_policy_en)
            }
            val isGoogle = base.contains("googleapis.com") || base.contains("generativelanguage")
            return if (isGoogle) {
                val url = "$base/v1beta/models/${cfg.model}:generateContent"
                val body = JSONObject().put("contents", org.json.JSONArray().put(org.json.JSONObject().put("parts", org.json.JSONArray()
                    .put(org.json.JSONObject().put("text", systemMsg))
                    .put(org.json.JSONObject().put("text", prompt))
                )))
                val reqBody: RequestBody = body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())
                val req = Request.Builder()
                    .url(url)
                    .addHeader("x-goog-api-key", cfg.apiKey ?: "")
                    .post(reqBody)
                    .build()
                val resp = client.newCall(req).execute()
                val respText = resp.body?.string() ?: ""
                if (!resp.isSuccessful) {
                    val lower = respText.lowercase()
                    if (lower.contains("user location is not supported")) {
                        try { FileLogger.e(TAG, "Gemini request blocked by region policy: ${respText.take(800)}") } catch (_: Exception) {}
                    }
                    throw IllegalStateException("Request failed: ${resp.code} ${respText}")
                }
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
                val url = "$base/v1/chat/completions"
                val messages = org.json.JSONArray()
                    .put(org.json.JSONObject().put("role", "system").put("content", systemMsg))
                    .put(org.json.JSONObject().put("role", "user").put("content", prompt))
                val body = org.json.JSONObject()
                    .put("model", cfg.model)
                    .put("messages", messages)
                    .put("temperature", 0.2)
                    .put("stream", false)
                val reqBody: RequestBody = body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())
                val req = Request.Builder()
                    .url(url)
                    .post(reqBody)
                    .addHeader("Authorization", "Bearer ${cfg.apiKey}")
                    .addHeader("Content-Type", "application/json")
                    .build()
                val resp = client.newCall(req).execute()
                val respText = resp.body?.string() ?: ""
                if (!resp.isSuccessful) throw IllegalStateException("Request failed: ${resp.code} ${respText}")
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

        private val DEFAULT_PROMPT_ZH = (
            """
  你是一位严格的中文日总结助手。基于我提供的“当天多个时间段的 overall_summary（仅用于上下文）”，必须生成“完整的当日总结 JSON”，不得提前结束或缺失任何字段或章节。

  输出要求（务必逐条满足）：
  - 仅输出一个 JSON 对象，且可被标准 JSON 解析；不要附加解释/前后缀；不要输出 JSON 之外的 Markdown 或任何其他文本。
  - 字段固定且全部必填：overall_summary、timeline、notification_brief。不得省略、置空或返回 null。
  - overall_summary 为纯 Markdown 文本（禁止使用代码块围栏```），必须包含以下结构：
    1) 第一段：无标题的整段总结，概括当天主题、节奏与收获；
    2) 依次包含这三个二级小节（标题用 Markdown 形式，且顺序固定）：
       "## 关键操作"
       "## 主要活动"
       "## 重点内容"
       每个小节至少 3 条要点（使用 “- ” 无序列表）。如信息不足，也必须保留小节，并给出不低于 1 条的“占位但有意义”的要点（如“无明显关键操作”），禁止删除小节。
  - timeline 为数组，按时间升序列出 5–12 条关键片段；每条结构：
    { "time": "HH:mm:ss-HH:mm:ss", "summary": "一句话行为（可用简短 Markdown 强调）" }
    如果上下文极少，最少也要 1 条，禁止为空。
  - notification_brief 为纯中文短句 1–3 句，不含 Markdown/列表/标题/代码围栏，覆盖当天重点且尽量精炼。
  - 禁止输出图片或图片链接；禁止返回除上述 3 个字段外的任何键；禁止使用 null；所有字符串需去除首尾空白。

  严格输出以下 JSON 结构（键名固定，且全部存在）：
  {
    "overall_summary": "(Markdown) 第一段为无标题整段总结；随后必须依次包含“## 关键操作”“## 主要活动”“## 重点内容”，每节为若干以“- ”开头的列表项",
    "timeline": [
      { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
    ],
    "notification_brief": "1-3 句中文纯文本，不含 Markdown"
  }
            """
        ).trimIndent()

        private val DEFAULT_PROMPT_EN = (
            """
  You are a strict English daily-summary assistant. Based on the provided "overall_summary" for multiple time ranges of the day (context only), you MUST generate a complete daily JSON summary. Do not terminate early or omit any fields/sections.

  Output requirements (satisfy all):
  - Output a single JSON object that can be parsed by standard JSON. Do NOT include explanations, prefixes/suffixes, or any text outside JSON (no Markdown outside JSON).
  - Fields are fixed and all required: overall_summary, timeline, notification_brief. Do not omit, leave empty, or return null.
  - overall_summary must be pure Markdown text (NO triple backtick code fences ```). It MUST include:
    1) First paragraph: a single untitled paragraph summarizing the day’s theme, rhythm, and takeaways;
    2) Then exactly these three second-level sections (Markdown headings) in the fixed order:
       "## Key Actions"
       "## Main Activities"
       "## Key Content"
       Each section must contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet (e.g., "No notable key actions"), never delete sections.
  - timeline must be an array in ascending time order with 5–12 key entries. Each item:
    { "time": "HH:mm:ss-HH:mm:ss", "summary": "One-sentence action (may use brief Markdown emphasis)" }
    If context is minimal, at least 1 item is required; it MUST NOT be empty.
  - notification_brief must be 1–3 short sentences of plain English (no Markdown/headings/lists/code fences), concise and covering the day’s highlights.
  - Do NOT output images or links; do NOT return any keys other than the 3 above; do NOT use null; trim leading/trailing spaces for all strings.

  Strictly output the following JSON shape (fixed keys, all present):
  {
    "overall_summary": "(Markdown) First paragraph is an untitled summary; then include sections “## Key Actions”, “## Main Activities”, “## Key Content”, each with bullet points starting with “- ”",
    "timeline": [
      { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
    ],
    "notification_brief": "1–3 sentences in plain English without Markdown"
  }
            """
        ).trimIndent()

        private val DEFAULT_PROMPT_JA = (
            """
  あなたは厳格な日本語の日次サマリーアシスタントです。提供される「当日の複数時間帯における overall_summary（コンテキストのみ）」をもとに、必ず完全な1日の JSON サマリーを生成してください。途中終了やフィールド／セクションの欠落は許されません。

  出力要件（すべて満たすこと）:
  - 標準 JSON で解析可能な1つの JSON オブジェクトだけを出力すること。説明文や前後の余分なテキスト、JSON 外の Markdown を絶対に含めないこと。
  - フィールドは固定で必須: overall_summary、timeline、notification_brief。省略・空文字・null を禁止します。
  - overall_summary は純粋な Markdown テキスト（コードブロック ``` は禁止）。構成は以下のとおり：
    1) 最初の段落: 見出しなしの段落で、当日のテーマ・進行・収穫を要約する。
    2) 次に必ず以下の二級見出しをこの順序で配置:
       "## 主要アクション"
       "## 主な活動"
       "## 重要コンテンツ"
       各セクションには少なくとも3つの箇条書き（"- "）を含めること。情報が不十分でもセクションを削除せず、意味のあるプレースホルダー（例: 「特筆すべき主要アクションなし」）を最低1つ含める。
  - timeline は時間昇順で 5～12 件の主要イベントを列挙する配列。各要素:
    { "time": "HH:mm:ss-HH:mm:ss", "summary": "1文の行動（Markdown で軽い強調可）" }
    コンテキストが少ない場合でも最低1件は必要。空配列は禁止。
  - notification_brief は日本語の短文 1～3 文で、Markdown・見出し・リスト・コードブロックを含めず、当日の要点を簡潔に表現すること。
  - 画像やリンクの出力は禁止。上記以外のキーを追加しない。null 使用禁止。文字列の前後空白は除去すること。

  出力は以下の JSON 形式を厳守（キー固定・全て必須）:
  {
    "overall_summary": "(Markdown) 最初は見出しなしの段落、その後に “## 主要アクション”“## 主な活動”“## 重要コンテンツ” を順番に配置し、各セクションは "- " 箇条書き",
    "timeline": [
      { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
    ],
    "notification_brief": "1～3文の日本語テキスト（Markdown なし）"
  }
            """
        ).trimIndent()

        private val DEFAULT_PROMPT_KO = (
            """
  당신은 엄격한 한국어 일일 요약 도우미입니다. 제공되는 "해당 날짜의 여러 시간대에 대한 overall_summary(컨텍스트용)"를 기반으로 반드시 완전한 일일 JSON 요약을 생성해야 합니다. 중간 종료나 필드/섹션 누락은 허용되지 않습니다.

  출력 요구 사항(모두 충족해야 함):
  - 표준 JSON으로 파싱 가능한 단일 JSON 객체만 출력합니다. 설명, 접두/접미 텍스트, JSON 외부의 Markdown을 절대 포함하지 마세요.
  - 필드는 고정이며 모두 필수: overall_summary, timeline, notification_brief. 누락/빈값/null 금지.
  - overall_summary 는 순수 Markdown 텍스트여야 하며(코드 블록 ``` 금지) 다음 구조를 따라야 합니다:
    1) 첫 단락: 제목 없는 한 단락으로 하루의 핵심 주제·리듬·성과를 요약합니다.
    2) 이어서 아래 세 개의 2단계 제목을 지정된 순서대로 포함합니다:
       "## 주요 행동"
       "## 주요 활동"
       "## 핵심 콘텐츠"
       각 섹션은 최소 3개의 "- " 불릿을 포함해야 합니다. 정보가 부족하더라도 섹션을 삭제하지 말고, 의미 있는 플레이스홀더(예: "눈에 띄는 주요 행동 없음")를 최소 1개 포함하세요.
  - timeline 은 시간 오름차순의 배열로 5~12개의 핵심 항목을 포함합니다. 각 항목 형식:
    { "time": "HH:mm:ss-HH:mm:ss", "summary": "한 문장 행동(간단한 Markdown 강조 가능)" }
    컨텍스트가 적더라도 최소 1개 항목을 포함해야 하며, 비워둘 수 없습니다.
  - notification_brief 는 Markdown/제목/목록/코드블록 없는 한국어 문장 1~3개로, 하루의 하이라이트를 간결하게 전달해야 합니다.
  - 이미지나 링크 출력 금지. 지정된 세 키 외의 다른 키 금지. null 사용 금지. 모든 문자열은 앞뒤 공백을 제거합니다.

  출력은 아래 JSON 형태를 엄격히 따릅니다(키 고정, 모두 필수):
  {
    "overall_summary": "(Markdown) 첫 단락은 제목 없는 요약, 이어서 “## 주요 행동”“## 주요 활동”“## 핵심 콘텐츠” 순서의 섹션과 "- " 불릿",
    "timeline": [
      { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
    ],
    "notification_brief": "Markdown 없는 한국어 1~3문장"
  }
            """
        ).trimIndent()

        private val DEFAULT_MORNING_PROMPT_ZH = (
            """
  你是一位中文晨间复盘助手。基于我提供的“昨日多个时间段的 overall_summary（仅用于理解背景）”，请为今天早上生成富有灵感的行动建议。

  输出规范：
  - 仅输出一个 JSON 对象，键固定为 tips，对应值为字符串数组；不要添加额外说明。
  - tips 数组长度须为 3-7 条。
  - 语气需温暖、治愈、富有人文关怀，更多陈述式鼓励与松弛提醒，避免任务驱动语气。
  - 每条建议使用 18-60 字中文完整句子，可穿插比喻、轻挑战或自我肯定；除非特别必要，仅允许最多一条问句。
  - 避免模板化措辞，禁止出现“昨天…今天…”“昨日…今日…”等句式，也不要让全部句子以相同词语开头。
  - 结合昨日的关键线索、人物或场景，从新的角度展望今日行动，可提醒风险、捕捉机会或调节心态，至少一条关注节奏/情绪/环境准备。
  - 严禁使用 Markdown、列表符号、编号、表情或代码围栏；纯文本即可。
  - 若上下文极少，仍需输出 3 条高质量的泛化建议。

  输出示例：{"tips": ["建议1", "建议2", "建议3"]}
            """
        ).trimIndent()

        private val DEFAULT_MORNING_PROMPT_EN = (
            """
  You are a morning briefing assistant. With the "yesterday overall_summary" snippets (context only), craft imaginative, forward-looking prompts for today.

  Output rules:
  - Return exactly one JSON object whose single key is tips (array of strings); no extra commentary.
  - The array must contain 3–7 items.
  - Aim for a warm, restorative, human-centered tone that favours gentle encouragement over task-driven commands.
  - Each tip is a complete English sentence (18–65 words); vary the style across items (metaphors, soft challenges, reflective statements). Unless absolutely necessary, use at most one question—prefer calm declarative guidance.
  - Avoid templated phrasing such as "Yesterday… today…" or starting every sentence with the same words. Weave yesterday’s cues indirectly while projecting fresh perspectives, including at least one note on mindset, cadence, or environment setup.
  - Plain text only: no Markdown, list markers, numbering, emojis, or code fences.
  - If context is sparse, still provide 3 substantive, broadly applicable ideas.

  Example: {"tips": ["Tip one", "Tip two", "Tip three"]}
            """
        ).trimIndent()

        private val DEFAULT_MORNING_PROMPT_JA = (
            """
  あなたは朝の振り返りアシスタントです。提供された「前日の overall_summary（コンテキストのみ）」から、本日へ向けた創造的な提案を生み出してください。

  出力要件：
  - JSON オブジェクト 1 つのみを返し、キーは tips 固定、値は文字列配列です。余計な説明は不要です。
  - tips 配列は 3～7 件。
  - ぬくもりのあるヒューマンタッチな口調で、癒やしやリズム調整を意識した励ましを中心にしてください。
  - 各提案は 18～60 文字程度の日本語文とし、比喩・小さなチャレンジ・穏やかな宣言など表現を変化させてください。特別な理由がない限り、問いかけは高々 1 件に抑えます。
  - 「昨日…今日…」「前日…本日…」のような定型句を避け、同じ言葉で始まる文を並べないこと。前日のキーワードをさりげなく織り込みつつ、新たな視点で本日の行動や心構え（少なくとも 1 件はペース/気分/環境整備）を示してください。
  - Markdown、箇条書き記号、番号、絵文字、コードブロックは禁止し、純テキストのみとします。
  - コンテキストが少なくても、質の高い汎用的な提案を 3 件以上提示してください。

  例：{"tips": ["提案1", "提案2", "提案3"]}
            """
        ).trimIndent()

        private val DEFAULT_MORNING_PROMPT_KO = (
            """
  당신은 아침 리뷰 도우미입니다. 제공된 "전날 overall_summary"(맥락 전용) 정보를 활용해 오늘을 위한 창의적인 제안을 만들어 주세요.

  출력 규칙:
  - JSON 객체 한 개만 반환하고 키는 tips 로 고정, 값은 문자열 배열입니다. 추가 설명은 금지합니다.
  - tips 배열 길이는 3~7개입니다.
  - 따뜻하고 치유적인 어조로 사람 중심의 배려를 강조하고, 과도한 업무 지향적 표현은 피하세요.
  - 각 제안은 18~60자 분량의 완전한 한국어 문장으로, 비유·작은 도전·부드러운 선언 등을 섞어 주세요. 특별한 사유가 없다면 물음표 사용은 최대 한 번으로 제한합니다.
  - "어제… 오늘…" "전날… 금일…"과 같은 틀에 박힌 문장을 사용하지 말고, 모든 문장이 같은 말로 시작하지 않도록 합니다. 전날의 단서를 은근히 연결하면서도 새로운 시각으로 오늘의 행동, 리스크, 기회, 혹은 마음가짐(최소 1건은 리듬·감정·환경 준비)을 제시하세요.
  - Markdown, 목록 기호, 번호, 이모지, 코드블록 사용은 금지합니다.
  - 맥락이 부족하더라도 가치 있는 일반화된 제안을 최소 3개 이상 작성하세요.

  예시: {"tips": ["제안1", "제안2", "제안3"]}
            """
        ).trimIndent()

        fun generateMorningInsightsForDisplayDate(ctx: Context, displayDateKey: String, force: Boolean = true): MorningInsightsRecord? {
            var db: SQLiteDatabase? = null
            var cursor: android.database.Cursor? = null
            return try {
                db = openDbRW(ctx)
                if (db == null) return null
                ensureMorningInsightsTable(db!!)
                if (!force) {
                    val existing = fetchMorningInsights(db!!, displayDateKey)
                    if (existing != null) return existing
                }

                val sourceDateKey = previousDateKey(displayDateKey)
                val range = dayRange(sourceDateKey) ?: return null

                val contexts = mutableListOf<String>()
                cursor = db!!.rawQuery(
                    """
                    SELECT s.start_time, s.end_time, r.structured_json
                    FROM segments s
                    JOIN segment_results r ON r.segment_id = s.id
                    WHERE s.start_time >= ? AND s.start_time <= ?
                    ORDER BY s.start_time ASC
                    """.trimIndent(),
                    arrayOf(range.first.toString(), range.second.toString())
                )
                while (cursor.moveToNext()) {
                    val st = cursor.getLong(0)
                    val et = cursor.getLong(1)
                    val raw = cursor.getString(2) ?: ""
                    if (raw.isBlank()) continue
                    val ov = try {
                        val j = JSONObject(raw)
                        (j.optString("overall_summary", "").trim())
                    } catch (_: Exception) { "" }
                    if (ov.isBlank()) continue
                    contexts.add("- [${fmtHms(st)}-${fmtHms(et)}] $ov")
                }

                val effectiveLang = resolveEffectiveLang(ctx)
                val languagePolicy = languagePolicyForLang(ctx, effectiveLang)
                val defaultTemplate = defaultMorningTemplate(effectiveLang)
                val addon = morningAddon(ctx, effectiveLang)
                val prompt = buildMorningPrompt(languagePolicy, defaultTemplate, addon, displayDateKey, sourceDateKey, contexts, effectiveLang)

                try { FileLogger.i(TAG, "MorningInsights: context=${contexts.size} source=$sourceDateKey lang=$effectiveLang") } catch (_: Exception) {}
                try {
                    FileLogger.d(TAG, "MorningInsights prompt preview: ${prompt.take(800)}")
                } catch (_: Exception) {}

                val (model, content) = callTextModel(ctx, prompt, effectiveLang)
                val stripped = stripFences(content.trim())
                val tips = parseMorningTips(stripped)
                if (tips.isEmpty()) {
                    try { FileLogger.w(TAG, "MorningInsights parse failed, tips empty") } catch (_: Exception) {}
                    return null
                }

                val record = MorningInsightsRecord(
                    dateKey = displayDateKey,
                    sourceDateKey = sourceDateKey,
                    tips = tips,
                    raw = stripped,
                    createdAt = System.currentTimeMillis()
                )
                saveMorningInsights(db!!, record)
                record
            } catch (e: Exception) {
                try { FileLogger.e(TAG, "generateMorningInsights failed: ${e.message}", e) } catch (_: Exception) {}
                null
            } finally {
                cursor?.close()
                try { db?.close() } catch (_: Exception) {}
            }
        }

        private fun resolveEffectiveLang(ctx: Context): String {
            return try {
                val prefs = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val langOpt = prefs.getString("flutter.locale_option", "system") ?: "system"
                val sys = java.util.Locale.getDefault().language?.lowercase() ?: "en"
                when (langOpt) {
                    "zh", "en", "ja", "ko" -> langOpt
                    "system" -> when {
                        sys.startsWith("zh") -> "zh"
                        sys.startsWith("ja") -> "ja"
                        sys.startsWith("ko") -> "ko"
                        else -> "en"
                    }
                    else -> "en"
                }
            } catch (_: Exception) { "zh" }
        }

        private fun languagePolicyForLang(ctx: Context, lang: String): String {
            return when (lang) {
                "ja" -> ctx.getString(R.string.ai_language_policy_ja)
                "ko" -> ctx.getString(R.string.ai_language_policy_ko)
                "en" -> ctx.getString(R.string.ai_language_policy_en)
                else -> ctx.getString(R.string.ai_language_policy_zh)
            }
        }

        private fun defaultMorningTemplate(lang: String): String {
            return when (lang) {
                "ja" -> DEFAULT_MORNING_PROMPT_JA
                "ko" -> DEFAULT_MORNING_PROMPT_KO
                "en" -> DEFAULT_MORNING_PROMPT_EN
                else -> DEFAULT_MORNING_PROMPT_ZH
            }
        }

        private fun morningAddon(ctx: Context, lang: String): String? {
            val extraKey = when (lang) {
                "ja" -> "prompt_morning_extra_ja"
                "ko" -> "prompt_morning_extra_ko"
                "en" -> "prompt_morning_extra_en"
                else -> "prompt_morning_extra_zh"
            }
            return try {
                val value = AISettingsNative.readSettingValue(ctx, extraKey)
                if (value != null && value.trim().isNotEmpty()) value.trim() else null
            } catch (_: Exception) { null }
        }

        private fun buildMorningPrompt(
            languagePolicy: String,
            template: String,
            addon: String?,
            displayDateKey: String,
            sourceDateKey: String,
            contexts: List<String>,
            lang: String
        ): String {
            val sb = StringBuilder()
            sb.append(languagePolicy).append('\n').append('\n')
            if (!addon.isNullOrEmpty()) {
                sb.append(bypassMarkersBegin(lang)).append('\n').append(addon).append('\n').append('\n')
                sb.append(template).append('\n').append('\n')
                sb.append(bypassMarkersEnd(lang)).append('\n').append(addon)
            } else {
                sb.append(template)
            }
            val labels = when (lang) {
                "ja" -> Triple("対象日", "前日", "コンテキスト（前日の overall_summary。理解のためのみで逐語引用禁止）")
                "ko" -> Triple("목표 날짜", "전날", "컨텍스트(전날 overall_summary, 이해용으로 참고만 가능, 그대로 반복 금지)")
                "en" -> Triple("Target Date", "Source Date", "Context (yesterday overall_summary, context only; do not restate verbatim)")
                else -> Triple("目标日期", "昨日日期", "上下文（昨日 overall_summary，仅用于理解背景，禁止逐句复述）")
            }
            val noContext = when (lang) {
                "ja" -> "(前日の情報がほぼありません。一般的な継続方針を提案してください)"
                "ko" -> "(전날 참고 컨텍스트가 거의 없습니다. 일반적인 후속 제안을 제공하세요)"
                "en" -> "(Very little context available; provide generalized forward-looking suggestions)"
                else -> "(昨日无可用上下文，请据此给出泛化建议)"
            }
            sb.append("\n\n").append(labels.first).append(": ").append(displayDateKey).append('\n')
            sb.append(labels.second).append(": ").append(sourceDateKey).append('\n')
            sb.append(labels.third).append("：\n")
            if (contexts.isEmpty()) {
                sb.append(noContext).append('\n')
            } else {
                contexts.forEach { sb.append(it).append('\n') }
            }
            return sb.toString()
        }

        private fun bypassMarkersBegin(lang: String): String {
            return when (lang) {
                "ja" -> "【重要な追加指示（開始）】"
                "ko" -> "***중요 추가 지침 (시작)***"
                "en" -> "***IMPORTANT EXTRA INSTRUCTIONS (BEGIN)***"
                else -> "【重要附加说明（开始）】"
            }
        }

        private fun bypassMarkersEnd(lang: String): String {
            return when (lang) {
                "ja" -> "【重要な追加指示（終了）】"
                "ko" -> "***중요 추가 지침 (종료)***"
                "en" -> "***IMPORTANT EXTRA INSTRUCTIONS (END)***"
                else -> "【重要附加说明（结束）】"
            }
        }

        private fun parseMorningTips(raw: String): List<String> {
            fun tryParse(jsonText: String): List<String> {
                return try {
                    val obj = JSONObject(jsonText)
                    val arr = obj.optJSONArray("tips") ?: return emptyList()
                    val list = mutableListOf<String>()
                    for (i in 0 until arr.length()) {
                        val tip = arr.optString(i, "").trim()
                        val cleaned = cleanupTip(tip)
                        if (cleaned.isNotEmpty()) list.add(cleaned)
                    }
                    list
                } catch (_: Exception) { emptyList() }
            }

            val primary = tryParse(raw)
            if (primary.isNotEmpty()) return primary
            val repaired = try { repairJsonUnescapedQuotes(raw, arrayOf("tips")) } catch (_: Exception) { raw }
            val second = tryParse(repaired)
            if (second.isNotEmpty()) return second

            // 回退：尝试宽松截取 tips 数组内容
            return try {
                val start = raw.indexOf('[')
                val end = raw.lastIndexOf(']')
                if (start >= 0 && end > start) {
                    val arrText = raw.substring(start, end + 1)
                    parseTipsJson(arrText)
                } else emptyList()
            } catch (_: Exception) { emptyList() }
        }

        private fun cleanupTip(raw: String): String {
            var text = raw.trim()
            if (text.isEmpty()) return text
            text = text.removePrefix("- ")
                .removePrefix("* ")
                .removePrefix("• ")
                .removePrefix("-")
                .removePrefix("*")
                .removePrefix("•")

            text = text.replaceFirst(Regex("""^\d+[.、]\s*"""), "")
            text = text.replaceFirst(Regex("""^[A-Za-z]\)\s*"""), "")
            text = text.replaceFirst(Regex("""^[A-Za-z][.、]\s*"""), "")
            text = text.replaceFirst(Regex("""^•\s*"""), "")
            text = text.replaceFirst(Regex("""^[\-•*]+\s*"""), "")
            text = text.replace(Regex("""\s+"""), " ")
            return text.trim()
        }

        private fun previousDateKey(dateKey: String): String {
            return try {
                val parts = dateKey.split('-')
                if (parts.size != 3) return dateKey
                val y = parts[0].toInt()
                val m = parts[1].toInt()
                val d = parts[2].toInt()
                val cal = Calendar.getInstance().apply {
                    set(y, m - 1, d, 0, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                    add(Calendar.DAY_OF_YEAR, -1)
                }
                String.format(
                    "%04d-%02d-%02d",
                    cal.get(Calendar.YEAR),
                    cal.get(Calendar.MONTH) + 1,
                    cal.get(Calendar.DAY_OF_MONTH)
                )
            } catch (_: Exception) { dateKey }
        }
    }
}


