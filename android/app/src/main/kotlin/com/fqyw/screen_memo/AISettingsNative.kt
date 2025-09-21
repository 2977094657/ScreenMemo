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


