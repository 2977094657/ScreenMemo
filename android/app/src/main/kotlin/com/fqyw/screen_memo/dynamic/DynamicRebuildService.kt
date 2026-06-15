package com.fqyw.screen_memo.dynamic

import com.fqyw.screen_memo.R

import com.fqyw.screen_memo.database.SegmentDatabaseHelper
import com.fqyw.screen_memo.diagnostics.RuntimeDiagnostics
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.MainActivity
import com.fqyw.screen_memo.segment.SegmentSummaryManager
import com.fqyw.screen_memo.settings.AISettingsNative
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

private const val RECENT_STREAM_CHUNK_LIMIT = 3

class DynamicRebuildService : Service() {

    companion object {
        private const val TAG = "DynamicRebuildService"
        private const val STATUS_TAG = "DYNAMIC_REBUILD"
        private const val ACTION_START = "com.fqyw.screen_memo.action.START_DYNAMIC_REBUILD"
        private const val ACTION_RESUME = "com.fqyw.screen_memo.action.RESUME_DYNAMIC_REBUILD"
        private const val ACTION_CANCEL = "com.fqyw.screen_memo.action.CANCEL_DYNAMIC_REBUILD"
        private const val NOTIFICATION_ID = 1037
        private const val CHANNEL_ID = "dynamic_rebuild_channel"
        private const val DEFAULT_DAY_CONCURRENCY = 1
        private const val MAX_DAY_CONCURRENCY = 10
        private const val DAY_RETRY_LIMIT = 3
        private const val TASK_MODE_REBUILD = "rebuild"
        private const val TASK_MODE_BACKFILL = "backfill"

        fun startOrResumeTask(
            context: Context,
            resumeExisting: Boolean = false,
            dayConcurrency: Int? = null,
            taskMode: String? = null,
            targetDayKey: String? = null,
        ): Map<String, Any?> {
            val appCtx = try { context.applicationContext } catch (_: Exception) { context }
            val normalizedTaskMode = normalizeTaskMode(taskMode)
            val normalizedTargetDayKey = normalizeTargetDayKey(targetDayKey)
            val normalizedConcurrency =
                normalizeDayConcurrency(
                    dayConcurrency
                        ?: UserSettingsStorage.getInt(
                            appCtx,
                            UserSettingsKeysNative.DYNAMIC_REBUILD_DAY_CONCURRENCY,
                            DEFAULT_DAY_CONCURRENCY,
                        ),
                )
            try {
                UserSettingsStorage.putInt(
                    appCtx,
                    UserSettingsKeysNative.DYNAMIC_REBUILD_DAY_CONCURRENCY,
                    normalizedConcurrency,
                )
            } catch (_: Exception) {}
            val current = DynamicRebuildTaskStore.load(appCtx)
            logBackfillDiag(
                appCtx,
                "startOrResumeTask requestedMode=$normalizedTaskMode resumeExisting=$resumeExisting " +
                    "targetDayKey=${normalizedTargetDayKey.ifBlank { "none" }} " +
                    "requestedConcurrency=${dayConcurrency ?: "null"} normalizedConcurrency=$normalizedConcurrency " +
                    "currentTaskId=${current?.taskId ?: "null"} currentMode=${current?.taskMode ?: "null"} " +
                    "currentStatus=${current?.status ?: "null"} currentRecoverable=${current?.isRecoverable() ?: false} " +
                    "currentCanContinue=${current?.canContinue() ?: false}",
            )
            if (current != null && current.isRecoverable()) {
                current.dayConcurrency = normalizeDayConcurrency(current.dayConcurrency)
                current.currentStage = "resume_requested"
                current.currentStageLabel = "恢复后台任务"
                current.currentStageDetail = "检测到未完成任务，继续在后台执行"
                current.appendRecentLog(
                    buildStageLogLine(
                        "恢复后台任务",
                        "检测到未完成任务，继续在后台执行",
                    ),
                )
                DynamicRebuildTaskStore.save(appCtx, current)
                logBackfillDiag(
                    appCtx,
                    "startOrResumeTask resumeRecoverable taskId=${current.taskId} mode=${current.taskMode} " +
                        "status=${current.status} dayConcurrency=${current.dayConcurrency} " +
                        "dayWorks=${current.dayWorks.size} totalSegments=${current.totalSegments} " +
                        "processed=${current.processedSegments} failed=${current.failedSegments}",
                )
                startService(appCtx, ACTION_RESUME)
                return current.toMap()
            }
            if (current != null && resumeExisting && current.canContinue()) {
                val aiConfig = AISettingsNative.readConfigSnapshot(appCtx, "segments")
                current.status = DynamicRebuildTaskState.STATUS_PENDING
                current.updatedAt = System.currentTimeMillis()
                current.completedAt = 0L
                current.lastError = null
                current.dayConcurrency = normalizedConcurrency
                current.dayWorks.forEach { day ->
                    when (day.status) {
                        DynamicRebuildDayWorkItem.STATUS_FAILED_WAITING -> {
                            day.status = DynamicRebuildDayWorkItem.STATUS_RETRY_PENDING
                            day.failedSegments = 0
                        }
                        DynamicRebuildDayWorkItem.STATUS_RUNNING -> {
                            day.status = DynamicRebuildDayWorkItem.STATUS_PENDING
                            day.failedSegments = 0
                        }
                    }
                }
                current.workerSlots.forEach { slot ->
                    if (slot.status != DynamicRebuildWorkerSlotState.STATUS_COMPLETED) {
                        slot.status = DynamicRebuildWorkerSlotState.STATUS_IDLE
                        slot.dayKey = ""
                        slot.totalSegments = 0
                        slot.processedSegments = 0
                        slot.currentRangeLabel = ""
                        slot.currentStageLabel = ""
                        slot.currentStageDetail = ""
                        slot.currentSegmentId = 0L
                        slot.recentStreamChunks.clear()
                    }
                }
                current.aiBaseUrl = aiConfig.baseUrl
                current.aiApiKey = aiConfig.apiKey
                current.aiModel = aiConfig.model
                current.aiProviderType = aiConfig.providerType
                current.aiChatPath = aiConfig.chatPath
                current.aiProviderId = aiConfig.providerId
                current.currentStage = "resume_requested"
                current.currentStageLabel = if (current.isBackfillMode()) "继续补全" else "继续重建"
                current.currentStageDetail =
                    "已重新读取当前模型 ${aiConfig.model}，沿用现有进度继续处理"
                current.appendRecentLog(
                    buildStageLogLine(
                        if (current.isBackfillMode()) "继续补全" else "继续重建",
                        "已重新读取当前模型 ${aiConfig.model}，沿用现有进度继续处理",
                    ),
                )
                current.refreshDerivedFields()
                DynamicRebuildTaskStore.save(appCtx, current)
                logBackfillDiag(
                    appCtx,
                    "startOrResumeTask continueExisting taskId=${current.taskId} mode=${current.taskMode} " +
                        "status=${current.status} dayConcurrency=${current.dayConcurrency} " +
                        "dayWorks=${current.dayWorks.size} totalSegments=${current.totalSegments} " +
                        "processed=${current.processedSegments} failed=${current.failedSegments} " +
                        "model=${aiConfig.model}",
                )
                startService(appCtx, ACTION_RESUME)
                return current.toMap()
            }

            val now = System.currentTimeMillis()
            val next = DynamicRebuildTaskState(
                taskId = "dynamic_rebuild_$now",
                taskMode = normalizedTaskMode,
                status = DynamicRebuildTaskState.STATUS_PREPARING,
                startedAt = now,
                updatedAt = now,
                completedAt = 0L,
                dayConcurrency = normalizedConcurrency,
                totalSegments = 0,
                processedSegments = 0,
                failedSegments = 0,
                currentDayKey = "",
                targetDayKey = normalizedTargetDayKey,
                timelineCutoffDayKey = "",
                currentSegmentId = 0L,
                currentRangeLabel = "",
                currentStage = "queued",
                currentStageLabel = if (normalizedTaskMode == TASK_MODE_BACKFILL) {
                    if (normalizedTargetDayKey.isNotBlank()) "等待当天补全启动" else "等待补全启动"
                } else {
                    if (normalizedTargetDayKey.isNotBlank()) "等待当天重建启动" else "等待后台启动"
                },
                currentStageDetail = if (normalizedTaskMode == TASK_MODE_BACKFILL) {
                    if (normalizedTargetDayKey.isNotBlank()) {
                        "补全任务已创建，等待后台服务扫描 $normalizedTargetDayKey 的缺漏"
                    } else {
                        "补全任务已创建，等待后台服务扫描缺漏"
                    }
                } else {
                    if (normalizedTargetDayKey.isNotBlank()) {
                        "当天重建任务已创建，等待后台服务准备 $normalizedTargetDayKey"
                    } else {
                        "任务已创建，等待后台服务开始准备"
                    }
                },
                lastError = null,
                segmentDurationSec = 0,
                segmentSampleIntervalSec = 0,
                aiBaseUrl = "",
                aiApiKey = "",
                aiModel = "",
                aiProviderType = null,
                aiChatPath = null,
                aiProviderId = null,
                recentLogs = mutableListOf(
                    buildStageLogLine(
                        if (normalizedTaskMode == TASK_MODE_BACKFILL) {
                            if (normalizedTargetDayKey.isNotBlank()) "等待当天补全启动" else "等待补全启动"
                        } else {
                            if (normalizedTargetDayKey.isNotBlank()) "等待当天重建启动" else "等待后台启动"
                        },
                        if (normalizedTaskMode == TASK_MODE_BACKFILL) {
                            if (normalizedTargetDayKey.isNotBlank()) {
                                "补全任务已创建，等待后台服务扫描 $normalizedTargetDayKey 的缺漏"
                            } else {
                                "补全任务已创建，等待后台服务扫描缺漏"
                            }
                        } else {
                            if (normalizedTargetDayKey.isNotBlank()) {
                                "当天重建任务已创建，等待后台服务准备 $normalizedTargetDayKey"
                            } else {
                                "任务已创建，等待后台服务开始准备"
                            }
                        },
                    ),
                ),
                dayWorks = mutableListOf(),
                workerSlots = MutableList(normalizedConcurrency) { index ->
                    DynamicRebuildWorkerSlotState(
                        slotId = index + 1,
                        retryLimit = DAY_RETRY_LIMIT,
                    )
                },
            )
            DynamicRebuildTaskStore.save(context, next)
            logBackfillDiag(
                appCtx,
                "startOrResumeTask createNew taskId=${next.taskId} mode=${next.taskMode} " +
                    "status=${next.status} dayConcurrency=${next.dayConcurrency} " +
                    "targetDayKey=${next.targetDayKey.ifBlank { "none" }}",
            )
            startService(context, ACTION_START)
            return next.toMap()
        }

        fun ensureResumedIfPending(
            context: Context,
            reason: String = "manual",
        ): Map<String, Any?> {
            val current = DynamicRebuildTaskStore.load(context)
            if (current != null && current.isRecoverable()) {
                FileLogger.i(TAG, "检测到可恢复的动态重建任务，尝试恢复执行，reason=$reason")
                startService(context, ACTION_RESUME)
                return current.toMap()
            }
            return current?.toMap() ?: DynamicRebuildTaskState.idle().toMap()
        }

        fun getTaskStatus(context: Context): Map<String, Any?> {
            return DynamicRebuildTaskStore.load(context)?.toMap()
                ?: DynamicRebuildTaskState.idle().toMap()
        }

        fun cancelTask(context: Context): Map<String, Any?> {
            val current = DynamicRebuildTaskStore.load(context)
                ?: return DynamicRebuildTaskState.idle().toMap()
            current.status = DynamicRebuildTaskState.STATUS_CANCELLED
            current.completedAt = System.currentTimeMillis()
            current.updatedAt = current.completedAt
            current.currentStage = "cancelled"
            current.currentStageLabel = "已停止"
            current.currentStageDetail =
                if (current.isBackfillMode()) "已请求停止所有补全线程，当前进度可稍后继续" else "已请求停止所有重建线程，当前进度可稍后继续"
            current.dayWorks.forEach { day ->
                if (day.status == DynamicRebuildDayWorkItem.STATUS_RUNNING) {
                    day.status = DynamicRebuildDayWorkItem.STATUS_PENDING
                }
            }
            current.workerSlots.forEach { slot ->
                if (slot.status == DynamicRebuildWorkerSlotState.STATUS_RUNNING ||
                    slot.status == DynamicRebuildWorkerSlotState.STATUS_RETRYING
                ) {
                    slot.status = DynamicRebuildWorkerSlotState.STATUS_IDLE
                    slot.currentStageLabel = "已停止"
                    slot.currentStageDetail = current.currentStageDetail
                    slot.recentStreamChunks.clear()
                }
            }
            current.appendRecentLog(
                buildStageLogLine(
                    "已停止",
                    current.currentStageDetail,
                ),
            )
            current.refreshDerivedFields()
            DynamicRebuildTaskStore.save(context, current)
            SegmentSummaryManager.cancelDynamicRebuildInFlightRequests("user_stop")
            startService(context, ACTION_CANCEL)
            return current.toMap()
        }

        fun clearTask(context: Context): Map<String, Any?> {
            val current = DynamicRebuildTaskStore.load(context)
            if (current?.isRecoverable() == true) {
                return current.toMap()
            }
            SegmentSummaryManager.cancelDynamicRebuildInFlightRequests("user_exit")
            DynamicRebuildTaskStore.clear(context)
            return DynamicRebuildTaskState.idle().toMap()
        }

        fun isTaskActive(context: Context): Boolean {
            return DynamicRebuildTaskStore.load(context)?.isRecoverable() == true
        }

        fun isCancellationRequested(context: Context): Boolean {
            return DynamicRebuildTaskStore.load(context)?.status ==
                DynamicRebuildTaskState.STATUS_CANCELLED
        }

        private fun normalizeDayConcurrency(raw: Int): Int {
            return raw.coerceIn(DEFAULT_DAY_CONCURRENCY, MAX_DAY_CONCURRENCY)
        }

        private fun normalizeTaskMode(raw: String?): String {
            return when (raw?.trim()?.lowercase(Locale.US)) {
                TASK_MODE_BACKFILL,
                "complete",
                "completion",
                "fill_missing" -> TASK_MODE_BACKFILL
                else -> TASK_MODE_REBUILD
            }
        }

        private fun normalizeTargetDayKey(raw: String?): String {
            val value = raw?.trim().orEmpty()
            if (!Regex("""\d{4}-\d{2}-\d{2}""").matches(value)) return ""
            return value
        }

        private fun logBackfillDiag(context: Context, message: String) {
            val normalized = message
                .replace("\r", " ")
                .replace("\n", " ")
                .trim()
            if (normalized.isEmpty()) return
            val appCtx = try { context.applicationContext } catch (_: Exception) { context }
            try {
                FileLogger.i(TAG, "BACKFILL_DIAG $normalized")
            } catch (_: Exception) {}
        }

        private fun startService(context: Context, action: String) {
            val intent = Intent(context, DynamicRebuildService::class.java).apply {
                this.action = action
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                FileLogger.e(TAG, "启动动态重建服务失败", e)
            }
        }
    }

    private val workerExecutor = Executors.newSingleThreadExecutor()
    private val workerStarted = AtomicBoolean(false)
    private val stateLock = Any()
    @Volatile private var activeDayExecutor: ExecutorService? = null
    private val activeDayFutures =
        Collections.synchronizedList(mutableListOf<Future<DayRunResult>>())
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        try {
            createNotificationChannel()
        } catch (e: Exception) {
            FileLogger.e(TAG, "创建动态重建通知渠道失败", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_RESUME
        if (action == ACTION_CANCEL) {
            requestCancelAllWorkers("action_cancel")
            if (workerStarted.get()) {
                return START_STICKY
            }
            val state = DynamicRebuildTaskStore.load(this)
            if (state != null) {
                try {
                    val notificationManager =
                        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(NOTIFICATION_ID, buildNotification(state))
                } catch (_: Exception) {}
            }
            stopSelf()
            return START_NOT_STICKY
        }

        val state = DynamicRebuildTaskStore.load(this)
        if (state == null || !state.isRecoverable()) {
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            startAsForeground(state)
        } catch (e: Exception) {
            handleForegroundStartupFailure(
                state = state,
                error = e,
                stage = "service_start_foreground_failed",
                label = "后台服务启动失败",
                detailPrefix = "启动前台通知失败",
            )
            stopSelf()
            return START_NOT_STICKY
        }
        if (workerStarted.compareAndSet(false, true)) {
            workerExecutor.execute { runWorker() }
        } else {
            updateNotification(state)
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        FileLogger.i(TAG, "系统移除任务，动态重建服务保持后台状态")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        try {
            workerExecutor.shutdownNow()
        } catch (_: Exception) {}
        releaseWakeLock()
        workerStarted.set(false)
        super.onDestroy()
    }

    private fun runWorker() {
        acquireWakeLock()
        var finalState: DynamicRebuildTaskState? = null
        try {
            var state = DynamicRebuildTaskStore.load(this) ?: return
            if (state.status == DynamicRebuildTaskState.STATUS_CANCELLED) {
                finalState = state
                return
            }
            synchronized(stateLock) {
                state.prepareForExecution()
                persistStateLocked(state)
            }

            recordStage(
                state = state,
                stage = "worker_started",
                label = "后台任务启动",
                detail = if (state.isBackfillMode()) "已进入按天并发补全流程" else "已进入按天并发重建流程",
            )

            if (!state.hasPreparedWorks()) {
                state = prepareWorkItems(state)
            }
            if (!state.isRecoverable()) {
                finalState = state
                return
            }

            synchronized(stateLock) {
                state.status = DynamicRebuildTaskState.STATUS_RUNNING
                state.refreshDerivedFields()
                persistStateLocked(state)
            }
            recordStage(
                state = state,
                stage = "running",
                label = if (state.isBackfillMode()) "开始按天并发补全" else "开始按天并发重建",
                detail = if (state.isBackfillMode()) {
                    "按天分组补齐缺失动态，最多 ${state.dayConcurrency} 天同时执行"
                } else {
                    "按天分组处理，最多 ${state.dayConcurrency} 天同时执行"
                },
            )

            finalState = processPreparedDays(state)
        } catch (e: Exception) {
            val failed = DynamicRebuildTaskStore.load(this) ?: DynamicRebuildTaskState.idle()
            failed.status = DynamicRebuildTaskState.STATUS_FAILED
            failed.lastError = e.message ?: e.toString()
            failed.completedAt = System.currentTimeMillis()
            failed.updatedAt = failed.completedAt
            failed.currentStage = "failed"
            failed.currentStageLabel = "任务失败"
            failed.currentStageDetail = failed.lastError ?: "后台重建失败"
            failed.appendRecentLog(
                buildStageLogLine(
                    "任务失败",
                    failed.currentStageDetail,
                ),
            )
            DynamicRebuildTaskStore.save(this, failed)
            FileLogger.e(TAG, "动态重建后台任务失败", e)
            finalState = failed
        } finally {
            workerStarted.set(false)
            releaseWakeLock()
            if (finalState != null) {
                finishTask(finalState!!)
            } else {
                stopSelf()
            }
        }
    }

    private fun prepareWorkItems(state: DynamicRebuildTaskState): DynamicRebuildTaskState {
        synchronized(stateLock) {
            state.status = DynamicRebuildTaskState.STATUS_PREPARING
            state.refreshDerivedFields()
            persistStateLocked(state)
        }
        recordStage(
            state = state,
            stage = "prepare_settings",
            label = "读取重建配置",
            detail = "正在读取分段长度、采样间隔与按天并发配置",
        )

        val durationSec = readSegmentDurationSec()
        val sampleIntervalSec = readSegmentSampleIntervalSec()
        val backfillMode = state.isBackfillMode()
        val targetDayKey = state.targetDayKey.trim()
        logBackfillDiag(
            this,
            "prepareWorkItems start taskId=${state.taskId} mode=${state.taskMode} backfill=$backfillMode " +
                "targetDayKey=${targetDayKey.ifBlank { "none" }} " +
                "status=${state.status} durationSec=$durationSec sampleIntervalSec=$sampleIntervalSec " +
                "dayConcurrency=${state.dayConcurrency} existingDayWorks=${state.dayWorks.size} " +
                "existingTotalSegments=${state.totalSegments}",
        )
        recordStage(
            state = state,
            stage = "prepare_worklist",
            label = if (backfillMode && targetDayKey.isNotBlank()) {
                "扫描当天缺漏"
            } else if (backfillMode) {
                "扫描缺漏清单"
            } else {
                "生成按天清单"
            },
            detail = if (backfillMode) {
                if (targetDayKey.isNotBlank()) {
                    "按截图时间扫描 $targetDayKey，跳过已有动态结果，仅收集当天缺失窗口"
                } else {
                    "按截图时间逐日扫描，跳过已有动态结果，仅收集缺失窗口"
                }
            } else {
                if (targetDayKey.isNotBlank()) {
                    "按截图时间计算 $targetDayKey 的重建范围，并按日期分组"
                } else {
                    "按截图时间顺序计算全量重建范围，并按日期分组"
                }
            },
        )
        if (backfillMode) {
            val targetBounds = if (targetDayKey.isNotBlank()) {
                SegmentSummaryManager.dayBoundsMillis(targetDayKey)
            } else {
                null
            }
            recordStage(
                state = state,
                stage = "prepare_normalize_overlap",
                label = "整理交错动态",
                detail = "正在归一化已有顶层动态时间交错，避免补全后列表交叉",
            )
            val normalized = try {
                SegmentSummaryManager.normalizeExistingRootOverlaps(
                    ctx = this,
                    startMillis = targetBounds?.first,
                    endMillis = targetBounds?.second,
                    limitClusters = 50,
                )
            } catch (_: Exception) {
                0
            }
            logBackfillDiag(
                this,
                "prepareWorkItems normalizeOverlap taskId=${state.taskId} normalizedClusters=$normalized",
            )
            if (normalized > 0) {
                recordStage(
                    state = state,
                    stage = "prepare_normalize_overlap_done",
                    label = "交错整理完成",
                    detail = "已归一化 $normalized 组交错动态",
                )
            }
        }
        val allWindows = if (backfillMode) {
            SegmentSummaryManager.buildMissingBackfillWorklist(
                this,
                durationSec,
                targetDayKey = targetDayKey,
            )
        } else {
            SegmentSummaryManager.buildFullRebuildWorklist(
                this,
                durationSec,
                targetDayKey = targetDayKey,
            )
        }
        val windows = if (targetDayKey.isNotBlank()) {
            SegmentSummaryManager.filterDynamicRebuildWindowsForDay(
                allWindows,
                targetDayKey,
            )
        } else {
            allWindows
        }
        logBackfillDiag(
            this,
            "prepareWorkItems worklistBuilt taskId=${state.taskId} mode=${state.taskMode} " +
                "targetDayKey=${targetDayKey.ifBlank { "none" }} allWindows=${allWindows.size} windows=${windows.size} " +
                "preview=${windows.take(12).joinToString(";") { window -> windowDiag(window.startTime, window.endTime, window.existingSegmentId) }}",
        )
        val dayWorks = buildDayWorkItems(windows).toMutableList()
        if (backfillMode) {
            reorderBackfillDaysForOverlapSafety(dayWorks)
        }
        logBackfillDiag(
            this,
            "prepareWorkItems dayWorksBuilt taskId=${state.taskId} days=${dayWorks.size} " +
                "totalWindows=${dayWorks.sumOf { it.totalSegments() }} " +
                "preview=${dayWorks.take(20).joinToString(";") { day -> "${day.dayKey}:${day.totalSegments()}" }}",
        )
        val aiConfig = if (windows.isNotEmpty()) {
            recordStage(
                state = state,
                stage = "prepare_ai_config",
                label = "读取 AI 配置",
                detail = if (backfillMode) "准备动态补全所需的模型配置" else "准备动态重建所需的模型配置",
            )
            AISettingsNative.readConfigSnapshot(this, "segments")
        } else {
            null
        }

        if (!backfillMode) {
            recordStage(
                state = state,
                stage = "prepare_reset",
                label = if (targetDayKey.isNotBlank()) "清空当天动态数据" else "清空旧动态数据",
                detail = if (targetDayKey.isNotBlank()) {
                    "删除 $targetDayKey 的旧动态、总结与样本，准备当天重建"
                } else {
                    "删除旧的动态、总结与样本，准备重建"
                },
            )
            val targetBounds = if (targetDayKey.isNotBlank()) {
                SegmentSummaryManager.dayBoundsMillis(targetDayKey)
            } else {
                null
            }
            if (targetDayKey.isNotBlank() && targetBounds == null) {
                state.status = DynamicRebuildTaskState.STATUS_COMPLETED
                state.completedAt = System.currentTimeMillis()
                state.updatedAt = state.completedAt
                state.currentStage = "completed_empty"
                state.currentStageLabel = "准备完成"
                state.currentStageDetail = "当天日期无效，未找到可重建的动态"
                state.appendRecentLog(
                    buildStageLogLine(
                        "准备完成",
                        "当天日期无效，未找到可重建的动态",
                    ),
                )
                synchronized(stateLock) {
                    persistStateLocked(state)
                }
                return state
            }
            if (targetBounds != null) {
                SegmentDatabaseHelper.resetDynamicRebuildArtifactsForDay(
                    this,
                    targetDayKey,
                    targetBounds.first,
                    targetBounds.second,
                )
            } else {
                SegmentDatabaseHelper.resetAllDynamicRebuildArtifacts(this)
            }
        } else {
            recordStage(
                state = state,
                stage = "prepare_keep_existing",
                label = "保留现有动态",
                detail = if (targetDayKey.isNotBlank()) {
                    "当天补全不会清空已有动态，只处理 $targetDayKey 扫描出的缺失窗口"
                } else {
                    "补全模式不会清空已有动态，只处理扫描出的缺失窗口"
                },
            )
        }

        state.segmentDurationSec = durationSec
        state.segmentSampleIntervalSec = sampleIntervalSec
        state.aiBaseUrl = aiConfig?.baseUrl ?: ""
        state.aiApiKey = aiConfig?.apiKey ?: ""
        state.aiModel = aiConfig?.model ?: ""
        state.aiProviderType = aiConfig?.providerType
        state.aiChatPath = aiConfig?.chatPath
        state.aiProviderId = aiConfig?.providerId
        state.dayWorks.clear()
        state.dayWorks.addAll(dayWorks)
        state.workerSlots.clear()
        repeat(state.dayConcurrency.coerceIn(DEFAULT_DAY_CONCURRENCY, MAX_DAY_CONCURRENCY)) { index ->
            state.workerSlots.add(
                DynamicRebuildWorkerSlotState(
                    slotId = index + 1,
                    retryLimit = DAY_RETRY_LIMIT,
                ),
            )
        }
        state.currentSegmentId = 0L
        state.lastError = null
        state.completedAt = 0L
        state.currentDayKey = ""
        state.currentRangeLabel = ""
        state.currentStage = ""
        state.currentStageLabel = ""
        state.currentStageDetail = ""
        state.refreshDerivedFields()

        if (state.dayWorks.isEmpty()) {
            state.status = DynamicRebuildTaskState.STATUS_COMPLETED
            state.completedAt = System.currentTimeMillis()
            state.updatedAt = state.completedAt
            state.currentStage = "completed_empty"
            state.currentStageLabel = "准备完成"
            state.currentStageDetail = if (backfillMode) "没有找到需要补全的动态" else "没有找到可重建的动态"
            state.appendRecentLog(
                buildStageLogLine(
                    "准备完成",
                    if (backfillMode) "没有找到需要补全的动态" else "没有找到可重建的动态",
                ),
            )
            synchronized(stateLock) {
                persistStateLocked(state)
            }
            logBackfillDiag(
                this,
                "prepareWorkItems completedEmpty taskId=${state.taskId} mode=${state.taskMode} " +
                    "reason=${state.currentStageDetail}",
            )
            return state
        }

        state.status = DynamicRebuildTaskState.STATUS_PENDING
        synchronized(stateLock) {
            state.refreshDerivedFields()
            persistStateLocked(state)
        }
        recordStage(
            state = state,
            stage = "prepare_done",
            label = "准备完成",
            detail =
                if (backfillMode) {
                    "发现 ${state.totalSegments} 条需补全动态，覆盖 ${state.totalDays()} 天，并发 ${state.dayConcurrency} 天"
                } else if (targetDayKey.isNotBlank()) {
                    "发现 ${state.totalSegments} 条当天重建动态，覆盖 ${state.totalDays()} 天，并发 ${state.dayConcurrency} 天"
                } else {
                    "共 ${state.totalSegments} 条动态，覆盖 ${state.totalDays()} 天，并发 ${state.dayConcurrency} 天"
                },
        )
        logBackfillDiag(
            this,
            "prepareWorkItems done taskId=${state.taskId} mode=${state.taskMode} " +
                "totalSegments=${state.totalSegments} totalDays=${state.totalDays()} " +
                "dayConcurrency=${state.dayConcurrency} aiModel=${state.aiModel}",
        )
        return state
    }

    private fun processPreparedDays(
        state: DynamicRebuildTaskState,
    ): DynamicRebuildTaskState {
        synchronized(stateLock) {
            state.prepareForExecution()
            state.status = DynamicRebuildTaskState.STATUS_RUNNING
            state.refreshDerivedFields()
            persistStateLocked(state)
        }
        if (isCancellationRequested()) {
            return markCancelled(state, "停止请求已生效，后台任务退出")
        }

        val parallelism = synchronized(stateLock) {
            state.parallelismForRun()
        }
        logBackfillDiag(
            this,
            "processPreparedDays start taskId=${state.taskId} mode=${state.taskMode} " +
                "parallelism=$parallelism dayWorks=${state.dayWorks.size} totalSegments=${state.totalSegments} " +
                "processed=${state.processedSegments} failed=${state.failedSegments}",
        )
        if (parallelism <= 0) {
            logBackfillDiag(
                this,
                "processPreparedDays noParallelism taskId=${state.taskId} reason=parallelism<=0",
            )
            return finalizeTaskState(state)
        }

        val dayExecutor = Executors.newFixedThreadPool(parallelism)
        activeDayExecutor = dayExecutor
        synchronized(activeDayFutures) {
            activeDayFutures.clear()
        }
        val completion = ExecutorCompletionService<DayRunResult>(dayExecutor)
        var inFlight = 0
        try {
            inFlight += submitAvailableDayAssignments(state, completion)
            logBackfillDiag(
                this,
                "processPreparedDays submittedInitial taskId=${state.taskId} inFlight=$inFlight",
            )
            while (inFlight > 0) {
                if (isCancellationRequested()) {
                    logBackfillDiag(
                        this,
                        "processPreparedDays cancelBeforeWait taskId=${state.taskId} inFlight=$inFlight",
                    )
                    requestCancelAllWorkers("cancel_before_wait")
                    return markCancelled(state, "已停止所有并发线程，后台任务退出")
                }
                val future = completion.poll(250L, TimeUnit.MILLISECONDS) ?: continue
                synchronized(activeDayFutures) {
                    activeDayFutures.remove(future)
                }
                val result = try {
                    future.get()
                } catch (_: java.util.concurrent.CancellationException) {
                    DayRunResult(0, -1, DayRunOutcome.CANCELLED)
                } catch (e: java.lang.InterruptedException) {
                    Thread.currentThread().interrupt()
                    if (isCancellationRequested()) {
                        requestCancelAllWorkers("interrupted_after_cancel")
                        return markCancelled(state, "已停止所有并发线程，后台任务退出")
                    }
                    throw e
                } catch (e: java.util.concurrent.ExecutionException) {
                    if (isCancellationRequested()) {
                        requestCancelAllWorkers("execution_failed_after_cancel")
                        return markCancelled(state, "已停止所有并发线程，后台任务退出")
                    }
                    val cause = e.cause
                    if (cause is Exception) throw cause
                    throw e
                }
                inFlight -= 1
                logBackfillDiag(
                    this,
                    "processPreparedDays workerResult taskId=${state.taskId} slot=${result.slotId} " +
                        "dayIndex=${result.dayIndex} outcome=${result.outcome} inFlightAfterPoll=$inFlight",
                )
                if (result.outcome == DayRunOutcome.CANCELLED || isCancellationRequested()) {
                    logBackfillDiag(
                        this,
                        "processPreparedDays workerCancelled taskId=${state.taskId} slot=${result.slotId} " +
                            "dayIndex=${result.dayIndex}",
                    )
                    requestCancelAllWorkers("worker_cancelled")
                    return markCancelled(state, "已停止所有并发线程，后台任务退出")
                }
                if (result.outcome == DayRunOutcome.FATAL) {
                    logBackfillDiag(
                        this,
                        "processPreparedDays fatal taskId=${state.taskId} slot=${result.slotId} " +
                            "dayIndex=${result.dayIndex} error=${clipForUi(result.fatalError?.message ?: "unknown", 240)}",
                    )
                    synchronized(stateLock) {
                        state.status = DynamicRebuildTaskState.STATUS_FAILED
                        state.lastError = result.fatalError?.message ?: "动态重建失败"
                        state.completedAt = System.currentTimeMillis()
                        state.updatedAt = state.completedAt
                        state.currentStage = "failed"
                        state.currentStageLabel = "任务失败"
                        state.currentStageDetail = state.lastError ?: "动态重建失败"
                        state.appendRecentLog(
                            buildStageLogLine(
                                "任务失败",
                                state.currentStageDetail,
                            ),
                        )
                        persistStateLocked(state)
                    }
                    return state
                }
                if (!isCancellationRequested()) {
                    val submitted = submitAvailableDayAssignments(state, completion)
                    inFlight += submitted
                    if (submitted > 0) {
                        logBackfillDiag(
                            this,
                            "processPreparedDays submittedMore taskId=${state.taskId} submitted=$submitted inFlight=$inFlight",
                        )
                    }
                }
            }
        } finally {
            dayExecutor.shutdownNow()
            if (activeDayExecutor === dayExecutor) {
                activeDayExecutor = null
            }
            synchronized(activeDayFutures) {
                activeDayFutures.clear()
            }
        }

        if (isCancellationRequested()) {
            logBackfillDiag(
                this,
                "processPreparedDays cancelledAtEnd taskId=${state.taskId}",
            )
            return markCancelled(state, "已中断当前 AI 请求，后台任务停止")
        }
        logBackfillDiag(
            this,
            "processPreparedDays finalize taskId=${state.taskId} processed=${state.processedSegments} " +
                "failed=${state.failedSegments} failedDays=${state.failedDayCount()}",
        )
        return finalizeTaskState(state)
    }

    private fun markCancelled(
        state: DynamicRebuildTaskState,
        detail: String,
    ): DynamicRebuildTaskState {
        val normalizedDetail = detail.trim().ifEmpty { "停止请求已生效，后台任务退出" }
        synchronized(stateLock) {
            state.status = DynamicRebuildTaskState.STATUS_CANCELLED
            state.lastError = null
            state.completedAt = System.currentTimeMillis()
            state.updatedAt = state.completedAt
            state.currentStage = "cancelled"
            state.currentStageLabel = "已停止"
            state.currentStageDetail = normalizedDetail
            state.workerSlots.forEach { slot ->
                if (slot.status == DynamicRebuildWorkerSlotState.STATUS_RUNNING ||
                    slot.status == DynamicRebuildWorkerSlotState.STATUS_RETRYING
                ) {
                    slot.status = DynamicRebuildWorkerSlotState.STATUS_IDLE
                    slot.currentStageLabel = "已停止"
                    slot.currentStageDetail = normalizedDetail
                }
            }
            state.refreshDerivedFields()
            state.appendRecentLog(
                buildStageLogLine(
                    "已停止",
                    normalizedDetail,
                ),
            )
            persistStateLocked(state)
        }
        return state
    }

    private fun submitAvailableDayAssignments(
        state: DynamicRebuildTaskState,
        completion: ExecutorCompletionService<DayRunResult>,
    ): Int {
        var submitted = 0
        while (true) {
            val assignment = synchronized(stateLock) {
                acquireNextAssignmentLocked(state)
            } ?: break
            val day = synchronized(stateLock) { state.dayWorks.getOrNull(assignment.dayIndex) }
            logBackfillDiag(
                this,
                "submitAssignment taskId=${state.taskId} slot=${assignment.slotId} dayIndex=${assignment.dayIndex} " +
                    "day=${day?.dayKey ?: ""} status=${day?.status ?: ""} nextIndex=${day?.nextWindowIndex ?: -1} " +
                    "total=${day?.totalSegments() ?: 0} retry=${day?.retryCount ?: 0}",
            )
            completion.submit {
                processDayAssignment(
                    state = state,
                    slotId = assignment.slotId,
                    dayIndex = assignment.dayIndex,
                )
            }.also { future ->
                synchronized(activeDayFutures) {
                    activeDayFutures.add(future)
                }
            }
            submitted += 1
        }
        return submitted
    }

    private fun requestCancelAllWorkers(reason: String) {
        val cancelledCalls = try {
            SegmentSummaryManager.cancelDynamicRebuildInFlightRequests(reason)
        } catch (_: Exception) {
            0
        }
        val futures = synchronized(activeDayFutures) {
            activeDayFutures.toList()
        }
        var cancelledFutures = 0
        for (future in futures) {
            try {
                if (!future.isDone && future.cancel(true)) {
                    cancelledFutures += 1
                }
            } catch (_: Exception) {}
        }
        try {
            activeDayExecutor?.shutdownNow()
        } catch (_: Exception) {}
        try {
            FileLogger.w(
                TAG,
                "动态重建：已请求停止所有并发线程，futures=$cancelledFutures/${futures.size}, aiCalls=$cancelledCalls, reason=$reason",
            )
        } catch (_: Exception) {}
    }

    private fun processDayAssignment(
        state: DynamicRebuildTaskState,
        slotId: Int,
        dayIndex: Int,
    ): DayRunResult {
        val aiConfig = try {
            synchronized(stateLock) {
                state.requireAiConfig()
            }
        } catch (e: Exception) {
            return DayRunResult(
                slotId = slotId,
                dayIndex = dayIndex,
                outcome = DayRunOutcome.FATAL,
                fatalError = e,
            )
        }

        while (true) {
            if (isCancellationRequested()) {
                return DayRunResult(slotId, dayIndex, DayRunOutcome.CANCELLED)
            }
            val snapshot = synchronized(stateLock) {
                val day = state.dayWorks.getOrNull(dayIndex)
                    ?: return@synchronized null
                val window = day.currentWindow()
                if (window == null) {
                    markDayCompletedLocked(state, dayIndex, slotId)
                    return@synchronized null
                }
                DayProcessingSnapshot(
                    dayKey = day.dayKey,
                    rangeLabel = window.rangeLabel,
                    windowStart = window.startTime,
                    windowEnd = window.endTime,
                    existingSegmentId = window.existingSegmentId,
                    processedSegments = day.processedSegments,
                    totalSegments = day.totalSegments(),
                    retryCount = day.retryCount,
                    currentSegmentId = state.workerSlots.firstOrNull { it.slotId == slotId }
                        ?.currentSegmentId ?: 0L,
                )
            } ?: return DayRunResult(slotId, dayIndex, DayRunOutcome.COMPLETED)
            logBackfillDiag(
                this,
                "processDay windowSnapshot taskId=${state.taskId} slot=$slotId dayIndex=$dayIndex " +
                    "day=${snapshot.dayKey} ordinal=${snapshot.processedSegments + 1}/${snapshot.totalSegments} " +
                    "retry=${snapshot.retryCount} window=${windowDiag(snapshot.windowStart, snapshot.windowEnd, snapshot.existingSegmentId)} " +
                    "currentSegmentId=${snapshot.currentSegmentId}",
            )

            recordStage(
                state = state,
                stage = "window_start",
                label = if (snapshot.retryCount > 0) {
                    "继续处理失败日期"
                } else if (state.isBackfillMode()) {
                    "开始补全当天动态"
                } else {
                    "开始处理当天动态"
                },
                detail =
                    "第 ${snapshot.processedSegments + 1}/${snapshot.totalSegments} 条 · ${snapshot.dayKey} ${snapshot.rangeLabel}".trim(),
                slotId = slotId,
                dayKey = snapshot.dayKey,
                currentRangeLabel = snapshot.rangeLabel,
                dayIndex = dayIndex,
            )

            try {
                logBackfillDiag(
                    this,
                    "processDay rebuildCall taskId=${state.taskId} slot=$slotId day=${snapshot.dayKey} " +
                        "window=${windowDiag(snapshot.windowStart, snapshot.windowEnd, snapshot.existingSegmentId)} " +
                        "passExistingSegmentId=${snapshot.currentSegmentId.takeIf { it > 0L } ?: snapshot.existingSegmentId}",
                )
                SegmentSummaryManager.rebuildWindowStrict(
                    ctx = this,
                    windowStart = snapshot.windowStart,
                    windowEnd = snapshot.windowEnd,
                    durationSec = state.segmentDurationSec,
                    sampleIntervalSec = state.segmentSampleIntervalSec,
                    aiConfig = aiConfig,
                    existingSegmentId = snapshot.currentSegmentId.takeIf { it > 0L }
                        ?: snapshot.existingSegmentId,
                    stageReporter = { stage, label, detail, segmentId ->
                        if (stage == SegmentSummaryManager.DYNAMIC_AI_STAGE_STREAM_CHUNK_PREVIEW) {
                            recordWorkerStreamChunk(
                                state = state,
                                slotId = slotId,
                                dayKey = snapshot.dayKey,
                                detail = detail,
                                segmentId = segmentId,
                                dayIndex = dayIndex,
                            )
                        } else {
                            recordStage(
                                state = state,
                                stage = stage,
                                label = label,
                                detail = detail,
                                segmentId = segmentId,
                                slotId = slotId,
                                dayKey = snapshot.dayKey,
                                currentRangeLabel = snapshot.rangeLabel,
                                dayIndex = dayIndex,
                            )
                        }
                    },
                )
                logBackfillDiag(
                    this,
                    "processDay rebuildReturn taskId=${state.taskId} slot=$slotId day=${snapshot.dayKey} " +
                        "window=${windowDiag(snapshot.windowStart, snapshot.windowEnd, snapshot.existingSegmentId)}",
                )
                val dayCompleted = synchronized(stateLock) {
                    val day = state.dayWorks.getOrNull(dayIndex)
                        ?: return@synchronized false
                    if (day.nextWindowIndex < day.totalSegments()) {
                        day.nextWindowIndex += 1
                    }
                    day.processedSegments = day.nextWindowIndex.coerceAtMost(day.totalSegments())
                    day.failedSegments = 0
                    day.lastError = null
                    val slot = state.workerSlots.firstOrNull { it.slotId == slotId }
                    if (slot != null) {
                        slot.currentSegmentId = 0L
                        slot.totalSegments = day.totalSegments()
                        slot.processedSegments = day.accountedSegments()
                        slot.retryCount = day.retryCount
                        slot.retryLimit = DAY_RETRY_LIMIT
                    }
                    val completed = day.nextWindowIndex >= day.totalSegments()
                    if (completed) {
                        markDayCompletedLocked(state, dayIndex, slotId)
                    } else {
                        day.status = DynamicRebuildDayWorkItem.STATUS_RUNNING
                        state.refreshDerivedFields()
                        persistStateLocked(state)
                    }
                    completed
                }
                logBackfillDiag(
                    this,
                    "processDay progressUpdated taskId=${state.taskId} slot=$slotId day=${snapshot.dayKey} " +
                        "dayCompleted=$dayCompleted nextOrdinal=${snapshot.processedSegments + 2}/${snapshot.totalSegments}",
                )
                if (dayCompleted) {
                    recordStage(
                        state = state,
                        stage = "day_completed",
                        label = "当天完成",
                        detail = if (state.isBackfillMode()) {
                            "已补全 ${snapshot.dayKey} 的 ${snapshot.totalSegments} 条缺失动态"
                        } else {
                            "已完成 ${snapshot.dayKey} 的 ${snapshot.totalSegments} 条动态"
                        },
                        slotId = slotId,
                        dayKey = snapshot.dayKey,
                        dayIndex = dayIndex,
                    )
                    logBackfillDiag(
                        this,
                        "processDay dayCompleted taskId=${state.taskId} slot=$slotId day=${snapshot.dayKey} " +
                            "total=${snapshot.totalSegments}",
                    )
                    return DayRunResult(slotId, dayIndex, DayRunOutcome.COMPLETED)
                }
                recordStage(
                    state = state,
                    stage = "window_completed",
                    label = "当前动态完成",
                    detail =
                        "已完成当天第 ${snapshot.processedSegments + 1}/${snapshot.totalSegments} 条",
                    slotId = slotId,
                    dayKey = snapshot.dayKey,
                    dayIndex = dayIndex,
                )
            } catch (e: SegmentSummaryManager.DynamicRebuildCancelledException) {
                logBackfillDiag(
                    this,
                    "processDay cancelledException taskId=${state.taskId} slot=$slotId day=${snapshot.dayKey} " +
                        "segment=${e.segmentId} message=${clipForUi(e.message ?: e.toString(), 240)}",
                )
                if (e.segmentId > 0L) {
                    synchronized(stateLock) {
                        state.workerSlots.firstOrNull { it.slotId == slotId }
                            ?.currentSegmentId = e.segmentId
                        persistStateLocked(state)
                    }
                }
                return DayRunResult(slotId, dayIndex, DayRunOutcome.CANCELLED)
            } catch (e: SegmentSummaryManager.DynamicRebuildStepException) {
                logBackfillDiag(
                    this,
                    "processDay stepException taskId=${state.taskId} slot=$slotId day=${snapshot.dayKey} " +
                        "segment=${e.segmentId} window=${windowDiag(snapshot.windowStart, snapshot.windowEnd, snapshot.existingSegmentId)} " +
                        "message=${clipForUi(e.message ?: e.toString(), 300)}",
                )
                if (isCancellationRequested()) {
                    return DayRunResult(slotId, dayIndex, DayRunOutcome.CANCELLED)
                }
                return handleDayFailure(
                    state = state,
                    slotId = slotId,
                    dayIndex = dayIndex,
                    errorMessage = e.message ?: e.toString(),
                    segmentId = e.segmentId,
                )
            } catch (e: Exception) {
                logBackfillDiag(
                    this,
                    "processDay exception taskId=${state.taskId} slot=$slotId day=${snapshot.dayKey} " +
                        "window=${windowDiag(snapshot.windowStart, snapshot.windowEnd, snapshot.existingSegmentId)} " +
                        "type=${e.javaClass.simpleName} message=${clipForUi(e.message ?: e.toString(), 300)}",
                )
                if (isCancellationRequested()) {
                    return DayRunResult(slotId, dayIndex, DayRunOutcome.CANCELLED)
                }
                return handleDayFailure(
                    state = state,
                    slotId = slotId,
                    dayIndex = dayIndex,
                    errorMessage = e.message ?: e.toString(),
                    segmentId = 0L,
                )
            }
        }
    }

    private fun handleDayFailure(
        state: DynamicRebuildTaskState,
        slotId: Int,
        dayIndex: Int,
        errorMessage: String,
        segmentId: Long,
    ): DayRunResult {
        val dayKey = synchronized(stateLock) {
            state.dayWorks.getOrNull(dayIndex)?.dayKey.orEmpty()
        }
        logBackfillDiag(
            this,
            "handleDayFailure start taskId=${state.taskId} slot=$slotId dayIndex=$dayIndex day=$dayKey " +
                "segment=$segmentId error=${clipForUi(errorMessage, 300)}",
        )
        recordStage(
            state = state,
            stage = "day_failure_probe",
            label = "失败后连续测试",
            detail = "动态请求失败，正在用真实问答测试 Key：${clipForUi(errorMessage, 160)}",
            segmentId = segmentId,
            slotId = slotId,
            dayKey = dayKey,
            dayIndex = dayIndex,
            forceLog = true,
        )

        val probe = try {
            val config = synchronized(stateLock) { state.requireAiConfig() }
            SegmentSummaryManager.probeDynamicRebuildAiAfterFailure(
                ctx = this,
                aiConfigOverride = config,
                attemptsPerKey = DAY_RETRY_LIMIT,
            )
        } catch (e: SegmentSummaryManager.DynamicRebuildCancelledException) {
            return DayRunResult(slotId, dayIndex, DayRunOutcome.CANCELLED)
        } catch (e: Exception) {
            SegmentSummaryManager.DynamicRebuildAiProbeResult(
                success = false,
                keyLabel = "",
                model = state.aiModel,
                attemptsUsed = 0,
                totalCandidates = 0,
                responsePreview = null,
                failureMessages = listOf(e.message ?: e.toString()),
            )
        }
        logBackfillDiag(
            this,
            "handleDayFailure probeResult taskId=${state.taskId} slot=$slotId day=$dayKey " +
                "success=${probe.success} keyLabel=${probe.keyLabel} attempts=${probe.attemptsUsed} " +
                "candidates=${probe.totalCandidates} failure=${clipForUi(probe.failureSummary, 300)}",
        )

        if (isCancellationRequested()) {
            return DayRunResult(slotId, dayIndex, DayRunOutcome.CANCELLED)
        }

        val outcome = synchronized(stateLock) {
            val day = state.dayWorks.getOrNull(dayIndex)
                ?: return@synchronized DayRunOutcome.FATAL
            val slot = state.workerSlots.firstOrNull { it.slotId == slotId }
            if (segmentId > 0L && slot != null) {
                slot.currentSegmentId = segmentId
            }
            state.lastError = errorMessage

            if (probe.success) {
                day.lastError = errorMessage
                day.retryCount = (day.retryCount + 1).coerceAtMost(DAY_RETRY_LIMIT - 1)
                day.failedSegments = 0
                day.status = DynamicRebuildDayWorkItem.STATUS_RETRY_PENDING
                if (slot != null) {
                    slot.status = DynamicRebuildWorkerSlotState.STATUS_FAILED_WAITING
                    slot.currentStageLabel = "测试通过，继续自动续跑"
                    slot.currentStageDetail =
                        "连续测试通过：${clipForUi(probe.successSummary, 180)}"
                    slot.processedSegments = day.accountedSegments()
                    slot.retryCount = day.retryCount
                    slot.retryLimit = DAY_RETRY_LIMIT
                }
                state.refreshDerivedFields()
                persistStateLocked(state)
                DayRunOutcome.RETRY_PENDING
            } else {
                val probeFailure = probe.failureSummary.ifBlank { "连续测试全部失败" }
                day.lastError =
                    "动态请求失败：${clipForUi(errorMessage, 500)}；连续测试失败：${clipForUi(probeFailure, 500)}"
                day.retryCount = DAY_RETRY_LIMIT
                day.failedSegments = day.pendingFailureCredit()
                day.status = DynamicRebuildDayWorkItem.STATUS_FAILED_WAITING
                if (slot != null) {
                    slot.status = DynamicRebuildWorkerSlotState.STATUS_FAILED_WAITING
                    slot.currentStageLabel = "等待手动继续"
                    slot.currentStageDetail =
                        "连续测试全部失败：${clipForUi(probeFailure, 180)}"
                    slot.processedSegments = day.accountedSegments()
                    slot.retryCount = day.retryCount
                    slot.retryLimit = DAY_RETRY_LIMIT
                }
                state.lastError = day.lastError
                state.refreshDerivedFields()
                persistStateLocked(state)
                DayRunOutcome.FAILED_WAITING
            }
        }
        if (outcome == DayRunOutcome.FATAL) {
            logBackfillDiag(
                this,
                "handleDayFailure fatalOutcome taskId=${state.taskId} slot=$slotId day=$dayKey",
            )
            return DayRunResult(slotId, dayIndex, outcome)
        }
        recordStage(
            state = state,
            stage = "day_failed",
            label =
                if (outcome == DayRunOutcome.RETRY_PENDING) {
                    "测试通过，继续自动续跑"
                } else {
                    "当天失败，等待手动继续"
                },
            detail =
                if (outcome == DayRunOutcome.RETRY_PENDING) {
                    "动态请求失败但连续测试通过：${clipForUi(probe.successSummary, 180)}；继续重试当前日期"
                } else {
                    val probeFailure = probe.failureSummary.ifBlank { "连续测试全部失败" }
                    "动态请求失败：${clipForUi(errorMessage, 180)}；连续测试全部失败：${clipForUi(probeFailure, 180)}"
                },
            segmentId = segmentId,
            slotId = slotId,
            dayKey = dayKey,
            dayIndex = dayIndex,
            forceLog = true,
        )
        logBackfillDiag(
            this,
            "handleDayFailure done taskId=${state.taskId} slot=$slotId day=$dayKey outcome=$outcome " +
                "retry=${synchronized(stateLock) { state.dayWorks.getOrNull(dayIndex)?.retryCount ?: -1 }}",
        )
        return DayRunResult(slotId, dayIndex, outcome)
    }

    private fun clipForUi(text: String, maxLen: Int): String {
        val normalized = text.replace("\r", " ").replace("\n", " ").trim()
        if (normalized.length <= maxLen) return normalized
        return normalized.substring(0, maxLen.coerceAtLeast(1)) + "..."
    }

    private fun finalizeTaskState(state: DynamicRebuildTaskState): DynamicRebuildTaskState {
        synchronized(stateLock) {
            state.refreshDerivedFields()
            val failedDays = state.failedDayCount()
            state.completedAt = System.currentTimeMillis()
            state.updatedAt = state.completedAt
            state.currentSegmentId = 0L
            state.workerSlots.forEach { slot ->
                if (slot.status == DynamicRebuildWorkerSlotState.STATUS_RUNNING ||
                    slot.status == DynamicRebuildWorkerSlotState.STATUS_RETRYING
                ) {
                    slot.status = DynamicRebuildWorkerSlotState.STATUS_IDLE
                    slot.currentStageLabel = ""
                    slot.currentStageDetail = ""
                    slot.currentRangeLabel = ""
                    slot.currentSegmentId = 0L
                }
            }
            if (failedDays > 0) {
                state.status = DynamicRebuildTaskState.STATUS_COMPLETED_WITH_FAILURES
                state.currentStage = "completed_with_failures"
                state.currentStageLabel = "部分完成"
                state.currentStageDetail =
                    if (state.isBackfillMode()) {
                        "已处理 ${state.processedSegments}/${state.totalSegments} 条动态，失败 ${state.failedSegments} 条，仍有 $failedDays/${state.totalDays()} 天待继续"
                    } else {
                        "已处理 ${state.processedSegments}/${state.totalSegments} 条动态，失败 ${state.failedSegments} 条，仍有 $failedDays/${state.totalDays()} 天待继续"
                    }
                state.appendRecentLog(
                    buildStageLogLine(
                        "部分完成",
                        state.currentStageDetail,
                    ),
                )
            } else {
                state.status = DynamicRebuildTaskState.STATUS_COMPLETED
                state.currentStage = "completed"
                state.currentStageLabel = "全部完成"
                state.currentStageDetail =
                    if (state.isBackfillMode()) {
                        "共补全 ${state.processedSegments}/${state.totalSegments} 条缺失动态"
                    } else {
                        "共完成 ${state.processedSegments}/${state.totalSegments} 条动态"
                    }
                state.appendRecentLog(
                    buildStageLogLine(
                        "全部完成",
                        state.currentStageDetail,
                    ),
                )
            }
            state.refreshDerivedFields()
            persistStateLocked(state)
        }
        logBackfillDiag(
            this,
            "finalizeTaskState taskId=${state.taskId} mode=${state.taskMode} status=${state.status} " +
                "total=${state.totalSegments} processed=${state.processedSegments} failed=${state.failedSegments} " +
                "failedDays=${state.failedDayCount()} completedDays=${state.completedDayCount()}",
        )
        try {
            SegmentSummaryManager.tick(applicationContext)
        } catch (_: Exception) {}
        return state
    }

    private fun acquireNextAssignmentLocked(
        state: DynamicRebuildTaskState,
    ): WorkerAssignment? {
        val slot = state.workerSlots.firstOrNull {
            it.status == DynamicRebuildWorkerSlotState.STATUS_IDLE ||
                it.status == DynamicRebuildWorkerSlotState.STATUS_COMPLETED ||
                it.status == DynamicRebuildWorkerSlotState.STATUS_FAILED_WAITING
        } ?: return null
        val dayIndex = state.dayWorks.indexOfFirst {
            it.status == DynamicRebuildDayWorkItem.STATUS_RETRY_PENDING
        }.takeIf { it >= 0 }
            ?: state.dayWorks.indexOfFirst {
                it.status == DynamicRebuildDayWorkItem.STATUS_PENDING
            }.takeIf { it >= 0 }
            ?: return null
        val day = state.dayWorks[dayIndex]
        val currentWindow = day.currentWindow()
        day.status = DynamicRebuildDayWorkItem.STATUS_RUNNING
        slot.status =
            if (day.retryCount > 0) {
                DynamicRebuildWorkerSlotState.STATUS_RETRYING
            } else {
                DynamicRebuildWorkerSlotState.STATUS_RUNNING
            }
        slot.dayKey = day.dayKey
        slot.totalSegments = day.totalSegments()
        slot.processedSegments = day.accountedSegments()
        slot.currentRangeLabel = currentWindow?.rangeLabel.orEmpty()
        slot.currentStageLabel = if (day.retryCount > 0) "恢复失败日期" else "等待执行"
        slot.currentStageDetail =
            if (day.retryCount > 0) {
                "准备从失败位置继续第 ${day.retryCount}/${DAY_RETRY_LIMIT} 次续跑"
            } else if (state.isBackfillMode()) {
                "准备补全 ${day.dayKey} 的 ${day.totalSegments()} 条缺失动态"
            } else {
                "准备处理 ${day.dayKey} 的 ${day.totalSegments()} 条动态"
            }
        slot.retryCount = day.retryCount
        slot.retryLimit = DAY_RETRY_LIMIT
        slot.recentStreamChunks.clear()
        state.refreshDerivedFields()
        state.appendRecentLog(
            buildWorkerStageLogLine(
                slot.slotId,
                day.dayKey,
                if (day.retryCount > 0) "恢复失败日期" else "领取日期任务",
                slot.currentStageDetail,
            ),
        )
        persistStateLocked(state)
        logBackfillDiag(
            this,
            "acquireAssignment taskId=${state.taskId} slot=${slot.slotId} dayIndex=$dayIndex " +
                "day=${day.dayKey} status=${day.status} retry=${day.retryCount} " +
                "nextIndex=${day.nextWindowIndex} total=${day.totalSegments()} " +
                "currentWindow=${currentWindow?.let { windowDiag(it.startTime, it.endTime, it.existingSegmentId) } ?: "none"}",
        )
        return WorkerAssignment(slot.slotId, dayIndex)
    }

    private fun markDayCompletedLocked(
        state: DynamicRebuildTaskState,
        dayIndex: Int,
        slotId: Int,
    ) {
        val day = state.dayWorks.getOrNull(dayIndex) ?: return
        val slot = state.workerSlots.firstOrNull { it.slotId == slotId }
        day.nextWindowIndex = day.totalSegments()
        day.processedSegments = day.totalSegments()
        day.failedSegments = 0
        day.status = DynamicRebuildDayWorkItem.STATUS_COMPLETED
        day.lastError = null
        if (slot != null) {
            slot.status = DynamicRebuildWorkerSlotState.STATUS_COMPLETED
            slot.dayKey = day.dayKey
            slot.totalSegments = day.totalSegments()
            slot.processedSegments = day.accountedSegments()
            slot.currentRangeLabel = ""
            slot.currentStageLabel = "当天完成"
            slot.currentStageDetail = if (state.isBackfillMode()) {
                "已补全 ${day.dayKey} 的 ${day.totalSegments()} 条缺失动态"
            } else {
                "已完成 ${day.dayKey} 的 ${day.totalSegments()} 条动态"
            }
            slot.currentSegmentId = 0L
            slot.retryCount = day.retryCount
            slot.retryLimit = DAY_RETRY_LIMIT
        }
        state.refreshDerivedFields()
        persistStateLocked(state)
        logBackfillDiag(
            this,
            "markDayCompleted taskId=${state.taskId} slot=$slotId day=${day.dayKey} " +
                "total=${day.totalSegments()} processed=${day.processedSegments}",
        )
    }

    private fun persistStateLocked(state: DynamicRebuildTaskState) {
        DynamicRebuildTaskStore.save(this, state)
        updateNotification(state)
    }

    private fun buildDayWorkItems(
        windows: List<SegmentSummaryManager.DynamicRebuildWindow>,
    ): List<DynamicRebuildDayWorkItem> {
        if (windows.isEmpty()) return emptyList()
        val grouped = LinkedHashMap<String, MutableList<DynamicRebuildWindowWorkItem>>()
        for (window in windows) {
            val dayKey = formatDayKey(window.startTime)
            val bucket = grouped.getOrPut(dayKey) { mutableListOf() }
            bucket.add(
                DynamicRebuildWindowWorkItem(
                    startTime = window.startTime,
                    endTime = window.endTime,
                    rangeLabel = formatRangeLabel(window.startTime, window.endTime),
                    existingSegmentId = window.existingSegmentId,
                ),
            )
        }
        return grouped.entries.map { (dayKey, dayWindows) ->
            DynamicRebuildDayWorkItem(
                dayKey = dayKey,
                windows = dayWindows,
                status = DynamicRebuildDayWorkItem.STATUS_PENDING,
            )
        }
    }

    private fun reorderBackfillDaysForOverlapSafety(
        dayWorks: MutableList<DynamicRebuildDayWorkItem>,
    ) {
        if (dayWorks.size <= 1) return
        val ordered = dayWorks.sortedBy { day ->
            day.windows.firstOrNull()?.startTime ?: Long.MAX_VALUE
        }
        dayWorks.clear()
        dayWorks.addAll(ordered)
    }

    private fun handleForegroundStartupFailure(
        state: DynamicRebuildTaskState,
        error: Exception,
        stage: String,
        label: String,
        detailPrefix: String,
    ) {
        val errorName = error.javaClass.simpleName.ifBlank { "Exception" }
        val detail = buildString {
            append(detailPrefix)
            append("：")
            append(errorName)
            val message = error.message?.trim().orEmpty()
            if (message.isNotEmpty()) {
                append(" - ")
                append(message)
            }
        }
        state.status = DynamicRebuildTaskState.STATUS_FAILED
        state.lastError = detail
        state.completedAt = System.currentTimeMillis()
        state.updatedAt = state.completedAt
        state.currentStage = stage
        state.currentStageLabel = label
        state.currentStageDetail = detail
        state.appendRecentLog(buildStageLogLine(label, detail))
        DynamicRebuildTaskStore.save(this, state)
        try {
            RuntimeDiagnostics.logSnapshot(
                this,
                TAG,
                stage,
                extras = mapOf(
                    "error" to errorName,
                    "message" to (error.message ?: "-"),
                ),
                force = true,
            )
        } catch (_: Exception) {}
        FileLogger.e(TAG, detail, error)
    }

    private fun finishTask(state: DynamicRebuildTaskState) {
        val text = buildTaskReport(state)
        when (state.status) {
            DynamicRebuildTaskState.STATUS_COMPLETED -> FileLogger.i(STATUS_TAG, text)
            DynamicRebuildTaskState.STATUS_COMPLETED_WITH_FAILURES -> FileLogger.w(STATUS_TAG, text)
            DynamicRebuildTaskState.STATUS_CANCELLED -> FileLogger.w(STATUS_TAG, text)
            DynamicRebuildTaskState.STATUS_FAILED -> FileLogger.e(STATUS_TAG, text)
            else -> FileLogger.i(STATUS_TAG, text)
        }

        try {
            stopForeground(false)
        } catch (_: Exception) {}

        try {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, buildNotification(state))
        } catch (_: Exception) {}

        stopSelf()
    }

    private fun startAsForeground(state: DynamicRebuildTaskState) {
        val notification = buildNotification(state)
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
    }

    private fun updateNotification(state: DynamicRebuildTaskState) {
        try {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, buildNotification(state))
        } catch (_: Exception) {}
    }

    private fun buildNotification(state: DynamicRebuildTaskState): Notification {
        val backfill = state.isBackfillMode()
        val title = when (state.status) {
            DynamicRebuildTaskState.STATUS_PREPARING ->
                if (backfill) "正在准备动态补全" else getString(R.string.dynamic_rebuild_notif_preparing_title)
            DynamicRebuildTaskState.STATUS_COMPLETED ->
                if (backfill) "动态补全完成" else getString(R.string.dynamic_rebuild_notif_done_title)
            DynamicRebuildTaskState.STATUS_COMPLETED_WITH_FAILURES ->
                if (backfill) "动态补全完成" else getString(R.string.dynamic_rebuild_notif_done_title)
            DynamicRebuildTaskState.STATUS_FAILED ->
                if (backfill) "动态补全失败" else getString(R.string.dynamic_rebuild_notif_failed_title)
            DynamicRebuildTaskState.STATUS_CANCELLED ->
                if (backfill) "动态补全已停止" else getString(R.string.dynamic_rebuild_notif_cancelled_title)
            else ->
                if (backfill) "正在补全动态" else getString(R.string.dynamic_rebuild_notif_running_title)
        }

        val detail = when (state.status) {
            DynamicRebuildTaskState.STATUS_PREPARING ->
                if (backfill) "正在扫描历史截图并查找缺失动态" else getString(R.string.dynamic_rebuild_notif_preparing_text)
            DynamicRebuildTaskState.STATUS_COMPLETED ->
                if (state.totalSegments <= 0) {
                    if (backfill) "没有需要补全的动态" else getString(R.string.dynamic_rebuild_notif_done_empty_text)
                } else {
                    if (backfill) {
                        "已补全 ${state.processedSegments} 个缺失动态"
                    } else {
                        getString(
                            R.string.dynamic_rebuild_notif_done_text,
                            state.processedSegments,
                        )
                    }
                }
            DynamicRebuildTaskState.STATUS_COMPLETED_WITH_FAILURES ->
                if (backfill) {
                    "已处理 ${state.processedSegments}/${state.totalSegments} 条缺失动态，失败 ${state.failedSegments} 条，仍有 ${state.failedDayCount()}/${state.totalDays()} 天待继续"
                } else {
                    "已处理 ${state.processedSegments}/${state.totalSegments} 条动态，失败 ${state.failedSegments} 条，仍有 ${state.failedDayCount()}/${state.totalDays()} 天待继续"
                }
            DynamicRebuildTaskState.STATUS_FAILED ->
                state.lastError ?: if (backfill) "补全任务执行失败，请打开动态页查看详情" else getString(R.string.dynamic_rebuild_notif_failed_generic)
            DynamicRebuildTaskState.STATUS_CANCELLED ->
                if (backfill) {
                    "已停止在 ${state.processedSegments}/${state.totalSegments}，可稍后继续补全"
                } else {
                    getString(
                        R.string.dynamic_rebuild_notif_cancelled_text,
                        state.processedSegments,
                        state.totalSegments,
                    )
                }
            else -> {
                val summary =
                    if (backfill) {
                        "正在补全第 ${state.currentWorkOrdinal()}/${state.totalSegments} 条缺失动态（${state.progressPercentText()}）"
                    } else {
                        getString(
                            R.string.dynamic_rebuild_notif_running_text,
                            state.currentWorkOrdinal(),
                            state.totalSegments,
                            state.progressPercentText(),
                        )
                    }
                val activeDays = state.activeDayKeys(limit = state.dayConcurrency)
                val scopeLines = mutableListOf<String>()
                scopeLines.add("并发 ${state.dayConcurrency} 天")
                if (activeDays.isNotEmpty()) {
                    scopeLines.add("当前：${activeDays.joinToString(" / ")}")
                } else if (state.timelineCutoffDayKey.isNotBlank()) {
                    scopeLines.add("排队到：${state.timelineCutoffDayKey}")
                } else {
                    scopeLines.add(
                        if (backfill) "正在扫描缺失动态" else getString(R.string.dynamic_rebuild_notif_running_scope_default)
                    )
                }
                "$summary\n${scopeLines.joinToString(" · ")}"
            }
        }
        val detailWithModel = appendNotificationModelDetail(detail, state)

        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("from_dynamic_rebuild_notification", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(detailWithModel.lineSequence().firstOrNull() ?: detailWithModel)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detailWithModel))
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        when (state.status) {
            DynamicRebuildTaskState.STATUS_PREPARING -> {
                builder.setOngoing(true)
                builder.setProgress(0, 0, true)
            }
            DynamicRebuildTaskState.STATUS_RUNNING,
            DynamicRebuildTaskState.STATUS_PENDING -> {
                builder.setOngoing(true)
                builder.setProgress(
                    state.totalSegments.coerceAtLeast(1),
                    state.processedSegments.coerceAtMost(state.totalSegments.coerceAtLeast(1)),
                    false,
                )
            }
            else -> {
                builder.setOngoing(false)
                builder.setAutoCancel(true)
            }
        }

        return builder.build()
    }

    private fun appendNotificationModelDetail(
        detail: String,
        state: DynamicRebuildTaskState,
    ): String {
        val model = state.aiModel.trim()
        if (model.isEmpty()) return detail
        val modelLine = "模型：$model"
        return if (detail.isBlank()) {
            modelLine
        } else {
            "$detail\n$modelLine"
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.dynamic_rebuild_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.dynamic_rebuild_channel_desc)
            setShowBadge(false)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "screen_memo:dynamic_rebuild",
            ).apply {
                setReferenceCounted(false)
                acquire(60L * 60L * 1000L)
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun buildTaskReport(state: DynamicRebuildTaskState): String {
        val sb = StringBuilder()
        sb.appendLine(if (state.isBackfillMode()) "ScreenMemo 动态补全报告" else "ScreenMemo 动态重建报告")
        sb.appendLine("模式: ${state.taskMode}")
        sb.appendLine("状态: ${state.status}")
        sb.appendLine("开始时间: ${state.startedAt}")
        sb.appendLine("完成时间: ${state.completedAt}")
        sb.appendLine("并发天数: ${state.dayConcurrency}")
        sb.appendLine("总段落数: ${state.totalSegments}")
        sb.appendLine("已处理段落: ${state.processedSegments}")
        sb.appendLine("失败段落: ${state.failedSegments}")
        sb.appendLine("待继续天数: ${state.failedDayCount()}/${state.totalDays()}")
        if (state.targetDayKey.isNotBlank()) {
            sb.appendLine("targetDayKey: ${state.targetDayKey}")
        }
        if (state.aiModel.isNotBlank()) {
            sb.appendLine("model: ${state.aiModel}")
        }
        if (state.currentDayKey.isNotBlank() || state.currentRangeLabel.isNotBlank()) {
            sb.appendLine("当前位置: 第 ${state.currentWorkOrdinal()}/${state.totalSegments} 条 ${state.currentDayKey} ${state.currentRangeLabel}".trim())
        }
        if (state.timelineCutoffDayKey.isNotBlank()) {
            sb.appendLine("timelineCutoffDayKey: ${state.timelineCutoffDayKey}")
        }
        if (state.currentStageLabel.isNotBlank()) {
            sb.appendLine("stage: ${state.currentStageLabel}")
        }
        if (state.currentStageDetail.isNotBlank()) {
            sb.appendLine("stageDetail: ${state.currentStageDetail}")
        }
        if (state.workerSlots.isNotEmpty()) {
            sb.appendLine("workers:")
            state.workerSlots.forEach { slot ->
                sb.appendLine(
                    "- T${slot.slotId} ${slot.status} ${slot.dayKey} ${slot.processedSegments}/${slot.totalSegments} retry=${slot.retryCount}/${slot.retryLimit}",
                )
            }
        }
        if (!state.lastError.isNullOrBlank()) {
            sb.appendLine("lastError: ${state.lastError}")
        }
        return sb.toString().trim()
    }

    private fun recordStage(
        state: DynamicRebuildTaskState,
        stage: String,
        label: String,
        detail: String = "",
        segmentId: Long = 0L,
        forceLog: Boolean = false,
        slotId: Int = 0,
        dayKey: String = "",
        currentRangeLabel: String? = null,
        dayIndex: Int = -1,
    ) {
        val normalizedStage = stage.trim()
        val normalizedLabel = label.trim()
        val normalizedDetail = detail.trim()
        synchronized(stateLock) {
            val slot = state.workerSlots.firstOrNull { it.slotId == slotId }
            val changed =
                forceLog ||
                    state.currentStage != normalizedStage ||
                    state.currentStageLabel != normalizedLabel ||
                    state.currentStageDetail != normalizedDetail ||
                    (segmentId > 0L && state.currentSegmentId != segmentId) ||
                    (slot != null && (
                        slot.currentStageLabel != normalizedLabel ||
                            slot.currentStageDetail != normalizedDetail ||
                            (currentRangeLabel != null && slot.currentRangeLabel != currentRangeLabel)
                    ))
            if (!changed) return
            state.currentStage = normalizedStage
            state.currentStageLabel = normalizedLabel
            state.currentStageDetail = normalizedDetail
            if (segmentId > 0L) {
                state.currentSegmentId = segmentId
            } else if (normalizedStage == "window_done" || normalizedStage == "window_skip_overlap") {
                state.currentSegmentId = 0L
            }
            if (slot != null) {
                slot.dayKey = if (dayKey.isNotBlank()) dayKey else slot.dayKey
                if (currentRangeLabel != null) {
                    slot.currentRangeLabel = currentRangeLabel
                }
                slot.currentStageLabel = normalizedLabel
                slot.currentStageDetail = normalizedDetail
                if (segmentId > 0L) {
                    slot.currentSegmentId = segmentId
                } else if (normalizedStage == "window_done" || normalizedStage == "window_skip_overlap") {
                    slot.currentSegmentId = 0L
                }
                val day = state.dayWorks.getOrNull(dayIndex)
                if (day != null) {
                    slot.totalSegments = day.totalSegments()
                    slot.processedSegments = day.accountedSegments()
                    slot.retryCount = day.retryCount
                    slot.retryLimit = DAY_RETRY_LIMIT
                    if (slot.status != DynamicRebuildWorkerSlotState.STATUS_COMPLETED &&
                        slot.status != DynamicRebuildWorkerSlotState.STATUS_FAILED_WAITING
                    ) {
                        slot.status =
                            if (day.retryCount > 0) {
                                DynamicRebuildWorkerSlotState.STATUS_RETRYING
                            } else {
                                DynamicRebuildWorkerSlotState.STATUS_RUNNING
                            }
                    }
                }
            }
            state.updatedAt = System.currentTimeMillis()
            state.refreshDerivedFields()
            state.appendRecentLog(
                if (slotId > 0 && dayKey.isNotBlank()) {
                    buildWorkerStageLogLine(slotId, dayKey, normalizedLabel, normalizedDetail)
                } else {
                    buildStageLogLine(normalizedLabel, normalizedDetail)
                },
            )
            persistStateLocked(state)
        }
    }

    private fun recordWorkerStreamChunk(
        state: DynamicRebuildTaskState,
        slotId: Int,
        dayKey: String,
        detail: String,
        segmentId: Long = 0L,
        dayIndex: Int = -1,
    ) {
        val normalizedDetail = detail.trim()
        if (normalizedDetail.isEmpty()) return
        synchronized(stateLock) {
            val slot = state.workerSlots.firstOrNull { it.slotId == slotId } ?: return
            if (dayKey.isNotBlank()) {
                slot.dayKey = dayKey
            }
            if (segmentId > 0L) {
                slot.currentSegmentId = segmentId
            }
            val day = state.dayWorks.getOrNull(dayIndex)
            if (day != null) {
                slot.totalSegments = day.totalSegments()
                slot.processedSegments = day.accountedSegments()
                slot.retryCount = day.retryCount
                slot.retryLimit = DAY_RETRY_LIMIT
            }
            if (slot.recentStreamChunks.lastOrNull() == normalizedDetail) {
                return
            }
            slot.recentStreamChunks.add(normalizedDetail)
            while (slot.recentStreamChunks.size > RECENT_STREAM_CHUNK_LIMIT) {
                slot.recentStreamChunks.removeAt(0)
            }
            state.updatedAt = System.currentTimeMillis()
            state.refreshDerivedFields()
            persistStateLocked(state)
        }
    }

    private fun readSegmentDurationSec(): Int {
        val raw = try {
            UserSettingsStorage.getInt(this, UserSettingsKeysNative.SEGMENT_DURATION_SEC, 5 * 60)
        } catch (_: Exception) { 5 * 60 }
        return if (raw <= 0) 5 * 60 else raw.coerceAtLeast(60)
    }

    private fun readSegmentSampleIntervalSec(): Int {
        val raw = try {
            UserSettingsStorage.getInt(this, UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC, 20)
        } catch (_: Exception) { 20 }
        return if (raw <= 0) 20 else raw.coerceAtLeast(5)
    }

    private fun isCancellationRequested(): Boolean {
        return DynamicRebuildTaskStore.load(this)?.status ==
            DynamicRebuildTaskState.STATUS_CANCELLED
    }

    private fun formatDayKey(millis: Long): String {
        if (millis <= 0L) return ""
        return try {
            SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(millis))
        } catch (_: Exception) {
            ""
        }
    }

    private fun formatRangeLabel(startMillis: Long, endMillis: Long): String {
        if (startMillis <= 0L || endMillis <= 0L) return ""
        val fmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        return try {
            "${fmt.format(Date(startMillis))}-${fmt.format(Date(endMillis))}"
        } catch (_: Exception) {
            ""
        }
    }

    private fun windowDiag(startMillis: Long, endMillis: Long, existingSegmentId: Long = 0L): String {
        val segPart = if (existingSegmentId > 0L) " existingSegmentId=$existingSegmentId" else ""
        return "${formatRangeLabel(startMillis, endMillis)}($startMillis-$endMillis)$segPart"
    }
}

private fun buildStageLogLine(label: String, detail: String): String {
    val time = try {
        SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
    } catch (_: Exception) {
        ""
    }
    val body = if (detail.isBlank()) label.trim() else "${label.trim()}：${detail.trim()}"
    return listOf(time.trim(), body.trim()).filter { it.isNotEmpty() }.joinToString(" ")
}

private fun buildWorkerStageLogLine(
    slotId: Int,
    dayKey: String,
    label: String,
    detail: String,
): String {
    val prefix = buildString {
        append("[T")
        append(slotId)
        append("]")
        if (dayKey.isNotBlank()) {
            append("[")
            append(dayKey.trim())
            append("]")
        }
    }
    val body = if (detail.isBlank()) label.trim() else "${label.trim()}：${detail.trim()}"
    val time = try {
        SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
    } catch (_: Exception) {
        ""
    }
    return listOf(time.trim(), prefix, body.trim())
        .filter { it.isNotEmpty() }
        .joinToString(" ")
}

private data class DynamicRebuildWindowWorkItem(
    val startTime: Long,
    val endTime: Long,
    val rangeLabel: String,
    val existingSegmentId: Long = 0L,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("startTime", startTime)
            .put("endTime", endTime)
            .put("rangeLabel", rangeLabel)
            .put("existingSegmentId", existingSegmentId)
    }

    companion object {
        fun fromJson(obj: JSONObject): DynamicRebuildWindowWorkItem {
            return DynamicRebuildWindowWorkItem(
                startTime = obj.optLong("startTime", 0L),
                endTime = obj.optLong("endTime", 0L),
                rangeLabel = obj.optString("rangeLabel", ""),
                existingSegmentId = obj.optLong("existingSegmentId", 0L),
            )
        }
    }

}

private data class DynamicRebuildDayWorkItem(
    val dayKey: String,
    val windows: MutableList<DynamicRebuildWindowWorkItem>,
    var nextWindowIndex: Int = 0,
    var processedSegments: Int = 0,
    var failedSegments: Int = 0,
    var status: String = STATUS_PENDING,
    var retryCount: Int = 0,
    var lastError: String? = null,
) {
    companion object {
        const val STATUS_PENDING = "pending"
        const val STATUS_RUNNING = "running"
        const val STATUS_RETRY_PENDING = "retry_pending"
        const val STATUS_FAILED_WAITING = "failed_waiting"
        const val STATUS_COMPLETED = "completed"

        fun fromJson(obj: JSONObject): DynamicRebuildDayWorkItem {
            val windows = mutableListOf<DynamicRebuildWindowWorkItem>()
            val windowsJson = obj.optJSONArray("windows") ?: JSONArray()
            for (i in 0 until windowsJson.length()) {
                val item = windowsJson.optJSONObject(i) ?: continue
                windows.add(DynamicRebuildWindowWorkItem.fromJson(item))
            }
            return DynamicRebuildDayWorkItem(
                dayKey = obj.optString("dayKey", ""),
                windows = windows,
                nextWindowIndex = obj.optInt("nextWindowIndex", 0),
                processedSegments = obj.optInt("processedSegments", 0),
                failedSegments = obj.optInt("failedSegments", 0),
                status = obj.optString("status", STATUS_PENDING),
                retryCount = obj.optInt("retryCount", 0),
                lastError = obj.optString("lastError", "").takeIf { it.isNotBlank() },
            )
        }
    }

    fun totalSegments(): Int = windows.size

    fun currentWindow(): DynamicRebuildWindowWorkItem? {
        if (nextWindowIndex < 0 || nextWindowIndex >= windows.size) return null
        return windows[nextWindowIndex]
    }

    fun pendingFailureCredit(): Int {
        return if (nextWindowIndex in 0 until windows.size) 1 else 0
    }

    fun accountedSegments(): Int {
        return (processedSegments + failedSegments).coerceIn(0, totalSegments())
    }

    fun normalizeProgressCounters() {
        val total = totalSegments()
        nextWindowIndex = nextWindowIndex.coerceIn(0, total)
        processedSegments = processedSegments.coerceIn(0, total)
        failedSegments =
            if (status == STATUS_FAILED_WAITING) {
                failedSegments
                    .coerceAtLeast(pendingFailureCredit())
                    .coerceIn(0, (total - processedSegments).coerceAtLeast(0))
            } else {
                0
            }
    }

    fun toJson(): JSONObject {
        val windowsJson = JSONArray()
        windows.forEach { windowsJson.put(it.toJson()) }
        return JSONObject()
            .put("dayKey", dayKey)
            .put("nextWindowIndex", nextWindowIndex)
            .put("processedSegments", processedSegments)
            .put("failedSegments", failedSegments)
            .put("status", status)
            .put("retryCount", retryCount)
            .put("lastError", lastError ?: JSONObject.NULL)
            .put("windows", windowsJson)
    }

}

private data class DynamicRebuildWorkerSlotState(
    val slotId: Int,
    var status: String = STATUS_IDLE,
    var dayKey: String = "",
    var totalSegments: Int = 0,
    var processedSegments: Int = 0,
    var currentRangeLabel: String = "",
    var currentStageLabel: String = "",
    var currentStageDetail: String = "",
    var currentSegmentId: Long = 0L,
    var retryCount: Int = 0,
    var retryLimit: Int = 0,
    var recentStreamChunks: MutableList<String> = mutableListOf(),
) {
    companion object {
        const val STATUS_IDLE = "idle"
        const val STATUS_RUNNING = "running"
        const val STATUS_RETRYING = "retrying"
        const val STATUS_COMPLETED = "completed"
        const val STATUS_FAILED_WAITING = "failed_waiting"

        fun fromJson(obj: JSONObject): DynamicRebuildWorkerSlotState {
            return DynamicRebuildWorkerSlotState(
                slotId = obj.optInt("slotId", 0),
                status = obj.optString("status", STATUS_IDLE),
                dayKey = obj.optString("dayKey", ""),
                totalSegments = obj.optInt("totalSegments", 0),
                processedSegments = obj.optInt("processedSegments", 0),
                currentRangeLabel = obj.optString("currentRangeLabel", ""),
                currentStageLabel = obj.optString("currentStageLabel", ""),
                currentStageDetail = obj.optString("currentStageDetail", ""),
                currentSegmentId = obj.optLong("currentSegmentId", 0L),
                retryCount = obj.optInt("retryCount", 0),
                retryLimit = obj.optInt("retryLimit", 0),
                recentStreamChunks = mutableListOf<String>().apply {
                    val recentChunksJson = obj.optJSONArray("recentStreamChunks") ?: JSONArray()
                    for (i in 0 until recentChunksJson.length()) {
                        val value = recentChunksJson.optString(i, "").trim()
                        if (value.isNotEmpty()) {
                            add(value)
                        }
                    }
                    while (size > RECENT_STREAM_CHUNK_LIMIT) {
                        removeAt(0)
                    }
                },
            )
        }
    }

    fun toJson(): JSONObject {
        val recentChunks = JSONArray()
        recentStreamChunks.forEach { recentChunks.put(it) }
        return JSONObject()
            .put("slotId", slotId)
            .put("status", status)
            .put("dayKey", dayKey)
            .put("totalSegments", totalSegments)
            .put("processedSegments", processedSegments)
            .put("currentRangeLabel", currentRangeLabel)
            .put("currentStageLabel", currentStageLabel)
            .put("currentStageDetail", currentStageDetail)
            .put("currentSegmentId", currentSegmentId)
            .put("retryCount", retryCount)
            .put("retryLimit", retryLimit)
            .put("recentStreamChunks", recentChunks)
    }
}

private data class WorkerAssignment(
    val slotId: Int,
    val dayIndex: Int,
)

private data class DayProcessingSnapshot(
    val dayKey: String,
    val rangeLabel: String,
    val windowStart: Long,
    val windowEnd: Long,
    val existingSegmentId: Long,
    val processedSegments: Int,
    val totalSegments: Int,
    val retryCount: Int,
    val currentSegmentId: Long,
)

private enum class DayRunOutcome {
    COMPLETED,
    RETRY_PENDING,
    FAILED_WAITING,
    CANCELLED,
    FATAL,
}

private data class DayRunResult(
    val slotId: Int,
    val dayIndex: Int,
    val outcome: DayRunOutcome,
    val fatalError: Exception? = null,
)

private data class DynamicRebuildTaskState(
    val taskId: String,
    var taskMode: String,
    var status: String,
    val startedAt: Long,
    var updatedAt: Long,
    var completedAt: Long,
    var dayConcurrency: Int,
    var totalSegments: Int,
    var processedSegments: Int,
    var failedSegments: Int,
    var currentDayKey: String,
    var targetDayKey: String,
    var timelineCutoffDayKey: String,
    var currentSegmentId: Long,
    var currentRangeLabel: String,
    var currentStage: String,
    var currentStageLabel: String,
    var currentStageDetail: String,
    var lastError: String?,
    var segmentDurationSec: Int,
    var segmentSampleIntervalSec: Int,
    var aiBaseUrl: String,
    var aiApiKey: String,
    var aiModel: String,
    var aiProviderType: String?,
    var aiChatPath: String?,
    var aiProviderId: Int?,
    val recentLogs: MutableList<String>,
    val dayWorks: MutableList<DynamicRebuildDayWorkItem>,
    val workerSlots: MutableList<DynamicRebuildWorkerSlotState>,
) {
    companion object {
        const val STATUS_IDLE = "idle"
        const val STATUS_PREPARING = "preparing"
        const val STATUS_PENDING = "pending"
        const val STATUS_RUNNING = "running"
        const val STATUS_COMPLETED = "completed"
        const val STATUS_COMPLETED_WITH_FAILURES = "completed_with_failures"
        const val STATUS_FAILED = "failed"
        const val STATUS_CANCELLED = "cancelled"

        fun idle(): DynamicRebuildTaskState {
            return DynamicRebuildTaskState(
                taskId = "",
                taskMode = "rebuild",
                status = STATUS_IDLE,
                startedAt = 0L,
                updatedAt = 0L,
                completedAt = 0L,
                dayConcurrency = 1,
                totalSegments = 0,
                processedSegments = 0,
                failedSegments = 0,
                currentDayKey = "",
                targetDayKey = "",
                timelineCutoffDayKey = "",
                currentSegmentId = 0L,
                currentRangeLabel = "",
                currentStage = "",
                currentStageLabel = "",
                currentStageDetail = "",
                lastError = null,
                segmentDurationSec = 0,
                segmentSampleIntervalSec = 0,
                aiBaseUrl = "",
                aiApiKey = "",
                aiModel = "",
                aiProviderType = null,
                aiChatPath = null,
                aiProviderId = null,
                recentLogs = mutableListOf(),
                dayWorks = mutableListOf(),
                workerSlots = mutableListOf(),
            )
        }
    }

    fun isRecoverable(): Boolean {
        return status == STATUS_PREPARING || status == STATUS_PENDING || status == STATUS_RUNNING
    }

    fun isBackfillMode(): Boolean = taskMode == "backfill"

    fun hasPreparedWorks(): Boolean = dayWorks.isNotEmpty() || totalSegments > 0

    fun canContinue(): Boolean {
        if (taskId.isBlank() || isRecoverable() || status == STATUS_IDLE) {
            return false
        }

        val hasRemainingByDays =
            dayWorks.any { it.status != DynamicRebuildDayWorkItem.STATUS_COMPLETED }
        val hasRemainingByProgress = totalSegments > 0 && processedSegments < totalSegments
        if (hasRemainingByDays || hasRemainingByProgress) return true

        // 停止/失败发生在准备阶段时，dayWorks 可能还没生成，但仍应允许继续。
        return (status == STATUS_FAILED ||
            status == STATUS_CANCELLED ||
            status == STATUS_COMPLETED_WITH_FAILURES) && dayWorks.isEmpty()
    }

    fun progressPercentText(): String {
        if (totalSegments <= 0) {
            return if (status == STATUS_COMPLETED) "100%" else "0%"
        }
        val ratio = processedSegments.toDouble() / totalSegments.toDouble()
        return String.format(Locale.US, "%.1f%%", (ratio * 100.0).coerceIn(0.0, 100.0))
    }

    fun currentWorkOrdinal(): Int {
        if (totalSegments <= 0) return 0
        return when {
            status == STATUS_COMPLETED -> totalSegments
            processedSegments >= totalSegments -> totalSegments
            else -> (processedSegments + 1).coerceAtMost(totalSegments)
        }
    }

    fun totalDays(): Int = dayWorks.size

    fun completedDayCount(): Int {
        return dayWorks.count { it.status == DynamicRebuildDayWorkItem.STATUS_COMPLETED }
    }

    fun failedDayCount(): Int {
        return dayWorks.count { it.status == DynamicRebuildDayWorkItem.STATUS_FAILED_WAITING }
    }

    fun pendingDayCount(): Int {
        return dayWorks.count {
            it.status == DynamicRebuildDayWorkItem.STATUS_PENDING ||
                it.status == DynamicRebuildDayWorkItem.STATUS_RUNNING ||
                it.status == DynamicRebuildDayWorkItem.STATUS_RETRY_PENDING
        }
    }

    fun parallelismForRun(): Int {
        return dayConcurrency.coerceIn(1, 10).coerceAtMost(pendingDayCount().coerceAtLeast(1))
    }

    fun appendRecentLog(entry: String) {
        val normalized = entry.trim()
        if (normalized.isEmpty()) return
        recentLogs.add(normalized)
        while (recentLogs.size > 160) {
            recentLogs.removeAt(0)
        }
    }

    fun requireAiConfig(): AISettingsNative.AIConfig {
        if (aiBaseUrl.isBlank() || aiApiKey.isBlank() || aiModel.isBlank()) {
            throw IllegalStateException("缺少 AI 配置")
        }
        return AISettingsNative.AIConfig(
            baseUrl = aiBaseUrl,
            apiKey = aiApiKey,
            model = aiModel,
            providerType = aiProviderType,
            chatPath = aiChatPath,
            providerId = aiProviderId,
        )
    }

    fun prepareForExecution() {
        taskMode = if (taskMode == "backfill") "backfill" else "rebuild"
        dayConcurrency = dayConcurrency.coerceIn(1, 10)
        while (workerSlots.size < dayConcurrency) {
            workerSlots.add(
                DynamicRebuildWorkerSlotState(
                    slotId = workerSlots.size + 1,
                    retryLimit = 3,
                ),
            )
        }
        if (workerSlots.size > dayConcurrency) {
            workerSlots.subList(dayConcurrency, workerSlots.size).clear()
        }
        workerSlots.forEach { slot ->
            if (slot.status == DynamicRebuildWorkerSlotState.STATUS_RUNNING ||
                slot.status == DynamicRebuildWorkerSlotState.STATUS_RETRYING
            ) {
                slot.status = DynamicRebuildWorkerSlotState.STATUS_IDLE
                slot.currentRangeLabel = ""
                slot.currentStageLabel = ""
                slot.currentStageDetail = ""
                slot.currentSegmentId = 0L
            }
            slot.retryLimit = 3
        }
        dayWorks.forEach { day ->
            if (day.status == DynamicRebuildDayWorkItem.STATUS_RUNNING) {
                day.status = DynamicRebuildDayWorkItem.STATUS_PENDING
            }
            day.normalizeProgressCounters()
        }
        refreshDerivedFields()
    }

    fun refreshDerivedFields() {
        dayWorks.forEach { day -> day.normalizeProgressCounters() }
        totalSegments = dayWorks.sumOf { it.totalSegments() }
        processedSegments = dayWorks.sumOf { it.accountedSegments() }
        failedSegments = dayWorks.sumOf { it.failedSegments }
        val primarySlot = workerSlots.firstOrNull {
            it.status == DynamicRebuildWorkerSlotState.STATUS_RUNNING ||
                it.status == DynamicRebuildWorkerSlotState.STATUS_RETRYING
        }
        currentDayKey = primarySlot?.dayKey ?: nextVisibleDayKey()
        currentRangeLabel = primarySlot?.currentRangeLabel.orEmpty()
        currentSegmentId = primarySlot?.currentSegmentId ?: 0L
        timelineCutoffDayKey = computeTimelineCutoffDayKey()
    }

    fun activeDayKeys(limit: Int): List<String> {
        if (limit <= 0) return emptyList()
        return workerSlots.asSequence()
            .filter {
                it.status == DynamicRebuildWorkerSlotState.STATUS_RUNNING ||
                    it.status == DynamicRebuildWorkerSlotState.STATUS_RETRYING
            }
            .map { it.dayKey.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .sortedDescending()
            .take(limit)
            .toList()
    }

    private fun nextVisibleDayKey(): String {
        return dayWorks.asSequence()
            .filter {
                it.status != DynamicRebuildDayWorkItem.STATUS_COMPLETED &&
                    it.dayKey.isNotBlank()
            }
            .map { it.dayKey }
            .sorted()
            .firstOrNull()
            .orEmpty()
    }

    private fun computeTimelineCutoffDayKey(): String {
        val active = activeDayKeys(limit = dayConcurrency)
        if (active.isNotEmpty()) return active.maxOrNull().orEmpty()
        return nextVisibleDayKey()
    }

    fun toMap(): Map<String, Any?> {
        return hashMapOf(
            "taskId" to taskId,
            "taskMode" to taskMode,
            "status" to status,
            "startedAt" to startedAt,
            "updatedAt" to updatedAt,
            "completedAt" to completedAt,
            "dayConcurrency" to dayConcurrency,
            "totalSegments" to totalSegments,
            "processedSegments" to processedSegments,
            "failedSegments" to failedSegments,
            "totalDays" to totalDays(),
            "completedDays" to completedDayCount(),
            "pendingDays" to pendingDayCount(),
            "failedDays" to failedDayCount(),
            "currentDayKey" to currentDayKey,
            "targetDayKey" to targetDayKey,
            "timelineCutoffDayKey" to timelineCutoffDayKey,
            "currentSegmentId" to currentSegmentId,
            "currentRangeLabel" to currentRangeLabel,
            "currentStage" to currentStage,
            "currentStageLabel" to currentStageLabel,
            "currentStageDetail" to currentStageDetail,
            "lastError" to lastError,
            "isActive" to isRecoverable(),
            "progressPercent" to progressPercentText(),
            "aiModel" to aiModel,
            "recentLogs" to recentLogs.toList(),
            "workers" to workerSlots.map {
                hashMapOf(
                    "slotId" to it.slotId,
                    "status" to it.status,
                    "dayKey" to it.dayKey,
                    "totalSegments" to it.totalSegments,
                    "processedSegments" to it.processedSegments,
                    "currentRangeLabel" to it.currentRangeLabel,
                    "currentStageLabel" to it.currentStageLabel,
                    "currentStageDetail" to it.currentStageDetail,
                    "currentSegmentId" to it.currentSegmentId,
                    "retryCount" to it.retryCount,
                    "retryLimit" to it.retryLimit,
                    "recentStreamChunks" to it.recentStreamChunks.toList(),
                )
            },
        )
    }
}

private object DynamicRebuildTaskStore {
    private const val PREFS_NAME = "dynamic_rebuild_task_state"
    private const val KEY_TASK_JSON = "task_json"
    private const val DEFAULT_DAY_CONCURRENCY = 1
    private const val MAX_DAY_CONCURRENCY = 10
    private const val DEFAULT_RETRY_LIMIT = 3

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    @Synchronized
    fun load(context: Context): DynamicRebuildTaskState? {
        val raw = prefs(context).getString(KEY_TASK_JSON, null)?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return try {
            val obj = JSONObject(raw)
            val recentLogs = mutableListOf<String>()
            val recentLogsJson = obj.optJSONArray("recentLogs") ?: JSONArray()
            for (i in 0 until recentLogsJson.length()) {
                val value = recentLogsJson.optString(i, "").trim()
                if (value.isNotEmpty()) {
                    recentLogs.add(value)
                }
            }
            val dayConcurrency =
                obj.optInt("dayConcurrency", DEFAULT_DAY_CONCURRENCY)
                    .coerceIn(DEFAULT_DAY_CONCURRENCY, MAX_DAY_CONCURRENCY)
            val dayWorks = loadDayWorks(obj)
            val workerSlots = loadWorkerSlots(obj, dayConcurrency)
            DynamicRebuildTaskState(
                taskId = obj.optString("taskId", ""),
                taskMode = when (obj.optString("taskMode", "rebuild").trim().lowercase(Locale.US)) {
                    "backfill", "complete", "completion", "fill_missing" -> "backfill"
                    else -> "rebuild"
                },
                status = obj.optString("status", DynamicRebuildTaskState.STATUS_IDLE),
                startedAt = obj.optLong("startedAt", 0L),
                updatedAt = obj.optLong("updatedAt", 0L),
                completedAt = obj.optLong("completedAt", 0L),
                dayConcurrency = dayConcurrency,
                totalSegments = obj.optInt("totalSegments", dayWorks.sumOf { it.totalSegments() }),
                processedSegments = obj.optInt("processedSegments", 0),
                failedSegments = obj.optInt("failedSegments", 0),
                currentDayKey = obj.optString("currentDayKey", ""),
                targetDayKey = obj.optString("targetDayKey", ""),
                timelineCutoffDayKey = obj.optString("timelineCutoffDayKey", ""),
                currentSegmentId = obj.optLong("currentSegmentId", 0L),
                currentRangeLabel = obj.optString("currentRangeLabel", ""),
                currentStage = obj.optString("currentStage", ""),
                currentStageLabel = obj.optString("currentStageLabel", ""),
                currentStageDetail = obj.optString("currentStageDetail", ""),
                lastError = obj.optString("lastError", "").takeIf { it.isNotBlank() },
                segmentDurationSec = obj.optInt("segmentDurationSec", 0),
                segmentSampleIntervalSec = obj.optInt("segmentSampleIntervalSec", 0),
                aiBaseUrl = obj.optString("aiBaseUrl", ""),
                aiApiKey = obj.optString("aiApiKey", ""),
                aiModel = obj.optString("aiModel", ""),
                aiProviderType = obj.optString("aiProviderType", "").takeIf { it.isNotBlank() },
                aiChatPath = obj.optString("aiChatPath", "").takeIf { it.isNotBlank() },
                aiProviderId = if (obj.has("aiProviderId") && !obj.isNull("aiProviderId")) obj.optInt("aiProviderId") else null,
                recentLogs = recentLogs,
                dayWorks = dayWorks,
                workerSlots = workerSlots,
            ).also { state ->
                state.dayConcurrency =
                    state.dayConcurrency.coerceIn(DEFAULT_DAY_CONCURRENCY, MAX_DAY_CONCURRENCY)
                if (state.workerSlots.isEmpty()) {
                    repeat(state.dayConcurrency) { index ->
                        state.workerSlots.add(
                            DynamicRebuildWorkerSlotState(
                                slotId = index + 1,
                                retryLimit = DEFAULT_RETRY_LIMIT,
                            ),
                        )
                    }
                }
                state.refreshDerivedFields()
            }
        } catch (e: Exception) {
            FileLogger.e("DynamicRebuildTaskStore", "读取动态重建任务状态失败", e)
            null
        }
    }

    @Synchronized
    fun save(context: Context, state: DynamicRebuildTaskState) {
        state.refreshDerivedFields()
        val dayWorks = JSONArray()
        val workerSlots = JSONArray()
        val recentLogs = JSONArray()
        state.dayWorks.forEach { dayWorks.put(it.toJson()) }
        state.workerSlots.forEach { workerSlots.put(it.toJson()) }
        state.recentLogs.forEach { recentLogs.put(it) }
        val obj = JSONObject()
            .put("taskId", state.taskId)
            .put("taskMode", state.taskMode)
            .put("status", state.status)
            .put("startedAt", state.startedAt)
            .put("updatedAt", state.updatedAt)
            .put("completedAt", state.completedAt)
            .put("dayConcurrency", state.dayConcurrency)
            .put("totalSegments", state.totalSegments)
            .put("processedSegments", state.processedSegments)
            .put("failedSegments", state.failedSegments)
            .put("currentDayKey", state.currentDayKey)
            .put("targetDayKey", state.targetDayKey)
            .put("timelineCutoffDayKey", state.timelineCutoffDayKey)
            .put("currentSegmentId", state.currentSegmentId)
            .put("currentRangeLabel", state.currentRangeLabel)
            .put("currentStage", state.currentStage)
            .put("currentStageLabel", state.currentStageLabel)
            .put("currentStageDetail", state.currentStageDetail)
            .put("lastError", state.lastError ?: JSONObject.NULL)
            .put("segmentDurationSec", state.segmentDurationSec)
            .put("segmentSampleIntervalSec", state.segmentSampleIntervalSec)
            .put("aiBaseUrl", state.aiBaseUrl)
            .put("aiApiKey", state.aiApiKey)
            .put("aiModel", state.aiModel)
            .put("aiProviderType", state.aiProviderType ?: JSONObject.NULL)
            .put("aiChatPath", state.aiChatPath ?: JSONObject.NULL)
            .put("aiProviderId", state.aiProviderId ?: JSONObject.NULL)
            .put("recentLogs", recentLogs)
            .put("dayWorks", dayWorks)
            .put("workerSlots", workerSlots)
        prefs(context).edit().putString(KEY_TASK_JSON, obj.toString()).commit()
    }

    @Synchronized
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_TASK_JSON).commit()
    }

    private fun loadDayWorks(obj: JSONObject): MutableList<DynamicRebuildDayWorkItem> {
        val dayWorks = mutableListOf<DynamicRebuildDayWorkItem>()
        val dayWorksJson = obj.optJSONArray("dayWorks") ?: JSONArray()
        for (i in 0 until dayWorksJson.length()) {
            val item = dayWorksJson.optJSONObject(i) ?: continue
            dayWorks.add(DynamicRebuildDayWorkItem.fromJson(item))
        }
        if (dayWorks.isNotEmpty()) {
            dayWorks.forEach { day ->
                day.normalizeProgressCounters()
            }
            return dayWorks
        }
        return migrateLegacyWorks(obj)
    }

    private fun loadWorkerSlots(
        obj: JSONObject,
        dayConcurrency: Int,
    ): MutableList<DynamicRebuildWorkerSlotState> {
        val slots = mutableListOf<DynamicRebuildWorkerSlotState>()
        val workerSlotsJson = obj.optJSONArray("workerSlots") ?: JSONArray()
        for (i in 0 until workerSlotsJson.length()) {
            val item = workerSlotsJson.optJSONObject(i) ?: continue
            val slot = DynamicRebuildWorkerSlotState.fromJson(item)
            if (slot.slotId > 0) {
                slot.retryLimit =
                    if (slot.retryLimit > 0) slot.retryLimit else DEFAULT_RETRY_LIMIT
                slots.add(slot)
            }
        }
        while (slots.size < dayConcurrency) {
            slots.add(
                DynamicRebuildWorkerSlotState(
                    slotId = slots.size + 1,
                    retryLimit = DEFAULT_RETRY_LIMIT,
                ),
            )
        }
        if (slots.size > dayConcurrency) {
            slots.subList(dayConcurrency, slots.size).clear()
        }
        return slots
    }

    private fun migrateLegacyWorks(obj: JSONObject): MutableList<DynamicRebuildDayWorkItem> {
        val worksJson = obj.optJSONArray("works") ?: JSONArray()
        if (worksJson.length() <= 0) return mutableListOf()

        val windows = mutableListOf<DynamicRebuildWindowWorkItem>()
        for (i in 0 until worksJson.length()) {
            val item = worksJson.optJSONObject(i) ?: continue
            val startTime =
                item.optLong(
                    "startTime",
                    item.optLong("windowStart", item.optLong("start", 0L)),
                )
            val endTime =
                item.optLong(
                    "endTime",
                    item.optLong("windowEnd", item.optLong("end", 0L)),
                )
            if (startTime <= 0L || endTime <= startTime) continue
            val rangeLabel = item.optString("rangeLabel", "").trim().ifEmpty {
                legacyFormatRangeLabel(startTime, endTime)
            }
            val existingSegmentId = item.optLong("existingSegmentId", 0L)
            windows.add(
                DynamicRebuildWindowWorkItem(
                    startTime = startTime,
                    endTime = endTime,
                    rangeLabel = rangeLabel,
                    existingSegmentId = existingSegmentId,
                ),
            )
        }
        if (windows.isEmpty()) return mutableListOf()

        val migrated = groupLegacyWindowsByDay(windows)
        val currentWorkIndex =
            obj.optInt("currentWorkIndex", obj.optInt("processedSegments", 0))
                .coerceIn(0, windows.size)
        val status = obj.optString("status", DynamicRebuildTaskState.STATUS_IDLE)
        var completedBefore = 0
        migrated.forEach { day ->
            val total = day.totalSegments()
            val completedForDay = (currentWorkIndex - completedBefore).coerceIn(0, total)
            day.nextWindowIndex = completedForDay
            day.processedSegments = completedForDay
            day.retryCount = 0
            day.lastError = null
            day.status = when {
                completedForDay >= total -> DynamicRebuildDayWorkItem.STATUS_COMPLETED
                status == DynamicRebuildTaskState.STATUS_COMPLETED ->
                    DynamicRebuildDayWorkItem.STATUS_COMPLETED
                else -> DynamicRebuildDayWorkItem.STATUS_PENDING
            }
            completedBefore += total
        }
        return migrated
    }

    private fun groupLegacyWindowsByDay(
        windows: List<DynamicRebuildWindowWorkItem>,
    ): MutableList<DynamicRebuildDayWorkItem> {
        val grouped = LinkedHashMap<String, MutableList<DynamicRebuildWindowWorkItem>>()
        windows.forEach { window ->
            val dayKey = legacyFormatDayKey(window.startTime)
            grouped.getOrPut(dayKey) { mutableListOf() }.add(window)
        }
        return grouped.entries.map { (dayKey, items) ->
            DynamicRebuildDayWorkItem(
                dayKey = dayKey,
                windows = items,
                status = DynamicRebuildDayWorkItem.STATUS_PENDING,
            )
        }.toMutableList()
    }

    private fun legacyFormatDayKey(millis: Long): String {
        if (millis <= 0L) return ""
        return try {
            SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(millis))
        } catch (_: Exception) {
            ""
        }
    }

    private fun legacyFormatRangeLabel(startMillis: Long, endMillis: Long): String {
        if (startMillis <= 0L || endMillis <= 0L) return ""
        val formatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        return try {
            "${formatter.format(Date(startMillis))}-${formatter.format(Date(endMillis))}"
        } catch (_: Exception) {
            ""
        }
    }
}
