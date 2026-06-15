package com.fqyw.screen_memo.segment

import com.fqyw.screen_memo.R

import com.fqyw.screen_memo.database.SegmentDatabaseHelper
import com.fqyw.screen_memo.dynamic.DynamicRebuildService
import com.fqyw.screen_memo.network.OkHttpClientFactory
import com.fqyw.screen_memo.settings.AISettingsNative
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
 
import com.fqyw.screen_memo.logging.FileLogger
import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.Timer
import java.util.TimerTask
import java.util.Collections
import java.util.HashSet
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.roundToInt

/**
 * 时间段总结管理器（原生）
 * - 入口：onScreenshotSaved(package, appName, filePathAbs, captureTime)
 * - 若不存在活动段落：以 当前图时间+durationSec 作为 endTime，startTime=endTime-durationSec
 *   注：根据需求1：需要"从当前图时间向后推1分钟，然后找大于该时间最近的一张图"，
 *       我们将此作为确定 startAnchor 的第一步，随后回溯 duration 构建段落范围。
 * - 在段落期间，按 sampleIntervalSec 从区间内寻找"最接近的截图（不限制±偏差，选最近）"，并缓存样本。
 * - 段落结束后，汇总去重应用+时间片，调用 Gemini 多模态生成结构化中文输出，持久化到 segment_results。
 */
object SegmentSummaryManager {

    private const val TAG = "SegmentSummaryManager"
    // 事件级图片上限（用于送入多模态模型），作为最终兜底
    // 需求：每个事件最多 16 张；若 ≤16 则全部送入
    internal const val PROVIDER_IMAGE_HARD_LIMIT = 16
    internal const val DYNAMIC_AI_STAGE_SUMMARY = "summary"
    internal const val DYNAMIC_AI_STAGE_MERGE_DECISION = "merge_decision"
    internal const val DYNAMIC_AI_STAGE_MERGE_SUMMARY = "merge_summary"
    internal const val DYNAMIC_AI_STAGE_STREAM_CHUNK_PREVIEW = "dynamic_ai_stream_chunk_preview"
    internal const val DYNAMIC_AI_HEARTBEAT_INTERVAL_MS = 30_000L
    internal const val DYNAMIC_AI_REQUEST_TIMEOUT_MS = 3L * 60L * 1000L
    internal const val DYNAMIC_AI_STREAM_FIRST_EVENT_TIMEOUT_MS = 180_000L
    internal const val DYNAMIC_AI_STREAM_PREVIEW_FLUSH_LEN = 36
    internal const val DYNAMIC_AI_STREAM_PREVIEW_MAX_LEN = 120
    private val dynamicRebuildInFlightCalls =
        Collections.synchronizedSet(mutableSetOf<Call>())

    data class ExistingDynamicWindow(
        val startTime: Long,
        val endTime: Long,
        val segmentId: Long = 0L,
        val hasCompliantResult: Boolean = false,
    )

    // 读写设置（SharedPreferences）
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)

    internal fun isDynamicRebuildTaskActive(ctx: Context): Boolean {
        return try {
            DynamicRebuildService.isTaskActive(ctx)
        } catch (_: Exception) {
            false
        }
    }

    internal fun logBackfillDiag(ctx: Context, message: String) {
        val normalized = message
            .replace("\r", " ")
            .replace("\n", " ")
            .trim()
        if (normalized.isEmpty()) return
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        try {
            FileLogger.i(TAG, "BACKFILL_DIAG $normalized")
        } catch (_: Exception) {}
    }

    private fun shortSha256(text: String): String {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(text.toByteArray(Charsets.UTF_8))
            digest.joinToString("") { b -> "%02x".format(b.toInt() and 0xff) }.take(16)
        } catch (_: Exception) {
            text.hashCode().toString(16)
        }
    }

    internal fun promptPrefixHash(text: String, maxChars: Int): String {
        val n = text.length.coerceAtMost(maxChars).coerceAtLeast(0)
        return "${n}:${shortSha256(text.take(n))}"
    }

    private fun isDynamicAutoRepairEnabled(ctx: Context): Boolean {
        return try {
            UserSettingsStorage.getBoolean(
                ctx,
                UserSettingsKeysNative.DYNAMIC_AUTO_REPAIR_ENABLED,
                true,
            )
        } catch (_: Exception) {
            true
        }
    }

    private fun shouldPauseRegularDynamicGeneration(
        ctx: Context,
        source: String,
        action: String,
    ): Boolean {
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        if (!isDynamicRebuildTaskActive(appCtx)) return false
        activeSegmentId = -1L
        try {
            FileLogger.d(TAG, "$source：动态重建进行中，$action")
        } catch (_: Exception) {}
        return true
    }

    internal data class DynamicAiStageSpec(
        val heartbeatStage: String,
        val heartbeatLabel: String,
        val fallbackStage: String,
        val fallbackLabel: String,
        val jsonRetryStage: String,
        val jsonRetryLabel: String,
    )

    internal fun resolveDynamicAiStageSpec(stageScope: String?): DynamicAiStageSpec? {
        return when (stageScope) {
            DYNAMIC_AI_STAGE_SUMMARY -> DynamicAiStageSpec(
                heartbeatStage = "summary_wait_ai_heartbeat",
                heartbeatLabel = "等待 AI 总结中",
                fallbackStage = "summary_ai_fallback",
                fallbackLabel = "AI 总结回退",
                jsonRetryStage = "summary_json_retry",
                jsonRetryLabel = "AI 总结结构修复",
            )
            DYNAMIC_AI_STAGE_MERGE_DECISION -> DynamicAiStageSpec(
                heartbeatStage = "merge_decision_wait_ai_heartbeat",
                heartbeatLabel = "等待合并判定中",
                fallbackStage = "merge_decision_ai_fallback",
                fallbackLabel = "合并判定回退",
                jsonRetryStage = "merge_decision_json_retry",
                jsonRetryLabel = "合并判定结构修复",
            )
            DYNAMIC_AI_STAGE_MERGE_SUMMARY -> DynamicAiStageSpec(
                heartbeatStage = "merge_summary_wait_ai_heartbeat",
                heartbeatLabel = "等待合并总结中",
                fallbackStage = "merge_summary_ai_fallback",
                fallbackLabel = "合并总结回退",
                jsonRetryStage = "merge_summary_json_retry",
                jsonRetryLabel = "合并总结结构修复",
            )
            else -> null
        }
    }

    internal fun reportDynamicAiFallback(
        stageReporter: ((String, String, String, Long) -> Unit)?,
        stageScope: String?,
        segmentId: Long,
        detail: String,
    ) {
        val spec = resolveDynamicAiStageSpec(stageScope) ?: return
        stageReporter?.invoke(spec.fallbackStage, spec.fallbackLabel, detail, segmentId)
    }

    internal fun reportDynamicAiJsonRetry(
        stageReporter: ((String, String, String, Long) -> Unit)?,
        stageScope: String?,
        segmentId: Long,
        detail: String,
    ) {
        val spec = resolveDynamicAiStageSpec(stageScope) ?: return
        stageReporter?.invoke(spec.jsonRetryStage, spec.jsonRetryLabel, detail, segmentId)
    }

    internal fun reportDynamicAiStreamChunk(
        stageReporter: ((String, String, String, Long) -> Unit)?,
        stageScope: String?,
        segmentId: Long,
        chunkPreview: String,
    ) {
        if (resolveDynamicAiStageSpec(stageScope) == null) return
        val normalized = normalizeDynamicAiStreamPreviewText(chunkPreview)
        if (normalized.isBlank()) return
        stageReporter?.invoke(
            DYNAMIC_AI_STAGE_STREAM_CHUNK_PREVIEW,
            "流式数据",
            normalized,
            segmentId,
        )
    }

    internal fun isDynamicAiStage(stageScope: String?): Boolean {
        return resolveDynamicAiStageSpec(stageScope) != null
    }

    internal fun resolveDynamicAiRequestTimeoutMs(stageScope: String?): Long? {
        return if (isDynamicAiStage(stageScope)) {
            DYNAMIC_AI_REQUEST_TIMEOUT_MS
        } else {
            null
        }
    }

    private fun isDynamicRebuildCancellationRequested(ctx: Context): Boolean {
        return try {
            DynamicRebuildService.isCancellationRequested(ctx)
        } catch (_: Exception) {
            false
        }
    }

    internal fun ensureDynamicRebuildNotCancelled(ctx: Context, segmentId: Long = 0L) {
        if (!isDynamicRebuildCancellationRequested(ctx)) return
        throw DynamicRebuildCancelledException(
            "动态重建已停止，已中断当前请求",
            segmentId,
        )
    }

    internal fun maybeThrowDynamicAiCancelled(
        ctx: Context,
        stageScope: String?,
        segmentId: Long = 0L,
    ) {
        if (!isDynamicAiStage(stageScope)) return
        ensureDynamicRebuildNotCancelled(ctx, segmentId)
    }

    private fun trackDynamicRebuildCall(stageScope: String?, call: Call) {
        if (!isDynamicAiStage(stageScope)) return
        dynamicRebuildInFlightCalls.add(call)
    }

    private fun untrackDynamicRebuildCall(stageScope: String?, call: Call) {
        if (!isDynamicAiStage(stageScope)) return
        dynamicRebuildInFlightCalls.remove(call)
    }

    internal fun <T> executeTrackedCall(
        ctx: Context,
        stageScope: String?,
        segmentId: Long,
        call: Call,
        block: (okhttp3.Response) -> T,
    ): T {
        trackDynamicRebuildCall(stageScope, call)
        try {
            maybeThrowDynamicAiCancelled(ctx, stageScope, segmentId)
            val response = call.execute()
            response.use { return block(it) }
        } finally {
            untrackDynamicRebuildCall(stageScope, call)
        }
    }

    internal fun sleepWithDynamicCancelAwareness(
        ctx: Context,
        stageScope: String?,
        segmentId: Long,
        sleepMs: Long,
    ) {
        if (sleepMs <= 0L) return
        var remaining = sleepMs
        while (remaining > 0L) {
            maybeThrowDynamicAiCancelled(ctx, stageScope, segmentId)
            val chunk = remaining.coerceAtMost(200L)
            Thread.sleep(chunk)
            remaining -= chunk
        }
    }

    fun cancelDynamicRebuildInFlightRequests(reason: String = "manual"): Int {
        val snapshot = synchronized(dynamicRebuildInFlightCalls) {
            dynamicRebuildInFlightCalls.toList()
        }
        if (snapshot.isEmpty()) return 0
        snapshot.forEach { call ->
            try {
                call.cancel()
            } catch (_: Exception) {}
        }
        try {
            FileLogger.w(TAG, "动态重建：收到取消请求，已中断 ${snapshot.size} 个在途 AI 请求，reason=$reason")
        } catch (_: Exception) {}
        return snapshot.size
    }

    @Volatile private var lastLoggedSampleIntervalSec: Int = -1
    @Volatile private var lastLoggedSegmentDurationSec: Int = -1
    @Volatile private var lastLoggedAiMinIntervalSec: Int = -1

    private fun getSampleIntervalSec(ctx: Context): Int {
        // 统一从 UserSettingsStorage 读取（先 DB 后 prefs），避免多进程/缓存导致的旧值问题。
        val raw = try {
            UserSettingsStorage.getInt(ctx, UserSettingsKeysNative.SEGMENT_SAMPLE_INTERVAL_SEC, 20)
        } catch (_: Exception) { 20 }
        val v = if (raw <= 0) 20 else raw.coerceAtLeast(5)
        if (v != lastLoggedSampleIntervalSec) {
            lastLoggedSampleIntervalSec = v
            try { FileLogger.i(TAG, "读取配置：segment_sample_interval_sec=${v}") } catch (_: Exception) {}
        }
        return v
    }

    private fun getSegmentDurationSec(ctx: Context): Int {
        val raw = try {
            UserSettingsStorage.getInt(ctx, UserSettingsKeysNative.SEGMENT_DURATION_SEC, 5 * 60)
        } catch (_: Exception) { 5 * 60 }
        val v = if (raw <= 0) 5 * 60 else raw.coerceAtLeast(60)
        if (v != lastLoggedSegmentDurationSec) {
            lastLoggedSegmentDurationSec = v
            try { FileLogger.i(TAG, "读取配置：segment_duration_sec=${v}") } catch (_: Exception) {}
        }
        return v
    }

    /** 合并图片上限（仅数量，不按时长），默认 50，可通过 SharedPreferences("merge_max_images_per_event") 覆盖 */
    private fun getMergeMaxImagesPerEvent(ctx: Context): Int {
        return try {
            val v = prefs(ctx).getInt("merge_max_images_per_event", 50)
            if (v <= 0) 50 else v
        } catch (_: Exception) { 50 }
    }

    // 活动段落缓存（仅存ID，其他实时查库）
    @Volatile private var activeSegmentId: Long = -1L

    // —— 动态生成 worker 池（多线程）——
    // 说明：不再强制单线程串行；避免某个任务卡住时把全局动态链路完全堵死。
    // 仍保留：tick/backfill 去抖（tickEnqueued/backfillEnqueued）与按段落/窗口去重集合。
    private const val WORKER_PARALLELISM = 3
    private val workerQueue = LinkedBlockingQueue<Runnable>()
    private val workerStartLock = Any()
    private val workerStarted = AtomicBoolean(false)
    private val workerThreadIds: MutableSet<Long> = Collections.synchronizedSet(HashSet())
    @Volatile private var workerThreads: List<Thread> = emptyList()

    private fun ensureWorkerStarted() {
        if (workerStarted.get()) return
        synchronized(workerStartLock) {
            if (workerStarted.get()) return
            val threads = ArrayList<Thread>(WORKER_PARALLELISM)
            for (i in 0 until WORKER_PARALLELISM) {
                val idx = i + 1
                val t = Thread {
                    val tid = Thread.currentThread().id
                    workerThreadIds.add(tid)
                    try {
                        while (true) {
                            try {
                                val r = workerQueue.take()
                                r.run()
                            } catch (_: InterruptedException) {
                                // ignore
                            } catch (e: Throwable) {
                                try { FileLogger.w(TAG, "worker loop 异常：${e.message}") } catch (_: Exception) {}
                                try { FileLogger.w(TAG, "worker loop 堆栈=\n" + e.stackTraceToString()) } catch (_: Exception) {}
                            }
                        }
                    } finally {
                        workerThreadIds.remove(tid)
                    }
                }
                t.name = "SegmentSummaryWorker-$idx"
                t.isDaemon = true
                t.start()
                threads.add(t)
            }
            workerThreads = threads
            workerStarted.set(true)
            try { FileLogger.i(TAG, "SegmentSummaryWorker started threads=${threads.size}") } catch (_: Exception) {}
        }
    }

    private fun isWorkerThread(): Boolean = workerThreadIds.contains(Thread.currentThread().id)

    private fun runOnWorker(tag: String, task: () -> Unit) {
        ensureWorkerStarted()
        if (isWorkerThread()) {
            task()
            return
        }
        workerQueue.put(
            Runnable {
                try {
                    task()
                } catch (e: Exception) {
                    try { FileLogger.w(TAG, "worker[$tag] 异常：${e.message}") } catch (_: Exception) {}
                    try { FileLogger.w(TAG, "worker[$tag] 堆栈=\n" + e.stackTraceToString()) } catch (_: Exception) {}
                }
            },
        )
    }

    // 强制异步：即使当前就在 worker 线程，也会放入队列尾部，避免深层嵌套阻塞当前任务
    private fun postOnWorker(tag: String, task: () -> Unit) {
        ensureWorkerStarted()
        workerQueue.put(
            Runnable {
                try {
                    task()
                } catch (e: Exception) {
                    try { FileLogger.w(TAG, "worker[$tag] 异常：${e.message}") } catch (_: Exception) {}
                    try { FileLogger.w(TAG, "worker[$tag] 堆栈=\n" + e.stackTraceToString()) } catch (_: Exception) {}
                }
            },
        )
    }

    private val tickEnqueued = AtomicBoolean(false)
    private val backfillEnqueued = AtomicBoolean(false)

    // 并发窗口去重：按 "start|end" 标识正在创建中的段落，避免同时间段重复创建
    private val creatingWindows: MutableSet<String> = Collections.synchronizedSet(HashSet())
    // 并发完成去重：避免同一 segment 被重复 finish/AI 调用
    private val finishingSegments: MutableSet<Long> = Collections.synchronizedSet(HashSet())
    // 窗口级完成去重：同一 (start,end) 仅允许一次 finish 流程
    private val finishingWindows: MutableSet<String> = Collections.synchronizedSet(HashSet())
    // 并发合并去重：避免同一 segment 被并发触发“向后合并链路”（含手动强制合并）
    private val mergingSegments: MutableSet<Long> = Collections.synchronizedSet(HashSet())

    // 最近窗口默认回看天数（用于日期修复、缺失结果补救等；避免全量扫描带来开销）。
    private const val RECENT_LOOKBACK_DAYS = 14

    // 全局AI请求速率限制：两次请求之间的最小间隔（毫秒）
    @Volatile private var nextAiAvailableMs: Long = 0L
    private val aiRateLock = Object()

    private fun getAiMinIntervalSec(ctx: Context): Int {
        // 可通过 SharedPreferences(键: ai_min_request_interval_sec) 配置；默认3秒，最低1秒
        val raw = try {
            UserSettingsStorage.getInt(ctx, UserSettingsKeysNative.AI_MIN_REQUEST_INTERVAL_SEC, 3)
        } catch (_: Exception) { 3 }
        val v = when {
            raw < 1 -> 1
            raw > 60 -> 60
            else -> raw
        }
        if (v != lastLoggedAiMinIntervalSec) {
            lastLoggedAiMinIntervalSec = v
            try { FileLogger.i(TAG, "读取配置：ai_min_request_interval_sec=${v}") } catch (_: Exception) {}
        }
        return v
    }

    /**
     * 申请一次AI请求配额：若距离上次请求未超过最小间隔，则等待剩余时间。
     * 采用"令牌时钟"：所有调用串行化到全局最小间隔，避免瞬时洪峰。
     * 返回本次实际等待的毫秒数（便于日志观测）。
     */
    internal fun acquireAiRateSlot(ctx: Context): Long {
        val intervalMs = getAiMinIntervalSec(ctx) * 1000L
        var waitMs = 0L
        val now = System.currentTimeMillis()
        synchronized(aiRateLock) {
            val target = if (nextAiAvailableMs <= now) now else nextAiAvailableMs
            waitMs = (target - now).coerceAtLeast(0L)
            // 预占下一个可用时间点，确保并发下也能按照间隔队列
            nextAiAvailableMs = target + intervalMs
        }
        if (waitMs > 0L) {
            try { FileLogger.i(TAG, "AI 速率限制：等待 ${waitMs}毫秒 (间隔=${intervalMs}毫秒)") } catch (_: Exception) {}
            try { Thread.sleep(waitMs) } catch (_: Exception) {}
        }
        return waitMs
    }

    fun onScreenshotSaved(ctx: Context, appPackage: String, appName: String, filePathAbs: String, captureTime: Long) {
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        if (isDynamicRebuildTaskActive(appCtx)) {
            try { FileLogger.i(TAG, "onScreenshotSaved：检测到动态重建任务运行中，跳过常规动态生成") } catch (_: Exception) {}
            return
        }
        runOnWorker("onScreenshotSaved") {
            onScreenshotSavedInternal(appCtx, appPackage, appName, filePathAbs, captureTime)
        }
    }

    private fun onScreenshotSavedInternal(ctx: Context, appPackage: String, appName: String, filePathAbs: String, captureTime: Long) {
        try {
            try { FileLogger.i(TAG, "onScreenshotSaved：包名=${appPackage} 文件=${filePathAbs} 时间戳=${captureTime}") } catch (_: Exception) {}
            if (
                shouldPauseRegularDynamicGeneration(
                    ctx,
                    "onScreenshotSavedInternal",
                    "跳过排队中的常规截图总结",
                )
            ) {
                return
            }
            if (activeSegmentId <= 0) {
                // 先回填历史窗口到最新的可完成段落
                backfillToLatest(ctx)
                if (
                    shouldPauseRegularDynamicGeneration(
                        ctx,
                        "onScreenshotSavedInternal",
                        "跳过排队中的常规截图总结",
                    )
                ) {
                    return
                }

                // 若仍无活动段落，则以当前截图时间作为起点创建"仅含有图片的窗口"
                val durationSec = getSegmentDurationSec(ctx)
                val intervalSec = getSampleIntervalSec(ctx)
                val startTime = captureTime
                val endTime = startTime + durationSec * 1000L
                // 进度下界：新窗口的 start 必须 > 已存在的最大 end
                val todayStart = startOfToday()
                val progressEnd = SegmentDatabaseHelper.getLastSegmentEndTimeInRange(ctx, todayStart, System.currentTimeMillis()) ?: 0L
                if (startTime <= progressEnd) {
                    try { FileLogger.i(TAG, "跳过创建窗口(早于进度)：start=${startTime} progressEnd=${progressEnd}") } catch (_: Exception) {}
                    // 已有较新的段覆盖本窗口范围，直接尝试推进/完成
                    tryCollectSamplesAndMaybeFinish(ctx)
                    return
                }
                val windowKey = "$startTime|$endTime"
                var created = false
                if (!SegmentDatabaseHelper.hasSegmentExact(ctx, startTime, endTime)) {
                    if (creatingWindows.add(windowKey)) {
                        try {
                            if (ensureNoRootOverlapBeforeCreate(ctx, startTime, endTime, "onScreenshotSaved")) {
                                val segId = SegmentDatabaseHelper.createSegment(
                                    ctx,
                                    startTime,
                                    endTime,
                                    durationSec,
                                    intervalSec,
                                    status = "collecting"
                                )
                                if (segId > 0) {
                                    activeSegmentId = segId
                                    created = true
                                    try { FileLogger.i(TAG, "段落(由当前截图创建)：id=${segId} start=${startTime} end=${endTime} duration=${durationSec}秒 interval=${intervalSec}秒") } catch (_: Exception) {}
                                }
                            }
                        } finally {
                            creatingWindows.remove(windowKey)
                        }
                    }
                }
                if (created) {
                    tryCollectSamplesAndMaybeFinish(ctx)
                    // 兜底：创建新事件时，尝试补救历史存在样本但缺少结果的段落
                    try { resumeMissingSummaries(ctx, limit = 1) } catch (_: Exception) {}
                }
            } else {
                // 已有活动段落，尝试补充采样或结束
                tryCollectSamplesAndMaybeFinish(ctx)
                // 额外回填历史窗口（若还有未完成）
                backfillToLatest(ctx)
            }
        } catch (e: Exception) {
            FileLogger.w(TAG, "截图保存回调异常：${e.message}")
        }
    }

    // 周期性驱动：用于在无新截图时也能结束段落并触发 AI
    // - tick 会调度到 worker 池执行；通过 tickEnqueued 去抖避免高频并发 tick
    fun tick(ctx: Context) {
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        if (isDynamicRebuildTaskActive(appCtx)) {
            try { FileLogger.i(TAG, "tick：检测到动态重建任务运行中，跳过常规推进") } catch (_: Exception) {}
            return
        }
        if (isWorkerThread()) {
            tickInternal(appCtx)
            return
        }
        if (!tickEnqueued.compareAndSet(false, true)) return
        runOnWorker("tick") {
            try {
                tickInternal(appCtx)
            } finally {
                tickEnqueued.set(false)
            }
        }
    }

    private fun tickInternal(ctx: Context) {
        if (
            shouldPauseRegularDynamicGeneration(
                ctx,
                "tickInternal",
                "跳过排队中的常规推进",
            )
        ) {
            return
        }
        try {
            try { FileLogger.d(TAG, "tick：驱动段落采样/完成") } catch (_: Exception) {}
            // 先推进所有 collecting 段落
            tryProgressAllCollecting(ctx)
            // 后台清理可能的重复窗口，仅小批量，避免阻塞
            try {
                val removed = SegmentDatabaseHelper.cleanupDuplicateSegments(ctx, limitGroups = 20)
                if (removed > 0) {
                    try { FileLogger.i(TAG, "tick：清理重复段落 count=$removed") } catch (_: Exception) {}
                }
            } catch (_: Exception) {}
            if (!isDynamicAutoRepairEnabled(ctx)) {
                return
            }
            // 后台补齐到当天最新可完整时段
            backfillToLatest(ctx)
            // 若用户删空了某些日期的动态（segments），这里会对“有截图但无段落”的日期进行回填重建，恢复日期 Tab。
            try { repairMissingDaysFromRecentShots(ctx) } catch (_: Exception) {}
            // 定时补救：扫描缺失结果的段落
            try { resumeMissingSummaries(ctx, limit = 2) } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    private fun repairMissingDaysFromRecentShots(ctx: Context) {
        if (
            shouldPauseRegularDynamicGeneration(
                ctx,
                "repairMissingDaysFromRecentShots",
                "跳过排队中的缺失日期修复",
            )
        ) {
            return
        }
        if (!isDynamicAutoRepairEnabled(ctx)) return
        // 默认仅检查近 14 天：与 UI“最近日期 Tab”窗口一致，避免全量扫描导致开销过大
        val dayMs = 24L * 60L * 60L * 1000L
        val lookbackDays = RECENT_LOOKBACK_DAYS
        val now = System.currentTimeMillis()
        val since = startOfToday() - (lookbackDays.toLong() - 1L) * dayMs

        val shots = try { SegmentDatabaseHelper.listShotsBetween(ctx, since, now) } catch (_: Exception) { emptyList() }
        if (shots.isEmpty()) return

        val shotDays = HashSet<String>()
        for (s in shots) {
            shotDays.add(dateKeyFromMillis(s.captureTime))
        }
        if (shotDays.isEmpty()) return

        val segStarts = try { SegmentDatabaseHelper.listGlobalSegmentStartTimesBetween(ctx, since, now) } catch (_: Exception) { emptyList() }
        val segDays = HashSet<String>()
        for (st in segStarts) {
            segDays.add(dateKeyFromMillis(st))
        }

        val missingDays = shotDays.filter { !segDays.contains(it) }.sorted()
        if (missingDays.isEmpty()) return

        // 限制：每次 tick 仅修复 1 天，避免在极端截图量下阻塞其它生成任务
        var repairedDays = 0
        for (dayKey in missingDays) {
            if (repairedDays >= 1) break
            val bounds = dayBoundsMillis(dayKey) ?: continue
            val created = rebuildGlobalSegmentsForDay(
                ctx,
                dayKey = dayKey,
                dayStartMillis = bounds.first,
                dayEndMillis = bounds.second,
                nowMillis = now,
            )
            if (created > 0) {
                repairedDays++
            }
        }
    }

    private fun rebuildGlobalSegmentsForDay(
        ctx: Context,
        dayKey: String,
        dayStartMillis: Long,
        dayEndMillis: Long,
        nowMillis: Long,
    ): Int {
        val durationSec = getSegmentDurationSec(ctx)
        val intervalSec = getSampleIntervalSec(ctx)
        val durationMs = durationSec * 1000L
        // 允许“跨天窗口”：只要 start_time 属于本日即可（UI 分组按 start_time）
        val scanEnd = kotlin.math.min(nowMillis, dayEndMillis + durationMs)

        val shots = try { SegmentDatabaseHelper.listShotsBetween(ctx, dayStartMillis, scanEnd) } catch (_: Exception) { emptyList() }
        if (shots.isEmpty()) return 0

        val existing = loadExistingRootWindows(ctx, kotlin.math.max(0L, dayStartMillis - durationMs), scanEnd + durationMs)
        val plan = planNonOverlappingWindows(
            shotTimes = shots.map { it.captureTime },
            existingWindows = existing,
            durationMs = durationMs,
            nowMillis = nowMillis,
            dayEndMillis = dayEndMillis,
        )
        var created = 0
        for (window in plan.windows) {
            val windowStart = window.startTime
            val windowEnd = window.endTime
            try {
                if (
                    !SegmentDatabaseHelper.hasSegmentExact(ctx, windowStart, windowEnd) &&
                    ensureNoRootOverlapBeforeCreate(ctx, windowStart, windowEnd, "repairMissingDay")
                ) {
                    val segId = SegmentDatabaseHelper.createSegment(
                        ctx,
                        startMillis = windowStart,
                        endMillis = windowEnd,
                        durationSec = durationSec,
                        sampleIntervalSec = intervalSec,
                        status = "completed",
                    )
                    if (segId > 0) {
                        val seg = SegmentDatabaseHelper.getSegmentById(ctx, segId)
                        if (seg != null) {
                            var samples = SegmentDatabaseHelper.getSamplesForSegment(ctx, segId)
                            if (samples.isEmpty()) {
                                samples = buildSamplesForSegment(ctx, seg)
                                if (samples.isNotEmpty()) {
                                    try { SegmentDatabaseHelper.saveSamples(ctx, seg.id, samples) } catch (_: Exception) {}
                                }
                            }
                        }
                        created++
                    }
                }
            } catch (_: Exception) {}
        }

        if (created > 0) {
            try { FileLogger.i(TAG, "repairDays: rebuilt day=$dayKey createdSegments=$created skippedCovered=${plan.skippedCovered} mergedShortGaps=${plan.mergedShortGaps}") } catch (_: Exception) {}
        }
        return created
    }

    fun dayBoundsMillis(dayKey: String): Pair<Long, Long>? {
        val parts = dayKey.split('-')
        if (parts.size != 3) return null
        val y = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        val d = parts[2].toIntOrNull() ?: return null
        val cal = java.util.Calendar.getInstance()
        cal.set(java.util.Calendar.YEAR, y)
        cal.set(java.util.Calendar.MONTH, m - 1)
        cal.set(java.util.Calendar.DAY_OF_MONTH, d)
        cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
        cal.set(java.util.Calendar.MINUTE, 0)
        cal.set(java.util.Calendar.SECOND, 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        val start = cal.timeInMillis
        cal.set(java.util.Calendar.HOUR_OF_DAY, 23)
        cal.set(java.util.Calendar.MINUTE, 59)
        cal.set(java.util.Calendar.SECOND, 59)
        cal.set(java.util.Calendar.MILLISECOND, 999)
        val end = cal.timeInMillis
        return Pair(start, end)
    }

    internal fun findFirstShotStrictAfter(ctx: Context, strictAfterMillis: Long): SegmentDatabaseHelper.ShotInfo? {
        // 小窗口向后2分钟内寻找，避免全局扫描
        val end = strictAfterMillis + 2 * 60_000L
        val shots = SegmentDatabaseHelper.listShotsBetween(ctx, strictAfterMillis, end)
        return shots.minByOrNull { it.captureTime }
    }

    private fun tryCollectSamplesAndMaybeFinish(ctx: Context) {
        if (
            shouldPauseRegularDynamicGeneration(
                ctx,
                "tryCollectSamplesAndMaybeFinish",
                "跳过排队中的段落推进",
            )
        ) {
            return
        }
        val seg = SegmentDatabaseHelper.getCollectingSegment(ctx) ?: run {
            activeSegmentId = -1L
            return
        }
        val interval = seg.sampleIntervalSec
        try {
            val settingInterval = getSampleIntervalSec(ctx)
            if (settingInterval != interval) {
                FileLogger.w(TAG, "collect：采样间隔不一致 seg.interval=${interval}秒 setting.interval=${settingInterval}秒 (segId=${seg.id})")
            }
        } catch (_: Exception) {}
        val start = seg.startTime
        val end = seg.endTime
        val totalSec = seg.durationSec
        // 槽位数按向下取整，确保不超过 时长/间隔 上限（示例：60/20=3）
        val totalSlots = (totalSec / interval).coerceAtLeast(1)

        val shots = SegmentDatabaseHelper.listShotsBetween(ctx, start, end)
        try { FileLogger.d(TAG, "collect：范围=${start}-${end} 截图数=${shots.size} 间隔=${interval}秒 槽位数=${totalSlots}") } catch (_: Exception) {}
        if (shots.isEmpty()) {
            val now = System.currentTimeMillis()
            if (now >= end) {
                // 到期且区间内无任何截图：标记完成，但不触发AI
                try { FileLogger.i(TAG, "complete(无截图)：seg=${seg.id} ${start}-${end}") } catch (_: Exception) {}
                SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                activeSegmentId = -1L
            }
            return
        }

        // 为每个时间槽选择"最近"的截图（不限制±，选择距离最小者），并按文件路径去重
        val samples = ArrayList<SegmentDatabaseHelper.Sample>()
        var inWindowCount = 0
        val seenPaths = HashSet<String>()
        for (i in 0 until totalSlots) {
            val isLast = (i == totalSlots - 1)
            val target = start + i * interval * 1000L
            var chosen: SegmentDatabaseHelper.ShotInfo? = null
            if (isLast) {
                // 最后一个槽位优先取 endTime 之后的第一张，保证不超过总数
                val post = findFirstShotStrictAfter(ctx, end)
                if (post != null) chosen = post
            }
            if (chosen == null) {
                var best: SegmentDatabaseHelper.ShotInfo? = null
                var bestDt = Long.MAX_VALUE
                for (s in shots) {
                    val dt = kotlin.math.abs(s.captureTime - target)
                    if (dt < bestDt) { bestDt = dt; best = s }
                }
                chosen = best
            }
            if (chosen != null && seenPaths.add(chosen.filePath)) {
                samples.add(
                    SegmentDatabaseHelper.Sample(
                        id = 0L,
                        segmentId = seg.id,
                        captureTime = chosen.captureTime,
                        filePath = chosen.filePath,
                        appPackageName = chosen.appPackageName,
                        appName = chosen.appName,
                        positionIndex = i
                    )
                )
                if (chosen.captureTime in start..end) inWindowCount++
            }
        }
        SegmentDatabaseHelper.saveSamples(ctx, seg.id, samples)

        val now = System.currentTimeMillis()
        if (now >= end) {
            // 段落结束：仅当窗口内至少有一张图时才触发AI
            if (inWindowCount > 0) {
                finishSegment(ctx, seg, samples)
            } else {
                try { FileLogger.i(TAG, "complete(窗口内无样本)：seg=${seg.id}") } catch (_: Exception) {}
                SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                activeSegmentId = -1L
            }
        }
    }

    private fun tryProgressAllCollecting(ctx: Context) {
        try {
            val list = SegmentDatabaseHelper.listCollectingSegments(ctx, limit = 50)
            val settingInterval = try { getSampleIntervalSec(ctx) } catch (_: Exception) { -1 }
            for (seg in list) {
                // activeSegmentId 仅作为提示，不强依赖
                activeSegmentId = seg.id
                val interval = seg.sampleIntervalSec
                if (settingInterval > 0 && settingInterval != interval) {
                    try { FileLogger.w(TAG, "progress: seg.interval=${interval}s != setting.interval=${settingInterval}s (segId=${seg.id})") } catch (_: Exception) {}
                }
                val start = seg.startTime
                val end = seg.endTime
                val totalSec = seg.durationSec
                val totalSlots = (totalSec / interval).coerceAtLeast(1)

                val shots = SegmentDatabaseHelper.listShotsBetween(ctx, start, end)
                if (shots.isEmpty()) {
                    val now = System.currentTimeMillis()
                    if (now >= end) finishSegment(ctx, seg, emptyList())
                    continue
                }

                val samples = ArrayList<SegmentDatabaseHelper.Sample>()
                var inWindowCount = 0
                val seenPaths = HashSet<String>()
                for (i in 0 until totalSlots) {
                    val isLast = (i == totalSlots - 1)
                    val target = start + i * interval * 1000L
                    var chosen: SegmentDatabaseHelper.ShotInfo? = null
                    if (isLast) {
                        val post = findFirstShotStrictAfter(ctx, end)
                        if (post != null) chosen = post
                    }
                    if (chosen == null) {
                        var best: SegmentDatabaseHelper.ShotInfo? = null
                        var bestDt = Long.MAX_VALUE
                        for (s in shots) {
                            val dt = kotlin.math.abs(s.captureTime - target)
                            if (dt < bestDt) { bestDt = dt; best = s }
                        }
                        chosen = best
                    }
                    if (chosen != null && seenPaths.add(chosen.filePath)) {
                        samples.add(
                            SegmentDatabaseHelper.Sample(
                                id = 0L,
                                segmentId = seg.id,
                                captureTime = chosen.captureTime,
                                filePath = chosen.filePath,
                                appPackageName = chosen.appPackageName,
                                appName = chosen.appName,
                                positionIndex = i
                            )
                        )
                        if (chosen.captureTime in start..end) inWindowCount++
                    }
                }
                SegmentDatabaseHelper.saveSamples(ctx, seg.id, samples)

                val now = System.currentTimeMillis()
                if (now >= end) {
                    if (inWindowCount > 0) {
                        finishSegment(ctx, seg, samples)
                    } else {
                        try { FileLogger.i(TAG, "complete(窗口内无样本)：seg=${seg.id}") } catch (_: Exception) {}
                        SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                        activeSegmentId = -1L
                    }
                }
            }
        } catch (_: Exception) {}
    }

    /**
     * 扫描当天时间线，若存在可以形成完整时段（durationSec）的窗口，
     * 对未创建/未完成的段落自动创建并采样直至最新窗口。
     */
    fun backfillToLatest(ctx: Context) {
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        if (isDynamicRebuildTaskActive(appCtx)) {
            try { FileLogger.i(TAG, "backfillToLatest：检测到动态重建任务运行中，跳过常规回填") } catch (_: Exception) {}
            return
        }
        if (!isDynamicAutoRepairEnabled(appCtx)) return
        if (isWorkerThread()) {
            backfillToLatestInternal(appCtx)
            return
        }
        if (!backfillEnqueued.compareAndSet(false, true)) return
        runOnWorker("backfillToLatest") {
            try {
                backfillToLatestInternal(appCtx)
            } finally {
                backfillEnqueued.set(false)
            }
        }
    }

    private fun backfillToLatestInternal(ctx: Context) {
        if (
            shouldPauseRegularDynamicGeneration(
                ctx,
                "backfillToLatestInternal",
                "跳过排队中的常规回填",
            )
        ) {
            return
        }
        try {
            val durationSec = getSegmentDurationSec(ctx)
            val intervalSec = getSampleIntervalSec(ctx)
            val todayStart = startOfToday()
            val now = System.currentTimeMillis()
            val shots = SegmentDatabaseHelper.listShotsBetween(ctx, todayStart, now)
            if (shots.isEmpty()) return

            // 只允许从"已存在的最大 end_time"之后开始回填，避免回到过去窗口
            val progressEnd = SegmentDatabaseHelper.getLastSegmentEndTimeInRange(ctx, todayStart, now) ?: todayStart
            try { FileLogger.i(TAG, "回填到最新：duration=${durationSec}秒 interval=${intervalSec}秒 shots=${shots.size} progressEnd=${progressEnd}") } catch (_: Exception) {}

            // 仅以"有图片的时间点"为起点，窗口为 [shotTime, shotTime + duration]
            var i = 0
            // 将 i 快速推进到首个 >= progressEnd 的截图
            while (i < shots.size && shots[i].captureTime < progressEnd) i++
            while (i < shots.size) {
                if (
                    shouldPauseRegularDynamicGeneration(
                        ctx,
                        "backfillToLatestInternal",
                        "停止继续创建新的常规动态",
                    )
                ) {
                    return
                }
                val planned = firstSafeWindowFromShots(
                    ctx = ctx,
                    shots = shots,
                    startIndex = i,
                    durationMs = durationSec * 1000L,
                    nowMillis = now,
                    dayEndMillis = null,
                ) ?: break
                val windowStart = planned.startTime
                val windowEnd = planned.endTime
                if (windowEnd > now) break // 仅处理已完整结束的窗口
                if (windowStart <= progressEnd) {
                    // 窗口在进度之前，跳过到第一个 >= progressEnd 的截图
                    while (i < shots.size && shots[i].captureTime < progressEnd) i++
                    continue
                }

                // 已存在完全相同的段落则跳过
                if (!SegmentDatabaseHelper.hasSegmentExact(ctx, windowStart, windowEnd)) {
                    // 若存在进行中的 collecting 段落，仅跳过与其时间范围重叠的窗口；
                    // 对于早于 active.startTime 的窗口继续回填，避免整体中断导致大段时间被跳过。
                    val active = SegmentDatabaseHelper.getCollectingSegment(ctx)
                    if (active != null) {
                        val overlap = !(windowEnd <= active.startTime || windowStart >= active.endTime)
                        if (overlap) {
                            // 跳过到不与 active 重叠的下一张（>= active.endTime）
                            var j2 = i + 1
                            while (j2 < shots.size && shots[j2].captureTime < active.endTime) j2++
                            i = j2
                            continue
                        }
                    }

                    if (!ensureNoRootOverlapBeforeCreate(ctx, windowStart, windowEnd, "backfillToLatest")) {
                        var j2 = i + 1
                        while (j2 < shots.size && shots[j2].captureTime < windowEnd) j2++
                        i = if (j2 <= i) i + 1 else j2
                        continue
                    }

                    val key = "$windowStart|$windowEnd"
                    if (creatingWindows.add(key)) {
                        try {
                            val segId = SegmentDatabaseHelper.createSegment(
                                ctx,
                                windowStart,
                                windowEnd,
                                durationSec,
                                intervalSec,
                                status = "collecting"
                            )
                            if (segId > 0) {
                                activeSegmentId = segId
                                try { FileLogger.i(TAG, "段落(由回填创建)：id=${segId} start=${windowStart} end=${windowEnd} duration=${durationSec}秒 interval=${intervalSec}秒") } catch (_: Exception) {}
                                tryCollectSamplesAndMaybeFinish(ctx)
                            }
                        } finally {
                            creatingWindows.remove(key)
                        }
                    }
                }

                // 跳到"下一个有图片且时间 >= windowEnd"的索引
                var j = i + 1
                while (j < shots.size && shots[j].captureTime < windowEnd) j++
                i = j
            }
        } catch (e: Exception) {
            try { FileLogger.w(TAG, "回填到最新异常：${e.message}") } catch (_: Exception) {}
        }
    }

    private fun finishSegment(ctx: Context, seg: SegmentDatabaseHelper.Segment, samples: List<SegmentDatabaseHelper.Sample>, force: Boolean = false) {
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        if (
            shouldPauseRegularDynamicGeneration(
                appCtx,
                "finishSegment",
                "跳过新的常规动态总结",
            )
        ) {
            return
        }
        // 并发去重：同一段落只允许一次完成流程
        if (!finishingSegments.add(seg.id)) {
            return
        }
        val windowKey = "${seg.startTime}|${seg.endTime}"
        if (!finishingWindows.add(windowKey)) {
            // 已有同窗口在完成流程中，跳过本次
            finishingSegments.remove(seg.id)
            return
        }
        // 强制异步：避免 finish(含 AI) 阻塞 tick/回填等调度链路
        postOnWorker("finishSegment") finishBlock@ {
            val ctx = appCtx
            if (
                shouldPauseRegularDynamicGeneration(
                    ctx,
                    "finishSegment",
                    "跳过排队中的常规动态总结",
                )
            ) {
                return@finishBlock
            }
            var mergeOutputText: String? = null
            var mergeStructuredJson: String? = null
            val preservedOriginalSummaries: List<String> = run {
                if (!force) return@run emptyList()
                val isMerged = try { SegmentDatabaseHelper.isMergedSegment(ctx, seg.id) } catch (_: Exception) { false }
                if (!isMerged) return@run emptyList()
                return@run try {
                    val existing = SegmentDatabaseHelper.getResultForSegment(ctx, seg.id)
                    val overall = extractOverallSummaryFromStructuredOrText(
                        parseStructuredJsonObject(existing.second),
                        existing.first
                    )
                    val parts = splitMergedEventSummaryParts(overall)
                    if (parts.size > 1) parts.drop(1) else emptyList()
                } catch (_: Exception) {
                    emptyList()
                }
            }
            try {
                try { FileLogger.i(TAG, "finish：开始 segment=${seg.id} samples=${samples.size} force=${force}") } catch (_: Exception) {}
                // 兜底：无样本则不进行AI
                if (samples.isEmpty()) {
                    try { FileLogger.w(TAG, "finish：无样本，跳过 AI seg=${seg.id}") } catch (_: Exception) {}
                    SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                    return@finishBlock
                }
                // 非强制模式下：存在结果即跳过；强制模式则无视现有结果重新生成
                if (!force) {
                    // 若同窗口已有任一结果，直接标记完成并跳过AI调用
                    if (SegmentDatabaseHelper.hasAnyResultForWindow(ctx, seg.startTime, seg.endTime)) {
                        try { FileLogger.w(TAG, "finish：窗口已有结果，跳过 seg=${seg.id}") } catch (_: Exception) {}
                        SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                        return@finishBlock
                    }
                    // 双重检查：该段落是否已写入结果（在极端并发下）
                    if (SegmentDatabaseHelper.hasResultForSegment(ctx, seg.id)) {
                        SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                        return@finishBlock
                    }
                }
                // 统一图片限额：确保提示中枚举的文件与实际送入模型的图片一致
                val capBySeg = (seg.durationSec / seg.sampleIntervalSec).coerceAtLeast(1)
                val effectiveCap = kotlin.math.min(capBySeg, PROVIDER_IMAGE_HARD_LIMIT)
                val samplesOrdered = samples.sortedBy { it.captureTime }
                val effSamples = if (samplesOrdered.size > effectiveCap) evenPick(samplesOrdered, effectiveCap) else samplesOrdered

                // 依据应用语言注入"语言强制策略"并选择对应提示词（支持 _zh/_en 与旧键回退）
                val langOpt = try { ctx.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE).getString("flutter.locale_option", "system") } catch (_: Exception) { "system" }
                val sysLang = try { java.util.Locale.getDefault().language?.lowercase() } catch (_: Exception) { "en" } ?: "en"
                val effectiveLang = when (langOpt) {
                    "zh", "en", "ja", "ko" -> langOpt
                    "system" -> when {
                        sysLang.startsWith("zh") -> "zh"
                        sysLang.startsWith("ja") -> "ja"
                        sysLang.startsWith("ko") -> "ko"
                        else -> "en"
                    }
                    else -> "en"
                }
                val isZhLang = effectiveLang == "zh"

                val extraHeader = try {
                    val key = when (effectiveLang) {
                        "zh" -> "prompt_segment_extra_zh"
                        else -> "prompt_segment_extra_en"
                    }
                    AISettingsNative.readSettingValue(ctx, key)
                } catch (_: Exception) { null }
                val legacyHeaderLang = try {
                    val key = when (effectiveLang) {
                        "zh" -> "prompt_segment_zh"
                        else -> "prompt_segment_en"
                    }
                    AISettingsNative.readSettingValue(ctx, key)
                } catch (_: Exception) { null }
                val legacyHeader = try {
                    AISettingsNative.readSettingValue(ctx, "prompt_segment")
                } catch (_: Exception) { null }

                val defaultHeaderZh =
                    "请基于以下多张屏幕图片进行中文总结，并输出结构化结果；必须严格遵循：\n" +
                    "- 禁止使用OCR文本；直接理解图片内容；\n" +
                    "- 不要逐图描述；按应用/主题整合用户在该时间段的'行为总结'（浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等）；\n" +
                    "- 对视频标题、作者、品牌等独特信息，按屏幕原样在输出中保留；\n" +
                    "- 对同一文章/视频/页面的连续图片，归为同一 content_group 做整体总结；\n" +
                    "- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现\\\"## 概览\\\"或\\\"## 总结\\\"等）；随后再使用 Markdown 小节呈现后续内容；\n" +
                    "- Markdown 要求：所有\"用于展示的文本字段\"须使用 Markdown（overall_summary 与 content_groups[].summary；timeline[].summary 可用简短 Markdown；key_actions[].detail 可用精简 Markdown）；禁止使用代码块围栏（例如 ```），仅输出纯 Markdown 文本；\n" +
                    "- overall_summary 必须按以下固定顺序包含且只能包含这三个二级标题：\"## 关键操作\"、\"## 主要活动\"、\"## 重点内容\"。标题中的 \"##\" 后必须保留一个空格；每个小节必须使用 \"- \" 输出至少 3 条要点，且列表项中的 \"-\" 后必须保留一个空格；如信息不足，仍必须保留该小节并至少提供 1 条有意义的占位要点；不得省略、改名或调整顺序。\n" +
                    "- 在\"## 关键操作\"中，将相邻/连续同类行为合并为区间，格式\"HH:mm:ss-HH:mm:ss：行为描述\"（例如\"08:16:41-08:27:21：浏览视频评论\"）；仅在行为中断或切换时新起一条；控制 3-8 条精要；\n" +
                    "以 JSON 输出以下字段（不要省略字段名）：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary；\n" +
                    "仅输出一个 JSON 对象，不要附加解释或 JSON 外的 Markdown；所有展示性内容（含后续小节）请写入 overall_summary 字段的 Markdown；\n" +
                    "字段约定：\n" +
                    "key_actions[]: [{\"type\":\"pay|login|register|permission_grant|oauth_authorize|purchase|bind_account|unbind_account|captcha|biometric|other\",\"app\":\"应用名\",\"ref_image\":\"文件名\",\"ref_time\":\"HH:mm:ss\",\"detail\":\"(Markdown) 精简说明，避免敏感信息\",\"confidence\":0.0}],\n" +
                    "content_groups[]: [{\"group_type\":\"article|video|page|playlist|feed\",\"title\":\"可为空\",\"app\":\"应用名\",\"start_time\":\"HH:mm:ss\",\"end_time\":\"HH:mm:ss\",\"image_count\":1,\"representative_images\":[\"文件名1\",\"文件名2\"],\"summary\":\"(Markdown) 本组内容的要点\"}],\n" +
                    "timeline[]: [{\"time\":\"HH:mm:ss\",\"app\":\"应用名\",\"action\":\"浏览|观看|聊天|购物|搜索|编辑|游戏|设置|下载|分享|其他\",\"summary\":\"(Markdown) 一句话行为（可简短强调）\"}],\n" +
                    "overall_summary: \"(Markdown) 开头是一段无标题的总结段落，随后使用小节与要点，避免流水账并尽可能保留信息\""

                val defaultHeaderEn =
                    "Please summarize multiple screenshots in English and output structured results. STRICT rules:\n" +
                    "- Do NOT use OCR text; understand images directly.\n" +
                    "- Do not describe image-by-image; integrate a 'behavior summary' over the time window by app/topic (browse/watch/chat/shop/work/settings/download/share/game, etc.).\n" +
                    "- Preserve unique on-screen info like video titles, authors, brands as-is.\n" +
                    "- Merge consecutive images from the same article/video/page into one content_group for a holistic summary.\n" +
                    "- Start with one plain paragraph (no heading) summarizing the time window; then present later content with Markdown subsections.\n" +
                    "- Markdown requirements: all display texts must use Markdown (overall_summary and content_groups[].summary; timeline[].summary may use brief Markdown; key_actions[].detail may use concise Markdown). NO code fences (```), only pure Markdown.\n" +
                    "- overall_summary MUST include exactly these three second-level sections in this fixed order:\n" +
                    "  \\\"## Key Actions\\\"\\n  \\\"## Main Activities\\\"\\n  \\\"## Key Content\\\"\\n" +
                    "  Each section MUST contain at least 3 bullet points using \\\"- \\\". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet. Do not omit or rename sections.\n" +
                    "- In \"## Key Actions\", merge adjacent/continuous same-type actions as a time range \"HH:mm:ss-HH:mm:ss: description\"; only when action breaks/changes start a new item; keep 3–8 concise items.\n" +
                    "Output these JSON fields (do not omit field names): apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.\n" +
                    "Only output a single JSON object; do not add explanations or Markdown outside JSON; all display content belongs to overall_summary (Markdown).\n" +
                    "Field conventions:\n" +
                    "key_actions[]: [{\"type\":\"pay|login|register|permission_grant|oauth_authorize|purchase|bind_account|unbind_account|captcha|biometric|other\",\"app\":\"App\",\"ref_image\":\"filename\",\"ref_time\":\"HH:mm:ss\",\"detail\":\"(Markdown) brief, avoid sensitive info\",\"confidence\":0.0}],\n" +
                    "content_groups[]: [{\"group_type\":\"article|video|page|playlist|feed\",\"title\":\"optional\",\"app\":\"App\",\"start_time\":\"HH:mm:ss\",\"end_time\":\"HH:mm:ss\",\"image_count\":1,\"representative_images\":[\"file1\",\"file2\"],\"summary\":\"(Markdown) group highlights\"}],\n" +
                    "timeline[]: [{\"time\":\"HH:mm:ss\",\"app\":\"App\",\"action\":\"browse|watch|chat|shop|search|edit|game|settings|download|share|other\",\"summary\":\"(Markdown) one-liner (may emphasize briefly)\"}],\n" +
                    "overall_summary: \"(Markdown) start with a single untitled paragraph; then sections with bullets; avoid narration and retain key info\""

                val languagePolicy = getStringByLang(
                    ctx,
                    effectiveLang,
                    R.string.ai_language_policy_zh,
                    R.string.ai_language_policy_en,
                    R.string.ai_language_policy_ja,
                    R.string.ai_language_policy_ko
                )
                val baseHeader = getStringByLang(
                    ctx,
                    effectiveLang,
                    R.string.segment_prompt_default_zh,
                    R.string.segment_prompt_default_en,
                    R.string.segment_prompt_default_ja,
                    R.string.segment_prompt_default_ko
                )
                val addon = sequenceOf(extraHeader, legacyHeaderLang, legacyHeader)
                    .firstOrNull { it != null && it.trim().isNotEmpty() }
                    ?.trim()
                val headerBuilder = StringBuilder()
                headerBuilder.append(languagePolicy).append("\n\n").append(baseHeader)
                if (!addon.isNullOrEmpty()) {
                    val label = when (effectiveLang) {
                        "zh" -> "附加说明："
                        "ja" -> "追加指示："
                        "ko" -> "추가 지침:"
                        else -> "Additional instructions:"
                    }
                    headerBuilder.append("\n\n").append(label).append('\n').append(addon)
                }
                val header = headerBuilder.toString()

                // 构造描述（仅时间点与应用，不包含OCR文本）
                val sb = StringBuilder()
                val timeRangeLabel = getStringByLang(ctx, effectiveLang, R.string.label_time_range_zh, R.string.label_time_range_en, R.string.label_time_range_ja, R.string.label_time_range_ko)
                val shotLabel = getStringByLang(ctx, effectiveLang, R.string.label_screenshot_at_zh, R.string.label_screenshot_at_en, R.string.label_screenshot_at_ja, R.string.label_screenshot_at_ko)
                val imageIndexLabel = when (effectiveLang) {
                    "zh" -> "图片索引（仅使用序号引用图片）"
                    "ja" -> "画像インデックス（画像参照は番号のみ）"
                    "ko" -> "이미지 인덱스(번호로만 참조)"
                    else -> "Image index list (reference by number only)"
                }
                val orderedForPrompt = effSamples.sortedBy { it.captureTime }

                sb.append(header).append('\n')
                sb.append(timeRangeLabel).append(fmt(seg.startTime)).append(" - ").append(fmt(seg.endTime)).append('\n')
                sb.append(imageIndexLabel).append('\n')
                for ((idx, s) in orderedForPrompt.withIndex()) {
                    val appDisplay = s.appName.trim().ifEmpty { s.appPackageName.trim() }
                    sb.append(shotLabel)
                        .append("[#").append(idx + 1).append("] ")
                        .append(fmt(s.captureTime))
                        .append(" | ")
                        .append(appDisplay)
                        .append('\n')
                }

                val prompt = sb.toString()
                if (
                    shouldPauseRegularDynamicGeneration(
                        ctx,
                        "finishSegment",
                        "阻止启动新的常规 AI 总结",
                    )
                ) {
                    return@finishBlock
                }
                try { FileLogger.i(TAG, "finish：调用 AI images=${effSamples.size}/${samples.size} seg=${seg.id}") } catch (_: Exception) {}
                val result = callGeminiWithImages(ctx, seg, effSamples, prompt)
                try {
                    FileLogger.i(TAG, "finish：AI 模型=${result.model} 输出长度=${result.outputText.length}")
                    val preview = truncateForLog(result.outputText, 3000)
                    FileLogger.i(TAG, "AI响应预览: ${preview}")
                } catch (_: Exception) {}
                // 将合并需要的摘要提前缓存；合并任务放到 finally 之后异步执行，避免阻塞完成清理。
                var outputToSave = result.outputText
                var structuredToSave = result.structuredJson
                if (preservedOriginalSummaries.isNotEmpty()) {
                    val patched = attachOriginalSummariesToMergedResult(
                        mergedOutputText = outputToSave,
                        mergedStructuredJson = structuredToSave,
                        prevOriginals = emptyList(),
                        curOriginals = preservedOriginalSummaries
                    )
                    outputToSave = patched.first
                    structuredToSave = patched.second
                }
                structuredToSave = normalizeImageRefsToFilenames(structuredToSave, effSamples)
                mergeOutputText = outputToSave
                mergeStructuredJson = structuredToSave
                SegmentDatabaseHelper.saveResult(
                    ctx,
                    seg.id,
                    provider = "gemini",
                    model = result.model,
                    outputText = outputToSave,
                    structuredJson = structuredToSave,
                    categories = result.categories,
                    rawRequest = result.rawRequest,
                    rawResponse = result.rawResponse
                )
                // 将图片标签/描述写入全局可复用表（按 file_path）
                try {
                    SegmentDatabaseHelper.upsertAiImageMetaFromStructuredJson(
                        ctx,
                        segmentId = seg.id,
                        samples = effSamples,
                        structuredJson = structuredToSave,
                        lang = effectiveLang
                    )
                } catch (_: Exception) {}
                // 重要：AI 结果已落盘，立即标记 completed，避免后续“合并链路”卡住导致 UI 长期显示 collecting
                // （即使后续 merge 失败/超时，段落本身也应视为已完成）
                try { SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed") } catch (_: Exception) {}
            } catch (e: Exception) {
                FileLogger.w(TAG, "finishSegment AI 异常：${e.message}")
                // 捕获更详细的异常类型与栈
                FileLogger.w(TAG, "AI 异常类型=${e::class.java.name}")
                FileLogger.w(TAG, "AI 异常堆栈=\n" + (e.stackTraceToString()))
                // 将错误预览文本持久化，供前端错误样式展示（即使配置读取失败，也要写入可见错误，避免 UI 一直为空）
                try {
                    val msg = e.message ?: "unknown error"
                    val idx = msg.indexOf('{')
                    val body = if (idx >= 0) msg.substring(idx) else msg
                    val previewLine = "AI error: " + body
                    var modelName = "unknown"
                    var baseUrl = ""
                    try {
                        val cfg = AISettingsNative.readConfigSnapshot(ctx)
                        if (cfg.model.isNotBlank()) modelName = cfg.model
                        baseUrl = cfg.baseUrl
                    } catch (_: Exception) {}
                    val reqTrace: String? = try {
                        val sbReq = StringBuilder()
                        sbReq.append("=== AI Request (exception) ===").append('\n')
                        if (baseUrl.trim().isNotEmpty()) {
                            sbReq.append("base_url=").append(baseUrl.trim()).append('\n')
                        }
                        sbReq.append("model=").append(modelName).append('\n')
                        sbReq.append("segment_id=").append(seg.id).append('\n')
                        sbReq.append("note=prompt not captured (exception before trace persisted)").append('\n')
                        sbReq.toString().trimEnd()
                    } catch (_: Exception) { null }
                    val respTrace: String? = try {
                        val sbResp = StringBuilder()
                        sbResp.append("=== AI Response (exception) ===").append('\n')
                        sbResp.append("message=").append(msg).append('\n')
                        sbResp.append('\n')
                        sbResp.append(e.stackTraceToString())
                        sbResp.toString().trimEnd()
                    } catch (_: Exception) { msg }
                    var outText = previewLine
                    var outStructured: String? = null
                    if (preservedOriginalSummaries.isNotEmpty()) {
                        val patched = attachOriginalSummariesToMergedResult(
                            mergedOutputText = outText,
                            mergedStructuredJson = outStructured,
                            prevOriginals = emptyList(),
                            curOriginals = preservedOriginalSummaries
                        )
                        outText = patched.first
                        outStructured = patched.second
                    }
                    SegmentDatabaseHelper.saveResult(
                        ctx,
                        seg.id,
                        provider = "gemini",
                        model = modelName,
                        outputText = outText,
                        structuredJson = outStructured,
                        categories = null,
                        rawRequest = reqTrace,
                        rawResponse = respTrace
                    )
                } catch (_: Exception) {}
            } finally {
                SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                activeSegmentId = -1L
                try { FileLogger.i(TAG, "finish：segment=${seg.id} 已完成") } catch (_: Exception) {}
                finishingSegments.remove(seg.id)
                finishingWindows.remove(windowKey)
                // 合并任务异步执行：避免 merge 阻塞 finish 的 finally，导致去重集合无法释放/状态无法推进。
                val out = mergeOutputText
                if (out != null && out.isNotBlank()) {
                    val sj = mergeStructuredJson
                    postOnWorker("merge") {
                        try { tryCompareAndMergeBackward(ctx, seg, samples, out, sj) } catch (_: Exception) {}
                    }
                }
            }
        }
    }


    data class DynamicRebuildAiProbeResult(
        val success: Boolean,
        val keyLabel: String,
        val model: String,
        val attemptsUsed: Int,
        val totalCandidates: Int,
        val responsePreview: String?,
        val failureMessages: List<String>,
    ) {
        val successSummary: String
            get() {
                val key = keyLabel.ifBlank { "legacy" }
                val modelText = model.ifBlank { "-" }
                val preview = responsePreview?.trim().orEmpty()
                return if (preview.isEmpty()) {
                    "$key · $modelText"
                } else {
                    "$key · $modelText · $preview"
                }
            }

        val failureSummary: String
            get() = failureMessages.lastOrNull()?.trim().orEmpty()
    }

    fun probeDynamicRebuildAiAfterFailure(
        ctx: Context,
        aiConfigOverride: AISettingsNative.AIConfig?,
        attemptsPerKey: Int = 3,
        timeoutMs: Long = 20_000L,
    ): DynamicRebuildAiProbeResult {
        val configs = resolveAiConfigCandidates(ctx, aiConfigOverride)
        val safeAttempts = attemptsPerKey.coerceAtLeast(1)
        val failures = ArrayList<String>()
        if (configs.isEmpty()) {
            return DynamicRebuildAiProbeResult(
                success = false,
                keyLabel = "",
                model = aiConfigOverride?.model.orEmpty(),
                attemptsUsed = 0,
                totalCandidates = 0,
                responsePreview = null,
                failureMessages = listOf("没有可用于连续测试的 AI Key"),
            )
        }

        var attemptsUsed = 0
        for ((candidateIndex, cfg) in configs.withIndex()) {
            val keyLabel = (cfg.providerKeyName ?: "").trim()
                .ifEmpty { cfg.providerKeyId?.let { "key#$it" } ?: "legacy" }
            for (attempt in 0 until safeAttempts) {
                attemptsUsed += 1
                val token = buildDynamicProbeToken()
                try {
                    FileLogger.i(
                        TAG,
                        "动态重建失败后连续测试：candidate=${candidateIndex + 1}/${configs.size} key=$keyLabel model=${cfg.model} attempt=${attempt + 1}/$safeAttempts",
                    )
                } catch (_: Exception) {}
                try {
                    val response = executeDynamicProbeRequest(
                        ctx = ctx,
                        cfg = cfg,
                        token = token,
                        timeoutMs = timeoutMs,
                    )
                    if (!probeResponseHasContent(response)) {
                        throw IllegalStateException(
                            "连续测试响应为空",
                        )
                    }
                    AISettingsNative.markProviderKeySuccess(ctx, cfg)
                    return DynamicRebuildAiProbeResult(
                        success = true,
                        keyLabel = keyLabel,
                        model = cfg.model,
                        attemptsUsed = attemptsUsed,
                        totalCandidates = configs.size,
                        responsePreview = truncateForLog(response.trim(), 120),
                        failureMessages = failures.toList(),
                    )
                } catch (e: DynamicRebuildCancelledException) {
                    throw e
                } catch (e: Exception) {
                    val msg = e.message ?: e.toString()
                    val type = classifyAiFailure(msg)
                    AISettingsNative.markProviderKeyFailure(
                        ctx,
                        cfg.providerKeyId,
                        type,
                        msg,
                        attempt + 1,
                    )
                    val line =
                        "$keyLabel attempt ${attempt + 1}/$safeAttempts [$type]: ${truncateForLog(msg, 300)}"
                    failures.add(line)
                    try { FileLogger.w(TAG, "动态重建失败后连续测试失败：$line") } catch (_: Exception) {}
                }
            }
        }

        return DynamicRebuildAiProbeResult(
            success = false,
            keyLabel = "",
            model = aiConfigOverride?.model.orEmpty(),
            attemptsUsed = attemptsUsed,
            totalCandidates = configs.size,
            responsePreview = null,
            failureMessages = failures.toList(),
        )
    }


    /**
     * 与上一个已完成段进行"是否为同一事件"的判断，若相同则合并并生成新总结；
     * 合并策略：将时间窗口扩展为 [prev.start, cur.end] 并基于合并后的样本重新请求AI。
     * 图片采样：若合计图片数超过 MAX_COMPARE_IMAGES，则两段各取一半，按时间均匀抽样。
     */
    private fun tryCompareAndMergeBackward(
        ctx: Context,
        cur: SegmentDatabaseHelper.Segment,
        curSamples: List<SegmentDatabaseHelper.Sample>,
        curOutputText: String,
        curStructured: String?,
        forceMerge: Boolean = false,
        specifiedPrevSegmentId: Long? = null,
        lockHeld: Boolean = false
    ) {
        if (
            shouldPauseRegularDynamicGeneration(
                ctx,
                "tryCompareAndMergeBackward",
                "跳过新的常规动态合并",
            )
        ) {
            return
        }
        if (!lockHeld) {
            if (!mergingSegments.add(cur.id)) {
                try { FileLogger.i(TAG, "merge: skip because already merging seg=${cur.id}") } catch (_: Exception) {}
                return
            }
        }
        try {
            try { FileLogger.i(TAG, "merge: begin compare cur=${cur.id} start=${fmt(cur.startTime)} with previous") } catch (_: Exception) {}
            val prev = run {
                val specified = specifiedPrevSegmentId?.takeIf { it > 0L }
                if (specified != null) {
                    val s = SegmentDatabaseHelper.getSegmentById(ctx, specified)
                    val ok = if (s != null && s.status == "completed") {
                        val rr = SegmentDatabaseHelper.getResultForSegment(ctx, s.id)
                        val ot = rr.first?.trim() ?: ""
                        val sj = rr.second?.trim() ?: ""
                        (ot.isNotEmpty() && !ot.equals("null", ignoreCase = true)) ||
                            (sj.isNotEmpty() && !sj.equals("null", ignoreCase = true))
                    } else false
                    if (ok) s else getOverlapOrPreviousCompletedSegmentWithResult(ctx, cur)
                } else {
                    getOverlapOrPreviousCompletedSegmentWithResult(ctx, cur)
                }
            }
            if (prev == null) {
                try { FileLogger.i(TAG, "merge: no previous completed-with-result segment before ${fmt(cur.startTime)}") } catch (_: Exception) {}
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        ctx,
                        segmentId = cur.id,
                        prevSegmentId = null,
                        decisionJson = null,
                        reason = if (forceMerge) "强制合并失败：未找到上一事件" else "未找到上一事件，跳过合并",
                        forced = forceMerge
                    )
                } catch (_: Exception) {}
                SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                return
            }

        // 动态合并硬限制：若触发限制则直接跳过 AI 判定与合并，并在 UI 展示原因。
        if (!forceMerge) {
            val maxSpanSecRaw = try {
                UserSettingsStorage.getInt(
                    ctx,
                    UserSettingsKeysNative.MERGE_DYNAMIC_MAX_SPAN_SEC,
                    3 * 3600
                )
            } catch (_: Exception) { 3 * 3600 }
            val maxGapSecRaw = try {
                UserSettingsStorage.getInt(
                    ctx,
                    UserSettingsKeysNative.MERGE_DYNAMIC_MAX_GAP_SEC,
                    3600
                )
            } catch (_: Exception) { 3600 }
            val maxSpanSec = if (maxSpanSecRaw < 0) 0 else maxSpanSecRaw
            val maxGapSec = if (maxGapSecRaw < 0) 0 else maxGapSecRaw
            val mergedSpanMs = kotlin.math.max(
                0L,
                kotlin.math.max(prev.endTime, cur.endTime) - kotlin.math.min(prev.startTime, cur.startTime),
            )
            val mergedGapMs = if (cur.startTime >= prev.endTime) cur.startTime - prev.endTime else 0L
            val spanExceeded = maxSpanSec > 0 && mergedSpanMs > maxSpanSec.toLong() * 1000L
            val gapExceeded = maxGapSec > 0 && mergedGapMs > maxGapSec.toLong() * 1000L
            if (spanExceeded || gapExceeded) {
                val spanMin = mergedSpanMs / 60000L
                val gapMin = mergedGapMs / 60000L
                val details = ArrayList<String>()
                if (spanExceeded) {
                    val limitMin = maxSpanSec.toLong() / 60L
                    details.add("触发整体跨度限制：${spanMin}分钟 > ${limitMin}分钟")
                }
                if (gapExceeded) {
                    val limitMin = maxGapSec.toLong() / 60L
                    details.add("触发时间间隔限制：${gapMin}分钟 > ${limitMin}分钟")
                }
                val reason = details.joinToString("；") + "，系统禁止合并"
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        ctx,
                        segmentId = cur.id,
                        prevSegmentId = prev.id,
                        decisionJson = null,
                        reason = reason,
                        forced = false
                    )
                } catch (_: Exception) {}
                SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                return
            }
        }

        // 读取上一个段的样本与文本（用于"已引用图片数"判断）
        val prevSamples = SegmentDatabaseHelper.getSamplesForSegment(ctx, prev.id)
        try { FileLogger.i(TAG, "merge: prev=${prev.id} A=${prevSamples.size} imgs, cur=${cur.id} B=${curSamples.size} imgs") } catch (_: Exception) {}
        val seenFiles = java.util.HashSet<String>()
        for (s in prevSamples) { seenFiles.add(s.filePath) }
        for (s in curSamples) { seenFiles.add(s.filePath) }
        val referencedCount = prevSamples.size + curSamples.size
        val referencedUnique = seenFiles.size
        try { FileLogger.i(TAG, "merge: referenced images total=${referencedCount} unique=${referencedUnique}") } catch (_: Exception) {}

        val mergedAllSamples = mergeSamples(prevSamples, curSamples)
        val mergedUniqueSamples = mergedAllSamples

        // 动态合并硬限制：图片数量（仅自动合并；强制合并不受限）
        if (!forceMerge) {
            val maxImagesRaw = try {
                UserSettingsStorage.getInt(
                    ctx,
                    UserSettingsKeysNative.MERGE_DYNAMIC_MAX_IMAGES,
                    200
                )
            } catch (_: Exception) { 200 }
            val maxImages = if (maxImagesRaw < 0) 0 else maxImagesRaw
            val imagesExceeded = maxImages > 0 && mergedUniqueSamples.size > maxImages
            if (imagesExceeded) {
                val reason = "触发图片数量限制：${mergedUniqueSamples.size}张 > ${maxImages}张，系统禁止合并"
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        ctx,
                        segmentId = cur.id,
                        prevSegmentId = prev.id,
                        decisionJson = null,
                        reason = reason,
                        forced = false
                    )
                } catch (_: Exception) {}
                SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                return
            }
        }

        val prevRes = SegmentDatabaseHelper.getResultForSegment(ctx, prev.id)
        val prevOutput = prevRes.first ?: ""

        // —— 合并前判定：提示词引导模型输出 same_event ——（强制合并时跳过）
        if (forceMerge) {
            try {
                SegmentDatabaseHelper.updateMergeDecisionInfo(
                    ctx,
                    segmentId = cur.id,
                    prevSegmentId = prev.id,
                    decisionJson = null,
                    reason = "用户强制合并：跳过判定，直接执行合并",
                    forced = true
                )
            } catch (_: Exception) {}
        } else run {
            val sb = StringBuilder()
            val langOpt2 = try { ctx.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE).getString("flutter.locale_option", "system") } catch (_: Exception) { "system" }
            val sysLang2 = try { java.util.Locale.getDefault().language?.lowercase() } catch (_: Exception) { "en" } ?: "en"
            val effectiveLang2 = when (langOpt2) {
                "zh", "en", "ja", "ko" -> langOpt2
                "system" -> when {
                    sysLang2.startsWith("zh") -> "zh"
                    sysLang2.startsWith("ja") -> "ja"
                    sysLang2.startsWith("ko") -> "ko"
                    else -> "en"
                }
                else -> "en"
            }
            val isZh2 = effectiveLang2 == "zh"
            val langPolicy2 = getStringByLang(
                ctx,
                effectiveLang2,
                R.string.ai_language_policy_zh,
                R.string.ai_language_policy_en,
                R.string.ai_language_policy_ja,
                R.string.ai_language_policy_ko
            )
            sb.append(langPolicy2).append('\n').append('\n')
            if (isZh2) {
                val gapMin = if (cur.startTime >= prev.endTime) (cur.startTime - prev.endTime) / 60000L else 0L
                sb.append("请判断两段时间是否属于同一用户事件：\n")
                    .append("注意：只根据画面语义与行为，不做OCR逐字比对；更关注是否为同一持续活动。\n")
                    .append("合并判定策略（放宽）：\n")
                    .append("- 若两段主要应用相同，或同属'视频观看/文章阅读/信息流浏览/社交浏览/购物浏览/办公操作'等同类行为，即使内容不同也视为同一事件；\n")
                    .append("- 时间间隔仅供参考，不设固定阈值；若后段延续了前段的同类行为或属于同一持续活动，倾向判定 same_event=true；\n")
                    .append("- 短暂且占比很小的打断（例如少量截图/短暂切换）应忽略；\n")
                    .append("- 请输出 JSON：{\\\"same_event\\\":true|false,\\\"reason\\\":\\\"简述\\\",\\\"primary_activity\\\":\\\"watching|reading|browsing|shopping|working|other\\\"}\n")
                    .append("段A：").append(fmt(prev.startTime)).append(" - ").append(fmt(prev.endTime)).append('\n')
                    .append("段B：").append(fmt(cur.startTime)).append(" - ").append(fmt(cur.endTime)).append('\n')
                    .append("两段各自的 overall_summary：\n")
                    .append("A: ").append(extractOverallSummary(prevOutput)).append('\n')
                    .append("B: ").append(extractOverallSummary(curOutputText)).append('\n')
                    .append("两段时间间隔约：").append(gapMin).append(" 分钟\n")
            } else {
                val gapMin = if (cur.startTime >= prev.endTime) (cur.startTime - prev.endTime) / 60000L else 0L
                sb.append("Decide whether the two time ranges belong to the same user event:\n")
                    .append("Note: Judge by on-screen semantics and behavior only; DO NOT rely on OCR word-by-word matching. Focus on whether it's the same continuous activity.\n")
                    .append("Merge decision guidelines (relaxed):\n")
                    .append("- If the main app is the same, or both are of the same activity type (video watching/article reading/feed browsing/social browsing/shopping/working), treat as the same event even when content differs.\n")
                    .append("- The time gap is only a reference (no fixed threshold). If the latter continues the former activity type or appears to be the same continuous activity, prefer same_event=true.\n")
                    .append("- Ignore brief interruptions with small proportion (e.g., few screenshots/short switches).\n")
                    .append("- Output JSON: {\\\"same_event\\\":true|false,\\\"reason\\\":\\\"brief\\\",\\\"primary_activity\\\":\\\"watching|reading|browsing|shopping|working|other\\\"}\n")
                    .append("Range A: ").append(fmt(prev.startTime)).append(" - ").append(fmt(prev.endTime)).append('\n')
                    .append("Range B: ").append(fmt(cur.startTime)).append(" - ").append(fmt(cur.endTime)).append('\n')
                    .append("Each range overall_summary:\n")
                    .append("A: ").append(extractOverallSummary(prevOutput)).append('\n')
                    .append("B: ").append(extractOverallSummary(curOutputText)).append('\n')
                    .append("Approximate gap between ranges: ").append(gapMin).append(" minutes\n")
            }

            // 送入判定的图片：最终受提供方硬上限保护（<= PROVIDER_IMAGE_HARD_LIMIT）。
            val decisionMaxAiImages = PROVIDER_IMAGE_HARD_LIMIT.coerceAtLeast(1)
            try {
                FileLogger.i(
                    TAG,
                    "merge: decision images unique=${mergedUniqueSamples.size} max_ai_images=${decisionMaxAiImages}"
                )
            } catch (_: Exception) {}
            val decide = callGeminiWithImages(
                ctx,
                cur,
                mergedUniqueSamples,
                sb.toString(),
                injectDynamicRules = false,
                maxImagesOverride = decisionMaxAiImages
            )
            val decisionText = decide.outputText
            var decisionJson: String? = null
            var decisionReason: String? = null
            val same: Boolean = try {
                val pair = extractJsonBlocks(decisionText)
                val jsonStr = pair.first
                decisionJson = jsonStr
                if (jsonStr != null) {
                    try {
                        val obj = org.json.JSONObject(jsonStr)
                        val rr = obj.optString("reason", "").trim()
                        if (rr.isNotEmpty()) decisionReason = rr
                        obj.optBoolean("same_event", false)
                    } catch (_: Exception) {
                        Regex("\"same_event\"\\s*:\\s*true", RegexOption.IGNORE_CASE).containsMatchIn(decisionText)
                    }
                } else {
                    Regex("\"same_event\"\\s*:\\s*true", RegexOption.IGNORE_CASE).containsMatchIn(decisionText)
                }
            } catch (_: Exception) {
                Regex("\"same_event\"\\s*:\\s*true", RegexOption.IGNORE_CASE).containsMatchIn(decisionText)
            }
            if (decisionReason.isNullOrBlank()) {
                val t = decisionText.trim()
                decisionReason = if (t.length <= 240) t else (t.substring(0, 240) + "…")
            }
            try {
                SegmentDatabaseHelper.updateMergeDecisionInfo(
                    ctx,
                    segmentId = cur.id,
                    prevSegmentId = prev.id,
                    decisionJson = decisionJson,
                    reason = decisionReason,
                    forced = false
                )
            } catch (_: Exception) {}
            try { FileLogger.i(TAG, "merge: decision same_event=${same} textLen=${decisionText.length}") } catch (_: Exception) {}
            try {
                val preview = truncateForLog(decisionText, 3000)
                FileLogger.i(TAG, "merge decision response: ${preview}")
            } catch (_: Exception) {}
            if (!same) { SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true); return }
        }

        // 合并后生成新的总结：基于合并后的样本重新调用 AI
        val maxAiImages = PROVIDER_IMAGE_HARD_LIMIT.coerceAtLeast(1)
        val mergePlan = planMergeAiInput(
            allSamples = mergedUniqueSamples,
            prevStructuredJson = prevRes.second,
            prevSamples = prevSamples,
            curStructuredJson = curStructured,
            curSamples = curSamples,
            maxAiImages = maxAiImages
        )
        val mergedAiSamples = mergePlan.aiSamples
        val mergeAiConfig = AISettingsNative.readConfigSnapshot(ctx)
        val slimOpenAiMergePrompt = shouldUseSlimOpenAiMergePrompt(mergeAiConfig)
        val mergePrompt = buildMergePrompt(
            ctx,
            prev,
            cur,
            mergedAiSamples,
            textOnlyDescriptions = mergePlan.textOnlyDescriptions,
            totalImages = mergedUniqueSamples.size,
            maxAttachedImages = maxAiImages,
            forced = forceMerge,
            slimImageMetadata = slimOpenAiMergePrompt,
        )
        try {
            FileLogger.i(
                TAG,
                "merge: merging window ${fmt(prev.startTime)}..${fmt(cur.endTime)} images=${mergedAiSamples.size}/${mergedUniqueSamples.size} (max_ai_images=${maxAiImages}) using merge prompt slim_openai_workaround=${slimOpenAiMergePrompt}"
            )
        } catch (_: Exception) {}
        val merged = try {
            callGeminiWithImages(
                ctx,
                cur,
                mergedAiSamples,
                mergePrompt,
                isMerge = true,
                maxImagesOverride = maxAiImages,
            )
        } catch (e: Exception) {
            try {
                SegmentDatabaseHelper.updateMergeDecisionInfo(
                    ctx,
                    segmentId = cur.id,
                    prevSegmentId = prev.id,
                    decisionJson = null,
                    reason = "合并失败：" + (e.message ?: e.toString()),
                    forced = forceMerge
                )
            } catch (_: Exception) {}
            SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
            return
        }
        try { FileLogger.i(TAG, "merge: merged summary saved for seg=${cur.id} outputSize=${merged.outputText.length}") } catch (_: Exception) {}
        // 将"合并后的 AI 输出"落盘
        try {
            val preview2 = truncateForLog(merged.outputText, 3000)
            FileLogger.i(TAG, "merged summary preview: ${preview2}")
        } catch (_: Exception) {}

        // 为“原始事件下拉菜单”补齐合并前内容：
        // 1) 取 prev/cur 的 overall_summary（若 cur 已是合并事件，则取其原始部分）
        // 2) 将这些原始摘要用 `---` 分隔追加到“合并后的 overall_summary”之后
        //    => Flutter 侧可通过 splitMergedEventSummaryParts(summary) 展示原始事件列表
        val prevOriginalSummaries = extractOriginalSummaryPartsForMerge(prevRes.first, prevRes.second)
        val curOriginalSummaries = extractOriginalSummaryPartsForMerge(curOutputText, curStructured)
        val mergedStructuredNormalizedByAiOrder = normalizeImageRefsToFilenames(
            merged.structuredJson,
            mergedAiSamples
        )
        val mergedPatched = attachOriginalSummariesToMergedResult(
            mergedOutputText = merged.outputText,
            mergedStructuredJson = mergedStructuredNormalizedByAiOrder,
            prevOriginals = prevOriginalSummaries,
            curOriginals = curOriginalSummaries
        )
        var mergedOutputTextForSave = mergedPatched.first
        var mergedStructuredForSave = mergedPatched.second
        var mergedCategoriesForSave: String? = merged.categories
        val prevCategoriesFromDb: String? = try { SegmentDatabaseHelper.getSegmentResult(ctx, prev.id)?.categories } catch (_: Exception) { null }
        val curCategoriesFromDb: String? = try { SegmentDatabaseHelper.getSegmentResult(ctx, cur.id)?.categories } catch (_: Exception) { null }

        // 合并事件的时间分隔线下方“一句话关键描述”来自 structured_json.key_actions[0].detail。
        // merge prompt 可能返回纯文本（无法提取 structured_json），或返回的 structured_json 不含 key_actions。
        // 这种情况下，合并会覆盖当前段结果并删除上一段，导致 UI 丢失关键描述；这里用原始事件结果补齐。
        run {
            val sjTrim = mergedStructuredForSave?.trim()
            val mergedObj = parseStructuredJsonObject(sjTrim)
            val sjMissingOrInvalid = mergedObj == null

            // 预先构造一个“基于原始事件的结构化兜底”，只在需要时使用（避免额外开销）。
            fun buildFallback(): TextFirstMergedResult = buildTextFirstMergedResult(
                prevOutputText = prevOutput,
                prevStructuredJson = prevRes.second,
                curOutputText = curOutputText,
                curStructuredJson = curStructured
            )

            fun pickOverallSummaryForFallback(fallback: TextFirstMergedResult): String {
                val candidate = mergedOutputTextForSave.trim()
                if (candidate.isEmpty() || candidate.equals("null", ignoreCase = true)) return fallback.outputText
                // 若像 JSON，则不要直接塞进 overall_summary（会污染展示）；退回到可读的文本兜底
                if (candidate.startsWith("{") && candidate.endsWith("}")) return fallback.outputText
                return candidate
            }

            if (sjMissingOrInvalid) {
                val fallback = buildFallback()
                mergedCategoriesForSave = pickNonEmpty(
                    mergedCategoriesForSave,
                    fallback.categoriesJson,
                    prevCategoriesFromDb,
                    curCategoriesFromDb
                )
                mergedStructuredForSave = try {
                    val obj = JSONObject(fallback.structuredJson)
                    obj.put("overall_summary", pickOverallSummaryForFallback(fallback))
                    obj.toString()
                } catch (_: Exception) {
                    fallback.structuredJson
                }
                return@run
            }

            try {
                fun hasUsableKeyActionDetail(arr: JSONArray?): Boolean {
                    if (arr == null || arr.length() == 0) return false
                    for (i in 0 until arr.length()) {
                        val v = arr.opt(i)
                        when (v) {
                            is JSONObject -> {
                                val d = v.optString("detail", "").trim()
                                if (d.isNotEmpty()) return true
                            }
                            is String -> {
                                if (v.trim().isNotEmpty()) return true
                            }
                        }
                    }
                    return false
                }

                // structured_json 存在但 key_actions 缺失/为空/不可用于 UI：从原始事件补齐
                val ka = mergedObj.optJSONArray("key_actions")
                if (!hasUsableKeyActionDetail(ka)) {
                    val fallback = buildFallback()
                    mergedCategoriesForSave = pickNonEmpty(
                        mergedCategoriesForSave,
                        fallback.categoriesJson,
                        prevCategoriesFromDb,
                        curCategoriesFromDb
                    )
                    try {
                        val fbObj = JSONObject(fallback.structuredJson)
                        val fbKa = fbObj.optJSONArray("key_actions")
                        if (hasUsableKeyActionDetail(fbKa)) {
                            mergedObj.put("key_actions", fbKa)
                        }
                    } catch (_: Exception) {
                    }
                }
                mergedStructuredForSave = mergedObj.toString()
            } catch (_: Exception) {
            }
        }

        // 合并 categories（标签）：始终兼容原始事件的 categories，避免合并后丢失。
        run {
            fun readCategoriesFromColumn(categories: String?): List<String> {
                val raw = categories?.trim()
                if (raw.isNullOrEmpty() || raw.equals("null", ignoreCase = true)) return emptyList()
                return try {
                    val arr = JSONArray(raw)
                    val out = ArrayList<String>(arr.length())
                    for (i in 0 until arr.length()) {
                        val v = arr.optString(i, "").trim()
                        if (v.isNotEmpty() && !v.equals("null", ignoreCase = true)) out.add(v)
                    }
                    out
                } catch (_: Exception) {
                    raw.split(Regex("[,，;；\\s]+"))
                        .map { it.trim() }
                        .filter { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
                }
            }

            val mergedObj = parseStructuredJsonObject(mergedStructuredForSave)
            val prevObj = parseStructuredJsonObject(prevRes.second)
            val curObj = parseStructuredJsonObject(curStructured)

            val originalCats = mergeUniqueStrings(
                mergeUniqueStrings(
                    readStringList(prevObj, "categories"),
                    readCategoriesFromColumn(prevCategoriesFromDb)
                ),
                mergeUniqueStrings(
                    readStringList(curObj, "categories"),
                    readCategoriesFromColumn(curCategoriesFromDb)
                )
            )
            val mergedCats = readStringList(mergedObj, "categories")
            val cats = mergeUniqueStrings(originalCats, mergedCats)
            if (cats.isEmpty()) return@run

            val catArr = JSONArray()
            for (v in cats) catArr.put(v)
            mergedCategoriesForSave = catArr.toString()

            if (mergedObj != null) {
                try {
                    mergedObj.put("categories", catArr)
                    mergedStructuredForSave = mergedObj.toString()
                } catch (_: Exception) {
                }
            }
        }
        val mergedWindowStart = kotlin.math.min(prev.startTime, cur.startTime)
        val mergedWindowEnd = kotlin.math.max(prev.endTime, cur.endTime)
        // 更新当前段时间窗口到合并范围
        SegmentDatabaseHelper.updateSegmentWindow(ctx, cur.id, mergedWindowStart, mergedWindowEnd)
        // 合并后必须写回 samples：否则删除 prev 后，其样本将永久丢失（导致图片标签/描述/引用图片缺失）。
        var mergedSamplesForUi: List<SegmentDatabaseHelper.Sample> = mergedUniqueSamples
        try {
            val curAfter = SegmentDatabaseHelper.getSegmentById(ctx, cur.id)
            if (curAfter != null) {
                val rebuilt = buildSamplesForSegment(ctx, curAfter)
                if (rebuilt.isNotEmpty()) {
                    mergedSamplesForUi = mergeSamples(mergedUniqueSamples, rebuilt)
                }
            }
            try { SegmentDatabaseHelper.saveSamples(ctx, cur.id, mergedSamplesForUi) } catch (_: Exception) {}
        } catch (_: Exception) {}
        // 合并结果默认不一定包含 image_descriptions/image_tags：尽量从原始事件结果中补齐，避免合并后“图片描述/NSFW 标签”缺失
        val mergedStructuredWithImages = mergeImageDescriptionsIntoStructuredJson(
            mergedStructuredJson = mergedStructuredForSave,
            mergedSamplesForUi = mergedSamplesForUi,
            mergedAiSamples = mergedAiSamples,
            prevStructuredJson = prevRes.second,
            prevSamples = prevSamples,
            curStructuredJson = curStructured,
            curSamples = curSamples
        ) ?: mergedStructuredForSave
        val mergedStructuredFinal = normalizeImageRefsToFilenames(
            mergedStructuredWithImages,
            mergedAiSamples
        ) ?: mergedStructuredWithImages
        // 覆写当前段的结果（保持上一个不变），并标记上一个段状态为 completed-merged 可选
        SegmentDatabaseHelper.saveResult(
            ctx,
            cur.id,
            provider = "gemini",
            model = merged.model,
            outputText = mergedOutputTextForSave,
            structuredJson = mergedStructuredFinal,
            categories = mergedCategoriesForSave,
            rawRequest = merged.rawRequest,
            rawResponse = merged.rawResponse
        )
        // 将合并后的图片标签/描述写入全局可复用表（按 file_path），避免合并事件在查看器/语义搜索中丢失图片元数据
        try {
            SegmentDatabaseHelper.upsertAiImageMetaFromStructuredJson(
                ctx,
                segmentId = cur.id,
                samples = mergedSamplesForUi,
                structuredJson = mergedStructuredFinal,
                lang = null
            )
        } catch (_: Exception) {}
        // 标记当前段为"已合并"，用于前端展示
        try { SegmentDatabaseHelper.setMergedFlag(ctx, cur.id, true) } catch (_: Exception) {}
        // 合并成功后：删除被合并的前一事件，避免同时存在
        try {
            SegmentDatabaseHelper.deleteSegmentCascade(ctx, prev.id)
            try { FileLogger.i(TAG, "merge: deleted previous segment id=${prev.id}") } catch (_: Exception) {}
        } catch (_: Exception) {}
        // 递归向前继续尝试合并
        try { FileLogger.i(TAG, "merge: continue backward compare from new start=${fmt(mergedWindowStart)}") } catch (_: Exception) {}
        SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
        tryCompareAndMergeBackward(
            ctx,
            cur.copy(startTime = mergedWindowStart, endTime = mergedWindowEnd),
            mergedSamplesForUi,
            mergedOutputTextForSave,
            mergedStructuredWithImages,
            forceMerge = false,
            lockHeld = true
        )
        } finally {
            if (!lockHeld) {
                mergingSegments.remove(cur.id)
            }
        }
    }

    internal fun tryCompareAndMergeBackwardStrict(
        ctx: Context,
        cur: SegmentDatabaseHelper.Segment,
        curSamples: List<SegmentDatabaseHelper.Sample>,
        curOutputText: String,
        curStructured: String?,
        aiConfig: AISettingsNative.AIConfig,
        forceMerge: Boolean = false,
        specifiedPrevSegmentId: Long? = null,
        lockHeld: Boolean = false,
        stageReporter: ((String, String, String, Long) -> Unit)? = null,
    ): Long {
        if (!lockHeld) {
            if (!mergingSegments.add(cur.id)) {
                try { FileLogger.i(TAG, "merge(strict): skip because already merging seg=${cur.id}") } catch (_: Exception) {}
                return cur.id
            }
        }
        try {
            ensureDynamicRebuildNotCancelled(ctx, cur.id)
            stageReporter?.invoke(
                "merge_find_previous",
                "检查是否需要合并",
                "正在为段落 #${cur.id} 查找上一条已完成动态",
                cur.id,
            )
            val prev = run {
                val specified = specifiedPrevSegmentId?.takeIf { it > 0L }
                if (specified != null) {
                    val s = SegmentDatabaseHelper.getSegmentById(ctx, specified)
                    val ok = if (s != null && s.status == "completed") {
                        val rr = SegmentDatabaseHelper.getResultForSegment(ctx, s.id)
                        _hasUsableSegmentResult(rr.first, rr.second)
                    } else false
                    if (ok) s else getOverlapOrPreviousCompletedSegmentWithResult(ctx, cur)
                } else {
                    getOverlapOrPreviousCompletedSegmentWithResult(ctx, cur)
                }
            }
            if (prev == null) {
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        ctx,
                        segmentId = cur.id,
                        prevSegmentId = null,
                        decisionJson = null,
                        reason = if (forceMerge) "强制合并失败：未找到上一事件" else "未找到上一事件，跳过合并",
                        forced = forceMerge,
                    )
                } catch (_: Exception) {}
                SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                stageReporter?.invoke(
                    "merge_skipped",
                    "跳过合并",
                    if (forceMerge) "未找到可强制合并的上一条动态" else "未找到上一条已完成动态",
                    cur.id,
                )
                return cur.id
            }

            if (!forceMerge) {
                val maxSpanSecRaw = try {
                    UserSettingsStorage.getInt(
                        ctx,
                        UserSettingsKeysNative.MERGE_DYNAMIC_MAX_SPAN_SEC,
                        3 * 3600,
                    )
                } catch (_: Exception) { 3 * 3600 }
                val maxGapSecRaw = try {
                    UserSettingsStorage.getInt(
                        ctx,
                        UserSettingsKeysNative.MERGE_DYNAMIC_MAX_GAP_SEC,
                        3600,
                    )
                } catch (_: Exception) { 3600 }
                val maxSpanSec = if (maxSpanSecRaw < 0) 0 else maxSpanSecRaw
                val maxGapSec = if (maxGapSecRaw < 0) 0 else maxGapSecRaw
                val mergedSpanMs = kotlin.math.max(
                    0L,
                    kotlin.math.max(prev.endTime, cur.endTime) - kotlin.math.min(prev.startTime, cur.startTime),
                )
                val mergedGapMs = if (cur.startTime >= prev.endTime) cur.startTime - prev.endTime else 0L
                val spanExceeded = maxSpanSec > 0 && mergedSpanMs > maxSpanSec.toLong() * 1000L
                val gapExceeded = maxGapSec > 0 && mergedGapMs > maxGapSec.toLong() * 1000L
                if (spanExceeded || gapExceeded) {
                    val spanMin = mergedSpanMs / 60000L
                    val gapMin = mergedGapMs / 60000L
                    val details = ArrayList<String>()
                    if (spanExceeded) {
                        val limitMin = maxSpanSec.toLong() / 60L
                        details.add("触发整体跨度限制：${spanMin}分钟 > ${limitMin}分钟")
                    }
                    if (gapExceeded) {
                        val limitMin = maxGapSec.toLong() / 60L
                        details.add("触发时间间隔限制：${gapMin}分钟 > ${limitMin}分钟")
                    }
                    val reason = details.joinToString("；") + "，系统禁止合并"
                    try {
                        SegmentDatabaseHelper.updateMergeDecisionInfo(
                            ctx,
                            segmentId = cur.id,
                            prevSegmentId = prev.id,
                            decisionJson = null,
                            reason = reason,
                            forced = false,
                        )
                    } catch (_: Exception) {}
                    SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                    stageReporter?.invoke(
                        "merge_skipped",
                        "跳过合并",
                        reason,
                        cur.id,
                    )
                    return cur.id
                }
            }

            val prevSamples = SegmentDatabaseHelper.getSamplesForSegment(ctx, prev.id)
            val mergedUniqueSamples = mergeSamples(prevSamples, curSamples)
            if (!forceMerge) {
                val maxImagesRaw = try {
                    UserSettingsStorage.getInt(
                        ctx,
                        UserSettingsKeysNative.MERGE_DYNAMIC_MAX_IMAGES,
                        200,
                    )
                } catch (_: Exception) { 200 }
                val maxImages = if (maxImagesRaw < 0) 0 else maxImagesRaw
                if (maxImages > 0 && mergedUniqueSamples.size > maxImages) {
                    val reason = "触发图片数量限制：${mergedUniqueSamples.size}张 > ${maxImages}张，系统禁止合并"
                    try {
                        SegmentDatabaseHelper.updateMergeDecisionInfo(
                            ctx,
                            segmentId = cur.id,
                            prevSegmentId = prev.id,
                            decisionJson = null,
                            reason = reason,
                            forced = false,
                        )
                    } catch (_: Exception) {}
                    SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                    stageReporter?.invoke(
                        "merge_skipped",
                        "跳过合并",
                        reason,
                        cur.id,
                    )
                    return cur.id
                }
            }

            val prevRes = SegmentDatabaseHelper.getResultForSegment(ctx, prev.id)
            val prevOutput = prevRes.first ?: ""

            if (forceMerge) {
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        ctx,
                        segmentId = cur.id,
                        prevSegmentId = prev.id,
                        decisionJson = null,
                        reason = "用户强制合并：跳过判定，直接执行合并",
                        forced = true,
                    )
                } catch (_: Exception) {}
            } else run {
                stageReporter?.invoke(
                    "merge_decision_prepare",
                    "准备合并判定",
                    "正在判断段落 #${cur.id} 是否应与上一条合并",
                    cur.id,
                )
                val sb = StringBuilder()
                val effectiveLang2 = resolveEffectiveLang(ctx)
                val isZh2 = effectiveLang2 == "zh"
                val langPolicy2 = getStringByLang(
                    ctx,
                    effectiveLang2,
                    R.string.ai_language_policy_zh,
                    R.string.ai_language_policy_en,
                    R.string.ai_language_policy_ja,
                    R.string.ai_language_policy_ko,
                )
                sb.append(langPolicy2).append('\n').append('\n')
                if (isZh2) {
                    val gapMin = if (cur.startTime >= prev.endTime) (cur.startTime - prev.endTime) / 60000L else 0L
                    sb.append("请判断两段时间是否属于同一用户事件：\n")
                        .append("注意：只根据画面语义与行为，不做OCR逐字比对；更关注是否为同一持续活动。\n")
                        .append("合并判定策略（放宽）：\n")
                        .append("- 若两段主要应用相同，或同属'视频观看/文章阅读/信息流浏览/社交浏览/购物浏览/办公操作'等同类行为，即使内容不同也视为同一事件；\n")
                        .append("- 时间间隔仅供参考，不设固定阈值；若后段延续了前段的同类行为或属于同一持续活动，倾向判定 same_event=true；\n")
                        .append("- 短暂且占比很小的打断（例如少量截图/短暂切换）应忽略；\n")
                        .append("- 请输出 JSON：{\\\"same_event\\\":true|false,\\\"reason\\\":\\\"简述\\\",\\\"primary_activity\\\":\\\"watching|reading|browsing|shopping|working|other\\\"}\n")
                        .append("段A：").append(fmt(prev.startTime)).append(" - ").append(fmt(prev.endTime)).append('\n')
                        .append("段B：").append(fmt(cur.startTime)).append(" - ").append(fmt(cur.endTime)).append('\n')
                        .append("两段各自的 overall_summary：\n")
                        .append("A: ").append(extractOverallSummary(prevOutput)).append('\n')
                        .append("B: ").append(extractOverallSummary(curOutputText)).append('\n')
                        .append("两段时间间隔约：").append(gapMin).append(" 分钟\n")
                } else {
                    val gapMin = if (cur.startTime >= prev.endTime) (cur.startTime - prev.endTime) / 60000L else 0L
                    sb.append("Decide whether the two time ranges belong to the same user event:\n")
                        .append("Note: Judge by on-screen semantics and behavior only; DO NOT rely on OCR word-by-word matching. Focus on whether it's the same continuous activity.\n")
                        .append("Merge decision guidelines (relaxed):\n")
                        .append("- If the main app is the same, or both are of the same activity type (video watching/article reading/feed browsing/social browsing/shopping/working), treat as the same event even when content differs.\n")
                        .append("- The time gap is only a reference (no fixed threshold). If the latter continues the former activity type or appears to be the same continuous activity, prefer same_event=true.\n")
                        .append("- Ignore brief interruptions with small proportion (e.g., few screenshots/short switches).\n")
                        .append("- Output JSON: {\\\"same_event\\\":true|false,\\\"reason\\\":\\\"brief\\\",\\\"primary_activity\\\":\\\"watching|reading|browsing|shopping|working|other\\\"}\n")
                        .append("Range A: ").append(fmt(prev.startTime)).append(" - ").append(fmt(prev.endTime)).append('\n')
                        .append("Range B: ").append(fmt(cur.startTime)).append(" - ").append(fmt(cur.endTime)).append('\n')
                        .append("Each range overall_summary:\n")
                        .append("A: ").append(extractOverallSummary(prevOutput)).append('\n')
                        .append("B: ").append(extractOverallSummary(curOutputText)).append('\n')
                        .append("Approximate gap between ranges: ").append(gapMin).append(" minutes\n")
                }

                stageReporter?.invoke(
                    "merge_decision_wait_ai",
                    "等待合并判定",
                    "已准备判定提示词，等待模型返回 same_event 结果",
                    cur.id,
                )
                ensureDynamicRebuildNotCancelled(ctx, cur.id)
                val decide = callGeminiWithImages(
                    ctx,
                    cur,
                    mergedUniqueSamples,
                    sb.toString(),
                    injectDynamicRules = false,
                    maxImagesOverride = PROVIDER_IMAGE_HARD_LIMIT.coerceAtLeast(1),
                    aiConfigOverride = aiConfig,
                    strictFailure = true,
                    stageReporter = stageReporter,
                    stageScope = DYNAMIC_AI_STAGE_MERGE_DECISION,
                )
                val decisionText = decide.outputText
                var decisionJson: String? = null
                var decisionReason: String? = null
                val same = try {
                    val pair = extractJsonBlocks(decisionText)
                    val jsonStr = pair.first
                    decisionJson = jsonStr
                    if (jsonStr != null) {
                        try {
                            val obj = org.json.JSONObject(jsonStr)
                            val rr = obj.optString("reason", "").trim()
                            if (rr.isNotEmpty()) decisionReason = rr
                            obj.optBoolean("same_event", false)
                        } catch (_: Exception) {
                            Regex("\"same_event\"\\s*:\\s*true", RegexOption.IGNORE_CASE).containsMatchIn(decisionText)
                        }
                    } else {
                        Regex("\"same_event\"\\s*:\\s*true", RegexOption.IGNORE_CASE).containsMatchIn(decisionText)
                    }
                } catch (_: Exception) {
                    Regex("\"same_event\"\\s*:\\s*true", RegexOption.IGNORE_CASE).containsMatchIn(decisionText)
                }
                if (decisionReason.isNullOrBlank()) {
                    val t = decisionText.trim()
                    decisionReason = if (t.length <= 240) t else (t.substring(0, 240) + "…")
                }
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        ctx,
                        segmentId = cur.id,
                        prevSegmentId = prev.id,
                        decisionJson = decisionJson,
                        reason = decisionReason,
                        forced = false,
                    )
                } catch (_: Exception) {}
                if (!same) {
                    SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                    stageReporter?.invoke(
                        "merge_not_same_event",
                        "跳过合并",
                        decisionReason ?: "模型判定不是同一事件",
                        cur.id,
                    )
                    return cur.id
                }
            }

            val maxAiImages = PROVIDER_IMAGE_HARD_LIMIT.coerceAtLeast(1)
            val mergePlan = planMergeAiInput(
                allSamples = mergedUniqueSamples,
                prevStructuredJson = prevRes.second,
                prevSamples = prevSamples,
                curStructuredJson = curStructured,
                curSamples = curSamples,
                maxAiImages = maxAiImages,
            )
            val mergedAiSamples = mergePlan.aiSamples
            val slimOpenAiMergePrompt = shouldUseSlimOpenAiMergePrompt(aiConfig)
            val mergePrompt = buildMergePrompt(
                ctx,
                prev,
                cur,
                mergedAiSamples,
                textOnlyDescriptions = mergePlan.textOnlyDescriptions,
                totalImages = mergedUniqueSamples.size,
                maxAttachedImages = maxAiImages,
                forced = forceMerge,
                slimImageMetadata = slimOpenAiMergePrompt,
            )

            val merged = try {
                ensureDynamicRebuildNotCancelled(ctx, cur.id)
                stageReporter?.invoke(
                    "merge_summary_wait_ai",
                    "等待合并总结",
                    "已准备合并提示词，等待模型生成合并后的总结",
                    cur.id,
                )
                callGeminiWithImages(
                    ctx,
                    cur,
                    mergedAiSamples,
                    mergePrompt,
                    isMerge = true,
                    maxImagesOverride = maxAiImages,
                    aiConfigOverride = aiConfig,
                    strictFailure = true,
                    stageReporter = stageReporter,
                    stageScope = DYNAMIC_AI_STAGE_MERGE_SUMMARY,
                )
            } catch (e: DynamicRebuildCancelledException) {
                throw e
            } catch (e: Exception) {
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        ctx,
                        segmentId = cur.id,
                        prevSegmentId = prev.id,
                        decisionJson = null,
                        reason = "合并失败：" + (e.message ?: e.toString()),
                        forced = forceMerge,
                    )
                } catch (_: Exception) {}
                SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
                throw DynamicRebuildStepException(
                    "动态重建合并失败：${e.message ?: e.toString()}",
                    cur.id,
                )
            }

            stageReporter?.invoke(
                "merge_save_result",
                "保存合并结果",
                "正在更新窗口、样本与合并后的 AI 总结",
                cur.id,
            )
            val prevOriginalSummaries = extractOriginalSummaryPartsForMerge(prevRes.first, prevRes.second)
            val curOriginalSummaries = extractOriginalSummaryPartsForMerge(curOutputText, curStructured)
            val mergedStructuredNormalizedByAiOrder = normalizeImageRefsToFilenames(
                merged.structuredJson,
                mergedAiSamples,
            )
            val mergedPatched = attachOriginalSummariesToMergedResult(
                mergedOutputText = merged.outputText,
                mergedStructuredJson = mergedStructuredNormalizedByAiOrder,
                prevOriginals = prevOriginalSummaries,
                curOriginals = curOriginalSummaries,
            )
            var mergedOutputTextForSave = mergedPatched.first
            var mergedStructuredForSave = mergedPatched.second
            var mergedCategoriesForSave: String? = merged.categories
            val prevCategoriesFromDb: String? = try { SegmentDatabaseHelper.getSegmentResult(ctx, prev.id)?.categories } catch (_: Exception) { null }
            val curCategoriesFromDb: String? = try { SegmentDatabaseHelper.getSegmentResult(ctx, cur.id)?.categories } catch (_: Exception) { null }

            run {
                val mergedObj = parseStructuredJsonObject(mergedStructuredForSave)
                val sjMissingOrInvalid = mergedObj == null

                fun buildFallback(): TextFirstMergedResult = buildTextFirstMergedResult(
                    prevOutputText = prevOutput,
                    prevStructuredJson = prevRes.second,
                    curOutputText = curOutputText,
                    curStructuredJson = curStructured,
                )

                fun pickOverallSummaryForFallback(fallback: TextFirstMergedResult): String {
                    val candidate = mergedOutputTextForSave.trim()
                    if (candidate.isEmpty() || candidate.equals("null", ignoreCase = true)) return fallback.outputText
                    if (candidate.startsWith("{") && candidate.endsWith("}")) return fallback.outputText
                    return candidate
                }

                if (sjMissingOrInvalid) {
                    val fallback = buildFallback()
                    mergedCategoriesForSave = pickNonEmpty(
                        mergedCategoriesForSave,
                        fallback.categoriesJson,
                        prevCategoriesFromDb,
                        curCategoriesFromDb,
                    )
                    mergedStructuredForSave = try {
                        val obj = JSONObject(fallback.structuredJson)
                        obj.put("overall_summary", pickOverallSummaryForFallback(fallback))
                        obj.toString()
                    } catch (_: Exception) {
                        fallback.structuredJson
                    }
                    return@run
                }

                try {
                    fun hasUsableKeyActionDetail(arr: JSONArray?): Boolean {
                        if (arr == null || arr.length() == 0) return false
                        for (i in 0 until arr.length()) {
                            val v = arr.opt(i)
                            when (v) {
                                is JSONObject -> {
                                    val d = v.optString("detail", "").trim()
                                    if (d.isNotEmpty()) return true
                                }
                                is String -> {
                                    if (v.trim().isNotEmpty()) return true
                                }
                            }
                        }
                        return false
                    }

                    val ka = mergedObj.optJSONArray("key_actions")
                    if (!hasUsableKeyActionDetail(ka)) {
                        val fallback = buildFallback()
                        mergedCategoriesForSave = pickNonEmpty(
                            mergedCategoriesForSave,
                            fallback.categoriesJson,
                            prevCategoriesFromDb,
                            curCategoriesFromDb,
                        )
                        try {
                            val fbObj = JSONObject(fallback.structuredJson)
                            val fbKa = fbObj.optJSONArray("key_actions")
                            if (hasUsableKeyActionDetail(fbKa)) {
                                mergedObj.put("key_actions", fbKa)
                            }
                        } catch (_: Exception) {
                        }
                    }
                    mergedStructuredForSave = mergedObj.toString()
                } catch (_: Exception) {
                }
            }

            run {
                fun readCategoriesFromColumn(categories: String?): List<String> {
                    val raw = categories?.trim()
                    if (raw.isNullOrEmpty() || raw.equals("null", ignoreCase = true)) return emptyList()
                    return try {
                        val arr = JSONArray(raw)
                        val out = ArrayList<String>(arr.length())
                        for (i in 0 until arr.length()) {
                            val v = arr.optString(i, "").trim()
                            if (v.isNotEmpty() && !v.equals("null", ignoreCase = true)) out.add(v)
                        }
                        out
                    } catch (_: Exception) {
                        raw.split(Regex("[,，;；\\s]+"))
                            .map { it.trim() }
                            .filter { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
                    }
                }

                val mergedObj = parseStructuredJsonObject(mergedStructuredForSave)
                val prevObj = parseStructuredJsonObject(prevRes.second)
                val curObj = parseStructuredJsonObject(curStructured)

                val originalCats = mergeUniqueStrings(
                    mergeUniqueStrings(
                        readStringList(prevObj, "categories"),
                        readCategoriesFromColumn(prevCategoriesFromDb),
                    ),
                    mergeUniqueStrings(
                        readStringList(curObj, "categories"),
                        readCategoriesFromColumn(curCategoriesFromDb),
                    ),
                )
                val mergedCats = readStringList(mergedObj, "categories")
                val cats = mergeUniqueStrings(originalCats, mergedCats)
                if (cats.isEmpty()) return@run

                val catArr = JSONArray()
                for (v in cats) catArr.put(v)
                mergedCategoriesForSave = catArr.toString()

                if (mergedObj != null) {
                    try {
                        mergedObj.put("categories", catArr)
                        mergedStructuredForSave = mergedObj.toString()
                    } catch (_: Exception) {
                    }
                }
            }

            val mergedWindowStart = kotlin.math.min(prev.startTime, cur.startTime)
            val mergedWindowEnd = kotlin.math.max(prev.endTime, cur.endTime)
            SegmentDatabaseHelper.updateSegmentWindow(ctx, cur.id, mergedWindowStart, mergedWindowEnd)
            var mergedSamplesForUi: List<SegmentDatabaseHelper.Sample> = mergedUniqueSamples
            try {
                val curAfter = SegmentDatabaseHelper.getSegmentById(ctx, cur.id)
                if (curAfter != null) {
                    val rebuilt = buildSamplesForSegment(ctx, curAfter)
                    if (rebuilt.isNotEmpty()) {
                        mergedSamplesForUi = mergeSamples(mergedUniqueSamples, rebuilt)
                    }
                }
                try { SegmentDatabaseHelper.saveSamples(ctx, cur.id, mergedSamplesForUi) } catch (_: Exception) {}
            } catch (_: Exception) {}

            val mergedStructuredWithImages = mergeImageDescriptionsIntoStructuredJson(
                mergedStructuredJson = mergedStructuredForSave,
                mergedSamplesForUi = mergedSamplesForUi,
                mergedAiSamples = mergedAiSamples,
                prevStructuredJson = prevRes.second,
                prevSamples = prevSamples,
                curStructuredJson = curStructured,
                curSamples = curSamples,
            ) ?: mergedStructuredForSave
            val mergedStructuredFinal = normalizeImageRefsToFilenames(
                mergedStructuredWithImages,
                mergedAiSamples,
            ) ?: mergedStructuredWithImages

            SegmentDatabaseHelper.saveResult(
                ctx,
                cur.id,
                provider = aiConfig.providerType?.trim()?.takeIf { it.isNotEmpty() } ?: "gemini",
                model = merged.model,
                outputText = mergedOutputTextForSave,
                structuredJson = mergedStructuredFinal,
                categories = mergedCategoriesForSave,
                rawRequest = merged.rawRequest,
                rawResponse = merged.rawResponse,
            )
            try {
                SegmentDatabaseHelper.upsertAiImageMetaFromStructuredJson(
                    ctx,
                    segmentId = cur.id,
                    samples = mergedSamplesForUi,
                    structuredJson = mergedStructuredFinal,
                    lang = null,
                )
            } catch (_: Exception) {}
            try { SegmentDatabaseHelper.setMergedFlag(ctx, cur.id, true) } catch (_: Exception) {}
            try {
                SegmentDatabaseHelper.deleteSegmentCascade(ctx, prev.id)
            } catch (_: Exception) {}
            SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
            stageReporter?.invoke(
                "merge_continue_backward",
                "继续向前检查合并",
                "当前段落已完成一次合并，继续检查是否还能与更早动态合并",
                cur.id,
            )
            return tryCompareAndMergeBackwardStrict(
                ctx,
                cur.copy(startTime = mergedWindowStart, endTime = mergedWindowEnd),
                mergedSamplesForUi,
                mergedOutputTextForSave,
                mergedStructuredWithImages,
                aiConfig = aiConfig,
                forceMerge = false,
                lockHeld = true,
                stageReporter = stageReporter,
            )
        } catch (e: DynamicRebuildCancelledException) {
            throw e
        } catch (e: DynamicRebuildStepException) {
            throw e
        } catch (e: Exception) {
            throw DynamicRebuildStepException(
                "动态重建合并失败：${e.message ?: e.toString()}",
                cur.id,
            )
        } finally {
            if (!lockHeld) {
                mergingSegments.remove(cur.id)
            }
        }
    }


    /** 为任意 segment 按"每槽位最近一图 + 最后一槽尝试 end 之后第一张"规则重建样本列表 */
    internal fun buildSamplesForSegment(ctx: Context, seg: SegmentDatabaseHelper.Segment): List<SegmentDatabaseHelper.Sample> {
        val interval = seg.sampleIntervalSec
        val start = seg.startTime
        val end = seg.endTime
        val totalSec = seg.durationSec
        val totalSlots = (totalSec / interval).coerceAtLeast(1)

        val shots = SegmentDatabaseHelper.listShotsBetween(ctx, start, end)
        val samples = ArrayList<SegmentDatabaseHelper.Sample>()
        val seenPaths = HashSet<String>()
        for (i in 0 until totalSlots) {
            val isLast = (i == totalSlots - 1)
            val target = start + i * interval * 1000L
            var chosen: SegmentDatabaseHelper.ShotInfo? = null
            if (isLast) {
                val post = findFirstShotStrictAfter(ctx, end)
                if (post != null) chosen = post
            }
            if (chosen == null) {
                var best: SegmentDatabaseHelper.ShotInfo? = null
                var bestDt = Long.MAX_VALUE
                for (s in shots) {
                    val dt = kotlin.math.abs(s.captureTime - target)
                    if (dt < bestDt) { bestDt = dt; best = s }
                }
                chosen = best
            }
            if (chosen != null && seenPaths.add(chosen.filePath)) {
                samples.add(
                    SegmentDatabaseHelper.Sample(
                        id = 0L,
                        segmentId = seg.id,
                        captureTime = chosen.captureTime,
                        filePath = chosen.filePath,
                        appPackageName = chosen.appPackageName,
                        appName = chosen.appName,
                        positionIndex = i
                    )
                )
            }
        }
        return samples
    }

    internal fun summarizeSegmentForRebuildStrict(
        ctx: Context,
        seg: SegmentDatabaseHelper.Segment,
        samples: List<SegmentDatabaseHelper.Sample>,
        aiConfig: AISettingsNative.AIConfig,
        stageReporter: ((String, String, String, Long) -> Unit)? = null,
    ): Pair<String, String?> {
        if (samples.isEmpty()) {
            stageReporter?.invoke(
                "summary_no_samples",
                "跳过 AI 总结",
                "当前时间窗没有可用样本图片",
                seg.id,
            )
            SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
            return Pair("", null)
        }

        val capBySeg = (seg.durationSec / seg.sampleIntervalSec).coerceAtLeast(1)
        val effectiveCap = kotlin.math.min(capBySeg, PROVIDER_IMAGE_HARD_LIMIT)
        val samplesOrdered = samples.sortedBy { it.captureTime }
        val effSamples = if (samplesOrdered.size > effectiveCap) {
            evenPick(samplesOrdered, effectiveCap)
        } else {
            samplesOrdered
        }
        val effectiveLang = resolveEffectiveLang(ctx)
        stageReporter?.invoke(
            "summary_prepare_prompt",
            "构建总结提示词",
            "为段落 #${seg.id} 组织 ${effSamples.size} 张样本图片",
            seg.id,
        )
        val prompt = buildSegmentSummaryPrompt(ctx, seg, effSamples, effectiveLang)

        val result = try {
            ensureDynamicRebuildNotCancelled(ctx, seg.id)
            stageReporter?.invoke(
                "summary_wait_ai",
                "等待 AI 总结",
                "已准备请求模型，总图片 ${effSamples.size} 张",
                seg.id,
            )
            callGeminiWithImages(
                ctx = ctx,
                seg = seg,
                samples = effSamples,
                prompt = prompt,
                aiConfigOverride = aiConfig,
                strictFailure = true,
                stageReporter = stageReporter,
                stageScope = DYNAMIC_AI_STAGE_SUMMARY,
            )
        } catch (e: DynamicRebuildCancelledException) {
            throw e
        } catch (e: Exception) {
            throw DynamicRebuildStepException(
                "动态重建 AI 调用失败：${e.message ?: e.toString()}",
                seg.id,
            )
        }

        val provider = aiConfig.providerType?.trim()?.takeIf { it.isNotEmpty() } ?: "gemini"
        val structuredToSave = normalizeImageRefsToFilenames(result.structuredJson, effSamples)
        stageReporter?.invoke(
            "summary_save_result",
            "写入 AI 总结结果",
            "模型已返回内容，正在保存段落 #${seg.id}",
            seg.id,
        )
        SegmentDatabaseHelper.saveResult(
            ctx,
            seg.id,
            provider = provider,
            model = result.model,
            outputText = result.outputText,
            structuredJson = structuredToSave,
            categories = result.categories,
            rawRequest = result.rawRequest,
            rawResponse = result.rawResponse,
        )
        if (!SegmentDatabaseHelper.hasResultForSegment(ctx, seg.id)) {
            throw DynamicRebuildStepException("动态重建结果落盘失败", seg.id)
        }
        try {
            SegmentDatabaseHelper.upsertAiImageMetaFromStructuredJson(
                ctx,
                segmentId = seg.id,
                samples = effSamples,
                structuredJson = structuredToSave,
                lang = effectiveLang,
            )
        } catch (_: Exception) {}
        SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
        stageReporter?.invoke(
            "summary_done",
            "AI 总结完成",
            "段落 #${seg.id} 已完成总结并落盘",
            seg.id,
        )
        return Pair(result.outputText, structuredToSave)
    }

    internal fun resolveEffectiveLang(ctx: Context): String {
        val langOpt = try {
            ctx.getSharedPreferences(
                "FlutterSharedPreferences",
                android.content.Context.MODE_PRIVATE,
            ).getString("flutter.locale_option", "system")
        } catch (_: Exception) {
            "system"
        }
        val sysLang = try {
            java.util.Locale.getDefault().language?.lowercase()
        } catch (_: Exception) {
            "en"
        } ?: "en"
        return when (langOpt) {
            "zh", "en", "ja", "ko" -> langOpt
            "system" -> when {
                sysLang.startsWith("zh") -> "zh"
                sysLang.startsWith("ja") -> "ja"
                sysLang.startsWith("ko") -> "ko"
                else -> "en"
            }
            else -> "en"
        }
    }

    internal fun buildSegmentSummaryPrompt(
        ctx: Context,
        seg: SegmentDatabaseHelper.Segment,
        samples: List<SegmentDatabaseHelper.Sample>,
        effectiveLang: String,
    ): String {
        val extraHeader = try {
            val key = when (effectiveLang) {
                "zh" -> "prompt_segment_extra_zh"
                else -> "prompt_segment_extra_en"
            }
            AISettingsNative.readSettingValue(ctx, key)
        } catch (_: Exception) { null }
        val legacyHeaderLang = try {
            val key = when (effectiveLang) {
                "zh" -> "prompt_segment_zh"
                else -> "prompt_segment_en"
            }
            AISettingsNative.readSettingValue(ctx, key)
        } catch (_: Exception) { null }
        val legacyHeader = try {
            AISettingsNative.readSettingValue(ctx, "prompt_segment")
        } catch (_: Exception) { null }

        val languagePolicy = getStringByLang(
            ctx,
            effectiveLang,
            R.string.ai_language_policy_zh,
            R.string.ai_language_policy_en,
            R.string.ai_language_policy_ja,
            R.string.ai_language_policy_ko,
        )
        val baseHeader = getStringByLang(
            ctx,
            effectiveLang,
            R.string.segment_prompt_default_zh,
            R.string.segment_prompt_default_en,
            R.string.segment_prompt_default_ja,
            R.string.segment_prompt_default_ko,
        )
        val addon = sequenceOf(extraHeader, legacyHeaderLang, legacyHeader)
            .firstOrNull { it != null && it.trim().isNotEmpty() }
            ?.trim()
        val headerBuilder = StringBuilder()
        headerBuilder.append(languagePolicy).append("\n\n").append(baseHeader)
        if (!addon.isNullOrEmpty()) {
            val label = when (effectiveLang) {
                "zh" -> "附加说明："
                "ja" -> "追加指示："
                "ko" -> "추가 지침:"
                else -> "Additional instructions:"
            }
            headerBuilder.append("\n\n").append(label).append('\n').append(addon)
        }

        val timeRangeLabel = getStringByLang(
            ctx,
            effectiveLang,
            R.string.label_time_range_zh,
            R.string.label_time_range_en,
            R.string.label_time_range_ja,
            R.string.label_time_range_ko,
        )
        val shotLabel = getStringByLang(
            ctx,
            effectiveLang,
            R.string.label_screenshot_at_zh,
            R.string.label_screenshot_at_en,
            R.string.label_screenshot_at_ja,
            R.string.label_screenshot_at_ko,
        )
        val imageIndexLabel = when (effectiveLang) {
            "zh" -> "图片索引（仅使用序号引用图片）"
            "ja" -> "画像インデックス（画像参照は番号のみ）"
            "ko" -> "이미지 인덱스(번호로만 참조)"
            else -> "Image index list (reference by number only)"
        }

        val sb = StringBuilder()
        sb.append(headerBuilder.toString()).append('\n')
        sb.append(timeRangeLabel)
            .append(fmt(seg.startTime))
            .append(" - ")
            .append(fmt(seg.endTime))
            .append('\n')
        sb.append(imageIndexLabel).append('\n')
        for ((idx, s) in samples.sortedBy { it.captureTime }.withIndex()) {
            val appDisplay = s.appName.trim().ifEmpty { s.appPackageName.trim() }
            sb.append(shotLabel)
                .append("[#")
                .append(idx + 1)
                .append("] ")
                .append(fmt(s.captureTime))
                .append(" | ")
                .append(appDisplay)
                .append('\n')
        }
        return sb.toString()
    }

    /**
     * 扫描并补救：针对“近 N 天”的 completed 段落，凡无内容（文本与结构化皆空）均尝试补救；
     * 如不存在样本，则按规则即时重建样本后再补救。
     */
    private fun resumeMissingSummaries(ctx: Context, limit: Int = 2) {
        if (
            shouldPauseRegularDynamicGeneration(
                ctx,
                "resumeMissingSummaries",
                "跳过排队中的缺失总结补救",
            )
        ) {
            return
        }
        if (!isDynamicAutoRepairEnabled(ctx)) return
        val dayMs = 24L * 60L * 60L * 1000L
        val since = startOfToday() - (RECENT_LOOKBACK_DAYS.toLong() - 1L) * dayMs
        val list = try { SegmentDatabaseHelper.listSegmentsNeedingSummary(ctx, limit = limit, sinceMillis = since) } catch (_: Exception) { emptyList() }
        try {
            if (list.isNotEmpty()) {
                FileLogger.i(TAG, "resumeMissing：候选=${list.size}，limit=${limit}，lookback=${RECENT_LOOKBACK_DAYS}d")
            }
        } catch (_: Exception) {}
        for (seg in list) {
            try {
                // 避免重复：若窗口已有任何结果则跳过
                if (SegmentDatabaseHelper.hasAnyResultForWindow(ctx, seg.startTime, seg.endTime)) continue

                var samples = SegmentDatabaseHelper.getSamplesForSegment(ctx, seg.id)
                if (samples.isEmpty()) {
                    // 即时重建样本并保存
                    samples = buildSamplesForSegment(ctx, seg)
                    if (samples.isNotEmpty()) {
                        try { SegmentDatabaseHelper.saveSamples(ctx, seg.id, samples) } catch (_: Exception) {}
                    }
                }
                if (samples.isEmpty()) {
                    try { FileLogger.w(TAG, "resumeMissing：seg=${seg.id} 重建后无 samples，跳过") } catch (_: Exception) {}
                    continue
                }
                // 直接复用 finish 逻辑
                try { FileLogger.i(TAG, "resumeMissing：重试 seg=${seg.id} ${fmt(seg.startTime)}-${fmt(seg.endTime)} 张数=${samples.size}") } catch (_: Exception) {}
                finishSegment(ctx, seg, samples)
            } catch (_: Exception) {}
        }

        // 额外：从当天第二个事件起，依次尝试未打过标记的段落进行合并判定
        try {
            val completed = SegmentDatabaseHelper.listUnattemptedCompletedSince(ctx, since, limit = 100)
            var firstStart: Long? = null
            for (s in completed) {
                if (firstStart == null) { firstStart = s.startTime; SegmentDatabaseHelper.setMergeAttempted(ctx, s.id, true); continue }
                val resultPair = SegmentDatabaseHelper.getResultForSegment(ctx, s.id)
                val out = resultPair.first ?: ""
                var samples = SegmentDatabaseHelper.getSamplesForSegment(ctx, s.id)
                if (samples.isEmpty()) {
                    samples = buildSamplesForSegment(ctx, s)
                    if (samples.isNotEmpty()) {
                        try { SegmentDatabaseHelper.saveSamples(ctx, s.id, samples) } catch (_: Exception) {}
                    }
                }
                if (samples.isEmpty() || out.isEmpty()) { SegmentDatabaseHelper.setMergeAttempted(ctx, s.id, true); continue }
                tryCompareAndMergeBackward(ctx, s, samples, out, resultPair.second)
            }
        } catch (_: Exception) {}
    }

    /**
     * 公开方法：按ID列表重试生成总结。
     * - force=true 时无视"已有结果/同窗已有结果"直接重跑并覆盖写入。
     */
    fun retrySegmentsByIds(ctx: Context, ids: List<Long>, force: Boolean = false): Int {
        if (ids.isEmpty()) return 0
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        if (isDynamicRebuildTaskActive(appCtx)) {
            try { FileLogger.i(TAG, "retrySegments：检测到动态重建任务运行中，拒绝单条重试 ids=${ids.size}") } catch (_: Exception) {}
            return 0
        }
        var retried = 0
        for (id in ids) {
            try {
                // 非强制：已有结果则跳过
                if (!force && SegmentDatabaseHelper.hasResultForSegment(appCtx, id)) continue
                val seg = SegmentDatabaseHelper.getSegmentById(appCtx, id) ?: continue
                var samples = SegmentDatabaseHelper.getSamplesForSegment(appCtx, id)
                if (samples.isEmpty()) {
                    samples = buildSamplesForSegment(appCtx, seg)
                    if (samples.isNotEmpty()) {
                        try { SegmentDatabaseHelper.saveSamples(appCtx, seg.id, samples) } catch (_: Exception) {}
                    }
                }
                if (samples.isEmpty()) continue
                try { FileLogger.i(TAG, "retrySegments: seg=${id} imgs=${samples.size} force=${force}") } catch (_: Exception) {}
                finishSegment(appCtx, seg, samples, force)
                retried++
            } catch (_: Exception) {}
        }
        return retried
    }

    data class DynamicRebuildWindow(
        val startTime: Long,
        val endTime: Long,
        val existingSegmentId: Long = 0L,
    )

    data class DynamicWindowPlanResult(
        val windows: List<DynamicRebuildWindow>,
        val skippedCovered: Int,
        val mergedShortGaps: Int,
    )

    class DynamicRebuildStepException(
        message: String,
        val segmentId: Long = 0L,
    ) : IllegalStateException(message)

    class DynamicRebuildCancelledException(
        message: String,
        val segmentId: Long = 0L,
    ) : IllegalStateException(message)

    internal fun loadExistingRootWindows(
        ctx: Context,
        startMillis: Long,
        endMillis: Long,
        excludeSegmentId: Long? = null,
    ): List<ExistingDynamicWindow> = loadExistingRootWindowsInternal(
        ctx = ctx,
        startMillis = startMillis,
        endMillis = endMillis,
        excludeSegmentId = excludeSegmentId,
    )

    internal fun firstSafeWindowFromShots(
        ctx: Context,
        shots: List<SegmentDatabaseHelper.ShotInfo>,
        startIndex: Int,
        durationMs: Long,
        nowMillis: Long,
        dayEndMillis: Long? = null,
    ): DynamicRebuildWindow? = firstSafeWindowFromShotsInternal(
        ctx = ctx,
        shots = shots,
        startIndex = startIndex,
        durationMs = durationMs,
        nowMillis = nowMillis,
        dayEndMillis = dayEndMillis,
    )

    internal fun ensureNoRootOverlapBeforeCreate(
        ctx: Context,
        startMillis: Long,
        endMillis: Long,
        source: String,
    ): Boolean = ensureNoRootOverlapBeforeCreateInternal(ctx, startMillis, endMillis, source)

    internal fun getOverlapOrPreviousCompletedSegmentWithResult(
        ctx: Context,
        cur: SegmentDatabaseHelper.Segment,
    ): SegmentDatabaseHelper.Segment? = getOverlapOrPreviousCompletedSegmentWithResultInternal(ctx, cur)

    fun buildFullRebuildWorklist(
        ctx: Context,
        durationSec: Int,
        targetDayKey: String? = null,
    ): List<DynamicRebuildWindow> = buildFullRebuildWorklistInternal(ctx, durationSec, targetDayKey)

    fun planNonOverlappingWindows(
        shotTimes: List<Long>,
        existingWindows: List<ExistingDynamicWindow>,
        durationMs: Long,
        nowMillis: Long,
        dayEndMillis: Long? = null,
    ): DynamicWindowPlanResult = planNonOverlappingWindowsInternal(
        shotTimes = shotTimes,
        existingWindows = existingWindows,
        durationMs = durationMs,
        nowMillis = nowMillis,
        dayEndMillis = dayEndMillis,
    )

    fun buildMissingBackfillWorklist(
        ctx: Context,
        durationSec: Int,
        targetDayKey: String? = null,
    ): List<DynamicRebuildWindow> = buildMissingBackfillWorklistInternal(ctx, durationSec, targetDayKey)

    fun filterDynamicRebuildWindowsForDay(
        windows: List<DynamicRebuildWindow>,
        targetDayKey: String,
    ): List<DynamicRebuildWindow> = filterDynamicRebuildWindowsForDayInternal(windows, targetDayKey)

    fun rebuildWindowStrict(
        ctx: Context,
        windowStart: Long,
        windowEnd: Long,
        durationSec: Int,
        sampleIntervalSec: Int,
        aiConfig: AISettingsNative.AIConfig,
        existingSegmentId: Long = 0L,
        stageReporter: ((String, String, String, Long) -> Unit)? = null,
    ): Long = rebuildWindowStrictInternal(
        ctx = ctx,
        windowStart = windowStart,
        windowEnd = windowEnd,
        durationSec = durationSec,
        sampleIntervalSec = sampleIntervalSec,
        aiConfig = aiConfig,
        existingSegmentId = existingSegmentId,
        stageReporter = stageReporter,
    )
    internal fun cleanupRebuildSegment(ctx: Context, segmentId: Long) {
        if (segmentId <= 0L) return
        val paths = try { SegmentDatabaseHelper.getSampleFilePaths(ctx, segmentId) } catch (_: Exception) { emptyList() }
        try { SegmentDatabaseHelper.deleteSegmentCascade(ctx, segmentId) } catch (_: Exception) {}
        if (paths.isNotEmpty()) {
            try { SegmentDatabaseHelper.deleteAiImageMetaByFilePaths(ctx, paths) } catch (_: Exception) {}
        }
    }

    internal fun resultRepairReason(outputText: String?, structuredJson: String?): String {
        val out = outputText?.trim().orEmpty()
        val sj = structuredJson?.trim().orEmpty()
        val outBlank = out.isEmpty() || out.equals("null", ignoreCase = true)
        val jsonBlank = sj.isEmpty() || sj.equals("null", ignoreCase = true)
        if (outBlank && jsonBlank) return "blank_output_and_json"
        if (jsonBlank) return "blank_structured_json"
        val obj = try {
            JSONObject(sj)
        } catch (e: Exception) {
            return "invalid_structured_json:${e.javaClass.simpleName}"
        }
        val meta = obj.optJSONObject("_meta")
        val manualRetry = when (val raw = meta?.opt("needs_manual_retry")) {
            is Boolean -> raw
            is Number -> raw.toInt() != 0
            is String -> {
                val v = raw.trim().lowercase()
                v == "true" || v == "1" || v == "yes"
            }
            else -> false
        }
        if (manualRetry) return "needs_manual_retry"
        return "none"
    }

    internal fun segmentDiag(ctx: Context, seg: SegmentDatabaseHelper.Segment): String {
        val reason = resultRepairReasonForSegment(ctx, seg.id)
        return "seg=${seg.id} ${fmt(seg.startTime)}-${fmt(seg.endTime)} status=${seg.status} reason=$reason"
    }

    internal fun resultRepairReasonForSegment(ctx: Context, segmentId: Long): String {
        val result = try {
            SegmentDatabaseHelper.getResultForSegment(ctx, segmentId)
        } catch (_: Exception) {
            Pair(null, null)
        }
        return resultRepairReason(result.first, result.second)
    }

    internal fun _hasUsableSegmentResult(outputText: String?, structuredJson: String?): Boolean {
        val ot = outputText?.trim().orEmpty()
        val sj = structuredJson?.trim().orEmpty()
        return (ot.isNotEmpty() && !ot.equals("null", ignoreCase = true)) ||
            (sj.isNotEmpty() && !sj.equals("null", ignoreCase = true))
    }

    fun normalizeExistingRootOverlaps(
        ctx: Context,
        startMillis: Long? = null,
        endMillis: Long? = null,
        limitClusters: Int = 20,
    ): Int {
        val clusters = try {
            SegmentDatabaseHelper.listRootOverlapClusters(
                context = ctx,
                startMillis = startMillis,
                endMillis = endMillis,
                limitClusters = limitClusters,
            )
        } catch (_: Exception) {
            emptyList()
        }
        var normalized = 0
        for (cluster in clusters) {
            try {
                val keepId = SegmentDatabaseHelper.mergeRootOverlapClusterStructurally(ctx, cluster)
                if (keepId > 0L) {
                    normalized++
                    try {
                        FileLogger.i(
                            TAG,
                            "normalizeOverlap: keep=$keepId segments=${cluster.segments.size} range=${fmt(cluster.startTime)}-${fmt(cluster.endTime)}",
                        )
                    } catch (_: Exception) {}
                }
            } catch (e: Exception) {
                try { FileLogger.w(TAG, "normalizeOverlap failed: ${e.message}") } catch (_: Exception) {}
            }
        }
        return normalized
    }

    /**
     * 公开方法：用户手动强制合并某段落与其上一段落（跳过 same_event 判定，直接走合并总结）。
     *
     * - prevSegmentId 可选：若提供则优先与该段落合并（必须为 completed 且有结果）
     * - 返回 true 表示已入队（异步执行）；false 表示参数/状态不满足（未入队）
     */
    fun forceMergeSegmentById(ctx: Context, segmentId: Long, prevSegmentId: Long? = null): Boolean {
        if (segmentId <= 0L) return false
        val appCtx = try { ctx.applicationContext } catch (_: Exception) { ctx }
        if (isDynamicRebuildTaskActive(appCtx)) {
            try { FileLogger.i(TAG, "forceMerge：检测到动态重建任务运行中，拒绝手动强制合并 seg=${segmentId}") } catch (_: Exception) {}
            return false
        }
        val seg = SegmentDatabaseHelper.getSegmentById(appCtx, segmentId) ?: return false
        if (seg.status != "completed") return false

        val resultPair = SegmentDatabaseHelper.getResultForSegment(appCtx, segmentId)
        val out = (resultPair.first ?: "").trim()
        if (out.isEmpty() || out.equals("null", ignoreCase = true)) return false

        var samples = SegmentDatabaseHelper.getSamplesForSegment(appCtx, segmentId)
        if (samples.isEmpty()) {
            samples = buildSamplesForSegment(appCtx, seg)
            if (samples.isNotEmpty()) {
                try { SegmentDatabaseHelper.saveSamples(appCtx, seg.id, samples) } catch (_: Exception) {}
            }
        }
        if (samples.isEmpty()) return false

        val prevIdToRecord = prevSegmentId?.takeIf { it > 0L }
            ?: try { SegmentDatabaseHelper.getPreviousCompletedSegmentWithResult(appCtx, seg.startTime)?.id } catch (_: Exception) { null }
        try {
            SegmentDatabaseHelper.updateMergeDecisionInfo(
                appCtx,
                segmentId = segmentId,
                prevSegmentId = prevIdToRecord,
                decisionJson = null,
                reason = "已请求强制合并（排队中）",
                forced = true
            )
        } catch (_: Exception) {}

        postOnWorker("forceMerge") {
            try {
                tryCompareAndMergeBackward(
                    appCtx,
                    seg,
                    samples,
                    out,
                    resultPair.second,
                    forceMerge = true,
                    specifiedPrevSegmentId = prevSegmentId
                )
            } catch (e: Exception) {
                try {
                    SegmentDatabaseHelper.updateMergeDecisionInfo(
                        appCtx,
                        segmentId = segmentId,
                        prevSegmentId = prevIdToRecord,
                        decisionJson = null,
                        reason = "强制合并异常：" + (e.message ?: e.toString()),
                        forced = true
                    )
                } catch (_: Exception) {}
                try { SegmentDatabaseHelper.setMergeAttempted(appCtx, segmentId, true) } catch (_: Exception) {}
            }
        }
        return true
    }

    internal fun fmt(ts: Long): String {
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = ts }
        val h = cal.get(java.util.Calendar.HOUR_OF_DAY)
        val m = cal.get(java.util.Calendar.MINUTE)
        val s = cal.get(java.util.Calendar.SECOND)
        return String.format("%02d:%02d:%02d", h, m, s)
    }

    data class Quad<A,B,C,D>(val first: A, val second: B, val third: C, val fourth: D)
}
