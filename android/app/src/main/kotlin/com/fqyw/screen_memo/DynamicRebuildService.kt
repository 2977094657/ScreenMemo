package com.fqyw.screen_memo

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
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class DynamicRebuildService : Service() {

    companion object {
        private const val TAG = "DynamicRebuildService"
        private const val STATUS_TAG = "DYNAMIC_REBUILD"
        private const val ACTION_START = "com.fqyw.screen_memo.action.START_DYNAMIC_REBUILD"
        private const val ACTION_RESUME = "com.fqyw.screen_memo.action.RESUME_DYNAMIC_REBUILD"
        private const val ACTION_CANCEL = "com.fqyw.screen_memo.action.CANCEL_DYNAMIC_REBUILD"
        private const val NOTIFICATION_ID = 1037
        private const val CHANNEL_ID = "dynamic_rebuild_channel"

        fun startOrResumeTask(
            context: Context,
            resumeExisting: Boolean = false,
        ): Map<String, Any?> {
            val current = DynamicRebuildTaskStore.load(context)
            if (current != null && current.isRecoverable()) {
                current.currentStage = "resume_requested"
                current.currentStageLabel = "恢复后台任务"
                current.currentStageDetail = "检测到未完成任务，继续在后台执行"
                current.appendRecentLog(
                    buildStageLogLine(
                        "恢复后台任务",
                        "检测到未完成任务，继续在后台执行",
                    ),
                )
                DynamicRebuildTaskStore.save(context, current)
                startService(context, ACTION_RESUME)
                return current.toMap()
            }
            if (current != null && resumeExisting && current.canContinue()) {
                current.status = DynamicRebuildTaskState.STATUS_PENDING
                current.updatedAt = System.currentTimeMillis()
                current.completedAt = 0L
                current.lastError = null
                current.currentStage = "resume_requested"
                current.currentStageLabel = "继续重建"
                current.currentStageDetail = "沿用现有进度，等待后台继续处理"
                current.appendRecentLog(
                    buildStageLogLine(
                        "继续重建",
                        "沿用现有进度，等待后台继续处理",
                    ),
                )
                DynamicRebuildTaskStore.save(context, current)
                startService(context, ACTION_RESUME)
                return current.toMap()
            }

            val now = System.currentTimeMillis()
            val next = DynamicRebuildTaskState(
                taskId = "dynamic_rebuild_$now",
                status = DynamicRebuildTaskState.STATUS_PREPARING,
                startedAt = now,
                updatedAt = now,
                completedAt = 0L,
                totalSegments = 0,
                processedSegments = 0,
                failedSegments = 0,
                currentDayKey = "",
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
                recentLogs = mutableListOf(
                    buildStageLogLine(
                        "等待后台启动",
                        "任务已创建，等待后台服务开始准备",
                    ),
                ),
                works = mutableListOf(),
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
                FileLogger.i(TAG, "??????????????????reason=$reason")
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
            startService(context, ACTION_CANCEL)
            return current.toMap()
        }

        fun isTaskActive(context: Context): Boolean {
            return DynamicRebuildTaskStore.load(context)?.isRecoverable() == true
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
                FileLogger.e(TAG, "?? DynamicRebuildService ??", e)
            }
        }
    }

    private val workerExecutor = Executors.newSingleThreadExecutor()
    private val workerStarted = AtomicBoolean(false)
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
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

        startAsForeground(state)
        if (workerStarted.compareAndSet(false, true)) {
            workerExecutor.execute { runWorker() }
        } else {
            updateNotification(state)
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        FileLogger.i(TAG, "??????????????????")
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

            recordStage(
                state = state,
                stage = "worker_started",
                label = "后台任务启动",
                detail = "已进入串行重建流程",
            )

            if (!state.hasPreparedWorks()) {
                state = prepareWorkItems(state)
            }
            if (!state.isRecoverable()) {
                finalState = state
                return
            }

            state.status = DynamicRebuildTaskState.STATUS_RUNNING
            recordStage(
                state = state,
                stage = "running",
                label = "开始串行重建",
                detail = "按时间顺序逐条重建动态",
            )

            finalState = processPreparedWorks(state)
        } catch (e: Exception) {
            val failed = DynamicRebuildTaskStore.load(this) ?: DynamicRebuildTaskState.idle()
            failed.status = DynamicRebuildTaskState.STATUS_FAILED
            failed.failedSegments += 1
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
            FileLogger.e(TAG, "??????????", e)
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
        state.status = DynamicRebuildTaskState.STATUS_PREPARING
        recordStage(
            state = state,
            stage = "prepare_settings",
            label = "读取重建配置",
            detail = "正在读取分段长度与采样间隔",
        )

        val durationSec = readSegmentDurationSec()
        val sampleIntervalSec = readSegmentSampleIntervalSec()
        recordStage(
            state = state,
            stage = "prepare_worklist",
            label = "生成时间窗清单",
            detail = "按截图时间顺序计算全量重建范围",
        )
        val works = SegmentSummaryManager.buildFullRebuildWorklist(this, durationSec)
        val aiConfig = if (works.isNotEmpty()) {
            recordStage(
                state = state,
                stage = "prepare_ai_config",
                label = "读取 AI 配置",
                detail = "准备动态重建所需的模型配置",
            )
            AISettingsNative.readConfig(this, "segments")
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
        state.works.clear()
        state.works.addAll(
            works.map {
                DynamicRebuildWorkItem(
                    startTime = it.startTime,
                    endTime = it.endTime,
                    dayKey = formatDayKey(it.startTime),
                    rangeLabel = formatRangeLabel(it.startTime, it.endTime),
                )
            },
        )
        state.totalSegments = state.works.size
        state.processedSegments = 0
        state.failedSegments = 0
        state.currentSegmentId = 0L
        state.currentDayKey = state.works.firstOrNull()?.dayKey.orEmpty()
        state.currentRangeLabel = state.works.firstOrNull()?.rangeLabel.orEmpty()
        state.lastError = null
        state.completedAt = 0L

        if (state.works.isEmpty()) {
            state.status = DynamicRebuildTaskState.STATUS_COMPLETED
            state.completedAt = state.updatedAt
            state.currentStage = "completed_empty"
            state.currentStageLabel = "准备完成"
            state.currentStageDetail = "没有找到可重建的动态"
            state.appendRecentLog(
                buildStageLogLine(
                    "准备完成",
                    "没有找到可重建的动态",
                ),
            )
            DynamicRebuildTaskStore.save(this, state)
            updateNotification(state)
            return state
        }

        state.status = DynamicRebuildTaskState.STATUS_PENDING
        recordStage(
            state = state,
            stage = "prepare_done",
            label = "准备完成",
            detail = "共 ${state.totalSegments} 条，下一条：${state.currentDayKey} ${state.currentRangeLabel}".trim(),
        )
        return state
    }

    private fun processPreparedWorks(
        state: DynamicRebuildTaskState,
    ): DynamicRebuildTaskState {
        while (state.processedSegments < state.works.size) {
            if (isCancellationRequested()) {
                state.status = DynamicRebuildTaskState.STATUS_CANCELLED
                state.completedAt = System.currentTimeMillis()
                state.updatedAt = state.completedAt
                state.currentStage = "cancelled"
                state.currentStageLabel = "已停止"
                state.currentStageDetail = "停止请求已生效，后台任务退出"
                state.appendRecentLog(
                    buildStageLogLine(
                        "已停止",
                        "停止请求已生效，后台任务退出",
                    ),
                )
                DynamicRebuildTaskStore.save(this, state)
                return state
            }

            val work = state.works[state.processedSegments]
            state.status = DynamicRebuildTaskState.STATUS_RUNNING
            state.currentSegmentId = 0L
            state.currentDayKey = work.dayKey
            state.currentRangeLabel = work.rangeLabel
            recordStage(
                state = state,
                stage = "window_start",
                label = "开始重建当前动态",
                detail = "第 ${state.currentWorkOrdinal()}/${state.totalSegments} 条 · ${work.dayKey} ${work.rangeLabel}".trim(),
            )

            try {
                SegmentSummaryManager.rebuildWindowStrict(
                    ctx = this,
                    windowStart = work.startTime,
                    windowEnd = work.endTime,
                    durationSec = state.segmentDurationSec,
                    sampleIntervalSec = state.segmentSampleIntervalSec,
                    aiConfig = state.requireAiConfig(),
                    existingSegmentId = state.currentSegmentId,
                    stageReporter = { stage, label, detail, segmentId ->
                        recordStage(
                            state = state,
                            stage = stage,
                            label = label,
                            detail = detail,
                            segmentId = segmentId,
                        )
                    },
                )
                state.currentSegmentId = 0L
                state.processedSegments += 1
                state.lastError = null
                recordStage(
                    state = state,
                    stage = "window_completed",
                    label = "当前动态完成",
                    detail = "已完成第 ${state.processedSegments}/${state.totalSegments} 条",
                )
            } catch (e: SegmentSummaryManager.DynamicRebuildStepException) {
                state.status = DynamicRebuildTaskState.STATUS_FAILED
                state.failedSegments += 1
                state.lastError = e.message ?: e.toString()
                if (e.segmentId > 0L) {
                    state.currentSegmentId = e.segmentId
                }
                state.completedAt = System.currentTimeMillis()
                state.updatedAt = state.completedAt
                state.currentStage = "failed"
                state.currentStageLabel = "当前动态失败"
                state.currentStageDetail = state.lastError ?: "动态重建失败"
                state.appendRecentLog(
                    buildStageLogLine(
                        "当前动态失败",
                        state.currentStageDetail,
                    ),
                )
                DynamicRebuildTaskStore.save(this, state)
                updateNotification(state)
                return state
            } catch (e: Exception) {
                state.status = DynamicRebuildTaskState.STATUS_FAILED
                state.failedSegments += 1
                state.lastError = e.message ?: e.toString()
                state.completedAt = System.currentTimeMillis()
                state.updatedAt = state.completedAt
                state.currentStage = "failed"
                state.currentStageLabel = "当前动态失败"
                state.currentStageDetail = state.lastError ?: "动态重建失败"
                state.appendRecentLog(
                    buildStageLogLine(
                        "当前动态失败",
                        state.currentStageDetail,
                    ),
                )
                DynamicRebuildTaskStore.save(this, state)
                updateNotification(state)
                return state
            }
        }

        state.status = DynamicRebuildTaskState.STATUS_COMPLETED
        state.completedAt = System.currentTimeMillis()
        state.updatedAt = state.completedAt
        state.currentSegmentId = 0L
        state.currentStage = "completed"
        state.currentStageLabel = "全部完成"
        state.currentStageDetail = "共完成 ${state.processedSegments}/${state.totalSegments} 条动态"
        state.appendRecentLog(
            buildStageLogLine(
                "全部完成",
                state.currentStageDetail,
            ),
        )
        DynamicRebuildTaskStore.save(this, state)
        try {
            SegmentSummaryManager.tick(applicationContext)
        } catch (_: Exception) {}
        return state
    }

    private fun finishTask(state: DynamicRebuildTaskState) {
        val text = buildTaskReport(state)
        when (state.status) {
            DynamicRebuildTaskState.STATUS_COMPLETED -> FileLogger.i(STATUS_TAG, text)
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
                val currentScope = when {
                    state.currentDayKey.isNotBlank() && state.currentRangeLabel.isNotBlank() ->
                        "当前：${state.currentDayKey} ${state.currentRangeLabel}".trim()
                    state.currentRangeLabel.isNotBlank() -> state.currentRangeLabel
                    else -> getString(R.string.dynamic_rebuild_notif_running_scope_default)
                }
                "$summary\n$currentScope"
            }
        }

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
            .setContentText(detail.lineSequence().firstOrNull() ?: detail)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
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
        sb.appendLine("ScreenMemo ??????")
        sb.appendLine("??: ${state.status}")
        sb.appendLine("??: ${state.startedAt}")
        sb.appendLine("??: ${state.completedAt}")
        sb.appendLine("???: ${state.totalSegments}")
        sb.appendLine("???: ${state.processedSegments}")
        sb.appendLine("????: ${state.failedSegments}")
        if (state.currentDayKey.isNotBlank() || state.currentRangeLabel.isNotBlank()) {
            sb.appendLine("??: 第 ${state.currentWorkOrdinal()}/${state.totalSegments} 条 ${state.currentDayKey} ${state.currentRangeLabel}".trim())
        }
        if (state.currentStageLabel.isNotBlank()) {
            sb.appendLine("stage: ${state.currentStageLabel}")
        }
        if (state.currentStageDetail.isNotBlank()) {
            sb.appendLine("stageDetail: ${state.currentStageDetail}")
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
    ) {
        val normalizedStage = stage.trim()
        val normalizedLabel = label.trim()
        val normalizedDetail = detail.trim()
        val changed =
            forceLog ||
                state.currentStage != normalizedStage ||
                state.currentStageLabel != normalizedLabel ||
                state.currentStageDetail != normalizedDetail ||
                (segmentId > 0L && state.currentSegmentId != segmentId)
        if (!changed) return
        state.currentStage = normalizedStage
        state.currentStageLabel = normalizedLabel
        state.currentStageDetail = normalizedDetail
        if (segmentId > 0L) {
            state.currentSegmentId = segmentId
        }
        state.updatedAt = System.currentTimeMillis()
        state.appendRecentLog(buildStageLogLine(normalizedLabel, normalizedDetail))
        DynamicRebuildTaskStore.save(this, state)
        updateNotification(state)
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

private data class DynamicRebuildWorkItem(
    val startTime: Long,
    val endTime: Long,
    val dayKey: String,
    val rangeLabel: String,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("startTime", startTime)
            .put("endTime", endTime)
            .put("dayKey", dayKey)
            .put("rangeLabel", rangeLabel)
    }

    companion object {
        fun fromJson(obj: JSONObject): DynamicRebuildWorkItem {
            return DynamicRebuildWorkItem(
                startTime = obj.optLong("startTime", 0L),
                endTime = obj.optLong("endTime", 0L),
                dayKey = obj.optString("dayKey", ""),
                rangeLabel = obj.optString("rangeLabel", ""),
            )
        }
    }
}

private data class DynamicRebuildTaskState(
    val taskId: String,
    var status: String,
    val startedAt: Long,
    var updatedAt: Long,
    var completedAt: Long,
    var totalSegments: Int,
    var processedSegments: Int,
    var failedSegments: Int,
    var currentDayKey: String,
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
    val recentLogs: MutableList<String>,
    val works: MutableList<DynamicRebuildWorkItem>,
) {
    companion object {
        const val STATUS_IDLE = "idle"
        const val STATUS_PREPARING = "preparing"
        const val STATUS_PENDING = "pending"
        const val STATUS_RUNNING = "running"
        const val STATUS_COMPLETED = "completed"
        const val STATUS_FAILED = "failed"
        const val STATUS_CANCELLED = "cancelled"

        fun idle(): DynamicRebuildTaskState {
            return DynamicRebuildTaskState(
                taskId = "",
                status = STATUS_IDLE,
                startedAt = 0L,
                updatedAt = 0L,
                completedAt = 0L,
                totalSegments = 0,
                processedSegments = 0,
                failedSegments = 0,
                currentDayKey = "",
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
                recentLogs = mutableListOf(),
                works = mutableListOf(),
            )
        }
    }

    fun isRecoverable(): Boolean {
        return status == STATUS_PREPARING || status == STATUS_PENDING || status == STATUS_RUNNING
    }

    fun hasPreparedWorks(): Boolean = works.isNotEmpty() || totalSegments > 0

    fun canContinue(): Boolean {
        return works.isNotEmpty() &&
            processedSegments < totalSegments &&
            (status == STATUS_FAILED || status == STATUS_CANCELLED)
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
            throw IllegalStateException("???? AI ????")
        }
        return AISettingsNative.AIConfig(
            baseUrl = aiBaseUrl,
            apiKey = aiApiKey,
            model = aiModel,
            providerType = aiProviderType,
            chatPath = aiChatPath,
        )
    }

    fun toMap(): Map<String, Any?> {
        return hashMapOf(
            "taskId" to taskId,
            "status" to status,
            "startedAt" to startedAt,
            "updatedAt" to updatedAt,
            "completedAt" to completedAt,
            "totalSegments" to totalSegments,
            "processedSegments" to processedSegments,
            "failedSegments" to failedSegments,
            "currentDayKey" to currentDayKey,
            "currentSegmentId" to currentSegmentId,
            "currentRangeLabel" to currentRangeLabel,
            "currentStage" to currentStage,
            "currentStageLabel" to currentStageLabel,
            "currentStageDetail" to currentStageDetail,
            "lastError" to lastError,
            "isActive" to isRecoverable(),
            "progressPercent" to progressPercentText(),
            "recentLogs" to recentLogs.toList(),
        )
    }
}

private object DynamicRebuildTaskStore {
    private const val PREFS_NAME = "dynamic_rebuild_task_state"
    private const val KEY_TASK_JSON = "task_json"

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    @Synchronized
    fun load(context: Context): DynamicRebuildTaskState? {
        val raw = prefs(context).getString(KEY_TASK_JSON, null)?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return try {
            val obj = JSONObject(raw)
            val works = mutableListOf<DynamicRebuildWorkItem>()
            val worksJson = obj.optJSONArray("works") ?: JSONArray()
            val recentLogs = mutableListOf<String>()
            for (i in 0 until worksJson.length()) {
                val item = worksJson.optJSONObject(i) ?: continue
                works.add(DynamicRebuildWorkItem.fromJson(item))
            }
            val recentLogsJson = obj.optJSONArray("recentLogs") ?: JSONArray()
            for (i in 0 until recentLogsJson.length()) {
                val value = recentLogsJson.optString(i, "").trim()
                if (value.isNotEmpty()) {
                    recentLogs.add(value)
                }
            }
            DynamicRebuildTaskState(
                taskId = obj.optString("taskId", ""),
                status = obj.optString("status", DynamicRebuildTaskState.STATUS_IDLE),
                startedAt = obj.optLong("startedAt", 0L),
                updatedAt = obj.optLong("updatedAt", 0L),
                completedAt = obj.optLong("completedAt", 0L),
                totalSegments = obj.optInt("totalSegments", works.size),
                processedSegments = obj.optInt("processedSegments", 0),
                failedSegments = obj.optInt("failedSegments", 0),
                currentDayKey = obj.optString("currentDayKey", ""),
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
                recentLogs = recentLogs,
                works = works,
            )
        } catch (e: Exception) {
            FileLogger.e("DynamicRebuildTaskStore", "??????????", e)
            null
        }
    }

    @Synchronized
    fun save(context: Context, state: DynamicRebuildTaskState) {
        val works = JSONArray()
        val recentLogs = JSONArray()
        state.works.forEach { works.put(it.toJson()) }
        state.recentLogs.forEach { recentLogs.put(it) }
        val obj = JSONObject()
            .put("taskId", state.taskId)
            .put("status", state.status)
            .put("startedAt", state.startedAt)
            .put("updatedAt", state.updatedAt)
            .put("completedAt", state.completedAt)
            .put("totalSegments", state.totalSegments)
            .put("processedSegments", state.processedSegments)
            .put("failedSegments", state.failedSegments)
            .put("currentDayKey", state.currentDayKey)
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
            .put("recentLogs", recentLogs)
            .put("works", works)
        prefs(context).edit().putString(KEY_TASK_JSON, obj.toString()).commit()
    }
}
