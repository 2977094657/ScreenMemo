package com.fqyw.screen_memo.channel

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import com.fqyw.screen_memo.settings.AISettingsNative
import com.fqyw.screen_memo.capture.AccessibilityServiceWatchdog
import com.fqyw.screen_memo.daily.DailySummaryNotifier
import com.fqyw.screen_memo.daily.DailySummaryScheduler
import com.fqyw.screen_memo.dynamic.DynamicRebuildService
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.importing.ImportOcrRepairService
import com.fqyw.screen_memo.settings.LegacySettingKeysNative
import com.fqyw.screen_memo.MainActivity
import com.fqyw.screen_memo.memory.MemoryRebuildNotifier
import com.fqyw.screen_memo.diagnostics.OEMCompatibilityHelper
import com.fqyw.screen_memo.logging.OutputFileLogger
import com.fqyw.screen_memo.permissions.PermissionGuideHelper
import com.fqyw.screen_memo.diagnostics.RuntimeDiagnostics
import com.fqyw.screen_memo.database.SegmentDatabaseHelper
import com.fqyw.screen_memo.segment.SegmentSummaryManager
import com.fqyw.screen_memo.storage.StorageMigrationManager
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import com.fqyw.screen_memo.storage.StorageAnalyzer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ExtractedMainMethodHandler(
    private val activity: MainActivity,
    private val methodChannel: MethodChannel,
) {
    private val tag = "MainActivity"

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "nativeLog" -> nativeLog(call, result)
            "setFileLoggingEnabled" -> setFileLoggingEnabled(call, result)
            "setNativeLogLevel" -> setNativeLogLevel(call, result)
            "setCategoryLoggingEnabled" -> setCategoryLoggingEnabled(call, result)
            "getOutputLogsDirToday" -> result.success(OutputFileLogger.getTodayDir(activity)?.absolutePath)
            "getPendingRuntimeDiagnostic" -> result.success(RuntimeDiagnostics.getPendingIssueSummary(activity))
            "markRuntimeDiagnosticHandled" -> {
                RuntimeDiagnostics.markIssueHandled(activity, call.argument<String>("id"))
                result.success(true)
            }
            "getSegmentsAIConfig" -> getSegmentsAIConfig(result)
            "setSegmentSettings" -> setSegmentSettings(call, result)
            "getSegmentSettings" -> getSegmentSettings(result)
            "getDynamicAutoRepairEnabled" -> getDynamicAutoRepairEnabled(result)
            "setDynamicAutoRepairEnabled" -> setDynamicAutoRepairEnabled(call, result)
            "setDynamicMergeLimits" -> setDynamicMergeLimits(call, result)
            "getDynamicMergeLimits" -> getDynamicMergeLimits(result)
            "setAiRequestIntervalSec" -> setAiRequestIntervalSec(call, result)
            "getAiRequestIntervalSec" -> getAiRequestIntervalSec(result)
            "checkPermissionGuideNeeded" -> result.success(PermissionGuideHelper.shouldShowPermissionGuide(activity))
            "getPermissionGuideText" -> result.success(PermissionGuideHelper.getPermissionGuideText(activity))
            "openAppDetailsSettings" -> result.success(PermissionGuideHelper.openAppDetailsSettings(activity))
            "openBatteryOptimizationSettings" -> result.success(PermissionGuideHelper.openBatteryOptimizationSettings(activity))
            "openAutoStartSettings" -> result.success(PermissionGuideHelper.openAutoStartSettings(activity))
            "markPermissionConfigured" -> {
                PermissionGuideHelper.markPermissionConfigured(activity, call.argument<String>("type") ?: "all")
                result.success(true)
            }
            "getPermissionStatus" -> result.success(PermissionGuideHelper.checkPermissionStatus(activity))
            "getPermissionReport" -> result.success(PermissionGuideHelper.generatePermissionReport(activity))
            "getDeviceInfo" -> result.success(OEMCompatibilityHelper.getDeviceInfo())
            "getEnabledImeList" -> getEnabledImeList(result)
            "getDefaultInputMethod" -> getDefaultInputMethod(result)
            "getDetailedStorageStats" -> getDetailedStorageStats(result)
            "getStorageMigrationStatus" -> getStorageMigrationStatus(result)
            "startStorageMigration" -> startStorageMigration(result)
            "checkServiceHealth" -> checkServiceHealth(result)
            "startImportOcrRepairTask" -> startImportOcrRepairTask(call, result)
            "getImportOcrRepairTaskStatus" -> getImportOcrRepairTaskStatus(result)
            "ensureImportOcrRepairTaskResumed" -> ensureImportOcrRepairTaskResumed(result)
            "cancelImportOcrRepairTask" -> cancelImportOcrRepairTask(result)
            "startDynamicRebuildTask" -> startDynamicRebuildTask(call, result)
            "getDynamicRebuildTaskStatus" -> getDynamicRebuildTaskStatus(result)
            "ensureDynamicRebuildTaskResumed" -> ensureDynamicRebuildTaskResumed(result)
            "cancelDynamicRebuildTask" -> cancelDynamicRebuildTask(result)
            "showMemoryRebuildNotification" -> showMemoryRebuildNotification(call, result)
            "cancelMemoryRebuildNotification" -> cancelMemoryRebuildNotification(result)
            "triggerSegmentTick" -> triggerSegmentTick(result)
            "retrySegments" -> retrySegments(call, result)
            "forceMergeSegment" -> forceMergeSegment(call, result)
            "showSimpleNotification" -> showSimpleNotification(call, result)
            "showNotification" -> showNotification(call, result)
            "scheduleDailySummaryNotification" -> scheduleDailySummaryNotification(call, result)
            "openAppNotificationSettings" -> openAppNotificationSettings(result)
            "openDailySummaryNotificationSettings" -> openDailySummaryNotificationSettings(result)
            "openExactAlarmSettings" -> openExactAlarmSettings(result)
            "setDailyBrief" -> setDailyBrief(call, result)
            "getDailyBrief" -> getDailyBrief(call, result)
            else -> return false
        }
        return true
    }

    private fun nativeLog(call: MethodCall, result: MethodChannel.Result) {
        try {
            val level = call.argument<String>("level") ?: "info"
            val tag = call.argument<String>("tag") ?: "Flutter"
            val msg = call.argument<String>("message") ?: ""
            when (level.lowercase()) {
                "debug" -> FileLogger.d(tag, msg)
                "warn" -> FileLogger.w(tag, msg)
                "error" -> FileLogger.e(tag, msg)
                else -> FileLogger.i(tag, msg)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("log_error", e.message, null)
        }
    }

    private fun setFileLoggingEnabled(call: MethodCall, result: MethodChannel.Result) {
        try {
            val enabled = call.argument<Boolean>("enabled") ?: true
            val sp = activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            sp.edit().putBoolean("logging_enabled", enabled).apply()
            FileLogger.enableFileLogging(enabled)
            FileLogger.setLevel(if (enabled) 4 else 1)
            try { OutputFileLogger.setEnabled(enabled) } catch (_: Exception) {}
            result.success(true)
        } catch (e: Exception) {
            result.error("log_toggle_error", e.message, null)
        }
    }

    private fun setNativeLogLevel(call: MethodCall, result: MethodChannel.Result) {
        try {
            val level = call.argument<String>("level")?.lowercase() ?: "debug"
            val lvl = when (level) {
                "error" -> 1
                "warn" -> 2
                "info" -> 3
                else -> 4
            }
            FileLogger.setLevel(lvl)
            result.success(true)
        } catch (e: Exception) {
            result.error("log_level_error", e.message, null)
        }
    }

    private fun setCategoryLoggingEnabled(call: MethodCall, result: MethodChannel.Result) {
        try {
            val category = call.argument<String>("category") ?: ""
            val enabled = call.argument<Boolean>("enabled") ?: false
            if (category.isNotBlank()) {
                FileLogger.setCategoryEnabled(activity, category, enabled)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("log_category_error", e.message, null)
        }
    }

    private fun getSegmentsAIConfig(result: MethodChannel.Result) {
        try {
            val cfg = AISettingsNative.readConfigSnapshot(activity)
            result.success(
                mapOf(
                    "baseUrl" to (cfg.baseUrl ?: ""),
                    "model" to (cfg.model ?: ""),
                    "apiKey" to (cfg.apiKey ?: ""),
                )
            )
        } catch (e: Exception) {
            result.error("read_failed", e.message, null)
        }
    }

    private fun setSegmentSettings(call: MethodCall, result: MethodChannel.Result) {
        try {
            val sample = (call.argument<Int>("sampleIntervalSec") ?: 20).coerceAtLeast(5)
            val duration = (call.argument<Int>("segmentDurationSec") ?: 300).coerceAtLeast(60)
            try { FileLogger.i(tag, "设置段落参数(call)：sampleIntervalSec=$sample segmentDurationSec=$duration") } catch (_: Exception) {}
            UserSettingsStorage.putInt(activity, UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC, sample)
            UserSettingsStorage.putInt(activity, UserSettingsKeysNative.SEGMENT_DURATION_SEC, duration)
            try {
                val n = SegmentDatabaseHelper.updateCollectingSegmentsSampleInterval(activity, sample)
                val cur = try { SegmentDatabaseHelper.getCollectingSegment(activity) } catch (_: Exception) { null }
                val persistedSample = try {
                    UserSettingsStorage.getInt(activity, UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC, 20)
                } catch (_: Exception) { -1 }
                val persistedDuration = try {
                    UserSettingsStorage.getInt(activity, UserSettingsKeysNative.SEGMENT_DURATION_SEC, 300)
                } catch (_: Exception) { -1 }
                try {
                    FileLogger.i(
                        tag,
                        "setSegmentSettings(persisted): sample=$persistedSample, duration=$persistedDuration, updatedCollecting=$n, collectingId=${cur?.id}, collectingInterval=${cur?.sampleIntervalSec}"
                    )
                } catch (_: Exception) {}
            } catch (_: Exception) {}
            result.success(true)
        } catch (e: Exception) {
            result.error("invalid_args", e.message, null)
        }
    }

    private fun getSegmentSettings(result: MethodChannel.Result) {
        try {
            val sample = UserSettingsStorage.getInt(
                activity,
                UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC,
                20,
            ).coerceAtLeast(5)
            val duration = UserSettingsStorage.getInt(
                activity,
                UserSettingsKeysNative.SEGMENT_DURATION_SEC,
                300,
            ).coerceAtLeast(60)
            try { FileLogger.i(tag, "获取段落参数：sampleIntervalSec=$sample segmentDurationSec=$duration") } catch (_: Exception) {}
            result.success(
                mapOf(
                    "sampleIntervalSec" to sample,
                    "segmentDurationSec" to duration,
                )
            )
        } catch (e: Exception) {
            result.error("read_failed", e.message, null)
        }
    }

    private fun getDynamicAutoRepairEnabled(result: MethodChannel.Result) {
        try {
            val enabled = UserSettingsStorage.getBoolean(
                activity,
                UserSettingsKeysNative.DYNAMIC_AUTO_REPAIR_ENABLED,
                true,
            )
            result.success(enabled)
        } catch (e: Exception) {
            result.error("read_failed", e.message, null)
        }
    }

    private fun setDynamicAutoRepairEnabled(call: MethodCall, result: MethodChannel.Result) {
        try {
            val enabled = call.argument<Boolean>("enabled") ?: true
            UserSettingsStorage.putBoolean(
                activity,
                UserSettingsKeysNative.DYNAMIC_AUTO_REPAIR_ENABLED,
                enabled,
            )
            try { FileLogger.i(tag, "设置动态自动补建开关：enabled=$enabled") } catch (_: Exception) {}
            result.success(enabled)
        } catch (e: Exception) {
            result.error("invalid_args", e.message, null)
        }
    }

    private fun setDynamicMergeLimits(call: MethodCall, result: MethodChannel.Result) {
        try {
            val spanRaw = call.argument<Int>("maxSpanSec") ?: (3 * 3600)
            val gapRaw = call.argument<Int>("maxGapSec") ?: 3600
            val maxImagesRaw = call.argument<Int>("maxImages") ?: 200
            val span = when {
                spanRaw < 0 -> 0
                spanRaw > 7 * 24 * 3600 -> 7 * 24 * 3600
                else -> spanRaw
            }
            val gap = when {
                gapRaw < 0 -> 0
                gapRaw > 7 * 24 * 3600 -> 7 * 24 * 3600
                else -> gapRaw
            }
            val maxImages = when {
                maxImagesRaw < 0 -> 0
                maxImagesRaw > 100000 -> 100000
                else -> maxImagesRaw
            }
            UserSettingsStorage.putInt(activity, UserSettingsKeysNative.MERGE_DYNAMIC_MAX_SPAN_SEC, span)
            UserSettingsStorage.putInt(activity, UserSettingsKeysNative.MERGE_DYNAMIC_MAX_GAP_SEC, gap)
            UserSettingsStorage.putInt(activity, UserSettingsKeysNative.MERGE_DYNAMIC_MAX_IMAGES, maxImages)
            result.success(true)
        } catch (e: Exception) {
            result.error("invalid_args", e.message, null)
        }
    }

    private fun getDynamicMergeLimits(result: MethodChannel.Result) {
        try {
            val span = UserSettingsStorage.getInt(
                activity,
                UserSettingsKeysNative.MERGE_DYNAMIC_MAX_SPAN_SEC,
                3 * 3600,
            ).let { if (it < 0) 0 else it }
            val gap = UserSettingsStorage.getInt(
                activity,
                UserSettingsKeysNative.MERGE_DYNAMIC_MAX_GAP_SEC,
                3600,
            ).let { if (it < 0) 0 else it }
            val maxImages = UserSettingsStorage.getInt(
                activity,
                UserSettingsKeysNative.MERGE_DYNAMIC_MAX_IMAGES,
                200,
            ).let { if (it < 0) 0 else it }
            result.success(
                mapOf(
                    "maxSpanSec" to span,
                    "maxGapSec" to gap,
                    "maxImages" to maxImages,
                )
            )
        } catch (e: Exception) {
            result.error("read_failed", e.message, null)
        }
    }

    private fun setAiRequestIntervalSec(call: MethodCall, result: MethodChannel.Result) {
        try {
            val secRaw = call.argument<Int>("seconds") ?: 3
            val sec = when {
                secRaw < 1 -> 1
                secRaw > 60 -> 60
                else -> secRaw
            }
            UserSettingsStorage.putInt(activity, UserSettingsKeysNative.AI_MIN_REQUEST_INTERVAL_SEC, sec)
            result.success(true)
        } catch (e: Exception) {
            result.error("invalid_args", e.message, null)
        }
    }

    private fun getAiRequestIntervalSec(result: MethodChannel.Result) {
        try {
            val sec = UserSettingsStorage.getInt(
                activity,
                UserSettingsKeysNative.AI_MIN_REQUEST_INTERVAL_SEC,
                3,
            )
            result.success(
                when {
                    sec < 1 -> 1
                    sec > 60 -> 60
                    else -> sec
                }
            )
        } catch (e: Exception) {
            result.error("read_failed", e.message, null)
        }
    }

    private fun getEnabledImeList(result: MethodChannel.Result) {
        try {
            val imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            val pms = activity.packageManager
            val list = imm.enabledInputMethodList?.map { imi ->
                val pkg = imi.packageName
                val label = try { imi.loadLabel(pms)?.toString() ?: pkg } catch (_: Exception) { pkg }
                mapOf(
                    "packageName" to pkg,
                    "appName" to label,
                )
            } ?: emptyList()
            result.success(list)
        } catch (e: Exception) {
            FileLogger.e(tag, "获取启用的输入法列表失败", e)
            result.success(emptyList<Map<String, String>>())
        }
    }

    private fun getDefaultInputMethod(result: MethodChannel.Result) {
        try {
            val id = Settings.Secure.getString(activity.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            if (id.isNullOrBlank()) {
                result.success(null)
            } else {
                val pkg = id.substringBefore('/')
                val pms = activity.packageManager
                val appName = try {
                    val ai = pms.getApplicationInfo(pkg, 0)
                    pms.getApplicationLabel(ai)?.toString() ?: pkg
                } catch (_: Exception) { pkg }
                result.success(
                    mapOf(
                        "id" to id,
                        "packageName" to "",
                        "appName" to appName,
                    )
                )
            }
        } catch (e: Exception) {
            FileLogger.e(tag, "读取默认输入法失败", e)
            result.success(null)
        }
    }

    private fun getDetailedStorageStats(result: MethodChannel.Result) {
        val pendingResult = result
        Thread {
            try {
                val data = StorageAnalyzer.collect(activity.applicationContext)
                activity.runOnUiThread { pendingResult.success(data) }
            } catch (e: Exception) {
                FileLogger.e(tag, "获取详细存储统计失败", e)
                activity.runOnUiThread {
                    pendingResult.error("storage_stats_failed", e.message, null)
                }
            }
        }.start()
    }

    private fun getStorageMigrationStatus(result: MethodChannel.Result) {
        try {
            val status = StorageMigrationManager.getStatus(activity.applicationContext)
            result.success(status.toMap())
        } catch (e: Exception) {
            result.error("migration_status_error", e.message, null)
        }
    }

    private fun startStorageMigration(result: MethodChannel.Result) {
        val pendingResult = result
        Thread {
            try {
                val migrationResult = StorageMigrationManager.migrate(activity.applicationContext) { progress ->
                    activity.runOnUiThread {
                        try {
                            methodChannel.invokeMethod("onStorageMigrationProgress", progress.toMap())
                        } catch (_: Exception) {}
                    }
                }
                activity.runOnUiThread {
                    pendingResult.success(migrationResult.toMap())
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    pendingResult.error("migration_failed", e.message, null)
                }
            }
        }.start()
    }

    private fun checkServiceHealth(result: MethodChannel.Result) {
        val watchdogStatus = AccessibilityServiceWatchdog.checkServiceStatus(activity)
        val statusSummary = AccessibilityServiceWatchdog.getStatusSummary(activity)
        FileLogger.i(tag, "手动健康检查结果：")
        FileLogger.i(tag, statusSummary)
        result.success(
            mapOf(
                "isReallyRunning" to watchdogStatus.isReallyRunning,
                "needsRestart" to watchdogStatus.needsRestart,
                "isSystemEnabled" to watchdogStatus.isSystemEnabled,
                "isInstanceExists" to watchdogStatus.isInstanceExists,
                "isProcessAlive" to watchdogStatus.isProcessAlive,
                "isHeartbeatValid" to watchdogStatus.isHeartbeatValid,
                "isFunctional" to watchdogStatus.isFunctional,
                "statusSummary" to statusSummary,
            )
        )
    }

    private fun startImportOcrRepairTask(call: MethodCall, result: MethodChannel.Result) {
        try {
            val onlyMissing = call.argument<Boolean>("onlyMissing") ?: true
            val batchSize = call.argument<Int>("batchSize") ?: 12
            val status = ImportOcrRepairService.startOrResumeTask(
                activity.applicationContext,
                onlyMissing,
                batchSize,
            )
            result.success(status)
        } catch (e: Exception) {
            result.error("start_import_ocr_task_failed", e.message, null)
        }
    }

    private fun getImportOcrRepairTaskStatus(result: MethodChannel.Result) {
        try {
            result.success(ImportOcrRepairService.getTaskStatus(activity.applicationContext))
        } catch (e: Exception) {
            result.error("get_import_ocr_task_status_failed", e.message, null)
        }
    }

    private fun ensureImportOcrRepairTaskResumed(result: MethodChannel.Result) {
        try {
            result.success(
                ImportOcrRepairService.ensureResumedIfPending(
                    activity.applicationContext,
                    "flutter_request",
                )
            )
        } catch (e: Exception) {
            result.error("ensure_import_ocr_task_resumed_failed", e.message, null)
        }
    }

    private fun cancelImportOcrRepairTask(result: MethodChannel.Result) {
        try {
            result.success(ImportOcrRepairService.cancelTask(activity.applicationContext))
        } catch (e: Exception) {
            result.error("cancel_import_ocr_task_failed", e.message, null)
        }
    }

    private fun startDynamicRebuildTask(call: MethodCall, result: MethodChannel.Result) {
        try {
            val resumeExisting = call.argument<Boolean>("resumeExisting") ?: false
            val dayConcurrency = call.argument<Int>("dayConcurrency")
            val status = DynamicRebuildService.startOrResumeTask(
                activity.applicationContext,
                resumeExisting,
                dayConcurrency,
            )
            result.success(status)
        } catch (e: Exception) {
            result.error("start_dynamic_rebuild_task_failed", e.message, null)
        }
    }

    private fun getDynamicRebuildTaskStatus(result: MethodChannel.Result) {
        try {
            result.success(DynamicRebuildService.getTaskStatus(activity.applicationContext))
        } catch (e: Exception) {
            result.error("get_dynamic_rebuild_task_status_failed", e.message, null)
        }
    }

    private fun ensureDynamicRebuildTaskResumed(result: MethodChannel.Result) {
        try {
            result.success(
                DynamicRebuildService.ensureResumedIfPending(
                    activity.applicationContext,
                    "flutter_request",
                )
            )
        } catch (e: Exception) {
            result.error("ensure_dynamic_rebuild_task_resumed_failed", e.message, null)
        }
    }

    private fun cancelDynamicRebuildTask(result: MethodChannel.Result) {
        try {
            result.success(DynamicRebuildService.cancelTask(activity.applicationContext))
        } catch (e: Exception) {
            result.error("cancel_dynamic_rebuild_task_failed", e.message, null)
        }
    }

    private fun showMemoryRebuildNotification(call: MethodCall, result: MethodChannel.Result) {
        try {
            val status = call.argument<String>("status") ?: "running"
            val processed = call.argument<Int>("processed") ?: 0
            val failed = call.argument<Int>("failed") ?: 0
            val total = call.argument<Int>("total") ?: 0
            val currentPosition = call.argument<Int>("currentPosition") ?: 0
            val currentSegmentId = call.argument<Int>("currentSegmentId") ?: 0
            val segmentSampleCursor = call.argument<Int>("segmentSampleCursor") ?: 0
            val segmentSampleTotal = call.argument<Int>("segmentSampleTotal") ?: 0
            val pauseReason = call.argument<String>("pauseReason")
            val lastError = call.argument<String>("lastError")
            result.success(
                MemoryRebuildNotifier.show(
                    activity.applicationContext,
                    status,
                    processed,
                    failed,
                    total,
                    currentPosition,
                    currentSegmentId,
                    segmentSampleCursor,
                    segmentSampleTotal,
                    pauseReason,
                    lastError,
                )
            )
        } catch (e: Exception) {
            result.error("show_memory_rebuild_notification_failed", e.message, null)
        }
    }

    private fun cancelMemoryRebuildNotification(result: MethodChannel.Result) {
        try {
            MemoryRebuildNotifier.cancel(activity.applicationContext)
            result.success(true)
        } catch (e: Exception) {
            result.error("cancel_memory_rebuild_notification_failed", e.message, null)
        }
    }

    private fun triggerSegmentTick(result: MethodChannel.Result) {
        try {
            try { FileLogger.i(tag, "triggerSegmentTick 调用") } catch (_: Exception) {}
            Thread {
                try {
                    try { FileLogger.i(tag, "triggerSegmentTick 线程开始") } catch (_: Exception) {}
                    SegmentSummaryManager.tick(activity)
                    try { FileLogger.i(tag, "triggerSegmentTick 线程结束") } catch (_: Exception) {}
                } catch (e: Exception) {
                    FileLogger.w(tag, "手动 tick 失败：${e.message}")
                }
            }.start()
            result.success(true)
        } catch (e: Exception) {
            result.error("tick_failed", e.message, null)
        }
    }

    private fun retrySegments(call: MethodCall, result: MethodChannel.Result) {
        try {
            val ids = (call.argument<List<Int>>("ids") ?: emptyList()).map { it.toLong() }
            val force = call.argument<Boolean>("force") ?: false
            try { FileLogger.i(tag, "retrySegments：ids=$ids force=$force") } catch (_: Exception) {}
            Thread {
                try {
                    val n = SegmentSummaryManager.retrySegmentsByIds(activity, ids, force)
                    activity.runOnUiThread { result.success(n) }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("retry_failed", e.message, null) }
                }
            }.start()
        } catch (e: Exception) {
            result.error("invalid_args", e.message, null)
        }
    }

    private fun forceMergeSegment(call: MethodCall, result: MethodChannel.Result) {
        try {
            val id = (call.argument<Int>("id") ?: 0).toLong()
            val prevId = call.argument<Int>("prev_id")?.toLong()
            try { FileLogger.i(tag, "forceMergeSegment：id=$id prev_id=$prevId") } catch (_: Exception) {}
            Thread {
                try {
                    val ok = SegmentSummaryManager.forceMergeSegmentById(activity, id, prevId)
                    activity.runOnUiThread { result.success(ok) }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("force_merge_failed", e.message, null) }
                }
            }.start()
        } catch (e: Exception) {
            result.error("invalid_args", e.message, null)
        }
    }

    private fun showSimpleNotification(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title = call.argument<String>("title") ?: "Daily Summary"
            val message = call.argument<String>("message") ?: ""
            try { FileLogger.i(tag, "显示简单通知：标题=$title 长度=${message.length}") } catch (_: Exception) {}
            val ok = DailySummaryNotifier.showSimple(activity, title, message)
            result.success(ok)
        } catch (e: Exception) {
            result.error("notify_failed", e.message, null)
        }
    }

    private fun showNotification(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title = call.argument<String>("title") ?: "Daily Summary"
            val message = call.argument<String>("message") ?: ""
            try { FileLogger.i(tag, "显示大文本通知：标题=$title 长度=${message.length}") } catch (_: Exception) {}
            val ok = DailySummaryNotifier.showBigText(activity, title, message)
            result.success(ok)
        } catch (e: Exception) {
            result.error("notify_failed", e.message, null)
        }
    }

    private fun scheduleDailySummaryNotification(call: MethodCall, result: MethodChannel.Result) {
        try {
            val hour = call.argument<Int>("hour") ?: 20
            val minute = call.argument<Int>("minute") ?: 0
            val enabled = call.argument<Boolean>("enabled") ?: true
            val ok = if (enabled) {
                DailySummaryScheduler.schedule(activity, hour, minute)
            } else {
                DailySummaryScheduler.cancel(activity)
            }
            try { FileLogger.i(tag, "调度每日总结通知：启用=$enabled 小时=$hour 分钟=$minute 结果=$ok") } catch (_: Exception) {}
            result.success(ok)
        } catch (e: Exception) {
            result.error("schedule_failed", e.message, null)
        }
    }

    private fun openAppNotificationSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                } else {
                    putExtra("app_package", activity.packageName)
                    putExtra("app_uid", activity.applicationInfo.uid)
                }
            }
            activity.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                activity.startActivity(fallback)
                result.success(true)
            } catch (e2: Exception) {
                result.error("open_app_notify_failed", e2.message, null)
            }
        }
    }

    private fun openDailySummaryNotificationSettings(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                val high = nm.getNotificationChannel("daily_summary_high")
                val channelId = if (high != null) "daily_summary_high" else "daily_summary"
                val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                }
                activity.startActivity(intent)
                result.success(true)
            } else {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra("app_package", activity.packageName)
                    putExtra("app_uid", activity.applicationInfo.uid)
                }
                activity.startActivity(intent)
                result.success(true)
            }
        } catch (e: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                activity.startActivity(fallback)
                result.success(true)
            } catch (e2: Exception) {
                result.error("open_channel_notify_failed", e2.message, null)
            }
        }
    }

    private fun openExactAlarmSettings(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                activity.startActivity(intent)
                result.success(true)
            } else {
                result.success(true)
            }
        } catch (e: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                activity.startActivity(fallback)
                result.success(true)
            } catch (e2: Exception) {
                result.error("open_exact_alarm_failed", e2.message, null)
            }
        }
    }

    private fun setDailyBrief(call: MethodCall, result: MethodChannel.Result) {
        try {
            val dateKey = call.argument<String>("dateKey") ?: ""
            val brief = call.argument<String>("brief") ?: ""
            val sp = activity.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            sp.edit()
                .putString("daily_brief_$dateKey", brief)
                .putString("daily_brief_last", brief)
                .apply()
            try { FileLogger.i(tag, "设置通知简报：dateKey=$dateKey 长度=${brief.length}") } catch (_: Exception) {}
            result.success(true)
        } catch (e: Exception) {
            result.error("set_brief_failed", e.message, null)
        }
    }

    private fun getDailyBrief(call: MethodCall, result: MethodChannel.Result) {
        try {
            val dateKey = call.argument<String>("dateKey") ?: ""
            val sp = activity.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            val brief = sp.getString("daily_brief_$dateKey", null)
            result.success(brief)
        } catch (e: Exception) {
            result.error("get_brief_failed", e.message, null)
        }
    }
}
