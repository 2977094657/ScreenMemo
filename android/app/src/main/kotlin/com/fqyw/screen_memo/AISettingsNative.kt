package com.fqyw.screen_memo

import android.content.Context
import android.database.sqlite.SQLiteDatabase
 
import java.io.File

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
        val providerKeyName: String? = null
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

    private fun selectProviderKey(db: SQLiteDatabase, providerId: Int, model: String): ProviderKeyCandidate? {
        return try {
            val now = System.currentTimeMillis()
            val target = model.trim().lowercase()
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
                    return ProviderKeyCandidate(
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
                }
            }
            null
        } catch (_: Exception) { null }
    }

    fun markProviderKeySuccess(context: Context, keyId: Long?) {
        if (keyId == null) return
        var db: SQLiteDatabase? = null
        try {
            val path = resolveMasterDbPath(context) ?: return
            db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE)
            val values = android.content.ContentValues().apply {
                put("failure_count", 0)
                putNull("cooldown_until_ms")
                putNull("last_error_type")
                putNull("last_error_message")
                putNull("last_failed_at")
                put("last_success_at", System.currentTimeMillis())
            }
            db.update("ai_provider_keys", values, "id = ?", arrayOf(keyId.toString()))
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun markProviderKeyFailure(context: Context, keyId: Long?, errorType: String, message: String, attemptCount: Int) {
        if (keyId == null) return
        var db: SQLiteDatabase? = null
        try {
            val path = resolveMasterDbPath(context) ?: return
            db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE)
            val retryable = errorType == "retryable"
            val values = android.content.ContentValues().apply {
                if (retryable) put("failure_count", attemptCount) else put("failure_count", 0)
                if (retryable && attemptCount >= 3) put("cooldown_until_ms", System.currentTimeMillis() + 10L * 60L * 1000L) else putNull("cooldown_until_ms")
                put("last_error_type", errorType)
                put("last_error_message", message.take(1000))
                put("last_failed_at", System.currentTimeMillis())
            }
            db.update("ai_provider_keys", values, "id = ?", arrayOf(keyId.toString()))
        } catch (_: Exception) {
        } finally { try { db?.close() } catch (_: Exception) {} }
    }

    fun readConfig(context: Context): AIConfig = readConfig(context, "segments")

    /**
     * 读取指定 AI 上下文的配置。
     * - aiContext: 'segments' | 'weekly' | 'memory' | ...（对应 Flutter 侧 ai_contexts.context）
     */
    fun readConfig(context: Context, aiContext: String): AIConfig {
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
                        try {
                            val prov = db!!.query(
                                "ai_providers",
                                arrayOf("base_url", "api_key", "type", "chat_path"),
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
                                }
                            }
                        } catch (_: Exception) { }

                        val keyCtx = readSetting(db!!, "api_key_$aiContext")?.trim()
                        val keyLegacy = readSetting(db!!, "api_key")?.trim()
                        val selectedKey = selectProviderKey(db!!, providerId, model)
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
                                providerKeyName = selectedKey?.name
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


