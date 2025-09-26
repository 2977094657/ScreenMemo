package com.fqyw.screen_memo

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
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
        val model: String
    )

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

    private fun openMasterDb(context: Context): SQLiteDatabase? {
        return try {
            val path = resolveMasterDbPath(context) ?: return null
            SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.CREATE_IF_NECESSARY)
        } catch (e: Exception) {
            Log.w(TAG, "openMasterDb failed: ${e.message}")
            null
        }
    }

    private fun readSetting(db: SQLiteDatabase, key: String): String? {
        return try {
            val c = db.query("ai_settings", arrayOf("value"), "key = ?", arrayOf(key), null, null, null, "1")
            c.use { cur -> if (cur.moveToFirst()) cur.getString(0) else null }
        } catch (_: Exception) { null }
    }

    fun readConfig(context: Context): AIConfig {
        var db: SQLiteDatabase? = null
        return try {
            db = openMasterDb(context)
            if (db == null) throw IllegalStateException("AI settings database unavailable")

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
                                return AIConfig(baseUrl = baseUrl!!, apiKey = apiKey!!, model = model!!)
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
                            return AIConfig(baseUrl = baseUrl!!, apiKey = apiKey!!, model = model!!)
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


