package com.fqyw.screen_memo

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Base64
 
import com.fqyw.screen_memo.FileLogger
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Timer
import java.util.TimerTask
import java.util.Collections
import java.util.HashSet
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
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
    private const val PROVIDER_IMAGE_HARD_LIMIT = 16

    // 读写设置（SharedPreferences）
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)

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
    private fun acquireAiRateSlot(ctx: Context): Long {
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
        runOnWorker("onScreenshotSaved") {
            onScreenshotSavedInternal(appCtx, appPackage, appName, filePathAbs, captureTime)
        }
    }

    private fun onScreenshotSavedInternal(ctx: Context, appPackage: String, appName: String, filePathAbs: String, captureTime: Long) {
        try {
            try { FileLogger.i(TAG, "onScreenshotSaved：包名=${appPackage} 文件=${filePathAbs} 时间戳=${captureTime}") } catch (_: Exception) {}
            if (activeSegmentId <= 0) {
                // 先回填历史窗口到最新的可完成段落
                backfillToLatest(ctx)

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
            // 后台补齐到当天最新可完整时段
            backfillToLatest(ctx)
            // 若用户删空了某些日期的动态（segments），这里会对“有截图但无段落”的日期进行回填重建，恢复日期 Tab。
            try { repairMissingDaysFromRecentShots(ctx) } catch (_: Exception) {}
            // 定时补救：扫描缺失结果的段落
            try { resumeMissingSummaries(ctx, limit = 2) } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    private fun repairMissingDaysFromRecentShots(ctx: Context) {
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

        var created = 0
        var i = 0
        while (i < shots.size) {
            val windowStart = shots[i].captureTime
            if (windowStart <= 0L) { i++; continue }
            if (windowStart > dayEndMillis) break // 仅生成 start_time 仍属于本日的段落

            val windowEnd = windowStart + durationMs
            if (windowEnd > nowMillis) break // 不满足“可完整结束”的动态生成条件

            try {
                if (!SegmentDatabaseHelper.hasSegmentExact(ctx, windowStart, windowEnd)) {
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

            // 跳到"下一个有图片且时间 >= windowEnd"的索引
            var j = i + 1
            while (j < shots.size && shots[j].captureTime < windowEnd) j++
            i = j
        }

        if (created > 0) {
            try { FileLogger.i(TAG, "repairDays: rebuilt day=$dayKey createdSegments=$created") } catch (_: Exception) {}
        }
        return created
    }

    private fun dateKeyFromMillis(ms: Long): String {
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = ms }
        val y = cal.get(java.util.Calendar.YEAR).toString().padStart(4, '0')
        val m = (cal.get(java.util.Calendar.MONTH) + 1).toString().padStart(2, '0')
        val d = cal.get(java.util.Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
        return "$y-$m-$d"
    }

    private fun dayBoundsMillis(dayKey: String): Pair<Long, Long>? {
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

    private fun findFirstShotStrictAfter(ctx: Context, strictAfterMillis: Long): SegmentDatabaseHelper.ShotInfo? {
        // 小窗口向后2分钟内寻找，避免全局扫描
        val end = strictAfterMillis + 2 * 60_000L
        val shots = SegmentDatabaseHelper.listShotsBetween(ctx, strictAfterMillis, end)
        return shots.minByOrNull { it.captureTime }
    }

    private fun tryCollectSamplesAndMaybeFinish(ctx: Context) {
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
                val windowStart = shots[i].captureTime
                val windowEnd = windowStart + durationSec * 1000L
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

                // 聚合应用与时间片，组织提示（仅使用实际送入的 effSamples）
                val byApp = LinkedHashMap<String, MutableList<SegmentDatabaseHelper.Sample>>()
                for (s in effSamples) {
                    byApp.getOrPut(s.appPackageName) { ArrayList() }.add(s)
                }

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
                    "- 后续小节建议包含：\"## 关键操作\"（按时间的要点清单）、\"## 主要活动\"（按应用/主题的要点清单）、\"## 重点内容\"（可保留的标题/作者/品牌等）；\n" +
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
                val appLabel = getStringByLang(ctx, effectiveLang, R.string.label_app_zh, R.string.label_app_en, R.string.label_app_ja, R.string.label_app_ko)
                val shotLabel = getStringByLang(ctx, effectiveLang, R.string.label_screenshot_at_zh, R.string.label_screenshot_at_en, R.string.label_screenshot_at_ja, R.string.label_screenshot_at_ko)
                val fileLabel = getStringByLang(ctx, effectiveLang, R.string.label_file_zh, R.string.label_file_en, R.string.label_file_ja, R.string.label_file_ko)

                sb.append(timeRangeLabel).append(fmt(seg.startTime)).append(" - ").append(fmt(seg.endTime)).append('\n')
                sb.append(header).append('\n')
                for ((pkg, list) in byApp) {
                    list.sortBy { it.captureTime }
                    val name = list.firstOrNull()?.appName ?: pkg
                    sb.append(appLabel).append(name).append(" (").append(pkg).append(")\n")
                    for (s in list) {
                        sb.append(shotLabel).append(fmt(s.captureTime)).append(fileLabel).append(File(s.filePath).name).append('\n')
                    }
                }

                val prompt = sb.toString()
                try { FileLogger.i(TAG, "finish：调用 AI images=${effSamples.size}/${samples.size} seg=${seg.id}") } catch (_: Exception) {}
                val result = callGeminiWithImages(ctx, seg, effSamples, prompt)
                try {
                    FileLogger.i(TAG, "finish：AI 模型=${result.first} 输出长度=${result.second.length}")
                    val preview = truncateForLog(result.second, 3000)
                    FileLogger.i(TAG, "AI响应预览: ${preview}")
                } catch (_: Exception) {}
                // 将合并需要的摘要提前缓存；合并任务放到 finally 之后异步执行，避免阻塞完成清理。
                var outputToSave = result.second
                var structuredToSave = result.third
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
                mergeOutputText = outputToSave
                mergeStructuredJson = structuredToSave
                SegmentDatabaseHelper.saveResult(
                    ctx,
                    seg.id,
                    provider = "gemini",
                    model = result.first,
                    outputText = outputToSave,
                    structuredJson = structuredToSave,
                    categories = result.fourth
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
                    try {
                        val cfg = AISettingsNative.readConfig(ctx)
                        if (cfg.model.isNotBlank()) modelName = cfg.model
                    } catch (_: Exception) {}
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
                        categories = null
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

    // 返回 (model, outputText, structuredJson, categories)
    private fun callGeminiWithImages(
        ctx: Context,
        seg: SegmentDatabaseHelper.Segment,
        samples: List<SegmentDatabaseHelper.Sample>,
        prompt: String,
        isMerge: Boolean = false,
        injectDynamicRules: Boolean = true,
        maxImagesOverride: Int? = null
    ): Quad<String, String, String?, String?> {
        val cfg = AISettingsNative.readConfig(ctx)
        val apiKey = cfg.apiKey
        val client = OkHttpClientFactory.newBuilder(ctx)
            .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(0, java.util.concurrent.TimeUnit.SECONDS) // 0 = no read timeout
            .writeTimeout(0, java.util.concurrent.TimeUnit.SECONDS) // 0 = no write timeout
            .retryOnConnectionFailure(true)
            .build()

        val model = cfg.model
        val base = if (cfg.baseUrl.endsWith('/')) cfg.baseUrl.dropLast(1) else cfg.baseUrl
        val isGoogle = base.contains("googleapis.com") || base.contains("generativelanguage")

        // 统一图片限额（默认：floor(duration/interval)，并受提供方硬上限保护；调用方可指定更小的 cap，但不可突破硬上限）
        val capBySeg = (seg.durationSec / seg.sampleIntervalSec).coerceAtLeast(1)
        val requestedCap = maxImagesOverride?.takeIf { it > 0 } ?: capBySeg
        val effectiveCap =
            kotlin.math.min(requestedCap, PROVIDER_IMAGE_HARD_LIMIT).coerceAtLeast(1)
        val samplesOrdered = samples.sortedBy { it.captureTime }
        val effSamples = if (samplesOrdered.size > effectiveCap) evenPick(samplesOrdered, effectiveCap) else samplesOrdered

        val promptWithRule = if (!injectDynamicRules) {
            prompt
        } else {
            // 依据应用语言注入动态规则：限制逐图文字描述上限（<= 总图数的 1/3）
            val langOptForRule = try { ctx.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE).getString("flutter.locale_option", "system") } catch (_: Exception) { "system" }
            val sysLangForRule = try { java.util.Locale.getDefault().language?.lowercase() } catch (_: Exception) { "en" } ?: "en"
            val isZhForRule = (langOptForRule == "zh") || (langOptForRule != "en" && sysLangForRule.startsWith("zh"))
            val effectiveLangForRule = when (langOptForRule) {
                "zh", "en", "ja", "ko" -> langOptForRule
                "system" -> when {
                    sysLangForRule.startsWith("zh") -> "zh"
                    sysLangForRule.startsWith("ja") -> "ja"
                    sysLangForRule.startsWith("ko") -> "ko"
                    else -> "en"
                }
                else -> "en"
            }
            val totalImagesToSend = effSamples.size
            val maxDescImages = (totalImagesToSend / 3)
            val dynamicCapRule = if (isMerge) {
                if (isZhForRule) {
                    """
- 仅对不超过总数三分之一的代表性图片进行文字描述（向下取整，允许0张）；例如本次共 ${totalImagesToSend} 张，最多描述 ${maxDescImages} 张；其余图片不要逐图描述，请合并进整体总结。
- 如需逐图说明，请使用 described_images[] 列出这些被描述的图片（长度≤上述上限）；每项：{file:"文件名", ref_time:"HH:mm:ss", app:"应用名", summary:"(Markdown) 单图关键信息与选择理由"}。
- key_actions[].ref_image 必须复用 content_groups[].representative_images 中已选择的文件名，不得新增超出上限的图片引用。
""".trim()
                } else {
                    """
- Provide textual descriptions for at most one-third of the images (floor; may be 0). For example, ${totalImagesToSend} images -> at most ${maxDescImages}. Do not narrate the rest image-by-image; integrate them into the summary.
- If you describe any individual images, list them in described_images[] (length <= the cap); each item: {file:"filename", ref_time:"HH:mm:ss", app:"App", summary:"(Markdown) key info and selection reason"}.
- key_actions[].ref_image MUST reuse filenames chosen in content_groups[].representative_images and MUST NOT exceed the cap.
""".trim()
                }
            } else {
                if (isZhForRule) {
                    """
- 仅对不超过总数三分之一的代表性图片进行文字描述（向下取整，允许0张）；例如本次共 ${totalImagesToSend} 张，最多描述 ${maxDescImages} 张；其余图片不要逐图描述，请合并进摘要。
- 仅使用 described_images[] 列出这些"被文字描述"的单张图片，数组长度<=上述上限；每项结构：{file:"文件名", ref_time:"HH:mm:ss", app:"应用名", summary:"(Markdown) 单图关键信息与选择理由"}。
- key_actions[].ref_image 必须复用 described_images[] 中的文件名，不得新增超出上限的图片引用。
""".trim()
                } else {
                    """
- Provide textual descriptions for at most one-third of the images (floor; may be 0). For example, ${totalImagesToSend} images -> at most ${maxDescImages}. Do not narrate the rest image-by-image; integrate them into the summary.
- Use described_images[] ONLY to list the individually described images, length <= the cap; each item: {file:"filename", ref_time:"HH:mm:ss", app:"App", summary:"(Markdown) key info and selection reason for the single image"}.
- key_actions[].ref_image MUST reuse filenames in described_images[] and MUST NOT exceed the cap.
""".trim()
                }
            }
            val dynamicImageRule = when (effectiveLangForRule) {
                "zh" -> """
 - 本次共 ${totalImagesToSend} 张图片。必须输出 image_tags[]，长度必须等于 ${totalImagesToSend}，且 file 必须与输入文件名完全一致（只写文件名，不写路径）。tags 必须为中文本地化标签；如涉及成人/裸露/性暗示等，请额外添加英文统一标签 "nsfw"（必须小写）。除 "nsfw" 外不要输出英文标签。
 - 必须输出 image_descriptions[] 覆盖所有图片：每项 {from_file:"文件名", to_file:"文件名", description:"至少6句自然语言（尽可能 8-12 句）"}；允许将连续且内容高度一致的图片合并为一段（例如连续聊天截图），用 from_file/to_file 表示范围；确保所有文件名被覆盖且不重复。
 - 为了便于后续检索/语义搜索：description 必须尽可能详尽、多角度描述画面（场景/界面布局/关键元素/可能的操作与意图/状态变化等），并覆盖尽可能多的可检索关键词/实体（应用/页面/功能/人物/地点/商品/流程等）。不要逐字抄写可见文字，也不要输出“可见文字：...”这类字段。每条 description 末尾必须追加 1 行：`关键词：...`（尽可能多、尽可能具体，可包含同义词/拆词/中英缩写；关键词建议至少 20 个，用 `、` 分隔）。
 - key_actions[].ref_image 必须引用本次输入的文件名之一（只能是文件名）。
 """.trim()
                "ja" -> """
 - 今回は画像が ${totalImagesToSend} 枚です。image_tags[] を必ず出力し、要素数は ${totalImagesToSend} と同じにしてください。file は入力にあるファイル名と完全一致（パス禁止）。tags は日本語のローカライズタグを使用し、成人/露出/性的示唆などがある場合は英語の統一タグ "nsfw"(小文字) を追加してください。"nsfw" 以外は英語タグを出力しないでください。
 - image_descriptions[] で全画像をカバーしてください。各要素: {from_file:"ファイル名", to_file:"ファイル名", description:"自然言語で6文以上（可能なら 8-12 文）"}。内容がほぼ同じ連続画像（例: チャットの連続スクショ）は 1 つにまとめ、from_file/to_file で範囲を表現してください。全ファイル名が重複なく必ず含まれるようにしてください。
 - 検索しやすくするため、description はできるだけ詳細に多角度で記述し（場面/レイアウト/主要要素/想定される操作や意図/状態変化など）、具体的な固有名詞/キーワード（アプリ/画面/機能/人物/場所/商品/ワークフロー等）をできるだけ多く含めてください。画面上の文字の書き起こしは不要で、`表示文字：...` のような欄も出力しないでください。各 description の末尾に必ず 1 行 `キーワード：...` を追加してください（できるだけ多く、同義語/分割語/略語も可；目安として 20 個以上）。
 - key_actions[].ref_image は今回入力したファイル名のいずれかを参照してください（ファイル名のみ）。
 """.trim()
                "ko" -> """
 - 이번 요청에는 이미지가 ${totalImagesToSend}장 있습니다. image_tags[]를 반드시 출력하고 길이는 ${totalImagesToSend}와 같아야 합니다. file은 입력 파일명과 완전히 일치해야 하며(경로 금지), tags는 한국어 로컬라이즈 태그를 사용하세요. 성인/노출/성적 암시 등이 있으면 영어 통일 태그 "nsfw"(소문자)를 추가하세요. "nsfw" 외에는 영어 태그를 출력하지 마세요.
 - image_descriptions[]로 모든 이미지를 커버하세요. 각 항목: {from_file:"파일명", to_file:"파일명", description:"자연어 6문장 이상(가능하면 8-12문장)"}. 내용이 거의 동일한 연속 이미지(예: 연속 채팅 캡처)는 1개로 묶고 from_file/to_file로 범위를 표시하세요. 모든 파일명이 중복 없이 반드시 포함되도록 하세요.
 - 검색/시맨틱 검색을 위해 description을 가능한 한 상세하고 다각도로 작성하세요(상황/레이아웃/핵심 요소/가능한 행동·의도/상태 변화 등). 구체적인 키워드/개체(앱/화면/기능/인물/장소/상품/워크플로 등)를 최대한 많이 포함하세요. 화면 글자 전사는 필요 없으며 `보이는 글자：...` 같은 항목도 출력하지 마세요. 각 description 끝에 반드시 1줄 `키워드：...`를 추가하세요(가능한 한 많이, 동의어/분해어/약어 포함 가능; 최소 20개 권장).
 - key_actions[].ref_image는 이번 입력 파일명 중 하나를 참조해야 합니다(파일명만).
 """.trim()
                else -> """
 - This request includes ${totalImagesToSend} images. You MUST output image_tags[] with exactly ${totalImagesToSend} items. Each item's file must exactly match the input filename (filename only, no path). tags must be localized to the prompt language; if the image contains adult/nudity/sexual content, add the unified English tag "nsfw" (lowercase). Do not output other English tags besides "nsfw" when the prompt language is not English.
 - You MUST output image_descriptions[] covering ALL images. Each item: {from_file:"filename", to_file:"filename", description:"at least 6 natural language sentences (aim for 8-12 if reasonable)"}. You may merge highly similar consecutive images (e.g., continuous chat screenshots) into one description group and use from_file/to_file to denote the range. Ensure every filename is covered exactly once (no missing, no duplicates).
 - For retrieval/semantic search, each description must be detailed and multi-angle (scene/layout/key elements/likely action & intent/state changes) and include as many concrete searchable keywords/entities as possible (app/page/feature/people/places/product/workflow, etc.). Do NOT transcribe long on-screen text and do NOT output a separate "Visible text" field/section. Append exactly ONE final line to each description: `Keywords: ...` (many items; include synonyms/split-words/abbreviations when helpful; aim for 20+ keywords).
 - key_actions[].ref_image MUST reference one of the input filenames (filename only).
 """.trim()
            }

            // 结构化呈现规则：开头一段纯文本总结，随后 Markdown 小节
            val dynamicStructureRule = if (isZhForRule) {
                "- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现\\\"## 概览\\\"或\\\"## 总结\\\"等）；随后再使用 Markdown 小节呈现后续内容。"
            } else {
                "- Start with one plain paragraph (no heading) summarizing the time window; then present details using Markdown subsections."
            }
            // 将规则同时注入到开头与结尾，增强模型注意力与遵循度
            // 说明：dynamicCapRule 约束 "described_images"（少量关键图），dynamicImageRule 约束 "image_tags/image_descriptions"（覆盖全部输入图）
            val headRules = listOf(dynamicCapRule, dynamicImageRule, dynamicStructureRule)
                .filter { it.isNotEmpty() }
                .joinToString("\n")
            if (headRules.isNotEmpty()) "$headRules\n\n$prompt\n$headRules" else prompt
        }

        // 速率限制：必要时等待
        val waited = acquireAiRateSlot(ctx)

        // 配置校验与请求前日志
        try {
            if (apiKey.isNullOrBlank()) {
                FileLogger.e(TAG, "AI 配置错误：缺少 apiKey")
            }
            if (base.isBlank()) {
                FileLogger.e(TAG, "AI 配置错误：缺少 baseUrl")
            }
            if (model.isBlank()) {
                FileLogger.e(TAG, "AI 配置提示：model 为空，如服务端支持将使用默认模型")
            }
            if (waited > 0L) {
                FileLogger.i(TAG, "AI 因速率限制等待了 ${waited}毫秒")
            }
        } catch (_: Exception) {}

        // 统计图片字节与预览
        var totalImageBytes = 0L
        var missingImages = 0
        val firstNames = ArrayList<String>()
        for (s in effSamples) {
            try {
                val f = File(s.filePath)
                val size = if (f.exists()) f.length() else 0L
                if (size <= 0L) missingImages++ else totalImageBytes += size
                if (firstNames.size < 6) firstNames.add(f.name)
            } catch (_: Exception) { missingImages++ }
        }
        val textLen = prompt.length
        val textLenWithRule = promptWithRule.length
        try {
            FileLogger.i(
                TAG,
                "AI 准备：提供方=${if (isGoogle) "google" else "openai-compat"}, 模型=${model}, baseUrl=${base}, 段ID=${seg.id}, 合并=${isMerge}, 文本长度=${textLen}, 文本长度(含规则)=${textLenWithRule}, 图片数=${samples.size}, 字节数=${totalImageBytes}, 缺失图片=${missingImages}, 前几个文件=${firstNames.joinToString("|")}"
            )
        } catch (_: Exception) {}
        try {
            val promptPreview = truncateForLog(promptWithRule, 800)
            FileLogger.i(TAG, "AI 提示词预览：${promptPreview}")
        } catch (_: Exception) {}
        try {
            OutputFileLogger.info(ctx, TAG, "AI 准备：提供方=${if (isGoogle) "google" else "openai-compat"}, 模型=${model}, baseUrl=${base}, 段ID=${seg.id}, 合并=${isMerge}, 文本长度=${textLen}, 文本长度(含规则)=${textLenWithRule}, 图片数=${samples.size}, 字节数=${totalImageBytes}, 缺失图片=${missingImages}, 前几个文件=${firstNames.joinToString("|")}")
        } catch (_: Exception) {}

        // 额外打印提示词预览（不含图片/密钥）：Logcat 截断 + 文件完整
        try {
            val promptPreview = truncateForLog(promptWithRule, 800)
            FileLogger.i(TAG, "AI 提示词预览：${promptPreview}")
        } catch (_: Exception) {}
        try {
            OutputFileLogger.info(ctx, TAG, "AI 提示词完整内容开始 >>>")
            OutputFileLogger.info(ctx, TAG, promptWithRule)
            OutputFileLogger.info(ctx, TAG, "AI 提示词完整内容结束 <<<")
        } catch (_: Exception) {}

        if (isGoogle) {
            // Gemini REST: POST {base}/v1beta/models/{model}:generateContent
            val url = "$base/v1beta/models/$model:generateContent"
            try { FileLogger.i(TAG, "AI 请求：地址=$url 模型=$model 图片数=${effSamples.size}") } catch (_: Exception) {}
            try { FileLogger.i(TAG, "AI 请求：地址=$url 模型=$model 图片数=${effSamples.size}") } catch (_: Exception) {}
            try { OutputFileLogger.info(ctx, TAG, "AI 请求：地址=$url 模型=$model 图片数=${effSamples.size}") } catch (_: Exception) {}

            val parts = JSONArray()
            parts.put(JSONObject().put("text", promptWithRule))
            for (s in effSamples) {
                val imgBytes = try { File(s.filePath).readBytes() } catch (_: Exception) { null }
                if (imgBytes == null || imgBytes.isEmpty()) continue
                val b64 = Base64.encodeToString(imgBytes, Base64.NO_WRAP)
                val inline = JSONObject()
                    .put("mimeType", guessMime(s.filePath))
                    .put("data", b64)
                parts.put(JSONObject().put("inlineData", inline))
            }
            val contents = JSONArray().put(JSONObject().put("parts", parts))
            val body = JSONObject().put("contents", contents).toString()
            val reqBody: RequestBody = body.toRequestBody("application/json; charset=utf-8".toMediaType())
            val req = Request.Builder()
                .url(url)
                .addHeader("x-goog-api-key", apiKey ?: "")
                .post(reqBody)
                .build()
            val t0 = System.currentTimeMillis()
            var respText = ""
            run {
                var attempt = 0
                val maxAttempts = 3
                var lastCode = -1
                var lastBody: String? = null
                while (attempt < maxAttempts) {
                    val start = System.currentTimeMillis()
                    try {
                        val resp = client.newCall(req).execute()
                        val end = System.currentTimeMillis()
                        lastCode = resp.code
                        try { FileLogger.i(TAG, "AI 响应元信息：code=${resp.code} 耗时毫秒=${end - start} 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { FileLogger.i(TAG, "AI 响应元信息：code=${resp.code} 耗时毫秒=${end - start} 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.info(ctx, TAG, "AI 响应元信息：code=${resp.code} 耗时毫秒=${end - start} 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        if (resp.isSuccessful) {
                            respText = resp.body?.string() ?: ""
                            break
                        } else {
                            lastBody = resp.body?.string()
                            if (!lastBody.isNullOrEmpty()) {
                                val lower = lastBody.lowercase()
                                if (lower.contains("user location is not supported")) {
                                    try { FileLogger.e(TAG, "Gemini 请求因地区策略被阻止：${truncateForLog(lastBody, 800)}") } catch (_: Exception) {}
                                }
                            }
                            val shouldRetry = resp.code >= 500
                            try { FileLogger.w(TAG, "AI 请求失败(code=${resp.code}) 尝试=${attempt + 1}/${maxAttempts} 响应体=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { FileLogger.w(TAG, "AI 请求失败(code=${resp.code}) 尝试=${attempt + 1}/${maxAttempts} 响应体=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { OutputFileLogger.error(ctx, TAG, "AI 请求失败(code=${resp.code}) 尝试=${attempt + 1}/${maxAttempts} 响应体=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            if (!shouldRetry) throw IllegalStateException("Request failed: ${resp.code} ${lastBody}")
                        }
                    } catch (e: java.net.SocketTimeoutException) {
                        try { FileLogger.w(TAG, "AI 请求超时 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { FileLogger.w(TAG, "AI 请求超时 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI 请求超时 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        // 继续重试
                    } catch (e: Exception) {
                        // 其他IO异常：仅第一次尝试记录，仍然重试
                        try { FileLogger.w(TAG, "AI 请求异常 尝试=${attempt + 1}/${maxAttempts}：${e.message}") } catch (_: Exception) {}
                        try { FileLogger.w(TAG, "AI 请求异常 尝试=${attempt + 1}/${maxAttempts}：${e.message}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI 请求异常 尝试=${attempt + 1}/${maxAttempts}：${e.message}") } catch (_: Exception) {}
                    }
                    attempt++
                    if (attempt < maxAttempts) {
                        val backoff = (1000L * (1 shl (attempt - 1))).coerceAtMost(5000L)
                        try { Thread.sleep(backoff) } catch (_: Exception) {}
                    } else if (lastCode >= 0) {
                        throw IllegalStateException("Request failed: ${lastCode} ${lastBody}")
                    } else {
                        throw IllegalStateException("Request failed: unknown error")
                    }
                }
            }
            try {
                FileLogger.d(TAG, "AI 响应长度=${respText.length}")
                val preview = truncateForLog(respText, 2000)
                FileLogger.i(TAG, "AI 响应预览：${preview}")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                FileLogger.i(TAG, "AI 响应预览：${preview}")
            } catch (_: Exception) {}
            // 完整响应落盘（分块写入）
            try {
                OutputFileLogger.info(ctx, TAG, "AI 响应完整内容开始 >>>")
                val text = respText
                val chunk = 1800
                var i = 0
                while (i < text.length) {
                    val end = kotlin.math.min(i + chunk, text.length)
                    OutputFileLogger.info(ctx, TAG, text.substring(i, end))
                    i = end
                }
                OutputFileLogger.info(ctx, TAG, "AI 响应完整内容结束 <<<")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                OutputFileLogger.info(ctx, TAG, "AI 响应预览：${preview}")
            } catch (_: Exception) {}

            var outputText = ""
            try {
                val obj = JSONObject(respText)
                val candidates = obj.optJSONArray("candidates")
                if (candidates != null && candidates.length() > 0) {
                    val c0 = candidates.getJSONObject(0)
                    val content = c0.optJSONObject("content")
                    val partsOut = content?.optJSONArray("parts")
                    if (partsOut != null && partsOut.length() > 0) {
                        val p0 = partsOut.getJSONObject(0)
                        outputText = p0.optString("text", "")
                    }
                }
            } catch (_: Exception) {}
            // 若无正常内容且响应体包含 error，则回落为直接保存错误预览，供前端显示
            if (outputText.isBlank()) {
                try {
                    val low = respText.lowercase()
                    outputText = when {
                        low.contains("\"error\"") || low.contains("no candidates returned") -> {
                            "AI response preview(Google): " + respText
                        }
                        respText.isNotBlank() -> {
                            "AI empty content(Google), raw response: " + truncateForLog(respText, 2000)
                        }
                        else -> "AI empty response(Google)"
                    }
                } catch (_: Exception) {}
            }
            val (structured, cats) = extractJsonBlocks(outputText)
            // 结构化 JSON 完整输出（Pretty JSON + 分块）
            try {
                if (structured != null && structured.trim().isNotEmpty()) {
                    var pretty = structured
                    try {
                        val jo = JSONObject(structured)
                        pretty = jo.toString(2)
                    } catch (_: Exception) {
                        try {
                            val ja = JSONArray(structured)
                            pretty = ja.toString(2)
                        } catch (_: Exception) {}
                    }
                    OutputFileLogger.info(ctx, TAG, "AI structured_json 开始 >>>")
                    val textSJ = pretty
                    val chunkSJ = 1800
                    var p = 0
                    while (p < textSJ.length) {
                        val end = kotlin.math.min(p + chunkSJ, textSJ.length)
                        OutputFileLogger.info(ctx, TAG, textSJ.substring(p, end))
                        p = end
                    }
                    OutputFileLogger.info(ctx, TAG, "AI structured_json 结束 <<<")
                } else {
                    OutputFileLogger.info(ctx, TAG, "AI structured_json 为空")
                }
                if (cats != null && cats.trim().isNotEmpty()) {
                    OutputFileLogger.info(ctx, TAG, "AI 分类：${cats}")
                }
            } catch (_: Exception) {}
            return Quad(model, outputText, structured, cats)
        } else {
            // OpenAI 兼容 REST: POST {base}/v1/chat/completions
            val url = "$base/v1/chat/completions"
            try { FileLogger.i(TAG, "AI 请求(OpenAI兼容)：地址=$url 模型=$model 图片数=${effSamples.size}") } catch (_: Exception) {}
            try { FileLogger.i(TAG, "AI 请求(OpenAI兼容)：地址=$url 模型=$model 图片数=${effSamples.size}") } catch (_: Exception) {}
            try { OutputFileLogger.info(ctx, TAG, "AI 请求(OpenAI兼容)：地址=$url 模型=$model 图片数=${effSamples.size}") } catch (_: Exception) {}

            val contentArr = JSONArray()
            contentArr.put(JSONObject().put("type", "text").put("text", promptWithRule))
            for (s in effSamples) {
                val imgBytes = try { File(s.filePath).readBytes() } catch (_: Exception) { null }
                if (imgBytes == null || imgBytes.isEmpty()) continue
                val b64 = Base64.encodeToString(imgBytes, Base64.NO_WRAP)
                val dataUrl = "data:" + guessMime(s.filePath) + ";base64," + b64
                val imageUrl = JSONObject().put("url", dataUrl)
                contentArr.put(JSONObject().put("type", "image_url").put("image_url", imageUrl))
            }
            val messages = JSONArray().put(JSONObject()
                .put("role", "user")
                .put("content", contentArr)
            )
            val body = JSONObject()
                .put("model", model)
                .put("messages", messages)
                .put("temperature", 0.2)
                .put("stream", false)
                .toString()

            val reqBody: RequestBody = body.toRequestBody("application/json; charset=utf-8".toMediaType())
            val req = Request.Builder()
                .url(url)
                .post(reqBody)
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .build()
            val t0 = System.currentTimeMillis()
            var respText = ""
            run {
                var attempt = 0
                val maxAttempts = 3
                var lastCode = -1
                var lastBody: String? = null
                while (attempt < maxAttempts) {
                    val start = System.currentTimeMillis()
                    try {
                        val resp = client.newCall(req).execute()
                        val end = System.currentTimeMillis()
                        lastCode = resp.code
                        try { FileLogger.i(TAG, "AI 响应元信息(OpenAI兼容)：code=${resp.code} 耗时毫秒=${end - start} 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { FileLogger.i(TAG, "AI 响应元信息(OpenAI兼容)：code=${resp.code} 耗时毫秒=${end - start} 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.info(ctx, TAG, "AI 响应元信息(OpenAI兼容)：code=${resp.code} 耗时毫秒=${end - start} 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        if (resp.isSuccessful) {
                            respText = resp.body?.string() ?: ""
                            // 检测 200 成功但响应体为错误或无候选的情况（如 {"error":{...}}）
                            var hasPayloadError = false
                            try {
                                val obj = org.json.JSONObject(respText)
                                val err = obj.optJSONObject("error")
                                if (err != null) {
                                    hasPayloadError = true
                                }
                            } catch (_: Exception) {
                                // 非 JSON 或无法解析则按正常成功处理
                            }
                            if (hasPayloadError) {
                                // 记录并视为"带错误负载的成功"，交由下游保存错误预览供前端展示，避免自动重试
                            try { FileLogger.w(TAG, "AI 成功(200)但响应体为错误(OpenAI)：body=${truncateForLog(respText, 800)}") } catch (_: Exception) {}
                            try { OutputFileLogger.error(ctx, TAG, "AI 成功(200)但响应体为错误(OpenAI)：body=${truncateForLog(respText, 800)}") } catch (_: Exception) {}
                                break
                            } else {
                                // 正常成功
                                break
                            }
                        } else {
                            lastBody = resp.body?.string()
                            val shouldRetry = resp.code >= 500
                            try { FileLogger.w(TAG, "AI 请求失败(OpenAI兼容)：code=${resp.code} 尝试=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { FileLogger.w(TAG, "AI 请求失败(OpenAI兼容)：code=${resp.code} 尝试=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { OutputFileLogger.error(ctx, TAG, "AI 请求失败(OpenAI兼容)：code=${resp.code} 尝试=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            if (!shouldRetry) throw IllegalStateException("Request failed: ${resp.code} ${lastBody}")
                        }
                    } catch (e: java.net.SocketTimeoutException) {
                        try { FileLogger.w(TAG, "AI 请求超时(OpenAI) 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { FileLogger.w(TAG, "AI 请求超时(OpenAI) 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI 请求超时(OpenAI) 尝试=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        // 继续重试
                    } catch (e: Exception) {
                        try { FileLogger.w(TAG, "AI 请求异常(OpenAI) 尝试=${attempt + 1}/${maxAttempts}：${e.message}") } catch (_: Exception) {}
                        try { FileLogger.w(TAG, "AI 请求异常(OpenAI) 尝试=${attempt + 1}/${maxAttempts}：${e.message}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI 请求异常(OpenAI) 尝试=${attempt + 1}/${maxAttempts}：${e.message}") } catch (_: Exception) {}
                    }
                    attempt++
                    if (attempt < maxAttempts) {
                        val backoff = (1000L * (1 shl (attempt - 1))).coerceAtMost(5000L)
                        try { Thread.sleep(backoff) } catch (_: Exception) {}
                    } else if (lastCode >= 0) {
                        throw IllegalStateException("Request failed: ${lastCode} ${lastBody}")
                    } else {
                        throw IllegalStateException("Request failed: unknown error")
                    }
                }
            }
            try {
                FileLogger.d(TAG, "AI 响应长度(OpenAI兼容)=${respText.length}")
                val preview = truncateForLog(respText, 2000)
                FileLogger.i(TAG, "AI 响应预览(OpenAI)：${preview}")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                FileLogger.i(TAG, "AI 响应预览(OpenAI)：${preview}")
            } catch (_: Exception) {}
            // 完整响应落盘（分块写入）
            try {
                OutputFileLogger.info(ctx, TAG, "AI 响应完整内容(OpenAI) 开始 >>>")
                val text2 = respText
                val chunk2 = 1800
                var j = 0
                while (j < text2.length) {
                    val end = kotlin.math.min(j + chunk2, text2.length)
                    OutputFileLogger.info(ctx, TAG, text2.substring(j, end))
                    j = end
                }
                OutputFileLogger.info(ctx, TAG, "AI 响应完整内容(OpenAI) 结束 <<<")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                OutputFileLogger.info(ctx, TAG, "AI 响应预览(OpenAI)：${preview}")
            } catch (_: Exception) {}
            var outputText = ""
            try {
                val obj = JSONObject(respText)
                val choices = obj.optJSONArray("choices")
                if (choices != null && choices.length() > 0) {
                    val c0 = choices.getJSONObject(0)
                    val msg = c0.optJSONObject("message")
                    outputText = msg?.optString("content", "") ?: ""
                }
            } catch (_: Exception) {}
            // 若无正常内容且响应体包含 error，则回落为直接保存错误预览，供前端显示
            if (outputText.isBlank()) {
                try {
                    val low = respText.lowercase()
                    outputText = when {
                        low.contains("\"error\"") || low.contains("no candidates returned") -> {
                            "AI response preview(OpenAI): " + respText
                        }
                        respText.isNotBlank() -> {
                            "AI empty content(OpenAI), raw response: " + truncateForLog(respText, 2000)
                        }
                        else -> "AI empty response(OpenAI)"
                    }
                } catch (_: Exception) {}
            }
            val (structured, cats) = extractJsonBlocks(outputText)
            // 结构化 JSON 完整输出（Pretty JSON + 分块）
            try {
                if (structured != null && structured.trim().isNotEmpty()) {
                    var pretty = structured
                    try {
                        val jo = JSONObject(structured)
                        pretty = jo.toString(2)
                    } catch (_: Exception) {
                        try {
                            val ja = JSONArray(structured)
                            pretty = ja.toString(2)
                        } catch (_: Exception) {}
                    }
                    OutputFileLogger.info(ctx, TAG, "AI structured_json(OpenAI) 开始 >>>")
                    val textSJ2 = pretty
                    val chunkSJ2 = 1800
                    var q = 0
                    while (q < textSJ2.length) {
                        val end = kotlin.math.min(q + chunkSJ2, textSJ2.length)
                        OutputFileLogger.info(ctx, TAG, textSJ2.substring(q, end))
                        q = end
                    }
                    OutputFileLogger.info(ctx, TAG, "AI structured_json(OpenAI) 结束 <<<")
                } else {
                    OutputFileLogger.info(ctx, TAG, "AI structured_json(OpenAI) 为空")
                }
                if (cats != null && cats.trim().isNotEmpty()) {
                    OutputFileLogger.info(ctx, TAG, "AI 分类(OpenAI)：${cats}")
                }
            } catch (_: Exception) {}
            return Quad(model, outputText, structured, cats)
        }
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
                    if (ok) s else SegmentDatabaseHelper.getPreviousCompletedSegmentWithResult(ctx, cur.startTime)
                } else {
                    SegmentDatabaseHelper.getPreviousCompletedSegmentWithResult(ctx, cur.startTime)
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
                sb.append("请判断两段时间是否属于同一用户事件：\n")
                    .append("段A：").append(fmt(prev.startTime)).append(" - ").append(fmt(prev.endTime)).append('\n')
                    .append("段B：").append(fmt(cur.startTime)).append(" - ").append(fmt(cur.endTime)).append('\n')
                    .append("注意：只根据画面语义与行为，不做OCR逐字比对；更关注是否为同一持续活动。\n")
                    .append("两段各自的 overall_summary：\n")
                    .append("A: ").append(extractOverallSummary(prevOutput)).append('\n')
                    .append("B: ").append(extractOverallSummary(curOutputText)).append('\n')
                val gapMin = kotlin.math.max(0L, (cur.startTime - prev.endTime)) / 60000L
                sb.append("两段时间间隔约：").append(gapMin).append(" 分钟\n")
                    .append("合并判定策略（放宽）：\n")
                    .append("- 若两段主要应用相同，或同属'视频观看/文章阅读/信息流浏览/社交浏览/购物浏览/办公操作'等同类行为，即使内容不同也视为同一事件；\n")
                    .append("- 若时间间隔 ≤ 3 分钟，或后段延续了前段的同类行为，倾向判定 same_event=true；\n")
                    .append("- 短暂且占比很小的打断（例如少量截图/短暂切换）应忽略；\n")
                    .append("- 请输出 JSON：{\\\"same_event\\\":true|false,\\\"reason\\\":\\\"简述\\\",\\\"primary_activity\\\":\\\"watching|reading|browsing|shopping|working|other\\\"}\n")
            } else {
                sb.append("Decide whether the two time ranges belong to the same user event:\n")
                    .append("Range A: ").append(fmt(prev.startTime)).append(" - ").append(fmt(prev.endTime)).append('\n')
                    .append("Range B: ").append(fmt(cur.startTime)).append(" - ").append(fmt(cur.endTime)).append('\n')
                    .append("Note: Judge by on-screen semantics and behavior only; DO NOT rely on OCR word-by-word matching. Focus on whether it's the same continuous activity.\n")
                    .append("Each range overall_summary:\n")
                    .append("A: ").append(extractOverallSummary(prevOutput)).append('\n')
                    .append("B: ").append(extractOverallSummary(curOutputText)).append('\n')
                val gapMin = kotlin.math.max(0L, (cur.startTime - prev.endTime)) / 60000L
                sb.append("Approximate gap between ranges: ").append(gapMin).append(" minutes\n")
                    .append("Merge decision guidelines (relaxed):\n")
                    .append("- If the main app is the same, or both are of the same activity type (video watching/article reading/feed browsing/social browsing/shopping/working), treat as the same event even when content differs.\n")
                    .append("- If the gap ≤ 3 minutes, or the latter continues the former activity type, prefer same_event=true.\n")
                    .append("- Ignore brief interruptions with small proportion (e.g., few screenshots/short switches).\n")
                    .append("- Output JSON: {\\\"same_event\\\":true|false,\\\"reason\\\":\\\"brief\\\",\\\"primary_activity\\\":\\\"watching|reading|browsing|shopping|working|other\\\"}\n")
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
            val decisionText = decide.second
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
        val mergePrompt = buildMergePrompt(
            ctx,
            prev,
            cur,
            mergedAiSamples,
            textOnlyDescriptions = mergePlan.textOnlyDescriptions,
            totalImages = mergedUniqueSamples.size,
            maxAttachedImages = maxAiImages,
            forced = forceMerge
        )
        try {
            FileLogger.i(
                TAG,
                "merge: merging window ${fmt(prev.startTime)}..${fmt(cur.endTime)} images=${mergedAiSamples.size}/${mergedUniqueSamples.size} (max_ai_images=${maxAiImages}) using merge prompt"
            )
        } catch (_: Exception) {}
        val merged = try {
            callGeminiWithImages(
                ctx,
                cur,
                mergedAiSamples,
                mergePrompt,
                isMerge = true,
                maxImagesOverride = maxAiImages
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
        try { FileLogger.i(TAG, "merge: merged summary saved for seg=${cur.id} outputSize=${merged.second.length}") } catch (_: Exception) {}
        // 将"合并后的 AI 输出"落盘
        try {
            val preview2 = truncateForLog(merged.second, 3000)
            FileLogger.i(TAG, "merged summary preview: ${preview2}")
        } catch (_: Exception) {}

        // 为“原始事件下拉菜单”补齐合并前内容：
        // 1) 取 prev/cur 的 overall_summary（若 cur 已是合并事件，则取其原始部分）
        // 2) 将这些原始摘要用 `---` 分隔追加到“合并后的 overall_summary”之后
        //    => Flutter 侧可通过 splitMergedEventSummaryParts(summary) 展示原始事件列表
        val prevOriginalSummaries = extractOriginalSummaryPartsForMerge(prevRes.first, prevRes.second)
        val curOriginalSummaries = extractOriginalSummaryPartsForMerge(curOutputText, curStructured)
        val mergedPatched = attachOriginalSummariesToMergedResult(
            mergedOutputText = merged.second,
            mergedStructuredJson = merged.third,
            prevOriginals = prevOriginalSummaries,
            curOriginals = curOriginalSummaries
        )
        var mergedOutputTextForSave = mergedPatched.first
        var mergedStructuredForSave = mergedPatched.second
        var mergedCategoriesForSave: String? = merged.fourth
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
        // 更新当前段时间窗口到合并范围
        SegmentDatabaseHelper.updateSegmentWindow(ctx, cur.id, prev.startTime, cur.endTime)
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
        // 覆写当前段的结果（保持上一个不变），并标记上一个段状态为 completed-merged 可选
        SegmentDatabaseHelper.saveResult(
            ctx,
            cur.id,
            provider = "gemini",
            model = merged.first,
            outputText = mergedOutputTextForSave,
            structuredJson = mergedStructuredWithImages,
            categories = mergedCategoriesForSave
        )
        // 将合并后的图片标签/描述写入全局可复用表（按 file_path），避免合并事件在查看器/语义搜索中丢失图片元数据
        try {
            SegmentDatabaseHelper.upsertAiImageMetaFromStructuredJson(
                ctx,
                segmentId = cur.id,
                samples = mergedSamplesForUi,
                structuredJson = mergedStructuredWithImages,
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
        try { FileLogger.i(TAG, "merge: continue backward compare from new start=${fmt(prev.startTime)}") } catch (_: Exception) {}
        SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
        tryCompareAndMergeBackward(
            ctx,
            cur.copy(startTime = prev.startTime),
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

    private data class TextFirstMergedResult(
        val outputText: String,
        val structuredJson: String,
        val categoriesJson: String?
    )

    private fun parseStructuredJsonObject(structuredJson: String?): JSONObject? {
        val sj = structuredJson?.trim()
        if (sj.isNullOrEmpty() || sj.equals("null", ignoreCase = true)) return null
        return try { JSONObject(sj) } catch (_: Exception) { null }
    }

    private fun readStringList(obj: JSONObject?, key: String): List<String> {
        val arr = obj?.optJSONArray(key) ?: return emptyList()
        val out = ArrayList<String>(arr.length())
        for (i in 0 until arr.length()) {
            val v = arr.optString(i, "").trim()
            if (v.isNotEmpty() && !v.equals("null", ignoreCase = true)) out.add(v)
        }
        return out
    }

    private fun mergeUniqueStrings(a: List<String>, b: List<String>): List<String> {
        val seen = LinkedHashSet<String>()
        for (s in a) {
            val v = s.trim()
            if (v.isNotEmpty()) seen.add(v)
        }
        for (s in b) {
            val v = s.trim()
            if (v.isNotEmpty()) seen.add(v)
        }
        return ArrayList(seen)
    }

    private fun concatJsonArrays(a: JSONArray?, b: JSONArray?): JSONArray {
        val out = JSONArray()
        if (a != null) {
            for (i in 0 until a.length()) out.put(a.opt(i))
        }
        if (b != null) {
            for (i in 0 until b.length()) out.put(b.opt(i))
        }
        return out
    }

    private fun pickNonEmpty(vararg candidates: String?): String {
        for (c in candidates) {
            val t = c?.trim()
            if (!t.isNullOrEmpty() && !t.equals("null", ignoreCase = true)) return t
        }
        return ""
    }

    private fun extractOverallSummaryFromStructuredOrText(obj: JSONObject?, fallbackText: String?): String {
        val fromStructured = obj?.optString("overall_summary", "")?.trim()
        if (!fromStructured.isNullOrEmpty() && !fromStructured.equals("null", ignoreCase = true)) return fromStructured
        return pickNonEmpty(fallbackText)
    }

    private fun splitMergedEventSummaryParts(summary: String): List<String> {
        val t = summary.trim()
        if (t.isEmpty() || t.equals("null", ignoreCase = true)) return emptyList()
        val normalized = summary.replace("\r\n", "\n").replace("\r", "\n")
        val parts = normalized.split(Regex("^\\s*---+\\s*$", RegexOption.MULTILINE))
        val out = ArrayList<String>(parts.size)
        for (p in parts) {
            val v = p.trim()
            if (v.isNotEmpty() && !v.equals("null", ignoreCase = true)) out.add(v)
        }
        return out
    }

    private fun extractOriginalSummaryPartsForMerge(outputText: String?, structuredJson: String?): List<String> {
        val obj = parseStructuredJsonObject(structuredJson)
        val overall = extractOverallSummaryFromStructuredOrText(obj, outputText)
        val parts = splitMergedEventSummaryParts(overall)
        if (parts.isEmpty()) return emptyList()
        // 若 summary 已包含 `---` 分隔，则第一段为“合并后的摘要”，后续为“原始事件摘要”
        return if (parts.size > 1) parts.drop(1) else parts
    }

    private fun attachOriginalSummariesToMergedResult(
        mergedOutputText: String,
        mergedStructuredJson: String?,
        prevOriginals: List<String>,
        curOriginals: List<String>
    ): Pair<String, String?> {
        val originals = ArrayList<String>(prevOriginals.size + curOriginals.size)
        for (s in prevOriginals) {
            val v = s.trim()
            if (v.isNotEmpty()) originals.add(v)
        }
        for (s in curOriginals) {
            val v = s.trim()
            if (v.isNotEmpty()) originals.add(v)
        }
        if (originals.isEmpty()) return Pair(mergedOutputText, mergedStructuredJson)

        val mergedObj = parseStructuredJsonObject(mergedStructuredJson)
        val mergedOverall = extractOverallSummaryFromStructuredOrText(mergedObj, mergedOutputText)
        val mergedParts = splitMergedEventSummaryParts(mergedOverall)
        if (mergedParts.size > 1) {
            // 已包含原始事件，避免重复追加
            return Pair(mergedOutputText, mergedStructuredJson)
        }

        val main = (mergedParts.firstOrNull() ?: mergedOverall).trim()
        val sb = StringBuilder()
        if (main.isNotEmpty()) sb.append(main) else sb.append(mergedOverall.trim())
        for (o in originals) {
            sb.append("\n\n---\n\n").append(o)
        }
        val combinedOverall = sb.toString()

        var outStructured: String? = mergedStructuredJson
        var outText = mergedOutputText
        if (mergedObj != null) {
            try {
                mergedObj.put("overall_summary", combinedOverall)
                outStructured = mergedObj.toString()
            } catch (_: Exception) {
            }
        } else {
            // structured_json 缺失时：退化为在 output_text 里追加分隔内容，保证前端仍能拆分展示
            val sb2 = StringBuilder()
            val head = mergedOutputText.trim()
            if (head.isNotEmpty() && !head.equals("null", ignoreCase = true)) {
                sb2.append(head)
            } else if (main.isNotEmpty()) {
                sb2.append(main)
            }
            for (o in originals) {
                sb2.append("\n\n---\n\n").append(o)
            }
            outText = sb2.toString()
        }
        return Pair(outText, outStructured)
    }

    private fun buildTextFirstMergedResult(
        prevOutputText: String,
        prevStructuredJson: String?,
        curOutputText: String,
        curStructuredJson: String?
    ): TextFirstMergedResult {
        val prevObj = parseStructuredJsonObject(prevStructuredJson)
        val curObj = parseStructuredJsonObject(curStructuredJson)

        val apps = mergeUniqueStrings(readStringList(prevObj, "apps"), readStringList(curObj, "apps"))
        val categories = mergeUniqueStrings(readStringList(prevObj, "categories"), readStringList(curObj, "categories"))

        val timeline = concatJsonArrays(prevObj?.optJSONArray("timeline"), curObj?.optJSONArray("timeline"))
        val keyActions = concatJsonArrays(prevObj?.optJSONArray("key_actions"), curObj?.optJSONArray("key_actions"))
        val contentGroups = concatJsonArrays(prevObj?.optJSONArray("content_groups"), curObj?.optJSONArray("content_groups"))

        val prevOverall = extractOverallSummaryFromStructuredOrText(prevObj, prevOutputText)
        val curOverall = extractOverallSummaryFromStructuredOrText(curObj, curOutputText)
        val mergedOverall = when {
            prevOverall.isNotEmpty() && curOverall.isNotEmpty() -> prevOverall + "\n\n---\n\n" + curOverall
            prevOverall.isNotEmpty() -> prevOverall
            else -> curOverall
        }

        val appsArr = JSONArray()
        for (v in apps) appsArr.put(v)
        val catArr = JSONArray()
        for (v in categories) catArr.put(v)

        val merged = JSONObject()
        merged.put("apps", appsArr)
        merged.put("categories", catArr)
        merged.put("timeline", timeline)
        merged.put("key_actions", keyActions)
        merged.put("content_groups", contentGroups)
        merged.put("overall_summary", mergedOverall)

        val categoriesJson = if (categories.isNotEmpty()) catArr.toString() else null
        val outputText = pickNonEmpty(mergedOverall, curOverall, prevOverall)
        return TextFirstMergedResult(
            outputText = outputText,
            structuredJson = merged.toString(),
            categoriesJson = categoriesJson
        )
    }

    private fun truncateForLog(text: String, maxLen: Int = 3000): String {
        return if (text.length <= maxLen) text else (text.substring(0, maxLen) + "…<truncated>")
    }

    private fun pickCompareImages(
        a: List<SegmentDatabaseHelper.Sample>,
        b: List<SegmentDatabaseHelper.Sample>,
        cap: Int
    ): Pair<List<SegmentDatabaseHelper.Sample>, List<SegmentDatabaseHelper.Sample>> {
        val maxCap = cap.coerceAtLeast(1)
        val total = a.size + b.size
        if (total <= maxCap) return Pair(a, b)
        val half = maxCap / 2
        return Pair(evenPick(a, half), evenPick(b, maxCap - half))
    }

    private fun evenPick(list: List<SegmentDatabaseHelper.Sample>, count: Int): List<SegmentDatabaseHelper.Sample> {
        if (list.isEmpty() || count <= 0) return emptyList()
        if (list.size <= count) return list
        val step = list.size.toDouble() / count
        val out = ArrayList<SegmentDatabaseHelper.Sample>(count)
        var idx = 0.0
        while (out.size < count) {
            out.add(list[idx.toInt().coerceIn(0, list.size - 1)])
            idx += step
        }
        return out
    }

    /** 为任意 segment 按"每槽位最近一图 + 最后一槽尝试 end 之后第一张"规则重建样本列表 */
    private fun buildSamplesForSegment(ctx: Context, seg: SegmentDatabaseHelper.Segment): List<SegmentDatabaseHelper.Sample> {
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

    private fun mergeSamples(
        a: List<SegmentDatabaseHelper.Sample>,
        b: List<SegmentDatabaseHelper.Sample>
    ): List<SegmentDatabaseHelper.Sample> {
        val all = (a + b).sortedBy { it.captureTime }
        val seen = HashSet<String>()
        val res = ArrayList<SegmentDatabaseHelper.Sample>(all.size)
        var pos = 0
        for (s in all) {
            if (seen.add(s.filePath)) {
                res.add(s.copy(positionIndex = pos++))
            }
        }
        return res
    }

    private data class ImageDescEntry(
        val from: String,
        val to: String,
        val description: String
    )

    private fun extractImageDescriptions(structuredJson: String?): List<ImageDescEntry> {
        val sj = structuredJson?.trim()
        if (sj.isNullOrEmpty() || sj.equals("null", ignoreCase = true)) return emptyList()
        return try {
            val root = JSONObject(sj)
            val arr = root.optJSONArray("image_descriptions") ?: return emptyList()
            val out = ArrayList<ImageDescEntry>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val from = obj.optString("from_file", obj.optString("from", obj.optString("start", ""))).trim()
                val to = obj.optString("to_file", obj.optString("to", obj.optString("end", ""))).trim()
                val desc = obj.optString("description", obj.optString("desc", "")).trim()
                if (desc.isEmpty()) continue
                val a = if (from.isNotEmpty()) from else to
                val b = if (to.isNotEmpty()) to else from
                if (a.isEmpty() || b.isEmpty()) continue
                out.add(ImageDescEntry(from = a, to = b, description = desc))
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }

    private data class MergeAiInputPlan(
        val aiSamples: List<SegmentDatabaseHelper.Sample>,
        val textOnlyDescriptions: List<ImageDescEntry>
    )

    private fun buildDescByFileFromStructuredJson(
        structuredJson: String?,
        samples: List<SegmentDatabaseHelper.Sample>
    ): Map<String, String> {
        if (samples.isEmpty()) return emptyMap()
        val list = extractImageDescriptions(structuredJson)
        if (list.isEmpty()) return emptyMap()

        val ordered = samples.sortedBy { it.captureTime }
        val files = ArrayList<String>(ordered.size)
        val indexByFile = HashMap<String, Int>(ordered.size * 2)
        for ((i, s) in ordered.withIndex()) {
            val name = try { File(s.filePath).name } catch (_: Exception) { "" }
            if (name.isEmpty()) continue
            files.add(name)
            indexByFile.putIfAbsent(name, i)
        }
        if (files.isEmpty()) return emptyMap()

        val descByFile = HashMap<String, String>(files.size * 2)
        for (e in list) {
            val ia = indexByFile[e.from] ?: continue
            val ib = indexByFile[e.to] ?: continue
            var start = ia
            var end = ib
            if (start > end) {
                val tmp = start
                start = end
                end = tmp
            }
            for (k in start..end) {
                if (k < 0 || k >= files.size) continue
                val f = files[k]
                if (!descByFile.containsKey(f)) {
                    descByFile[f] = e.description
                }
            }
        }
        return descByFile
    }

    private fun buildTextOnlyDescriptionRanges(
        orderedFiles: List<String>,
        descByFile: Map<String, String>,
        excludedFiles: Set<String>
    ): List<ImageDescEntry> {
        if (orderedFiles.isEmpty() || descByFile.isEmpty()) return emptyList()
        val out = ArrayList<ImageDescEntry>()
        var rangeStartFile: String? = null
        var rangeEndFile: String? = null
        var currentDesc: String? = null

        fun flush() {
            val a = rangeStartFile
            val b = rangeEndFile
            val d = currentDesc
            if (!a.isNullOrBlank() && !b.isNullOrBlank() && !d.isNullOrBlank()) {
                out.add(ImageDescEntry(from = a, to = b, description = d))
            }
            rangeStartFile = null
            rangeEndFile = null
            currentDesc = null
        }

        for (f in orderedFiles) {
            if (excludedFiles.contains(f)) {
                flush()
                continue
            }
            val d = (descByFile[f] ?: "").trim()
            if (d.isEmpty()) {
                flush()
                continue
            }
            if (currentDesc == null) {
                rangeStartFile = f
                rangeEndFile = f
                currentDesc = d
                continue
            }
            if (d == currentDesc) {
                rangeEndFile = f
            } else {
                flush()
                rangeStartFile = f
                rangeEndFile = f
                currentDesc = d
            }
        }
        flush()

        return out
    }

    private fun planMergeAiInput(
        allSamples: List<SegmentDatabaseHelper.Sample>,
        prevStructuredJson: String?,
        prevSamples: List<SegmentDatabaseHelper.Sample>,
        curStructuredJson: String?,
        curSamples: List<SegmentDatabaseHelper.Sample>,
        maxAiImages: Int
    ): MergeAiInputPlan {
        val cap = maxAiImages.coerceAtLeast(1)
        if (allSamples.isEmpty()) return MergeAiInputPlan(aiSamples = emptyList(), textOnlyDescriptions = emptyList())

        val prevDesc = buildDescByFileFromStructuredJson(prevStructuredJson, prevSamples)
        val curDesc = buildDescByFileFromStructuredJson(curStructuredJson, curSamples)
        val descByFile = HashMap<String, String>(prevDesc.size + curDesc.size + 8)
        descByFile.putAll(prevDesc)
        descByFile.putAll(curDesc)

        val ordered = allSamples.sortedBy { it.captureTime }
        val withDesc = ArrayList<SegmentDatabaseHelper.Sample>(ordered.size)
        val withoutDesc = ArrayList<SegmentDatabaseHelper.Sample>(ordered.size)
        for (s in ordered) {
            val name = try { File(s.filePath).name } catch (_: Exception) { "" }
            val d = (descByFile[name] ?: "").trim()
            if (d.isEmpty()) withoutDesc.add(s) else withDesc.add(s)
        }

        val chosenUndescribed =
            if (withoutDesc.size > cap) evenPick(withoutDesc, cap) else withoutDesc
        val remaining = cap - chosenUndescribed.size
        val chosenDescribed = when {
            remaining <= 0 -> emptyList()
            withDesc.size > remaining -> evenPick(withDesc, remaining)
            else -> withDesc
        }

        val aiSamples = (chosenUndescribed + chosenDescribed)
            .sortedBy { it.captureTime }
            .mapIndexed { idx, s -> s.copy(positionIndex = idx) }

        val excludedFiles = HashSet<String>(aiSamples.size * 2)
        for (s in aiSamples) {
            val name = try { File(s.filePath).name } catch (_: Exception) { "" }
            if (name.isNotEmpty()) excludedFiles.add(name)
        }
        val orderedFiles = ordered.mapNotNull { s ->
            val name = try { File(s.filePath).name } catch (_: Exception) { "" }
            name.takeIf { it.isNotEmpty() }
        }
        val textOnlyRanges = buildTextOnlyDescriptionRanges(
            orderedFiles = orderedFiles,
            descByFile = descByFile,
            excludedFiles = excludedFiles
        )

        return MergeAiInputPlan(aiSamples = aiSamples, textOnlyDescriptions = textOnlyRanges)
    }

    private data class ImageTagEntry(
        val file: String,
        val refTime: String?,
        val app: String?,
        val tags: List<String>
    )

    private fun extractImageTags(structuredJson: String?): Map<String, ImageTagEntry> {
        val sj = structuredJson?.trim()
        if (sj.isNullOrEmpty() || sj.equals("null", ignoreCase = true)) return emptyMap()
        return try {
            val root = JSONObject(sj)
            val arr = root.optJSONArray("image_tags") ?: return emptyMap()
            val out = HashMap<String, ImageTagEntry>(arr.length() * 2)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val file = obj.optString("file", "").trim()
                if (file.isEmpty()) continue
                val app = obj.optString("app", "").trim().ifEmpty { null }
                val ref = obj.optString("ref_time", obj.optString("time", "")).trim().ifEmpty { null }
                val raw = obj.opt("tags")
                val tags = ArrayList<String>()
                when (raw) {
                    is JSONArray -> {
                        for (j in 0 until raw.length()) {
                            val t = raw.optString(j, "").trim()
                            if (t.isNotEmpty()) tags.add(t)
                        }
                    }
                    is String -> {
                        raw.split(Regex("[，,;；\\s]+"))
                            .map { it.trim() }
                            .filter { it.isNotEmpty() }
                            .forEach { tags.add(it) }
                    }
                }
                val cleaned = tags.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
                if (cleaned.isEmpty()) continue
                out[file] = ImageTagEntry(file = file, refTime = ref, app = app, tags = cleaned)
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun mergeImageDescriptionsIntoStructuredJson(
        mergedStructuredJson: String?,
        mergedSamplesForUi: List<SegmentDatabaseHelper.Sample>,
        mergedAiSamples: List<SegmentDatabaseHelper.Sample>,
        prevStructuredJson: String?,
        prevSamples: List<SegmentDatabaseHelper.Sample>,
        curStructuredJson: String?,
        curSamples: List<SegmentDatabaseHelper.Sample>
    ): String? {
        val sj = mergedStructuredJson?.trim()
        if (mergedSamplesForUi.isEmpty()) return mergedStructuredJson

        val root = when {
            sj.isNullOrEmpty() || sj.equals("null", ignoreCase = true) -> JSONObject()
            else -> try { JSONObject(sj) } catch (_: Exception) { return mergedStructuredJson }
        }

        val ordered = mergedSamplesForUi.sortedBy { it.captureTime }
        val files = ArrayList<String>(ordered.size)
        val indexByFile = HashMap<String, Int>(ordered.size * 2)
        val sampleByFile = HashMap<String, SegmentDatabaseHelper.Sample>(ordered.size * 2)
        for ((i, s) in ordered.withIndex()) {
            val name = try { File(s.filePath).name } catch (_: Exception) { "" }
            if (name.isEmpty()) continue
            files.add(name)
            indexByFile.putIfAbsent(name, i)
            sampleByFile.putIfAbsent(name, s)
        }
        if (files.isEmpty()) return mergedStructuredJson

        fun buildFileSet(samples: List<SegmentDatabaseHelper.Sample>): Set<String> {
            val set = HashSet<String>(samples.size * 2)
            for (s in samples) {
                val name = try { File(s.filePath).name } catch (_: Exception) { "" }
                if (name.isNotEmpty()) set.add(name)
            }
            return set
        }

        val descByFile = HashMap<String, String>(files.size * 2)

        fun applyDescriptions(structuredJson: String?, sourceFileSet: Set<String>, overwrite: Boolean) {
            val list = extractImageDescriptions(structuredJson)
            if (list.isEmpty()) return
            for (e in list) {
                val a = e.from
                val b = e.to
                val desc = e.description
                val ia = indexByFile[a]
                val ib = indexByFile[b]
                if (ia == null || ib == null) continue

                var start = ia
                var end = ib
                if (start > end) {
                    val tmp = start
                    start = end
                    end = tmp
                }

                for (k in start..end) {
                    if (k < 0 || k >= files.size) continue
                    val f = files[k]
                    if (!sourceFileSet.contains(f)) continue
                    if (!overwrite && descByFile.containsKey(f)) continue
                    descByFile[f] = desc
                }
            }
        }

        // 合并提示词生成的描述优先级最低：仅用于填补缺失，避免覆盖原事件更细的描述
        applyDescriptions(mergedStructuredJson, buildFileSet(mergedAiSamples), overwrite = false)
        applyDescriptions(prevStructuredJson, buildFileSet(prevSamples), overwrite = true)
        applyDescriptions(curStructuredJson, buildFileSet(curSamples), overwrite = true)

        // 合并 image_tags：用于缩略图 NSFW 遮罩与详情展示，避免合并后 tags 缺失
        val tagByFile = HashMap<String, ImageTagEntry>(files.size * 2)

        fun applyTags(structuredJson: String?, sourceFileSet: Set<String>, overwrite: Boolean) {
            val map = extractImageTags(structuredJson)
            if (map.isEmpty()) return
            for ((file, entry) in map) {
                if (!sourceFileSet.contains(file)) continue
                if (!overwrite && tagByFile.containsKey(file)) continue
                tagByFile[file] = entry
            }
        }

        applyTags(mergedStructuredJson, buildFileSet(mergedAiSamples), overwrite = false)
        applyTags(prevStructuredJson, buildFileSet(prevSamples), overwrite = true)
        applyTags(curStructuredJson, buildFileSet(curSamples), overwrite = true)

        val tagArr = JSONArray()
        for (f in files) {
            val entry = tagByFile[f] ?: continue
            val sample = sampleByFile[f]
            val tags = entry.tags
            if (tags.isEmpty()) continue
            val obj = JSONObject()
            obj.put("file", f)
            val app = (entry.app?.trim()?.takeIf { it.isNotEmpty() }
                ?: sample?.appName?.trim()?.takeIf { it.isNotEmpty() }
                ?: sample?.appPackageName?.trim()?.takeIf { it.isNotEmpty() }
                ?: "")
            if (app.isNotEmpty()) obj.put("app", app)
            val refTime = (entry.refTime?.trim()?.takeIf { it.isNotEmpty() }
                ?: (sample?.captureTime?.let { fmt(it) } ?: ""))
            if (refTime.isNotEmpty()) obj.put("ref_time", refTime)
            val ja = JSONArray()
            for (t in tags) ja.put(t)
            obj.put("tags", ja)
            tagArr.put(obj)
        }
        if (tagArr.length() > 0) {
            root.put("image_tags", tagArr)
        }

        // 压缩为不重叠的连续 range，确保每个文件最多落入一个描述范围
        val outArr = JSONArray()
        var rangeStartFile: String? = null
        var rangeEndFile: String? = null
        var currentDesc: String? = null

        fun flush() {
            val a = rangeStartFile
            val b = rangeEndFile
            val d = currentDesc
            if (!a.isNullOrBlank() && !b.isNullOrBlank() && !d.isNullOrBlank()) {
                val obj = JSONObject()
                obj.put("from_file", a)
                obj.put("to_file", b)
                obj.put("description", d)
                outArr.put(obj)
            }
            rangeStartFile = null
            rangeEndFile = null
            currentDesc = null
        }

        for (f in files) {
            val d = (descByFile[f] ?: "").trim()
            if (d.isEmpty()) {
                flush()
                continue
            }
            if (currentDesc == null) {
                rangeStartFile = f
                rangeEndFile = f
                currentDesc = d
                continue
            }
            if (d == currentDesc) {
                rangeEndFile = f
            } else {
                flush()
                rangeStartFile = f
                rangeEndFile = f
                currentDesc = d
            }
        }
        flush()

        if (outArr.length() > 0) {
            root.put("image_descriptions", outArr)
        }
        return root.toString()
    }

    private fun extractOverallSummary(text: String): String {
        val start = text.indexOf("overall_summary")
        if (start < 0) return text.take(200)
        val brace = text.indexOf('{', start)
        val endBrace = text.lastIndexOf('}')
        if (brace >= 0 && endBrace > brace) {
            val json = text.substring(brace, endBrace + 1)
            return try {
                val o = org.json.JSONObject(json)
                o.optString("overall_summary", text.take(200))
            } catch (_: Exception) { text.take(200) }
        }
        return text.take(200)
    }

    private fun buildMergePrompt(
        ctx: Context,
        a: SegmentDatabaseHelper.Segment,
        b: SegmentDatabaseHelper.Segment,
        samples: List<SegmentDatabaseHelper.Sample>,
        textOnlyDescriptions: List<ImageDescEntry> = emptyList(),
        totalImages: Int? = null,
        maxAttachedImages: Int? = null,
        forced: Boolean = false
    ): String {
        val byApp = LinkedHashMap<String, MutableList<SegmentDatabaseHelper.Sample>>()
        for (s in samples) byApp.getOrPut(s.appPackageName) { ArrayList() }.add(s)

        // 依据应用语言注入"语言强制策略"并选择合并提示词（支持 _zh/_en 与旧键回退）
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

        val extraHeader = try { AISettingsNative.readSettingValue(ctx, if (isZhLang) "prompt_merge_extra_zh" else "prompt_merge_extra_en") } catch (_: Exception) { null }
        val legacyHeaderLang = try { AISettingsNative.readSettingValue(ctx, if (isZhLang) "prompt_merge_zh" else "prompt_merge_en") } catch (_: Exception) { null }
        val legacyHeader = try { AISettingsNative.readSettingValue(ctx, "prompt_merge") } catch (_: Exception) { null }

        val defaultHeaderZh =
            "请基于以下图片产出合并后的总结；必须遵循以下规则（中文输出，结构化JSON，行为导向，禁止逐图/禁止OCR）：\n" +
            "- 禁止使用OCR文本，直接理解图片内容；\n" +
            "- 不要对每张图片逐条描述；请产出用户在该时间段的'行为总结'，如 浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等，按应用或主题整合；\n" +
            "- 对包含视频标题、作者、品牌等独特信息，按屏幕原样保留；\n" +
            "- 对同一文章/视频/页面的连续图片，归为同一 content_group，做整体总结；\n" +
            "- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现\\\"## 概览\\\"或\\\"## 总结\\\"等）；随后再使用 Markdown 小节呈现后续内容；\n" +
            "- Markdown 要求：所有\"用于展示的文本字段\"须使用 Markdown（overall_summary 与 content_groups[].summary），用小标题与项目符号清晰呈现；禁止输出 Markdown 代码块标记（如 ```），仅纯 Markdown 文本；\n" +
            "- overall_summary 必须按以下固定顺序包含且只能包含这三个二级标题：\"## 关键操作\"、\"## 主要活动\"、\"## 重点内容\"。每个小节必须使用 \"- \" 输出至少 3 条要点；如信息不足，仍必须保留该小节并至少提供 1 条有意义的占位要点；不得省略、改名或调整顺序。\n" +
            "- 在\"## 关键操作\"中，将相邻/连续同类行为合并为区间，格式\"HH:mm:ss-HH:mm:ss：行为描述\"（例如\"08:16:41-08:27:21：浏览视频评论\"）；仅在行为中断或切换时新起一条；控制 3-8 条精要；\n" +
            "- 为尽可能保留信息，可在 Markdown 中使用无序/有序列表、加粗/斜体与内联代码高亮（但不要使用代码块）；\n" +
            "以 JSON 输出以下字段（与普通事件保持一致，不要省略字段名）：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary；\n" +
            "字段约定：\n" +
            "key_actions[]: [{\"type\":\"pay|login|register|permission_grant|oauth_authorize|purchase|bind_account|unbind_account|captcha|biometric|other\",\"app\":\"应用名\",\"ref_image\":\"文件名\",\"ref_time\":\"HH:mm:ss\",\"detail\":\"简要说明（避免敏感信息）\",\"confidence\":0.0}],\n" +
            "content_groups[]: [{\"group_type\":\"article|video|page|playlist|feed\",\"title\":\"可为空\",\"app\":\"应用名\",\"start_time\":\"HH:mm:ss\",\"end_time\":\"HH:mm:ss\",\"image_count\":1,\"representative_images\":[\"文件名1\",\"文件名2\"],\"summary\":\"本组内容的Markdown要点\"}],\n" +
            "timeline[]: [{\"time\":\"HH:mm:ss\",\"app\":\"应用名\",\"action\":\"浏览|观看|聊天|购物|搜索|编辑|游戏|设置|下载|分享|其他\",\"summary\":\"一句话行为（可用简短Markdown强调）\"}],\n" +
            "overall_summary: \"开头为无标题的一段总结，随后使用Markdown小节与要点，保留多事件合并后的关键信息\"；\n" +
            "仅输出一个 JSON 对象，不要附加解释或 JSON 外的 Markdown；所有展示性内容（含后续小节）请写入 overall_summary 字段的 Markdown"

        val defaultHeaderEn =
            "Please produce a merged summary for the following images. MUST follow (English output, structured JSON, behavior-focused, no per-image narration / no OCR):\n" +
            "- Do NOT use OCR; understand images directly.\n" +
            "- Do not describe each image; output a 'behavior summary' over the period (browse/watch/chat/shop/work/settings/download/share/game, etc.), grouped by app/topic.\n" +
            "- Preserve unique on-screen info (video titles/authors/brands) as seen.\n" +
            "- Merge consecutive images from the same article/video/page into one content_group and summarize holistically.\n" +
            "- Start with one plain paragraph (no headings) summarizing the period; then present details using Markdown sections.\n" +
            "- Markdown requirements: all display texts use Markdown (overall_summary and content_groups[].summary); headings and bullet points for clarity; NO code fences (```), only pure Markdown.\n" +
            "- overall_summary MUST include exactly these three second-level sections in this fixed order:\n" +
            "  \\\"## Key Actions\\\"\\n  \\\"## Main Activities\\\"\\n  \\\"## Key Content\\\"\\n" +
            "  Each section MUST contain at least 3 bullet points using \\\"- \\\". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet. Do not omit or rename sections.\n" +
            "- In \"## Key Actions\", merge adjacent same-type actions into ranges \"HH:mm:ss-HH:mm:ss: description\"; only new item when action breaks; keep 3–8 concise lines.\n" +
            "- content_groups[].summary uses 1–3 Markdown bullets for group topic/representative titles/intent.\n" +
            "Output JSON fields (same as normal event): apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary.\n" +
            "Only output ONE JSON object; no explanations or Markdown outside JSON; all display content belongs to overall_summary (Markdown)."

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
            R.string.merge_prompt_default_zh,
            R.string.merge_prompt_default_en,
            R.string.merge_prompt_default_ja,
            R.string.merge_prompt_default_ko
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

        val sb = StringBuilder()
        val titleLabel = getStringByLang(ctx, effectiveLang, R.string.title_merged_event_summary_zh, R.string.title_merged_event_summary_en, R.string.title_merged_event_summary_ja, R.string.title_merged_event_summary_ko)
        val timeRangeLabel = getStringByLang(ctx, effectiveLang, R.string.label_time_range_zh, R.string.label_time_range_en, R.string.label_time_range_ja, R.string.label_time_range_ko)
        val appLabel = getStringByLang(ctx, effectiveLang, R.string.label_app_zh, R.string.label_app_en, R.string.label_app_ja, R.string.label_app_ko)
        val shotLabel = getStringByLang(ctx, effectiveLang, R.string.label_screenshot_at_zh, R.string.label_screenshot_at_en, R.string.label_screenshot_at_ja, R.string.label_screenshot_at_ko)
        val fileLabel = getStringByLang(ctx, effectiveLang, R.string.label_file_zh, R.string.label_file_en, R.string.label_file_ja, R.string.label_file_ko)

        sb.append(titleLabel).append('\n')
            .append(timeRangeLabel).append(fmt(a.startTime)).append(" - ").append(fmt(b.endTime)).append('\n')
            .append(header).append('\n')
        run {
            val provided = samples.size
            val total = totalImages ?: provided
            val cap = (maxAttachedImages ?: PROVIDER_IMAGE_HARD_LIMIT).coerceAtLeast(1)
            val note = when (effectiveLang) {
                "zh" ->
                    "注意：受模型图片数量限制，本次仅附带 $provided 张图片（上限 $cap）。本事件共涉及 $total 张图片；未附带的图片若已有历史描述，将在末尾以文字形式提供，供合并总结时参考。对“仅文字描述”的部分，请不要凭空补全画面细节。"
                else ->
                    "Note: due to the model image limit, this request attaches only $provided images (max $cap). This merged event contains $total images; for the rest, existing descriptions (if any) are provided below as text-only context. For text-only descriptions, do not invent extra visual details."
            }
            sb.append(note).append('\n').append('\n')
            if (forced) {
                val forcedNote = when (effectiveLang) {
                    "zh" -> "用户已确认需要强制合并：请直接生成合并后的总结，不需要判断是否属于同一事件。"
                    else -> "User confirmed a forced merge: directly produce the merged summary; do not judge whether they are the same event."
                }
                sb.append(forcedNote).append('\n').append('\n')
            }
        }
        for ((pkg, list) in byApp) {
            list.sortBy { it.captureTime }
            val name = list.firstOrNull()?.appName ?: pkg
            sb.append(appLabel).append(name).append(" (").append(pkg).append(")\n")
            for (s in list) {
                sb.append(shotLabel).append(fmt(s.captureTime)).append(fileLabel).append(File(s.filePath).name).append('\n')
            }
        }
        if (textOnlyDescriptions.isNotEmpty()) {
            val label = when (effectiveLang) {
                "zh" -> "以下图片不发送原图，仅提供已有描述（请将描述视为事实，不要自行扩写）："
                else -> "The following images are NOT attached; only existing descriptions are provided (treat as facts; do not expand/hallucinate):"
            }
            sb.append('\n').append(label).append('\n')
            for (e in textOnlyDescriptions) {
                sb.append("- ").append(e.from).append(" - ").append(e.to).append(": ").append(e.description).append('\n')
            }
        }
        return sb.toString()
    }

    /**
     * 扫描并补救：针对“近 N 天”的 completed 段落，凡无内容（文本与结构化皆空）均尝试补救；
     * 如不存在样本，则按规则即时重建样本后再补救。
     */
    private fun resumeMissingSummaries(ctx: Context, limit: Int = 2) {
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
        var retried = 0
        for (id in ids) {
            try {
                // 非强制：已有结果则跳过
                if (!force && SegmentDatabaseHelper.hasResultForSegment(ctx, id)) continue
                val seg = SegmentDatabaseHelper.getSegmentById(ctx, id) ?: continue
                var samples = SegmentDatabaseHelper.getSamplesForSegment(ctx, id)
                if (samples.isEmpty()) {
                    samples = buildSamplesForSegment(ctx, seg)
                    if (samples.isNotEmpty()) {
                        try { SegmentDatabaseHelper.saveSamples(ctx, seg.id, samples) } catch (_: Exception) {}
                    }
                }
                if (samples.isEmpty()) continue
                try { FileLogger.i(TAG, "retrySegments: seg=${id} imgs=${samples.size} force=${force}") } catch (_: Exception) {}
                finishSegment(ctx, seg, samples, force)
                retried++
            } catch (_: Exception) {}
        }
        return retried
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

    private fun getStringByLang(
        ctx: Context,
        lang: String,
        zhId: Int,
        enId: Int,
        jaId: Int,
        koId: Int
    ): String {
        return when (lang) {
            "zh" -> ctx.getString(zhId)
            "ja" -> ctx.getString(jaId)
            "ko" -> ctx.getString(koId)
            else -> ctx.getString(enId)
        }
    }

    private fun guessMime(path: String): String {
        val lower = path.lowercase()
        return when {
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".png") -> "image/png"
            else -> "image/png"
        }
    }

    private fun isDamagedImageFile(filePath: String): Boolean {
        if (filePath.isBlank()) return true
        val f = try { File(filePath) } catch (_: Exception) { return true }
        val ok = try { f.exists() && f.length() > 0L } catch (_: Exception) { false }
        if (!ok) return true
        return try {
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(filePath, opts)
            opts.outWidth <= 0 || opts.outHeight <= 0
        } catch (_: Exception) { true }
    }

    private fun extractJsonBlocks(text: String): Pair<String?, String?> {
        // 尝试提取 JSON；若存在 categories 字段则单独返回其字符串表示
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start >= 0 && end > start) {
            val json = text.substring(start, end + 1)
            return try {
                val obj = JSONObject(json)
                val cats = obj.optJSONArray("categories")?.toString()
                Pair(json, cats)
            } catch (_: Exception) {
                Pair(json, null)
            }
        }
        return Pair(null, null)
    }

    private fun fmt(ts: Long): String {
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = ts }
        val h = cal.get(java.util.Calendar.HOUR_OF_DAY)
        val m = cal.get(java.util.Calendar.MINUTE)
        val s = cal.get(java.util.Calendar.SECOND)
        return String.format("%02d:%02d:%02d", h, m, s)
    }

    data class Quad<A,B,C,D>(val first: A, val second: B, val third: C, val fourth: D)

    private fun startOfToday(): Long {
        val cal = java.util.Calendar.getInstance()
        cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
        cal.set(java.util.Calendar.MINUTE, 0)
        cal.set(java.util.Calendar.SECOND, 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun endOfToday(): Long {
        val cal = java.util.Calendar.getInstance()
        cal.set(java.util.Calendar.HOUR_OF_DAY, 23)
        cal.set(java.util.Calendar.MINUTE, 59)
        cal.set(java.util.Calendar.SECOND, 59)
        cal.set(java.util.Calendar.MILLISECOND, 999)
        return cal.timeInMillis
    }
}
