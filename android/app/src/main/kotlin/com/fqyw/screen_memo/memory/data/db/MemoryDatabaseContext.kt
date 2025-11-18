package com.fqyw.screen_memo.memory.data.db

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import com.fqyw.screen_memo.FileLogger
import java.io.File

/**
 * 将 Room 数据库绑定到 output/databases 目录，确保导出备份时可以一并打包。
 */
internal class MemoryDatabaseContext(base: Context) : ContextWrapper(base) {

    private val databaseRoot: File by lazy {
        val internal = baseContext.filesDir
            ?: baseContext.applicationContext?.filesDir
            ?: baseContext.getExternalFilesDir(null)
            ?: throw IllegalStateException("无法获取应用内部存储目录")
        val dir = File(internal, OUTPUT_RELATIVE_PATH)
        if (!dir.exists()) {
            try {
                dir.mkdirs()
            } catch (t: Throwable) {
                FileLogger.e(TAG, "无法创建数据库目录: ${dir.absolutePath}", t)
            }
        }
        dir
    }

    override fun getDatabasePath(name: String): File {
        val target = File(databaseRoot, name)
        val parent = target.parentFile
        if (parent != null && !parent.exists()) {
            try {
                parent.mkdirs()
            } catch (t: Throwable) {
                FileLogger.e(TAG, "创建数据库父目录失败: ${parent.absolutePath}", t)
            }
        }
        return target
    }

    override fun getApplicationContext(): Context {
        return this
    }

    override fun openOrCreateDatabase(
        name: String,
        mode: Int,
        factory: SQLiteDatabase.CursorFactory?
    ): SQLiteDatabase {
        val path = getDatabasePath(name)
        return SQLiteDatabase.openOrCreateDatabase(path, factory)
    }

    override fun openOrCreateDatabase(
        name: String,
        mode: Int,
        factory: SQLiteDatabase.CursorFactory?,
        errorHandler: DatabaseErrorHandler?
    ): SQLiteDatabase {
        val path = getDatabasePath(name)
        return SQLiteDatabase.openDatabase(
            path.path,
            factory,
            SQLiteDatabase.CREATE_IF_NECESSARY,
            errorHandler
        )
    }

    override fun deleteDatabase(name: String): Boolean {
        val file = getDatabasePath(name)
        var deleted = false
        if (file.exists()) {
            deleted = file.delete()
        }
        val wal = File(file.path + "-wal")
        if (wal.exists()) {
            deleted = wal.delete() || deleted
        }
        val shm = File(file.path + "-shm")
        if (shm.exists()) {
            deleted = shm.delete() || deleted
        }
        return deleted
    }

    companion object {
        private const val TAG = "MemoryDbContext"
        internal const val OUTPUT_RELATIVE_PATH = "output/databases"
    }
}


