package com.fqyw.screen_memo

import android.content.Context
import android.database.sqlite.SQLiteDatabase
 
import java.io.File
import okhttp3.Request
import org.json.JSONObject

/**
 * 原生侧读取 AI 配置（与 Flutter 侧 ai_settings 共用主库）
 */
object AISettingsNative {

    private const val TAG = "AISettingsNative"
    private const val MASTER_DB_DIR_RELATIVE = "output/databases"
    private const val MASTER_DB_FILE_NAME = "screenshot_memo.db"

    data class AIConfig(
        val baseUrl: String,
        val apiKey: String,
        val model: String,
        val providerType: String? = null,
        val chatPath: String? = null,
        val providerKeyId: Long? = null,
        val providerKeyName: String? = null,
        val providerId: Int? = null,
        val balanceEndpointType: String? = null,
        val balanceAutoDeleteZeroKey: Boolean = false
    )

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

    private fun openMasterDb(context: Context): SQLiteDatabase? {
        return try {
            val path = resolveMasterDbPath(context) ?: return null
            SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY)
        } catch (e: Exception) {
            FileLogger.w(TAG, "打开主库失败：${e.message}")
            null
        }
    }

    private fun readSetting(db: SQLiteDatabase, key: String): String? {
        return try {
            val c = db.query("ai_settings", arrayOf("value"), "key = ?", arrayOf(key), null, null, null, "1")
            c.use { cur -> if (cur.moveToFirst()) cur.getString(0) else null }
        } catch (_: Exception) { null }
    }


    data class ProviderKeyCandidate(
        val id: Long,
        val name: String,
        val apiKey: String,
        val models: List<String>,
        val priority: Int,
        val orderIndex: Int,
        val failureCount: Int,
        val cooldownUntilMs: Long?,
        val lastErrorType: String?
    )

    private fun parseModelsJson(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val arr = org.json.JSONArray(raw)
            val out = ArrayList<String>()
            for (i in 0 until arr.length()) {
                val v = arr.optString(i).trim()
                if (v.isNotEmpty()) out.add(v)
            }
            out
        } catch (_: Exception) { emptyList() }
    }

    private fun selectProviderKeys(
        context: Context,
        db: SQLiteDatabase,
        providerId: Int,
        model: String,
        rotateKey: Boolean,
    ): List<ProviderKeyCandidate> {
        return try {
            val now = System.currentTimeMillis()
            val target = model.trim().lowercase()
            val candidates = ArrayList<ProviderKeyCandidate>()
            val c = db.query(
                "ai_provider_keys",
                arrayOf("id", "name", "api_key", "models_json", "priority", "order_index", "failure_count", "cooldown_until_ms", "last_error_type", "enabled"),
                "provider_id = ? AND enabled != 0",
                arrayOf(providerId.toString()),
                null, null,
                "priority ASC, order_index ASC, id ASC"
            )
            c.use { cur ->
                while (cur.moveToNext()) {
                    val models = parseModelsJson(cur.getString(cur.getColumnIndexOrThrow("models_json")))
                    if (models.none { it.trim().lowercase() == target }) continue
                    val err = cur.getString(cur.getColumnIndexOrThrow("last_error_type"))
                    if (err == "auth_failed") continue
                    val cooldownIdx = cur.getColumnIndexOrThrow("cooldown_until_ms")
                    val cooldown = if (cur.isNull(cooldownIdx)) null else cur.getLong(cooldownIdx)
                    if (cooldown != null && cooldown > now) continue
                    val apiKey = cur.getString(cur.getColumnIndexOrThrow("api_key"))?.trim().orEmpty()
                    if (apiKey.isEmpty()) continue
                    candidates.add(
                        ProviderKeyCandidate(
                            id = cur.getLong(cur.getColumnIndexOrThrow("id")),
                            name = cur.getString(cur.getColumnIndexOrThrow("name")) ?: "Key",
                            apiKey = apiKey,
                            models = models,
                            priority = cur.getInt(cur.getColumnIndexOrThrow("priority")),
                            orderIndex = cur.getInt(cur.getColumnIndexOrThrow("order_index")),
                            failureCount = cur.getInt(cur.getColumnIndexOrThrow("failure_count")),
                            cooldownUntilMs = cooldown,
                            lastErrorType = err
                        )
                    )
                }
            }
            if (candidates.isEmpty()) return emptyList()

            val ordered = ArrayList<ProviderKeyCandidate>()
            var index = 0
            while (index < candidates.size) {
                val priority = candidates[index].priority
                val group = ArrayList<ProviderKeyCandidate>()
                while (index < candidates.size && candidates[index].priority == priority) {
                    group.add(candidates[index])
                    index += 1
                }
                val cursorKey = "ai_key_rr_${providerId}_${target}_${priority}"
                val cursor = readSetting(db, cursorKey)?.trim()?.toIntOrNull() ?: 0
                val start = if (group.isEmpty()) 0 else Math.floorMod(cursor, group.size)
                for (i in group.indices) {
                    ordered.add(group[(start + i) % group.size])
                }
                if (rotateKey && group.size > 1) {
                    writeSettingValue(context, cursorKey, ((cursor + 1) % group.size).toString())
                }
            }
            ordered
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun selectProviderKey(
        context: Context,
        db: SQLiteDatabase,
        providerId: Int,
        model: String,
        rotateKey: Boolean,
    ): ProviderKeyCandidate? = selectProviderKeys(context, db, providerId, model, rotateKey).firstOrNull()

    private fun writeSettingValue(context: Context, key: String, value: String?) {
        var writable: SQLiteDatabase? = null
        try {
            val path = resolveMasterDbPath(context) ?: return
            writable = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE)
            if (value == null) {
                writable.delete("ai_settings", "key = ?", arrayOf(key))
            } else {
                val values = android.content.ContentValues().apply { put("key", key); put("value", value) }
                writable.insertWithOnConflict("ai_settings", null, values, SQLiteDatabase.CONFLICT_REPLACE)
            }
        } catch (_: Exception) {
        } finally {
            try { writable?.close() } catch (_: Exception) {}
        }
    }

    private fun ensureProviderKeyStatsColumns(db: SQLiteDatabase) {
        try {
            db.execSQL("ALTER TABLE ai_provider_keys ADD COLUMN success_count INTEGER NOT NULL DEFAULT 0")
        } catch (_: Exception) {
        }
        try {
            db.execSQL("ALTER TABLE ai_provider_keys ADD COLUMN failure_total_count INTEGER NOT NULL DEFAULT 0")
        } catch (_: Exception) {
        }
    }


    private fun normalizeBalanceEndpointType(value: String?): String {
        val v = value?.trim()?.lowercase().orEmpty()
        return when (v) {
            "new_api" -> "new_api"
            "sub2api" -> "sub2api"
            else -> "none"
        }
    }

    private fun normalizeBaseUrl(value: String?): String {
        val raw = value?.trim().orEmpty().ifEmpty { "https://api.openai.com" }
        return raw.trimEnd('/')
    }

    private fun formatUsd(value: Double): String {
        val digits = if (kotlin.math.abs(value) >= 1000.0) 2 else 4
        return java.lang.String.format(java.util.Locale.US, "%.${digits}f", value)
            .trimEnd('0')
            .trimEnd('.')
    }

    private fun refreshProviderKeyBalanceAsync(context: Context, cfg: AIConfig) {
        val keyId = cfg.providerKeyId ?: return
        val providerId = cfg.providerId ?: return
        val endpointType = normalizeBalanceEndpointType(cfg.balanceEndpointType)
        if (endpointType == "none") return
        val appContext = context.applicationContext
        Thread {
            var db: SQLiteDatabase? = null
            try {
                val baseUrl = normalizeBaseUrl(cfg.baseUrl)
                val client = OkHttpClientFactory.newBuilder(appContext)
                    .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(20, java.util.concurrent.TimeUnit.SECONDS)
                    .writeTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                    .build()
                var display: String
                var total: Double? = null
                var currency = "USD"
                var rawPreview = ""
                if (endpointType == "new_api") {
                    val subReq = Request.Builder()
                        .url("$baseUrl/dashboard/billing/subscription")
                        .addHeader("Authorization", "Bearer ${cfg.apiKey}")
                        .get()
                        .build()
                    client.newCall(subReq).execute().use { resp ->
                        val body = resp.body?.string().orEmpty()
                        rawPreview = body.take(1000)
                        if (!resp.isSuccessful) throw IllegalStateException("new-api subscription request failed: ${resp.code} $body")
                        val obj = JSONObject(body)
                        val hardLimit = when {
                            obj.has("hard_limit_usd") -> obj.optDouble("hard_limit_usd")
                            obj.has("system_hard_limit_usd") -> obj.optDouble("system_hard_limit_usd")
                            else -> obj.optDouble("soft_limit_usd")
                        }
                        var totalUsage = 0.0
                        try {
                            val usageReq = Request.Builder()
                                .url("$baseUrl/dashboard/billing/usage")
                                .addHeader("Authorization", "Bearer ${cfg.apiKey}")
                                .get()
                                .build()
                            client.newCall(usageReq).execute().use { usageResp ->
                                val usageBody = usageResp.body?.string().orEmpty()
                                if (usageResp.isSuccessful) totalUsage = JSONObject(usageBody).optDouble("total_usage", 0.0)
                            }
                        } catch (_: Exception) {}
                        total = hardLimit - totalUsage / 100.0
                    }
                    display = "\$${formatUsd(total ?: 0.0)}"
                } else {
                    val req = Request.Builder()
                        .url("$baseUrl/v1/usage")
                        .addHeader("Authorization", "Bearer ${cfg.apiKey}")
                        .get()
                        .build()
                    client.newCall(req).execute().use { resp ->
                        val body = resp.body?.string().orEmpty()
                        rawPreview = body.take(1000)
                        if (!resp.isSuccessful) throw IllegalStateException("sub2api usage request failed: ${resp.code} $body")
                        val obj = JSONObject(body)
                        currency = obj.optString("unit", "USD").ifBlank { "USD" }
                        val remaining = when {
                            obj.has("remaining") -> obj.optDouble("remaining")
                            obj.has("balance") -> obj.optDouble("balance")
                            obj.optJSONObject("quota")?.has("remaining") == true -> obj.optJSONObject("quota")!!.optDouble("remaining")
                            else -> Double.NaN
                        }
                        if (remaining.isNaN()) throw IllegalStateException("sub2api usage parse failed: $body")
                        if (remaining < 0) {
                            display = "∞ $currency".trim()
                            total = null
                        } else {
                            total = remaining
                            display = "\$${formatUsd(remaining)}"
                        }
                    }
                }

                val path = resolveMasterDbPath(appContext) ?: return@Thread
                db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE)
                ensureProviderKeyBalanceColumns(db!!)
                val values = android.content.ContentValues().apply {
                    put("balance_display", display)
                    if (total != null) put("balance_total", total!!) else putNull("balance_total")
                    put("balance_currency", currency)
                    put("balance_raw", rawPreview)
                    put("balance_updated_at", System.currentTimeMillis())
                }
                db!!.update("ai_provider_keys", values, "id = ?", arrayOf(keyId.toString()))
                if (cfg.balanceAutoDeleteZeroKey && total != null && (total ?: 0.0) <= 0.000001) {
                    db!!.delete("ai_provider_keys", "id = ?", arrayOf(keyId.toString()))
                    FileLogger.i(TAG, "auto-delete zero-balance key provider=$providerId key=$keyId")
                }
            } catch (e: Exception) {
                try { FileLogger.w(TAG, "刷新 Key 余额失败：key=$keyId error=${e.message}") } catch (_: Exception) {}
            } finally {
                try { db?.close() } catch (_: Exception) {}
            }
        }.start()
    }

    private fun ensureProviderKeyBalanceColumns(db: SQLiteDatabase) {
        try { db.execSQL("ALTER TABLE ai_provider_keys ADD COLUMN balance_display TEXT") } catch (_: Exception) {}
        try { db.execSQL("ALTER TABLE ai_provider_keys ADD COLUMN balance_total REAL") } catch (_: Exception) {}
        try { db.execSQL("ALTER TABLE ai_provider_keys ADD COLUMN balance_currency TEXT") } catch (_: Exception) {}
        try { db.execSQL("ALTER TABLE ai_provider_keys ADD COLUMN balance_raw TEXT") } catch (_: Exception) {}
        try { db.execSQL("ALTER TABLE ai_provider_keys ADD COLUMN balance_updated_at INTEGER") } catch (_: Exception) {}
    }

    fun markProviderKeySuccess(context: Context, keyId: Long?) {
        if (keyId == null) return
        var db: SQLiteDatabase? = null
        try {
            val path = resolveMasterDbPath(context) ?: return
            db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE)
            ensureProviderKeyStatsColumns(db!!)
            db!!.execSQL(
                """
                UPDATE ai_provider_keys
                SET failure_count = 0,
                    success_count = COALESCE(success_count, 0) + 1,
                    cooldown_until_ms = NULL,
                    last_error_type = NULL,
                    last_error_message = NULL,
                    last_failed_at = NULL,
                    last_success_at = ?
                WHERE id = ?
                """.trimIndent(),
                arrayOf<Any>(System.currentTimeMillis(), keyId)
            )
        } catch (e: Exception) {
            try { FileLogger.w(TAG, "更新 Key 成功统计失败：${e.message}") } catch (_: Exception) {}
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun markProviderKeySuccess(context: Context, cfg: AIConfig?) {
        if (cfg == null) return
        markProviderKeySuccess(context, cfg.providerKeyId)
        refreshProviderKeyBalanceAsync(context, cfg)
    }

    fun markProviderKeyFailure(context: Context, keyId: Long?, errorType: String, message: String, attemptCount: Int) {
        if (keyId == null) return
        var db: SQLiteDatabase? = null
        try {
            val path = resolveMasterDbPath(context) ?: return
            db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE)
            ensureProviderKeyStatsColumns(db!!)
            val retryable = errorType == "retryable"
            val failureCount = if (retryable) attemptCount else 0
            val cooldownUntil = if (retryable && attemptCount >= 3) {
                System.currentTimeMillis() + 10L * 60L * 1000L
            } else {
                null
            }
            db!!.execSQL(
                """
                UPDATE ai_provider_keys
                SET failure_count = ?,
                    failure_total_count = COALESCE(failure_total_count, 0) + 1,
                    cooldown_until_ms = ?,
                    last_error_type = ?,
                    last_error_message = ?,
                    last_failed_at = ?
                WHERE id = ?
                """.trimIndent(),
                arrayOf<Any?>(
                    failureCount,
                    cooldownUntil,
                    errorType,
                    message.take(1000),
                    System.currentTimeMillis(),
                    keyId,
                )
            )
        } catch (e: Exception) {
            try { FileLogger.w(TAG, "更新 Key 失败统计失败：${e.message}") } catch (_: Exception) {}
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun readConfig(context: Context): AIConfig = readConfig(context, "segments", rotateKey = true)

    fun readConfigSnapshot(context: Context, aiContext: String = "segments"): AIConfig =
        readConfig(context, aiContext, rotateKey = false)

    fun readConfigCandidates(context: Context, aiContext: String = "segments", maxCandidates: Int = 32): List<AIConfig> {
        var db: SQLiteDatabase? = null
        return try {
            db = openMasterDb(context)
            if (db == null) return listOf(readConfig(context, aiContext, rotateKey = true))
            val limit = maxCandidates.coerceIn(1, 64)
            val ctxCursor = db!!.query(
                "ai_contexts",
                arrayOf("provider_id", "model"),
                "context = ?",
                arrayOf(aiContext),
                null, null, null, "1"
            )
            ctxCursor.use { cc ->
                if (!cc.moveToFirst()) return listOf(readConfig(context, aiContext, rotateKey = true))
                val providerId = cc.getInt(cc.getColumnIndexOrThrow("provider_id"))
                val model = cc.getString(cc.getColumnIndexOrThrow("model"))?.trim().orEmpty()
                if (providerId <= 0 || model.isBlank()) return listOf(readConfig(context, aiContext, rotateKey = true))

                var baseUrl: String? = null
                var providerApiKey: String? = null
                var providerType: String? = null
                var chatPath: String? = null
                var balanceEndpointType: String? = null
                var balanceAutoDeleteZeroKey = false
                val prov = db!!.query(
                    "ai_providers",
                    arrayOf("base_url", "api_key", "type", "chat_path", "balance_endpoint_type", "balance_auto_delete_zero_key"),
                    "id = ?",
                    arrayOf(providerId.toString()),
                    null, null, null, "1"
                )
                prov.use { cp ->
                    if (cp.moveToFirst()) {
                        baseUrl = cp.getString(cp.getColumnIndexOrThrow("base_url"))?.trim()
                        providerApiKey = cp.getString(cp.getColumnIndexOrThrow("api_key"))?.trim()
                        providerType = cp.getString(cp.getColumnIndexOrThrow("type"))?.trim()
                        chatPath = cp.getString(cp.getColumnIndexOrThrow("chat_path"))?.trim()
                        val beIdx = cp.getColumnIndex("balance_endpoint_type")
                        balanceEndpointType = if (beIdx >= 0) cp.getString(beIdx)?.trim() else null
                        val bdIdx = cp.getColumnIndex("balance_auto_delete_zero_key")
                        balanceAutoDeleteZeroKey = bdIdx >= 0 && cp.getInt(bdIdx) != 0
                    }
                }

                val typeLower = (providerType ?: "").trim().lowercase()
                val effectiveBase = when {
                    !baseUrl.isNullOrEmpty() -> baseUrl!!
                    typeLower == "gemini" -> "https://generativelanguage.googleapis.com"
                    typeLower == "claude" -> "https://api.anthropic.com"
                    typeLower == "azure_openai" -> throw IllegalStateException("AI base_url missing for Azure OpenAI")
                    else -> "https://api.openai.com"
                }
                val effectiveChatPath = chatPath?.trim()?.takeIf { it.isNotEmpty() }
                val selectedKeys = selectProviderKeys(context, db!!, providerId, model, rotateKey = true)
                val out = ArrayList<AIConfig>()
                for (key in selectedKeys.take(limit)) {
                    out.add(
                        AIConfig(
                            baseUrl = effectiveBase,
                            apiKey = key.apiKey,
                            model = model,
                            providerType = providerType,
                            chatPath = effectiveChatPath,
                            providerKeyId = key.id,
                            providerKeyName = key.name,
                            providerId = providerId,
                            balanceEndpointType = balanceEndpointType,
                            balanceAutoDeleteZeroKey = balanceAutoDeleteZeroKey,
                        )
                    )
                }
                if (out.isNotEmpty()) return out

                val keyCtx = readSetting(db!!, "api_key_$aiContext")?.trim()
                val keyLegacy = readSetting(db!!, "api_key")?.trim()
                val fallbackKey = when {
                    !providerApiKey.isNullOrEmpty() -> providerApiKey!!
                    !keyCtx.isNullOrEmpty() -> keyCtx!!
                    !keyLegacy.isNullOrEmpty() -> keyLegacy!!
                    else -> ""
                }
                if (fallbackKey.isNotBlank()) {
                    return listOf(
                        AIConfig(
                            baseUrl = effectiveBase,
                            apiKey = fallbackKey,
                            model = model,
                            providerType = providerType,
                            chatPath = effectiveChatPath,
                            providerId = providerId,
                            balanceEndpointType = balanceEndpointType,
                            balanceAutoDeleteZeroKey = balanceAutoDeleteZeroKey,
                        )
                    )
                }
            }
            listOf(readConfig(context, aiContext, rotateKey = true))
        } catch (_: Exception) {
            try { listOf(readConfig(context, aiContext, rotateKey = true)) } catch (e: Exception) { throw e }
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 读取指定 AI 上下文的配置。
     * - aiContext: 'segments' | 'weekly' | 'memory' | ...（对应 Flutter 侧 ai_contexts.context）
     */
    fun readConfig(context: Context, aiContext: String): AIConfig =
        readConfig(context, aiContext, rotateKey = true)

    private fun readConfig(context: Context, aiContext: String, rotateKey: Boolean): AIConfig {
        var db: SQLiteDatabase? = null
        return try {
            db = openMasterDb(context)
            if (db == null) throw IllegalStateException("AI settings database unavailable")

            // 0) v6+ 新架构：优先使用 ai_contexts(aiContext) + ai_providers
            // - provider 与 model 从 ai_contexts 读取
            // - base_url/chat_path/type/api_key 从 ai_providers 读取；必要时回退默认/旧版键
            // - api_key 优先 ai_providers.api_key；再回退 ai_settings.api_key_{aiContext}；再回退 ai_settings.api_key（兼容旧版）
            try {
                val ctxCursor = db!!.query(
                    "ai_contexts",
                    arrayOf("provider_id", "model"),
                    "context = ?",
                    arrayOf(aiContext),
                    null, null, null, "1"
                )
                ctxCursor.use { cc ->
                    if (cc.moveToFirst()) {
                        val pidIdx = cc.getColumnIndex("provider_id")
                        val modelIdx = cc.getColumnIndex("model")
                        val providerId = if (pidIdx >= 0) cc.getInt(pidIdx) else -1
                        val model = if (modelIdx >= 0) (cc.getString(modelIdx)?.trim() ?: "") else ""

                        var baseUrl: String? = null
                        var providerApiKey: String? = null
                        var providerType: String? = null
                        var chatPath: String? = null
                        var balanceEndpointType: String? = null
                        var balanceAutoDeleteZeroKey = false
                        try {
                            val prov = db!!.query(
                                "ai_providers",
                                arrayOf("base_url", "api_key", "type", "chat_path", "balance_endpoint_type", "balance_auto_delete_zero_key"),
                                "id = ?",
                                arrayOf(providerId.toString()),
                                null, null, null, "1"
                            )
                            prov.use { cp ->
                                if (cp.moveToFirst()) {
                                    val bIdx = cp.getColumnIndex("base_url")
                                    baseUrl = if (bIdx >= 0) cp.getString(bIdx)?.trim() else null
                                    val kIdx = cp.getColumnIndex("api_key")
                                    providerApiKey = if (kIdx >= 0) cp.getString(kIdx)?.trim() else null
                                    val tIdx = cp.getColumnIndex("type")
                                    providerType = if (tIdx >= 0) cp.getString(tIdx)?.trim() else null
                                    val pIdx = cp.getColumnIndex("chat_path")
                                    chatPath = if (pIdx >= 0) cp.getString(pIdx)?.trim() else null
                                    val beIdx = cp.getColumnIndex("balance_endpoint_type")
                                    balanceEndpointType = if (beIdx >= 0) cp.getString(beIdx)?.trim() else null
                                    val bdIdx = cp.getColumnIndex("balance_auto_delete_zero_key")
                                    balanceAutoDeleteZeroKey = bdIdx >= 0 && cp.getInt(bdIdx) != 0
                                }
                            }
                        } catch (_: Exception) { }

                        val keyCtx = readSetting(db!!, "api_key_$aiContext")?.trim()
                        val keyLegacy = readSetting(db!!, "api_key")?.trim()
                        val selectedKey = selectProviderKey(context, db!!, providerId, model, rotateKey)
                        val apiKey = when {
                            selectedKey != null -> selectedKey.apiKey
                            !providerApiKey.isNullOrEmpty() -> providerApiKey
                            !keyCtx.isNullOrEmpty() -> keyCtx
                            else -> keyLegacy
                        }
                        val typeLower = (providerType ?: "").trim().lowercase()
                        val effectiveBase = when {
                            !baseUrl.isNullOrEmpty() -> baseUrl!!
                            typeLower == "gemini" -> "https://generativelanguage.googleapis.com"
                            typeLower == "claude" -> "https://api.anthropic.com"
                            typeLower == "azure_openai" -> throw IllegalStateException("AI base_url missing for Azure OpenAI")
                            else -> "https://api.openai.com"
                        }
                        val effectiveChatPath = chatPath?.trim()?.takeIf { it.isNotEmpty() }

                        if (!apiKey.isNullOrEmpty() && model.isNotEmpty()) {
                            return AIConfig(
                                baseUrl = effectiveBase,
                                apiKey = apiKey!!,
                                model = model,
                                providerType = providerType,
                                chatPath = effectiveChatPath,
                                providerKeyId = selectedKey?.id,
                                providerKeyName = selectedKey?.name,
                                providerId = providerId,
                                balanceEndpointType = balanceEndpointType,
                                balanceAutoDeleteZeroKey = balanceAutoDeleteZeroKey
                            )
                        }
                    }
                }
            } catch (_: Exception) { }

            // 1) 优先使用“激活分组”的配置（ai_site_groups）
            val activeIdStr = readSetting(db!!, "active_group_id")?.trim()
            val activeId = try { activeIdStr?.toInt() } catch (_: Exception) { null }
            if (activeId != null) {
                try {
                    val cursor = db!!.query(
                        "ai_site_groups",
                        arrayOf("base_url", "api_key", "model", "enabled"),
                        "id = ?",
                        arrayOf(activeId.toString()),
                        null, null, null, "1"
                    )
                    cursor.use { c ->
                        if (c.moveToFirst()) {
                            val enabledIdx = c.getColumnIndex("enabled")
                            val enabledOk = if (enabledIdx >= 0) c.getInt(enabledIdx) != 0 else true

                            val baseIdx = c.getColumnIndex("base_url")
                            val keyIdx  = c.getColumnIndex("api_key")
                            val modelIdx= c.getColumnIndex("model")
                            val baseUrl = if (baseIdx >= 0) c.getString(baseIdx)?.trim() else null
                            val apiKey  = if (keyIdx  >= 0) c.getString(keyIdx )?.trim() else null
                            val model   = if (modelIdx>= 0) c.getString(modelIdx)?.trim() else null

                            if (enabledOk && !baseUrl.isNullOrEmpty() && !apiKey.isNullOrEmpty() && !model.isNullOrEmpty()) {
                                return AIConfig(
                                    baseUrl = baseUrl!!,
                                    apiKey = apiKey!!,
                                    model = model!!
                                )
                            }
                        }
                    }
                } catch (_: Exception) {
                    // 分组读取异常则回退未分组
                }
            }

            // 2) 若未设置激活分组或读取失败，则选用“启用的首个分组”（与 Flutter 侧排序对齐：order_index ASC, id ASC）
            try {
                val cursor2 = db!!.query(
                    "ai_site_groups",
                    arrayOf("base_url", "api_key", "model"),
                    "enabled != 0",
                    null,
                    null, null,
                    "order_index ASC, id ASC",
                    "1"
                )
                cursor2.use { c ->
                    if (c.moveToFirst()) {
                        val baseIdx = c.getColumnIndex("base_url")
                        val keyIdx  = c.getColumnIndex("api_key")
                        val modelIdx= c.getColumnIndex("model")
                        val baseUrl = if (baseIdx >= 0) c.getString(baseIdx)?.trim() else null
                        val apiKey  = if (keyIdx  >= 0) c.getString(keyIdx )?.trim() else null
                        val model   = if (modelIdx>= 0) c.getString(modelIdx)?.trim() else null
                        if (!baseUrl.isNullOrEmpty() && !apiKey.isNullOrEmpty() && !model.isNullOrEmpty()) {
                            return AIConfig(
                                baseUrl = baseUrl!!,
                                apiKey = apiKey!!,
                                model = model!!
                            )
                        }
                    }
                }
            } catch (_: Exception) {
                // 分组读取失败则继续回退未分组键
            }

            // 3) 回退未分组键（ai_settings）
            val baseUrl = readSetting(db!!, "base_url")?.trim()
            val apiKey = readSetting(db!!, "api_key")?.trim()
            val model = readSetting(db!!, "model")?.trim()
            if (baseUrl.isNullOrEmpty()) throw IllegalStateException("AI base_url is empty")
            if (apiKey.isNullOrEmpty()) throw IllegalStateException("AI api_key is empty")
            if (model.isNullOrEmpty()) throw IllegalStateException("AI model is empty")
            AIConfig(baseUrl = baseUrl, apiKey = apiKey, model = model)
        } catch (e: Exception) {
            throw e
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    // 读取任意 ai_settings 键值（去除首尾空白，空串视为 null）
    fun readSettingValue(context: Context, key: String): String? {
        var db: SQLiteDatabase? = null
        return try {
            db = openMasterDb(context)
            if (db == null) return null
            val v = readSetting(db!!, key)
            val trimmed = v?.trim()
            if (trimmed.isNullOrEmpty()) null else trimmed
        } catch (_: Exception) {
            null
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }
}


