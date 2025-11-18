package com.fqyw.screen_memo

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.util.LinkedHashSet

object UserSettingsStorage {

    private const val TAG = "UserSettingsStorage"
    private const val PREF_NAME = "screen_memo_prefs"

    fun putString(
        context: Context,
        key: String,
        value: String?,
        aliasKeys: List<String> = emptyList(),
        legacyPrefKeys: List<String> = emptyList()
    ) {
        try {
            writeRaw(context, key, value)
            aliasKeys.forEach { alias ->
                writeRaw(context, alias, value)
            }
            writePrefsString(context, key, value, legacyPrefKeys + aliasKeys)
        } catch (t: Throwable) {
            Log.w(TAG, "putString failed key=$key error=${t.message}")
        }
    }

    fun putInt(
        context: Context,
        key: String,
        value: Int,
        aliasKeys: List<String> = emptyList(),
        legacyPrefKeys: List<String> = emptyList()
    ) {
        putString(context, key, value.toString(), aliasKeys, legacyPrefKeys)
        val editor = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE).edit()
        val prefKeys = uniqueKeys(listOf(key) + aliasKeys + legacyPrefKeys)
        for (prefKey in prefKeys) {
            editor.putInt(prefKey, value)
        }
        editor.apply()
    }

    fun putBoolean(
        context: Context,
        key: String,
        value: Boolean,
        aliasKeys: List<String> = emptyList(),
        legacyPrefKeys: List<String> = emptyList()
    ) {
        putString(context, key, if (value) "1" else "0", aliasKeys, legacyPrefKeys)
        val editor = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE).edit()
        val prefKeys = uniqueKeys(listOf(key) + aliasKeys + legacyPrefKeys)
        for (prefKey in prefKeys) {
            editor.putBoolean(prefKey, value)
        }
        editor.apply()
    }

    fun getString(
        context: Context,
        key: String,
        defaultValue: String? = null,
        aliasKeys: List<String> = emptyList(),
        legacyPrefKeys: List<String> = emptyList()
    ): String? {
        try {
            openDatabase(context)?.use { db ->
                queryValue(db, key)?.let { return it }
                for (alias in aliasKeys) {
                    val aliasValue = queryValue(db, alias)
                    if (aliasValue != null) {
                        writeRaw(context, key, aliasValue)
                        return aliasValue
                    }
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "getString db read failed key=$key error=${t.message}")
        }

        val allKeys = uniqueKeys(listOf(key) + aliasKeys + legacyPrefKeys)
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        for (prefKey in allKeys) {
            if (!prefs.contains(prefKey)) continue
            val raw = prefs.all[prefKey] ?: continue
            val str = raw.toString()
            writeRaw(context, key, str)
            return str
        }
        return defaultValue
    }

    fun getInt(
        context: Context,
        key: String,
        defaultValue: Int = 0,
        aliasKeys: List<String> = emptyList(),
        legacyPrefKeys: List<String> = emptyList()
    ): Int {
        val raw = getString(context, key, null, aliasKeys, legacyPrefKeys) ?: return defaultValue
        return raw.toIntOrNull() ?: defaultValue
    }

    fun getBoolean(
        context: Context,
        key: String,
        defaultValue: Boolean = false,
        aliasKeys: List<String> = emptyList(),
        legacyPrefKeys: List<String> = emptyList()
    ): Boolean {
        val raw = getString(context, key, null, aliasKeys, legacyPrefKeys) ?: return defaultValue
        val lower = raw.lowercase()
        return when {
            lower in setOf("1", "true", "yes", "on") -> true
            lower in setOf("0", "false", "no", "off") -> false
            else -> defaultValue
        }
    }

    fun remove(context: Context, key: String) {
        try {
            openDatabase(context)?.use { db ->
                db.delete("user_settings", "key = ?", arrayOf(key))
            }
        } catch (t: Throwable) {
            Log.w(TAG, "remove failed key=$key error=${t.message}")
        }
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(key)
            .apply()
    }

    private fun openDatabase(context: Context): SQLiteDatabase? {
        return try {
            val path = ScreenshotDatabaseHelper.resolveMasterDbPath(context) ?: return null
            val db = SQLiteDatabase.openDatabase(
                path,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY
            )
            ensureUserSettingsTable(db)
            db
        } catch (t: Throwable) {
            Log.w(TAG, "openDatabase failed: ${t.message}")
            null
        }
    }

    private fun ensureUserSettingsTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS user_settings (
              key TEXT PRIMARY KEY,
              value TEXT,
              updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_user_settings_updated_at ON user_settings(updated_at)")
    }

    private fun writeRaw(context: Context, key: String, value: String?) {
        try {
            openDatabase(context)?.use { db ->
                if (value == null) {
                    db.delete("user_settings", "key = ?", arrayOf(key))
                } else {
                    val cv = ContentValues().apply {
                        put("key", key)
                        put("value", value)
                        put("updated_at", System.currentTimeMillis())
                    }
                    db.insertWithOnConflict(
                        "user_settings",
                        null,
                        cv,
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "writeRaw failed key=$key error=${t.message}")
        }
    }

    private fun writePrefsString(context: Context, key: String, value: String?, extraKeys: List<String>) {
        val editor = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE).edit()
        val allKeys = uniqueKeys(listOf(key) + extraKeys)
        for (k in allKeys) {
            if (value == null) {
                editor.remove(k)
            } else {
                editor.putString(k, value)
            }
        }
        editor.apply()
    }

    private fun queryValue(db: SQLiteDatabase, key: String): String? {
        var cursor: Cursor? = null
        return try {
            cursor = db.query(
                "user_settings",
                arrayOf("value"),
                "key = ?",
                arrayOf(key),
                null,
                null,
                null,
                "1"
            )
            if (cursor.moveToFirst()) {
                cursor.getString(0)
            } else {
                null
            }
        } catch (_: Throwable) {
            null
        } finally {
            try {
                cursor?.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun uniqueKeys(keys: List<String>): List<String> {
        val set = LinkedHashSet<String>()
        for (key in keys) {
            if (key.isNotBlank()) {
                set.add(key)
            }
        }
        return set.toList()
    }
}


