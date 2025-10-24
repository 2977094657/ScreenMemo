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
                val base = context.getExternalFilesDir(null)?.absolutePath ?: return null
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
                val isZh = try {
                    val langOpt = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.locale_option", "system")
                    val sys = java.util.Locale.getDefault().language?.lowercase() ?: "en"
                    (langOpt == "zh") || (langOpt != "en" && sys.startsWith("zh"))
                } catch (_: Exception) { true }
                val languagePolicy = if (isZh) ctx.getString(R.string.ai_language_policy_zh) else ctx.getString(R.string.ai_language_policy_en)
                val custom = try { AISettingsNative.readSettingValue(ctx, if (isZh) "prompt_daily_zh" else "prompt_daily_en") } catch (_: Exception) { null }
                val customLegacy = try { AISettingsNative.readSettingValue(ctx, "prompt_daily") } catch (_: Exception) { null }
                val header = languagePolicy + "\n\n" + ((custom ?: customLegacy) ?: if (isZh) DEFAULT_PROMPT_ZH else DEFAULT_PROMPT_EN)
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
                val (model, content) = callTextModel(ctx, prompt, isZh)
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

        private fun callTextModel(ctx: Context, prompt: String, isZh: Boolean): Pair<String, String> {
            val cfg = AISettingsNative.readConfig(ctx)
            val client = OkHttpClient.Builder()
                .connectTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
                .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
                .writeTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)
                .retryOnConnectionFailure(true)
                .build()
            val base = if (cfg.baseUrl.endsWith('/')) cfg.baseUrl.dropLast(1) else cfg.baseUrl
            val systemMsg = if (isZh) ctx.getString(R.string.ai_language_policy_zh) else ctx.getString(R.string.ai_language_policy_en)
            val isGoogle = base.contains("googleapis.com") || base.contains("generativelanguage")
            return if (isGoogle) {
                val url = "$base/v1beta/models/${cfg.model}:generateContent?key=${cfg.apiKey}"
                val body = JSONObject().put("contents", org.json.JSONArray().put(org.json.JSONObject().put("parts", org.json.JSONArray()
                    .put(org.json.JSONObject().put("text", systemMsg))
                    .put(org.json.JSONObject().put("text", prompt))
                )))
                val reqBody: RequestBody = body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())
                val req = Request.Builder().url(url).post(reqBody).build()
                val resp = client.newCall(req).execute()
                if (!resp.isSuccessful) throw IllegalStateException("Request failed: ${resp.code} ${resp.body?.string()}")
                val respText = resp.body?.string() ?: ""
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
                if (!resp.isSuccessful) throw IllegalStateException("Request failed: ${resp.code} ${resp.body?.string()}")
                val respText = resp.body?.string() ?: ""
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
    }
}


