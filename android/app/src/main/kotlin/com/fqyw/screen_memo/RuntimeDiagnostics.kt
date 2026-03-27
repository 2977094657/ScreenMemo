package com.fqyw.screen_memo

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.KeyguardManager
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.PowerManager
import android.view.Display
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 原生运行态诊断：
 * - 启动时记录最近一次进程退出原因（含用户主动停止）
 * - 关键生命周期落盘，尽量在被系统回收前保留线索
 * - 记录最近一次截屏成功/失败，便于复盘“通知还在但不截屏”的状态
 */
object RuntimeDiagnostics {

    private const val PREFS_NAME = "screen_memo_runtime_diag"
    private const val KEY_LAST_LOGGED_EXIT_TS = "last_logged_exit_ts"
    private const val KEY_LAST_STAGE = "last_stage"
    private const val KEY_LAST_STAGE_AT = "last_stage_at"
    private const val KEY_LAST_CAPTURE_SUCCESS_AT = "last_capture_success_at"
    private const val KEY_LAST_CAPTURE_SUCCESS_APP = "last_capture_success_app"
    private const val KEY_LAST_CAPTURE_FAILURE_AT = "last_capture_failure_at"
    private const val KEY_LAST_CAPTURE_FAILURE_REASON = "last_capture_failure_reason"
    private const val KEY_LAST_CAPTURE_FAILURE_CODE = "last_capture_failure_code"
    private const val KEY_PENDING_ISSUE_JSON = "pending_issue_json"

    private val tsFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())
    private val dateDirFmt = SimpleDateFormat("yyyy/MM/dd", Locale.getDefault())
    private val dayFmt = SimpleDateFormat("dd", Locale.getDefault())

    fun logProcessStart(context: Context, tag: String, stage: String, force: Boolean = false) {
        try {
            logRecentExitReasonsIfNeeded(context, tag, force)
        } catch (e: Exception) {
            logLine(context, tag, "logRecentExitReasonsIfNeeded failed: ${e.message}", force = true, error = true)
        }
        logSnapshot(context, tag, stage, force = force)
    }

    fun logSnapshot(
        context: Context,
        tag: String,
        stage: String,
        extras: Map<String, Any?> = emptyMap(),
        force: Boolean = false,
    ) {
        try {
            val prefs = prefs(context)
            val lastCaptureAt = prefs.getLong(KEY_LAST_CAPTURE_SUCCESS_AT, 0L)
            val lastCaptureApp = prefs.getString(KEY_LAST_CAPTURE_SUCCESS_APP, "") ?: ""
            val lastFailureAt = prefs.getLong(KEY_LAST_CAPTURE_FAILURE_AT, 0L)
            val lastFailureReason = prefs.getString(KEY_LAST_CAPTURE_FAILURE_REASON, "") ?: ""
            val lastFailureCode = prefs.getInt(KEY_LAST_CAPTURE_FAILURE_CODE, Int.MIN_VALUE)

            val snapshot = linkedMapOf<String, Any?>(
                "stage" to stage,
                "pid" to android.os.Process.myPid(),
                "proc" to getCurrentProcessName(context),
                "manufacturer" to Build.MANUFACTURER,
                "brand" to Build.BRAND,
                "model" to Build.MODEL,
                "sdk" to Build.VERSION.SDK_INT,
                "ignoreBatteryOpt" to isIgnoringBatteryOptimizations(context),
                "backgroundRestricted" to isBackgroundRestricted(context),
                "interactive" to isInteractive(context),
                "keyguardLocked" to isKeyguardLocked(context),
                "displayOn" to isDisplayOn(context),
                "fgServiceRunning" to ServiceStateManager.isForegroundServiceRunning(context),
                "accessibilityRunning" to ServiceStateManager.isAccessibilityServiceRunning(context),
                "lastCaptureAt" to formatTs(lastCaptureAt),
                "lastCaptureApp" to lastCaptureApp.ifBlank { "-" },
                "lastFailureAt" to formatTs(lastFailureAt),
                "lastFailureReason" to lastFailureReason.ifBlank { "-" },
                "lastFailureCode" to if (lastFailureCode == Int.MIN_VALUE) "-" else lastFailureCode,
            )
            extras.forEach { (key, value) -> snapshot[key] = value ?: "-" }

            val message = snapshot.entries.joinToString(separator = " | ") { (key, value) ->
                "$key=$value"
            }

            prefs.edit()
                .putString(KEY_LAST_STAGE, stage)
                .putLong(KEY_LAST_STAGE_AT, System.currentTimeMillis())
                .apply()

            logLine(context, tag, message, force = force)
        } catch (e: Exception) {
            logLine(context, tag, "logSnapshot failed at $stage: ${e.message}", force = true, error = true)
        }
    }

    fun noteCaptureSuccess(context: Context, tag: String, targetApp: String?, filePath: String?) {
        try {
            prefs(context).edit()
                .putLong(KEY_LAST_CAPTURE_SUCCESS_AT, System.currentTimeMillis())
                .putString(KEY_LAST_CAPTURE_SUCCESS_APP, targetApp ?: "")
                .apply()
            clearPendingCaptureFailureIfPresent(context)
            logSnapshot(
                context,
                tag,
                "capture_success",
                extras = mapOf(
                    "targetApp" to (targetApp ?: "-"),
                    "saved" to (!filePath.isNullOrBlank()),
                    "filePath" to (filePath ?: "-"),
                )
            )
        } catch (e: Exception) {
            logLine(context, tag, "noteCaptureSuccess failed: ${e.message}", force = true, error = true)
        }
    }

    fun noteCaptureFailure(
        context: Context,
        tag: String,
        reason: String,
        errorCode: Int? = null,
        extras: Map<String, Any?> = emptyMap(),
        force: Boolean = false,
    ) {
        try {
            val detectedAt = System.currentTimeMillis()
            val editor = prefs(context).edit()
                .putLong(KEY_LAST_CAPTURE_FAILURE_AT, detectedAt)
                .putString(KEY_LAST_CAPTURE_FAILURE_REASON, reason)
            if (errorCode != null) {
                editor.putInt(KEY_LAST_CAPTURE_FAILURE_CODE, errorCode)
            }
            editor.apply()

            val allExtras = LinkedHashMap<String, Any?>()
            allExtras["reason"] = reason
            if (errorCode != null) {
                allExtras["errorCode"] = errorCode
                allExtras["errorName"] = accessibilityScreenshotErrorName(errorCode)
            }
            allExtras.putAll(extras)
            logSnapshot(context, tag, "capture_failure", extras = allExtras, force = force)
            recordPendingCaptureFailure(context, detectedAt, reason, errorCode, allExtras)
        } catch (e: Exception) {
            logLine(context, tag, "noteCaptureFailure failed: ${e.message}", force = true, error = true)
        }
    }

    fun getPendingIssueSummary(context: Context): Map<String, Any?>? {
        val raw = prefs(context).getString(KEY_PENDING_ISSUE_JSON, null) ?: return null
        return try {
            jsonToMap(JSONObject(raw))
        } catch (e: Exception) {
            logLine(
                context,
                "RuntimeDiagnostics",
                "getPendingIssueSummary failed: ${e.message}",
                force = true,
                error = true,
            )
            null
        }
    }

    fun markIssueHandled(context: Context, issueId: String? = null) {
        try {
            val current = getPendingIssueSummary(context)
            val currentId = current?.get("id")?.toString()
            if (issueId.isNullOrBlank() || currentId.isNullOrBlank() || issueId == currentId) {
                prefs(context).edit().remove(KEY_PENDING_ISSUE_JSON).apply()
            }
        } catch (e: Exception) {
            logLine(
                context,
                "RuntimeDiagnostics",
                "markIssueHandled failed: ${e.message}",
                force = true,
                error = true,
            )
        }
    }

    fun accessibilityScreenshotErrorName(errorCode: Int): String {
        return when (errorCode) {
            1 -> "INTERNAL_ERROR"
            2 -> "NO_ACCESSIBILITY_ACCESS"
            3 -> "INTERVAL_TIME_SHORT"
            4 -> "INVALID_DISPLAY"
            else -> "UNKNOWN_$errorCode"
        }
    }

    private fun logRecentExitReasonsIfNeeded(context: Context, tag: String, force: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return
        }

        val prefs = prefs(context)
        val lastLoggedTs = prefs.getLong(KEY_LAST_LOGGED_EXIT_TS, 0L)
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exits = try {
            activityManager.getHistoricalProcessExitReasons(null, 0, 8)
        } catch (_: Exception) {
            emptyList()
        }

        if (exits.isEmpty()) {
            return
        }

        val filtered = exits
            .filter { info ->
                val processName = info.processName ?: ""
                processName.startsWith(context.packageName)
            }
            .sortedByDescending { it.timestamp }

        if (filtered.isEmpty()) {
            return
        }

        var maxLoggedTs = lastLoggedTs
        filtered.forEach { info ->
            if (info.timestamp <= lastLoggedTs) {
                return@forEach
            }
            maxLoggedTs = maxOf(maxLoggedTs, info.timestamp)
            val message = buildString {
                append("recent_exit")
                append(" | process=").append(info.processName ?: "-")
                append(" | reason=").append(exitReasonName(info.reason))
                append(" | status=").append(info.status)
                append(" | importance=").append(info.importance)
                append(" | timestamp=").append(formatTs(info.timestamp))
                append(" | desc=").append(info.description ?: "-")
            }
            logLine(context, tag, message, force = force)
        }

        val latestInteresting = filtered.firstOrNull { info ->
            info.timestamp > lastLoggedTs && shouldSurfaceExitReason(info.reason)
        }
        if (latestInteresting != null) {
            recordPendingExitIssue(context, latestInteresting)
        }

        if (maxLoggedTs > lastLoggedTs) {
            prefs.edit().putLong(KEY_LAST_LOGGED_EXIT_TS, maxLoggedTs).apply()
        }
    }

    private fun exitReasonName(reason: Int): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return reason.toString()
        }
        return when (reason) {
            ApplicationExitInfo.REASON_ANR -> "ANR"
            ApplicationExitInfo.REASON_CRASH -> "CRASH"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
            ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INIT_FAILURE"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
            ApplicationExitInfo.REASON_OTHER -> "OTHER"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
            ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
            ApplicationExitInfo.REASON_UNKNOWN -> "UNKNOWN"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
            ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
            else -> "REASON_$reason"
        }
    }

    private fun shouldSurfaceExitReason(reason: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        return when (reason) {
            ApplicationExitInfo.REASON_ANR,
            ApplicationExitInfo.REASON_CRASH,
            ApplicationExitInfo.REASON_CRASH_NATIVE,
            ApplicationExitInfo.REASON_DEPENDENCY_DIED,
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE,
            ApplicationExitInfo.REASON_LOW_MEMORY,
            ApplicationExitInfo.REASON_PERMISSION_CHANGE,
            ApplicationExitInfo.REASON_SIGNALED,
            ApplicationExitInfo.REASON_USER_REQUESTED,
            ApplicationExitInfo.REASON_USER_STOPPED -> true
            else -> false
        }
    }

    private fun recordPendingCaptureFailure(
        context: Context,
        detectedAt: Long,
        reason: String,
        errorCode: Int?,
        extras: Map<String, Any?>,
    ) {
        val errorName = errorCode?.let(::accessibilityScreenshotErrorName)
        val targetApp = extras["targetApp"]?.toString()?.takeIf { it.isNotBlank() && it != "-" }
        val logFilePath = buildPreferredLogFilePath(context, detectedAt, preferError = true)
        val details = linkedMapOf<String, Any?>(
            "诊断类型" to "截图失败",
            "记录时间" to formatTs(detectedAt),
            "失败原因" to reason,
            "错误码" to (errorCode ?: "-"),
            "错误名" to (errorName ?: "-"),
            "目标应用" to (targetApp ?: "-"),
            "日志文件" to (logFilePath ?: "-"),
        )
        extras.forEach { (key, value) ->
            if (key !in setOf("reason", "errorCode", "errorName", "filePath")) {
                details[key] = value ?: "-"
            }
        }
        val summary = buildString {
            append("最近一次截屏失败")
            if (reason.isNotBlank()) {
                append("：").append(reason)
            }
            if (!targetApp.isNullOrBlank()) {
                append("，目标应用 ").append(targetApp)
            }
            if (!errorName.isNullOrBlank()) {
                append(" (").append(errorName).append(")")
            }
        }
        storePendingIssue(
            context,
            linkedMapOf(
                "id" to buildIssueId("capture_failure", detectedAt, reason),
                "type" to "capture_failure",
                "title" to "检测到截图失败",
                "summary" to summary,
                "detectedAt" to detectedAt,
                "reason" to reason,
                "errorCode" to errorCode,
                "errorName" to errorName,
                "targetApp" to targetApp,
                "logDirPath" to buildLogDirPath(context, detectedAt),
                "logFilePath" to logFilePath,
                "searchHint" to (errorName ?: reason),
                "copyText" to buildCopyText(details),
            ),
        )
    }

    private fun recordPendingExitIssue(context: Context, info: ApplicationExitInfo) {
        val detectedAt = System.currentTimeMillis()
        val reasonName = exitReasonName(info.reason)
        val logFilePath = buildPreferredLogFilePath(context, detectedAt, preferError = false)
        val details = linkedMapOf<String, Any?>(
            "诊断类型" to "进程退出",
            "检测时间" to formatTs(detectedAt),
            "退出时间" to formatTs(info.timestamp),
            "退出原因" to reasonName,
            "状态码" to info.status,
            "重要级别" to info.importance,
            "进程名" to (info.processName ?: "-"),
            "描述" to (info.description ?: "-"),
            "日志文件" to (logFilePath ?: "-"),
        )
        val summary = exitReasonSummary(reasonName, info.description)
        storePendingIssue(
            context,
            linkedMapOf(
                "id" to buildIssueId("recent_exit", info.timestamp, reasonName),
                "type" to "recent_exit",
                "title" to "检测到上次运行异常退出",
                "summary" to summary,
                "detectedAt" to detectedAt,
                "exitTimestamp" to info.timestamp,
                "exitReason" to reasonName,
                "exitStatus" to info.status,
                "exitImportance" to info.importance,
                "exitDescription" to (info.description ?: ""),
                "logDirPath" to buildLogDirPath(context, detectedAt),
                "logFilePath" to logFilePath,
                "searchHint" to "recent_exit",
                "copyText" to buildCopyText(details),
            ),
        )
    }

    private fun exitReasonSummary(reasonName: String, description: String?): String {
        val normalizedDescription = description.orEmpty().lowercase(Locale.ROOT)
        return when (reasonName) {
            "USER_REQUESTED", "USER_STOPPED" -> when {
                normalizedDescription.contains("com.oplus.battery") ->
                    "系统记录到上次进程被 OnePlus 电池管理强制停止，常见于后台运行限制或省电策略触发。"
                normalizedDescription.contains("battery") ->
                    "系统记录到上次进程被系统电池管理主动停止，后台保活可能未完全生效。"
                else ->
                    "系统记录到上次进程被主动停止，常见于从最近任务划掉或系统清理后台。"
            }
            "PERMISSION_CHANGE" -> "系统记录到上次进程因权限变化退出，可能与权限被撤销或系统重置有关。"
            "LOW_MEMORY" -> "系统记录到上次进程因内存压力退出，后台保活和截图链路可能因此中断。"
            "ANR", "CRASH", "CRASH_NATIVE", "SIGNALED" -> "系统记录到上次进程异常退出，建议先复制诊断信息并打开日志文件定位。"
            else -> "系统记录到上次进程异常结束，建议结合日志确认是否为系统回收、用户划掉后台或权限状态变化。"
        }
    }

    private fun storePendingIssue(context: Context, payload: Map<String, Any?>) {
        try {
            val json = JSONObject()
            payload.forEach { (key, value) ->
                json.put(key, value ?: JSONObject.NULL)
            }
            prefs(context).edit().putString(KEY_PENDING_ISSUE_JSON, json.toString()).apply()
        } catch (e: Exception) {
            logLine(
                context,
                "RuntimeDiagnostics",
                "storePendingIssue failed: ${e.message}",
                force = true,
                error = true,
            )
        }
    }

    private fun clearPendingCaptureFailureIfPresent(context: Context) {
        val current = getPendingIssueSummary(context) ?: return
        if (current["type"]?.toString() == "capture_failure") {
            prefs(context).edit().remove(KEY_PENDING_ISSUE_JSON).apply()
        }
    }

    private fun buildIssueId(type: String, timestamp: Long, anchor: String?): String {
        val safeAnchor = anchor?.replace(Regex("[^A-Za-z0-9_\\-]+"), "_") ?: "na"
        return "$type:$timestamp:$safeAnchor"
    }

    private fun buildCopyText(details: LinkedHashMap<String, Any?>): String {
        return details.entries.joinToString(separator = "\n") { (key, value) ->
            "$key: ${value ?: "-"}"
        }
    }

    private fun buildLogDirPath(context: Context, timestamp: Long): String? {
        val base = context.getExternalFilesDir(null) ?: return null
        val dayKey = dateDirFmt.format(Date(timestamp))
        return File(base, "output/logs/$dayKey").absolutePath
    }

    private fun buildPreferredLogFilePath(context: Context, timestamp: Long, preferError: Boolean): String? {
        val primary = buildLogFilePath(context, timestamp, isError = preferError)
        val fallback = buildLogFilePath(context, timestamp, isError = !preferError)
        return when {
            primary?.let { File(it).exists() } == true -> primary
            fallback?.let { File(it).exists() } == true -> fallback
            primary != null -> primary
            else -> fallback
        }
    }

    private fun buildLogFilePath(context: Context, timestamp: Long, isError: Boolean): String? {
        val dirPath = buildLogDirPath(context, timestamp) ?: return null
        val day = dayFmt.format(Date(timestamp))
        val suffix = if (isError) "error" else "info"
        return File(dirPath, "${day}_${suffix}.log").absolutePath
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.opt(key)
            map[key] = if (value == JSONObject.NULL) null else value
        }
        return map
    }

    private fun logLine(context: Context, tag: String, message: String, force: Boolean, error: Boolean = false) {
        if (force) {
            if (error) {
                OutputFileLogger.errorForce(context, tag, message)
            } else {
                OutputFileLogger.infoForce(context, tag, message)
            }
            return
        }
        if (error) {
            FileLogger.e(tag, message)
        } else {
            FileLogger.i(tag, message)
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun getCurrentProcessName(context: Context): String {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val pid = android.os.Process.myPid()
            am.runningAppProcesses?.firstOrNull { it.pid == pid }?.processName ?: "-"
        } catch (_: Exception) {
            "-"
        }
    }

    private fun formatTs(ts: Long): String {
        if (ts <= 0L) {
            return "-"
        }
        return try {
            tsFormat.format(Date(ts))
        } catch (_: Exception) {
            ts.toString()
        }
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(context.packageName)
        } catch (_: Exception) {
            false
        }
    }

    private fun isBackgroundRestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return false
        }
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.isBackgroundRestricted
        } catch (_: Exception) {
            false
        }
    }

    private fun isInteractive(context: Context): Boolean {
        return try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                powerManager.isInteractive
            } else {
                @Suppress("DEPRECATION")
                powerManager.isScreenOn
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isKeyguardLocked(context: Context): Boolean {
        return try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                km.isDeviceLocked || km.isKeyguardLocked
            } else {
                km.isKeyguardLocked
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isDisplayOn(context: Context): Boolean {
        return try {
            val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            @Suppress("DEPRECATION")
            val display = displayManager.getDisplay(Display.DEFAULT_DISPLAY)
            when (display?.state ?: Display.STATE_UNKNOWN) {
                Display.STATE_ON -> true
                Display.STATE_UNKNOWN -> isInteractive(context)
                else -> false
            }
        } catch (_: Exception) {
            false
        }
    }
}
