package com.fqyw.screen_memo.settings
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * 原生侧读取“每应用截图设置”（独立 SQLite settings.db）。
 * 路径：<files>/output/databases/shards/<sanitizedPackage>/settings.db
 * 表：settings(key TEXT PRIMARY KEY, value TEXT)
 */
object PerAppSettingsBridge {

    data class QualitySettings(
        val format: String?,
        val quality: Int?,
        val useTargetSize: Boolean?,
        val targetSizeKb: Int?,
    )

    private fun sanitize(packageName: String): String {
        return packageName.replace(Regex("[^A-Za-z0-9_]"), "_")
    }

    private fun resolveDbPath(context: Context, packageName: String): String? {
        return try {
            val base = context.filesDir.absolutePath
            val dir = File(base, "output/databases/shards/${sanitize(packageName)}")
            File(dir, "settings.db").absolutePath
        } catch (_: Exception) { null }
    }

    private fun readValue(db: SQLiteDatabase, key: String): String? {
        return try {
            val c = db.query("settings", arrayOf("value"), "key = ?", arrayOf(key), null, null, null, "1")
            c.use { cur -> if (cur.moveToFirst()) cur.getString(0) else null }
        } catch (_: Exception) { null }
    }

    private fun parseBool(s: String?): Boolean? {
        if (s == null) return null
        val t = s.lowercase()
        return when {
            t == "1" || t == "true" || t == "yes" -> true
            t == "0" || t == "false" || t == "no" -> false
            else -> null
        }
    }

    private fun parseInt(s: String?): Int? {
        return try { s?.toInt() } catch (_: Exception) { null }
    }

    /**
     * 若 use_custom=true 则返回每应用质量设置；否则返回 null（表示使用全局）。
     */
    fun readQualitySettingsIfCustom(context: Context, packageName: String?): QualitySettings? {
        if (packageName.isNullOrBlank()) return null
        val path = resolveDbPath(context, packageName) ?: return null
        val file = File(path)
        if (!file.exists()) return null
        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
            val useCustom = parseBool(readValue(db, "use_custom")) ?: false
            if (!useCustom) {
                null
            } else {
                val format = readValue(db, "image_format")
                val quality = parseInt(readValue(db, "image_quality"))
                val useTarget = parseBool(readValue(db, "use_target_size"))
                val tkb = parseInt(readValue(db, "target_size_kb"))
                QualitySettings(format, quality, useTarget, tkb)
            }
        } catch (_: Exception) {
            null
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }

    /**
     * 若 use_custom=true 且存在 screenshot_interval_sec，则返回每应用自定义间隔（秒，限制在5..60）；否则返回 null。
     */
    fun readIntervalIfCustom(context: Context, packageName: String?): Int? {
        if (packageName.isNullOrBlank()) return null
        val path = resolveDbPath(context, packageName) ?: return null
        val file = File(path)
        if (!file.exists()) return null
        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
            val useCustom = parseBool(readValue(db, "use_custom")) ?: false
            if (!useCustom) return null
            val iv = parseInt(readValue(db, "screenshot_interval_sec")) ?: return null
            iv.coerceIn(5, 60)
        } catch (_: Exception) {
            null
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }
}


