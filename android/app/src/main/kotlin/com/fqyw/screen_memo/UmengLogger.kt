package com.fqyw.screen_memo

import android.util.Log
import java.util.ArrayDeque

/**
 * Minimal wrapper to send user logs to Umeng APM (UMCrash).
 * - Keeps a small ring buffer of recent logs for quick attach.
 * - Uses reflection to avoid hard dependency on specific UMCrash API versions.
 */
object UmengLogger {
    private const val TAG = "UmengLogger"
    private const val DEFAULT_TAG = "UserLog"
    private const val MAX_BUFFER = 200

    private val buffer = ArrayDeque<String>(MAX_BUFFER)
    private val umCrashClass: Class<*>? by lazy {
        try { Class.forName("com.umeng.umcrash.UMCrash") } catch (_: Exception) { null }
    }

    @Synchronized
    fun breadcrumb(message: String, tag: String = DEFAULT_TAG) {
        appendToBuffer("$tag: $message")
        // 本地 info 日志
        AppContextProvider.context()?.let { ctx ->
            OutputFileLogger.info(ctx, tag, message)
        }
        tryInvoke("generateCustomLog", arrayOf(String::class.java, String::class.java), message, tag)
    }

    @Synchronized
    fun reportError(t: Throwable, attachRecent: Boolean = true) {
        // 本地 error 日志
        AppContextProvider.context()?.let { ctx ->
            OutputFileLogger.error(ctx, DEFAULT_TAG, t.message ?: t.toString())
        }
        if (attachRecent) {
            val snapshot = buffer.joinToString(separator = "\n")
            tryInvoke(
                "generateCustomLog",
                arrayOf(String::class.java, String::class.java),
                "Recent logs before error:\n$snapshot",
                DEFAULT_TAG
            )
            // 也记录到本地 error 文件
            AppContextProvider.context()?.let { ctx ->
                OutputFileLogger.error(ctx, DEFAULT_TAG, "Recent logs before error:\n$snapshot")
            }
        }
        tryInvoke("reportError", arrayOf(Throwable::class.java), t)
    }

    @Synchronized
    fun setUserId(userId: String) {
        tryInvoke("setUserIdentifier", arrayOf(String::class.java), userId)
    }

    @Synchronized
    private fun appendToBuffer(line: String) {
        if (buffer.size == MAX_BUFFER) buffer.removeFirst()
        buffer.addLast(line)
    }

    private fun tryInvoke(name: String, params: Array<Class<*>>, vararg args: Any?) {
        try {
            val cls = umCrashClass ?: return
            val m = cls.getMethod(name, *params)
            m.invoke(null, *args)
        } catch (e: Exception) {
            Log.w(TAG, "UMCrash.$name not available", e)
        }
    }
}
