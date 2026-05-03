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
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
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

        fun startOrResumeTask(
            context: Context,
            resumeExisting: Boolean = false,
            dayConcurrency: Int? = null,
        ): Map<String, Any?> {
            val appCtx = try { context.applicationContext } catch (_: Exception) { context }
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
                        DynamicRebuildDayWorkItem.STATUS_FAILED_WAITING ->
                            day.status = DynamicRebuildDayWorkItem.STATUS_RETRY_PENDING
                        DynamicRebuildDayWorkItem.STATUS_RUNNING ->
                            day.status = DynamicRebuildDayWorkItem.STATUS_PENDING
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
                current.currentStageLabel = "继续重建"
                current.currentStageDetail =
                    "已重新读取当前模型 ${aiConfig.model}，沿用现有进度继续处理"
                current.appendRecentLog(
                    buildStageLogLine(
                        "继续重建",
                        "已重新读取当前模型 ${aiConfig.model}，沿用现有进度继续处理",
                    ),
                )
                current.refreshDerivedFields()
                DynamicRebuildTaskStore.save(appCtx, current)
                startService(appCtx, ACTION_RESUME)
                return current.toMap()
            }

            val now = System.currentTimeMillis()
            val next = DynamicRebuildTaskState(
                taskId = "dynamic_rebuild_$now",
                status = DynamicRebuildTaskState.STATUS_PREPARING,
                startedAt = now,
                updatedAt = now,
                completedAt = 0L,
                dayConcurrency = normalizedConcurrency,
                totalSegments = 0,
                processedSegments = 0,
                failedSegments = 0,
                currentDayKey = "",
                timelineCutoffDayKey = "",
                currentSegmentId = 0L,
                currentRangeLabel = "",
                currentStage = "queued",
                currentStageLabel = "等待后台启动",
                currentStageDetail = "任务已创建，等待后台服务开始准备",
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
                        "等待后台启动",
                        "任务已创建，等待后台服务开始准备",
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
            current.currentStageDetail = "已停止后台重建，当前进度可稍后继续"
            current.appendRecentLog(
                buildStageLogLine(
                    "已停止",
                    "已停止后台重建，当前进度可稍后继续",
                ),
            )
            DynamicRebuildTaskStore.save(context, current)
            SegmentSummaryManager.cancelDynamicRebuildInFlightRequests("user_stop")
            startService(context, ACTION_CANCEL)
            return current.toMap()
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
                detail = "已进入按天并发重建流程",
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
                label = "开始按天并发重建",
                detail = "按天分组处理，最多 ${state.dayConcurrency} 天同时执行",
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
        recordStage(
            state = state,
            stage = "prepare_worklist",
            label = "生成按天清单",
            detail = "按截图时间顺序计算全量重建范围，并按日期分组",
        )
        val windows = SegmentSummaryManager.buildFullRebuildWorklist(this, durationSec)
        val dayWorks = buildDayWorkItems(windows)
        val aiConfig = if (windows.isNotEmpty()) {
            recordStage(
                state = state,
                stage = "prepare_ai_config",
                label = "读取 AI 配置",
                detail = "准备动态重建所需的模型配置",
            )
            AISettingsNative.readConfigSnapshot(this, "segments")
        } else {
            null
        }

        recordStage(
            state = state,
            stage = "prepare_reset",
            label = "清空旧动态数据",
            detail = "删除旧的动态、总结与样本，准备重建",
        )
        SegmentDatabaseHelper.resetAllDynamicRebuildArtifacts(this)

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
            state.currentStageDetail = "没有找到可重建的动态"
            state.appendRecentLog(
                buildStageLogLine(
                    "准备完成",
                    "没有找到可重建的动态",
                ),
            )
            synchronized(stateLock) {
                persistStateLocked(state)
            }
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
                "共 ${state.totalSegments} 条动态，覆盖 ${state.totalDays()} 天，并发 ${state.dayConcurrency} 天",
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
        if (parallelism <= 0) {
            return finalizeTaskState(state)
        }

        val dayExecutor = Executors.newFixedThreadPool(parallelism)
        val completion = ExecutorCompletionService<DayRunResult>(dayExecutor)
        var inFlight = 0
        try {
            inFlight += submitAvailableDayAssignments(state, completion)
            while (inFlight > 0) {
                val future = completion.take()
                val result = future.get()
                inFlight -= 1
                if (result.outcome == DayRunOutcome.FATAL) {
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
                    inFlight += submitAvailableDayAssignments(state, completion)
                }
            }
        } finally {
            dayExecutor.shutdownNow()
        }

        if (isCancellationRequested()) {
            return markCancelled(state, "已中断当前 AI 请求，后台任务停止")
        }
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
            completion.submit {
                processDayAssignment(
                    state = state,
                    slotId = assignment.slotId,
                    dayIndex = assignment.dayIndex,
                )
            }
            submitted += 1
        }
        return submitted
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
                    processedSegments = day.processedSegments,
                    totalSegments = day.totalSegments(),
                    retryCount = day.retryCount,
                    currentSegmentId = state.workerSlots.firstOrNull { it.slotId == slotId }
                        ?.currentSegmentId ?: 0L,
                )
            } ?: return DayRunResult(slotId, dayIndex, DayRunOutcome.COMPLETED)

            recordStage(
                state = state,
                stage = "window_start",
                label = if (snapshot.retryCount > 0) "继续处理失败日期" else "开始处理当天动态",
                detail =
                    "第 ${snapshot.processedSegments + 1}/${snapshot.totalSegments} 条 · ${snapshot.dayKey} ${snapshot.rangeLabel}".trim(),
                slotId = slotId,
                dayKey = snapshot.dayKey,
                currentRangeLabel = snapshot.rangeLabel,
                dayIndex = dayIndex,
            )

            try {
                SegmentSummaryManager.rebuildWindowStrict(
                    ctx = this,
                    windowStart = snapshot.windowStart,
                    windowEnd = snapshot.windowEnd,
                    durationSec = state.segmentDurationSec,
                    sampleIntervalSec = state.segmentSampleIntervalSec,
                    aiConfig = aiConfig,
                    existingSegmentId = snapshot.currentSegmentId,
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
                val dayCompleted = synchronized(stateLock) {
                    val day = state.dayWorks.getOrNull(dayIndex)
                        ?: return@synchronized false
                    if (day.nextWindowIndex < day.totalSegments()) {
                        day.nextWindowIndex += 1
                    }
                    day.processedSegments = day.nextWindowIndex.coerceAtMost(day.totalSegments())
                    day.lastError = null
                    val slot = state.workerSlots.firstOrNull { it.slotId == slotId }
                    if (slot != null) {
                        slot.currentSegmentId = 0L
                        slot.totalSegments = day.totalSegments()
                        slot.processedSegments = day.processedSegments
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
                if (dayCompleted) {
                    recordStage(
                        state = state,
                        stage = "day_completed",
                        label = "当天完成",
                        detail = "已完成 ${snapshot.dayKey} 的 ${snapshot.totalSegments} 条动态",
                        slotId = slotId,
                        dayKey = snapshot.dayKey,
                        dayIndex = dayIndex,
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
                if (e.segmentId > 0L) {
                    synchronized(stateLock) {
                        state.workerSlots.firstOrNull { it.slotId == slotId }
                            ?.currentSegmentId = e.segmentId
                        persistStateLocked(state)
                    }
                }
                return DayRunResult(slotId, dayIndex, DayRunOutcome.CANCELLED)
            } catch (e: SegmentSummaryManager.DynamicRebuildStepException) {
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
        val outcome = synchronized(stateLock) {
            val day = state.dayWorks.getOrNull(dayIndex)
                ?: return@synchronized DayRunOutcome.FATAL
            val slot = state.workerSlots.firstOrNull { it.slotId == slotId }
            day.lastError = errorMessage
            day.retryCount += 1
            if (segmentId > 0L && slot != null) {
                slot.currentSegmentId = segmentId
            }
            if (day.retryCount < DAY_RETRY_LIMIT) {
                day.status = DynamicRebuildDayWorkItem.STATUS_RETRY_PENDING
                if (slot != null) {
                    slot.status = DynamicRebuildWorkerSlotState.STATUS_FAILED_WAITING
                    slot.currentStageLabel = "等待自动续跑"
                    slot.currentStageDetail = "失败后等待空闲线程继续第 ${day.retryCount}/${DAY_RETRY_LIMIT} 次续跑"
                }
                state.lastError = errorMessage
                state.refreshDerivedFields()
                persistStateLocked(state)
                DayRunOutcome.RETRY_PENDING
            } else {
                day.status = DynamicRebuildDayWorkItem.STATUS_FAILED_WAITING
                if (slot != null) {
                    slot.status = DynamicRebuildWorkerSlotState.STATUS_FAILED_WAITING
                    slot.currentStageLabel = "等待手动继续"
                    slot.currentStageDetail = "已达到自动续跑上限 ${DAY_RETRY_LIMIT} 次"
                }
                state.lastError = errorMessage
                state.refreshDerivedFields()
                persistStateLocked(state)
                DayRunOutcome.FAILED_WAITING
            }
        }
        recordStage(
            state = state,
            stage = "day_failed",
            label = if (outcome == DayRunOutcome.RETRY_PENDING) "当天失败，等待自动续跑" else "当天失败，等待手动继续",
            detail = errorMessage,
            segmentId = segmentId,
            slotId = slotId,
            dayKey = synchronized(stateLock) { state.dayWorks.getOrNull(dayIndex)?.dayKey.orEmpty() },
            dayIndex = dayIndex,
            forceLog = true,
        )
        return DayRunResult(slotId, dayIndex, outcome)
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
                    "已完成 ${state.processedSegments}/${state.totalSegments} 条动态，仍有 $failedDays/${state.totalDays()} 天待继续"
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
                    "共完成 ${state.processedSegments}/${state.totalSegments} 条动态"
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
        slot.processedSegments = day.processedSegments
        slot.currentRangeLabel = currentWindow?.rangeLabel.orEmpty()
        slot.currentStageLabel = if (day.retryCount > 0) "恢复失败日期" else "等待执行"
        slot.currentStageDetail =
            if (day.retryCount > 0) {
                "准备从失败位置继续第 ${day.retryCount}/${DAY_RETRY_LIMIT} 次续跑"
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
        day.status = DynamicRebuildDayWorkItem.STATUS_COMPLETED
        day.lastError = null
        if (slot != null) {
            slot.status = DynamicRebuildWorkerSlotState.STATUS_COMPLETED
            slot.dayKey = day.dayKey
            slot.totalSegments = day.totalSegments()
            slot.processedSegments = day.processedSegments
            slot.currentRangeLabel = ""
            slot.currentStageLabel = "当天完成"
            slot.currentStageDetail = "已完成 ${day.dayKey} 的 ${day.totalSegments()} 条动态"
            slot.currentSegmentId = 0L
            slot.retryCount = day.retryCount
            slot.retryLimit = DAY_RETRY_LIMIT
        }
        state.refreshDerivedFields()
        persistStateLocked(state)
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
        val title = when (state.status) {
            DynamicRebuildTaskState.STATUS_PREPARING -> getString(R.string.dynamic_rebuild_notif_preparing_title)
            DynamicRebuildTaskState.STATUS_COMPLETED -> getString(R.string.dynamic_rebuild_notif_done_title)
            DynamicRebuildTaskState.STATUS_COMPLETED_WITH_FAILURES -> getString(R.string.dynamic_rebuild_notif_done_title)
            DynamicRebuildTaskState.STATUS_FAILED -> getString(R.string.dynamic_rebuild_notif_failed_title)
            DynamicRebuildTaskState.STATUS_CANCELLED -> getString(R.string.dynamic_rebuild_notif_cancelled_title)
            else -> getString(R.string.dynamic_rebuild_notif_running_title)
        }

        val detail = when (state.status) {
            DynamicRebuildTaskState.STATUS_PREPARING ->
                getString(R.string.dynamic_rebuild_notif_preparing_text)
            DynamicRebuildTaskState.STATUS_COMPLETED ->
                if (state.totalSegments <= 0) {
                    getString(R.string.dynamic_rebuild_notif_done_empty_text)
                } else {
                    getString(
                        R.string.dynamic_rebuild_notif_done_text,
                        state.processedSegments,
                    )
                }
            DynamicRebuildTaskState.STATUS_COMPLETED_WITH_FAILURES ->
                "已完成 ${state.processedSegments}/${state.totalSegments} 条动态，仍有 ${state.failedDayCount()}/${state.totalDays()} 天待继续"
            DynamicRebuildTaskState.STATUS_FAILED ->
                state.lastError ?: getString(R.string.dynamic_rebuild_notif_failed_generic)
            DynamicRebuildTaskState.STATUS_CANCELLED ->
                getString(
                    R.string.dynamic_rebuild_notif_cancelled_text,
                    state.processedSegments,
                    state.totalSegments,
                )
            else -> {
                val summary = getString(
                    R.string.dynamic_rebuild_notif_running_text,
                    state.currentWorkOrdinal(),
                    state.totalSegments,
                    state.progressPercentText(),
                )
                val activeDays = state.activeDayKeys(limit = state.dayConcurrency)
                val scopeLines = mutableListOf<String>()
                scopeLines.add("并发 ${state.dayConcurrency} 天")
                if (activeDays.isNotEmpty()) {
                    scopeLines.add("当前：${activeDays.joinToString(" / ")}")
                } else if (state.timelineCutoffDayKey.isNotBlank()) {
                    scopeLines.add("排队到：${state.timelineCutoffDayKey}")
                } else {
                    scopeLines.add(getString(R.string.dynamic_rebuild_notif_running_scope_default))
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
        sb.appendLine("ScreenMemo 动态重建报告")
        sb.appendLine("状态: ${state.status}")
        sb.appendLine("开始时间: ${state.startedAt}")
        sb.appendLine("完成时间: ${state.completedAt}")
        sb.appendLine("并发天数: ${state.dayConcurrency}")
        sb.appendLine("总段落数: ${state.totalSegments}")
        sb.appendLine("已处理段落: ${state.processedSegments}")
        sb.appendLine("待继续天数: ${state.failedDayCount()}/${state.totalDays()}")
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
                }
                val day = state.dayWorks.getOrNull(dayIndex)
                if (day != null) {
                    slot.totalSegments = day.totalSegments()
                    slot.processedSegments = day.processedSegments
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
                slot.processedSegments = day.processedSegments
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
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("startTime", startTime)
            .put("endTime", endTime)
            .put("rangeLabel", rangeLabel)
    }

    companion object {
        fun fromJson(obj: JSONObject): DynamicRebuildWindowWorkItem {
            return DynamicRebuildWindowWorkItem(
                startTime = obj.optLong("startTime", 0L),
                endTime = obj.optLong("endTime", 0L),
                rangeLabel = obj.optString("rangeLabel", ""),
            )
        }
    }
}

private data class DynamicRebuildDayWorkItem(
    val dayKey: String,
    val windows: MutableList<DynamicRebuildWindowWorkItem>,
    var nextWindowIndex: Int = 0,
    var processedSegments: Int = 0,
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

    fun toJson(): JSONObject {
        val windowsJson = JSONArray()
        windows.forEach { windowsJson.put(it.toJson()) }
        return JSONObject()
            .put("dayKey", dayKey)
            .put("nextWindowIndex", nextWindowIndex)
            .put("processedSegments", processedSegments)
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
    var status: String,
    val startedAt: Long,
    var updatedAt: Long,
    var completedAt: Long,
    var dayConcurrency: Int,
    var totalSegments: Int,
    var processedSegments: Int,
    var failedSegments: Int,
    var currentDayKey: String,
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
                status = STATUS_IDLE,
                startedAt = 0L,
                updatedAt = 0L,
                completedAt = 0L,
                dayConcurrency = 1,
                totalSegments = 0,
                processedSegments = 0,
                failedSegments = 0,
                currentDayKey = "",
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
            day.nextWindowIndex = day.nextWindowIndex.coerceIn(0, day.totalSegments())
            day.processedSegments = day.processedSegments.coerceIn(0, day.totalSegments())
        }
        refreshDerivedFields()
    }

    fun refreshDerivedFields() {
        totalSegments = dayWorks.sumOf { it.totalSegments() }
        processedSegments = dayWorks.sumOf { it.processedSegments }
        failedSegments = failedDayCount()
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
                status = obj.optString("status", DynamicRebuildTaskState.STATUS_IDLE),
                startedAt = obj.optLong("startedAt", 0L),
                updatedAt = obj.optLong("updatedAt", 0L),
                completedAt = obj.optLong("completedAt", 0L),
                dayConcurrency = dayConcurrency,
                totalSegments = obj.optInt("totalSegments", dayWorks.sumOf { it.totalSegments() }),
                processedSegments = obj.optInt("processedSegments", 0),
                failedSegments = obj.optInt("failedSegments", 0),
                currentDayKey = obj.optString("currentDayKey", ""),
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
            .put("status", state.status)
            .put("startedAt", state.startedAt)
            .put("updatedAt", state.updatedAt)
            .put("completedAt", state.completedAt)
            .put("dayConcurrency", state.dayConcurrency)
            .put("totalSegments", state.totalSegments)
            .put("processedSegments", state.processedSegments)
            .put("failedSegments", state.failedSegments)
            .put("currentDayKey", state.currentDayKey)
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

    private fun loadDayWorks(obj: JSONObject): MutableList<DynamicRebuildDayWorkItem> {
        val dayWorks = mutableListOf<DynamicRebuildDayWorkItem>()
        val dayWorksJson = obj.optJSONArray("dayWorks") ?: JSONArray()
        for (i in 0 until dayWorksJson.length()) {
            val item = dayWorksJson.optJSONObject(i) ?: continue
            dayWorks.add(DynamicRebuildDayWorkItem.fromJson(item))
        }
        if (dayWorks.isNotEmpty()) {
            dayWorks.forEach { day ->
                day.nextWindowIndex = day.nextWindowIndex.coerceIn(0, day.totalSegments())
                day.processedSegments = day.processedSegments.coerceIn(0, day.totalSegments())
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
            windows.add(
                DynamicRebuildWindowWorkItem(
                    startTime = startTime,
                    endTime = endTime,
                    rangeLabel = rangeLabel,
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
