package com.fqyw.screen_memo

import android.content.Context
import android.util.Base64
import android.util.Log
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
import kotlin.math.roundToInt

/**
 * 时间段总结管理器（原生）
 * - 入口：onScreenshotSaved(package, appName, filePathAbs, captureTime)
 * - 若不存在活动段落：以 当前图时间+durationSec 作为 endTime，startTime=endTime-durationSec
 *   注：根据需求1：需要“从当前图时间向后推1分钟，然后找大于该时间最近的一张图”，
 *       我们将此作为确定 startAnchor 的第一步，随后回溯 duration 构建段落范围。
 * - 在段落期间，按 sampleIntervalSec 从区间内寻找“最接近的截图（不限制±偏差，选最近）”，并缓存样本。
 * - 段落结束后，汇总去重应用+时间片，调用 Gemini 多模态生成结构化中文输出，持久化到 segment_results。
 */
object SegmentSummaryManager {

    private const val TAG = "SegmentSummaryManager"
    // 提供方硬上限（例如 OpenAI 报错 max allowed is 16），作为最终兜底
    private const val PROVIDER_IMAGE_HARD_LIMIT = 16

    // 读写设置（SharedPreferences）
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)

    private fun getSampleIntervalSec(ctx: Context): Int {
        val v = prefs(ctx).getInt("segment_sample_interval_sec", -1)
        if (v <= 0) return 20
        return v.coerceAtLeast(5)
    }

    private fun getSegmentDurationSec(ctx: Context): Int {
        val v = prefs(ctx).getInt("segment_duration_sec", -1)
        if (v <= 0) return 5 * 60
        return v.coerceAtLeast(60)
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

    // 并发窗口去重：按 “start|end” 标识正在创建中的段落，避免同时间段重复创建
    private val creatingWindows: MutableSet<String> = Collections.synchronizedSet(HashSet())
    // 并发完成去重：避免同一 segment 被重复 finish/AI 调用
    private val finishingSegments: MutableSet<Long> = Collections.synchronizedSet(HashSet())
    // 窗口级完成去重：同一 (start,end) 仅允许一次 finish 流程
    private val finishingWindows: MutableSet<String> = Collections.synchronizedSet(HashSet())

    // 全局AI请求速率限制：两次请求之间的最小间隔（毫秒）
    @Volatile private var nextAiAvailableMs: Long = 0L
    private val aiRateLock = Object()

    private fun getAiMinIntervalSec(ctx: Context): Int {
        // 可通过 SharedPreferences(键: ai_min_request_interval_sec) 配置；默认3秒，最低1秒
        return try {
            val v = prefs(ctx).getInt("ai_min_request_interval_sec", 3)
            if (v < 1) 1 else if (v > 60) 60 else v
        } catch (_: Exception) { 3 }
    }

    /**
     * 申请一次AI请求配额：若距离上次请求未超过最小间隔，则等待剩余时间。
     * 采用“令牌时钟”：所有调用串行化到全局最小间隔，避免瞬时洪峰。
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
            try { FileLogger.i(TAG, "AI rate limit: wait ${waitMs}ms (interval=${intervalMs}ms)") } catch (_: Exception) {}
            try { Thread.sleep(waitMs) } catch (_: Exception) {}
        }
        return waitMs
    }

    @Synchronized
    fun onScreenshotSaved(ctx: Context, appPackage: String, appName: String, filePathAbs: String, captureTime: Long) {
        try {
            try { FileLogger.i(TAG, "onScreenshotSaved: pkg=${appPackage}, file=${filePathAbs}, ts=${captureTime}") } catch (_: Exception) {}
            if (activeSegmentId <= 0) {
                // 先回填历史窗口到最新的可完成段落
                backfillToLatest(ctx)

                // 若仍无活动段落，则以当前截图时间作为起点创建“仅含有图片的窗口”
                val durationSec = getSegmentDurationSec(ctx)
                val startTime = captureTime
                val endTime = startTime + durationSec * 1000L
                // 进度下界：新窗口的 start 必须 > 已存在的最大 end
                val todayStart = startOfToday()
                val progressEnd = SegmentDatabaseHelper.getLastSegmentEndTimeInRange(ctx, todayStart, System.currentTimeMillis()) ?: 0L
                if (startTime <= progressEnd) {
                    try { FileLogger.i(TAG, "skip creating window before progress: start=${startTime}, progressEnd=${progressEnd}") } catch (_: Exception) {}
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
                                getSampleIntervalSec(ctx),
                                status = "collecting"
                            )
                            if (segId > 0) {
                                activeSegmentId = segId
                                created = true
                                try { FileLogger.i(TAG, "segment(created by current shot) id=${segId}, start=${startTime}, end=${endTime}") } catch (_: Exception) {}
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
            Log.w(TAG, "onScreenshotSaved error: ${e.message}")
            try { FileLogger.w(TAG, "onScreenshotSaved error: ${e.message}") } catch (_: Exception) {}
        }
    }

    // 周期性驱动：用于在无新截图时也能结束段落并触发AI
    fun tick(ctx: Context) {
        try {
            try { FileLogger.d(TAG, "tick: driving segment sampling/finish") } catch (_: Exception) {}
            // 先推进所有 collecting 段落
            tryProgressAllCollecting(ctx)
            // 后台清理可能的重复窗口，仅小批量，避免阻塞
            try {
                val removed = SegmentDatabaseHelper.cleanupDuplicateSegments(ctx, limitGroups = 20)
                if (removed > 0) { try { FileLogger.i(TAG, "tick: cleaned dup segments count=$removed") } catch (_: Exception) {} }
            } catch (_: Exception) {}
            // 后台补齐到当天最新可完整时段
            backfillToLatest(ctx)
            // 定时补救：扫描缺失结果的段落
            try { resumeMissingSummaries(ctx, limit = 2) } catch (_: Exception) {}
        } catch (_: Exception) {}
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
        val start = seg.startTime
        val end = seg.endTime
        val totalSec = seg.durationSec
        // 槽位数按向下取整，确保不超过 时长/间隔 上限（示例：60/20=3）
        val totalSlots = (totalSec / interval).coerceAtLeast(1)

        val shots = SegmentDatabaseHelper.listShotsBetween(ctx, start, end)
        try { FileLogger.d(TAG, "collect: range=${start}-${end}, shots=${shots.size}, interval=${interval}s slots=${totalSlots}") } catch (_: Exception) {}
        if (shots.isEmpty()) {
            val now = System.currentTimeMillis()
            if (now >= end) {
                // 到期且区间内无任何截图：标记完成，但不触发AI
                try { FileLogger.i(TAG, "complete(no-shots): seg=${seg.id} ${start}-${end}") } catch (_: Exception) {}
                SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                activeSegmentId = -1L
            }
            return
        }

        // 为每个时间槽选择“最近”的截图（不限制±，选择距离最小者），并按文件路径去重
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
                try { FileLogger.i(TAG, "complete(no-inwindow-sample): seg=${seg.id}") } catch (_: Exception) {}
                SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                activeSegmentId = -1L
            }
        }
    }

    private fun tryProgressAllCollecting(ctx: Context) {
        try {
            val list = SegmentDatabaseHelper.listCollectingSegments(ctx, limit = 50)
            for (seg in list) {
                // activeSegmentId 仅作为提示，不强依赖
                activeSegmentId = seg.id
                val interval = seg.sampleIntervalSec
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
                        try { FileLogger.i(TAG, "complete(no-inwindow-sample): seg=${seg.id}") } catch (_: Exception) {}
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
        try {
            val durationSec = getSegmentDurationSec(ctx)
            val intervalSec = getSampleIntervalSec(ctx)
            val todayStart = startOfToday()
            val now = System.currentTimeMillis()
            val shots = SegmentDatabaseHelper.listShotsBetween(ctx, todayStart, now)
            if (shots.isEmpty()) return

            // 只允许从“已存在的最大 end_time”之后开始回填，避免回到过去窗口
            val progressEnd = SegmentDatabaseHelper.getLastSegmentEndTimeInRange(ctx, todayStart, now) ?: todayStart

            // 仅以“有图片的时间点”为起点，窗口为 [shotTime, shotTime + duration]
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
                                tryCollectSamplesAndMaybeFinish(ctx)
                            }
                        } finally {
                            creatingWindows.remove(key)
                        }
                    }
                }

                // 跳到“下一个有图片且时间 >= windowEnd”的索引
                var j = i + 1
                while (j < shots.size && shots[j].captureTime < windowEnd) j++
                i = j
            }
        } catch (e: Exception) {
            try { FileLogger.w(TAG, "backfillToLatest error: ${e.message}") } catch (_: Exception) {}
        }
    }

    private fun finishSegment(ctx: Context, seg: SegmentDatabaseHelper.Segment, samples: List<SegmentDatabaseHelper.Sample>, force: Boolean = false) {
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
        Thread {
            try {
                try { FileLogger.i(TAG, "finish: begin segment=${seg.id}, samples=${samples.size}, force=${force}") } catch (_: Exception) {}
                // 兜底：无样本则不进行AI
                if (samples.isEmpty()) {
                    try { FileLogger.w(TAG, "finish: no samples, skip ai seg=${seg.id}") } catch (_: Exception) {}
                    SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                    return@Thread
                }
                // 非强制模式下：存在结果即跳过；强制模式则无视现有结果重新生成
                if (!force) {
                    // 若同窗口已有任一结果，直接标记完成并跳过AI调用
                    if (SegmentDatabaseHelper.hasAnyResultForWindow(ctx, seg.startTime, seg.endTime)) {
                        try { FileLogger.w(TAG, "finish: window already has result, skip seg=${seg.id}") } catch (_: Exception) {}
                        SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                        return@Thread
                    }
                    // 双重检查：该段落是否已写入结果（在极端并发下）
                    if (SegmentDatabaseHelper.hasResultForSegment(ctx, seg.id)) {
                        SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                        return@Thread
                    }
                }
                // 聚合应用与时间片，组织提示
                val byApp = LinkedHashMap<String, MutableList<SegmentDatabaseHelper.Sample>>()
                for (s in samples) {
                    byApp.getOrPut(s.appPackageName) { ArrayList() }.add(s)
                }

                // 依据应用语言注入“语言强制策略”并选择对应提示词（支持 _zh/_en 与旧键回退）
                val langOpt = try { ctx.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE).getString("flutter.locale_option", "system") } catch (_: Exception) { "system" }
                val sysLang = try { java.util.Locale.getDefault().language?.lowercase() } catch (_: Exception) { "en" } ?: "en"
                val isZhLang = (langOpt == "zh") || (langOpt != "en" && sysLang.startsWith("zh"))

                val customHeaderLang = try {
                    AISettingsNative.readSettingValue(ctx, if (isZhLang) "prompt_segment_zh" else "prompt_segment_en")
                } catch (_: Exception) { null }
                val customHeaderLegacy = try {
                    AISettingsNative.readSettingValue(ctx, "prompt_segment")
                } catch (_: Exception) { null }

                val defaultHeaderZh =
                    "请基于以下多张屏幕图片进行中文总结，并输出结构化结果；必须严格遵循：\n" +
                    "- 禁止使用OCR文本；直接理解图片内容；\n" +
                    "- 不要逐图描述；按应用/主题整合用户在该时间段的‘行为总结’（浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等）；\n" +
                    "- 对视频标题、作者、品牌等独特信息，按屏幕原样在输出中保留；\n" +
                    "- 对同一文章/视频/页面的连续图片，归为同一 content_group 做整体总结；\n" +
                    "- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现“## 概览”或“## 总结”等）；随后再使用 Markdown 小节呈现后续内容；\n" +
                    "- Markdown 要求：所有“用于展示的文本字段”须使用 Markdown（overall_summary 与 content_groups[].summary；timeline[].summary 可用简短 Markdown；key_actions[].detail 可用精简 Markdown）；禁止使用代码块围栏（例如 ```），仅输出纯 Markdown 文本；\n" +
                    "- 后续小节建议包含：\"## 关键操作\"（按时间的要点清单）、\"## 主要活动\"（按应用/主题的要点清单）、\"## 重点内容\"（可保留的标题/作者/品牌等）；\n" +
                    "- 在“## 关键操作”中，将相邻/连续同类行为合并为区间，格式“HH:mm:ss-HH:mm:ss：行为描述”（例如“08:16:41-08:27:21：浏览视频评论”）；仅在行为中断或切换时新起一条；控制 3-8 条精要；\n" +
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

                val languagePolicy = getByLang(ctx, R.string.ai_language_policy_zh, R.string.ai_language_policy_en, isZhLang)

                val header =
                    languagePolicy + "\n\n" + ((customHeaderLang ?: customHeaderLegacy) ?: getByLang(ctx, R.string.segment_prompt_default_zh, R.string.segment_prompt_default_en, isZhLang))

                // 构造描述（仅时间点与应用，不包含OCR文本）
                val sb = StringBuilder()
                val timeRangeLabel = getByLang(ctx, R.string.label_time_range_zh, R.string.label_time_range_en, isZhLang)
                val appLabel = getByLang(ctx, R.string.label_app_zh, R.string.label_app_en, isZhLang)
                val shotLabel = getByLang(ctx, R.string.label_screenshot_at_zh, R.string.label_screenshot_at_en, isZhLang)
                val fileLabel = getByLang(ctx, R.string.label_file_zh, R.string.label_file_en, isZhLang)

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
                try { FileLogger.i(TAG, "finish: calling AI with images=${samples.size} seg=${seg.id}") } catch (_: Exception) {}
                val result = callGeminiWithImages(ctx, seg, samples, prompt)
                try {
                    FileLogger.i(TAG, "finish: ai model=${result.first}, outputSize=${result.second.length}")
                    val preview = truncateForLog(result.second, 3000)
                    FileLogger.i(TAG, "AI响应预览: ${preview}")
                } catch (_: Exception) {}
                SegmentDatabaseHelper.saveResult(
                    ctx,
                    seg.id,
                    provider = "gemini",
                    model = result.first,
                    outputText = result.second,
                    structuredJson = result.third,
                    categories = result.fourth
                )
                // 生成后尝试与上一个已完成事件对比并合并
                try {
                    tryCompareAndMergeBackward(ctx, seg, samples, result.second, result.third)
                } catch (_: Exception) {}
            } catch (e: Exception) {
                Log.w(TAG, "finishSegment ai error: ${e.message}")
                try {
                    FileLogger.w(TAG, "finishSegment ai error: ${e.message}")
                    // 捕获更详细的异常类型与栈
                    FileLogger.w(TAG, "ai exception class=${e::class.java.name}")
                    FileLogger.w(TAG, "ai exception stack=\n" + (e.stackTraceToString()))
                } catch (_: Exception) {}
                // 将错误预览文本持久化，供前端错误样式展示
                try {
                    val cfg = AISettingsNative.readConfig(ctx)
                    val msg = e.message ?: "unknown error"
                    val idx = msg.indexOf('{')
                    val body = if (idx >= 0) msg.substring(idx) else msg
                    val previewLine = "AI response preview(OpenAI): " + body
                    SegmentDatabaseHelper.saveResult(
                        ctx,
                        seg.id,
                        provider = "gemini",
                        model = cfg.model,
                        outputText = previewLine,
                        structuredJson = null,
                        categories = null
                    )
                } catch (_: Exception) {}
            } finally {
                SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                activeSegmentId = -1L
                try { FileLogger.i(TAG, "finish: segment=${seg.id} completed") } catch (_: Exception) {}
                finishingSegments.remove(seg.id)
                finishingWindows.remove(windowKey)
            }
        }.start()
    }

    // 返回 (model, outputText, structuredJson, categories)
    private fun callGeminiWithImages(
        ctx: Context,
        seg: SegmentDatabaseHelper.Segment,
        samples: List<SegmentDatabaseHelper.Sample>,
        prompt: String,
        isMerge: Boolean = false
    ): Quad<String, String, String?, String?> {
        val cfg = AISettingsNative.readConfig(ctx)
        val apiKey = cfg.apiKey
        val client = OkHttpClient.Builder()
            .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(0, java.util.concurrent.TimeUnit.SECONDS) // 0 = no read timeout
            .writeTimeout(0, java.util.concurrent.TimeUnit.SECONDS) // 0 = no write timeout
            .retryOnConnectionFailure(true)
            .build()

        val model = cfg.model
        val base = if (cfg.baseUrl.endsWith('/')) cfg.baseUrl.dropLast(1) else cfg.baseUrl
        val isGoogle = base.contains("googleapis.com") || base.contains("generativelanguage")

        // 统一图片限额（单段：floor(duration/interval)，并受提供方硬上限保护）
        val capBySeg = (seg.durationSec / seg.sampleIntervalSec).coerceAtLeast(1)
        val effectiveCap = kotlin.math.min(capBySeg, PROVIDER_IMAGE_HARD_LIMIT)
        val samplesOrdered = samples.sortedBy { it.captureTime }
        val effSamples = if (samplesOrdered.size > effectiveCap) evenPick(samplesOrdered, effectiveCap) else samplesOrdered

        // 基于应用语言计算“最多三分之一图片可被文字描述”的动态规则（向下取整，允许0张）
        val langOptForRule = try { ctx.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE).getString("flutter.locale_option", "system") } catch (_: Exception) { "system" }
        val sysLangForRule = try { java.util.Locale.getDefault().language?.lowercase() } catch (_: Exception) { "en" } ?: "en"
        val isZhForRule = (langOptForRule == "zh") || (langOptForRule != "en" && sysLangForRule.startsWith("zh"))
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
- 仅使用 described_images[] 列出这些“被文字描述”的单张图片，数组长度<=上述上限；每项结构：{file:"文件名", ref_time:"HH:mm:ss", app:"应用名", summary:"(Markdown) 单图关键信息与选择理由"}。
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

        // 结构化呈现规则：开头一段纯文本总结，随后 Markdown 小节
        val dynamicStructureRule = if (isZhForRule) {
            "- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现“## 概览”或“## 总结”等）；随后再使用 Markdown 小节呈现后续内容。"
        } else {
            "- Start with one plain paragraph (no heading) summarizing the time window; then present details using Markdown subsections."
        }
        // 将规则同时注入到开头与结尾，增强模型注意力与遵循度
        val headRules = listOf(dynamicCapRule, dynamicStructureRule).filter { it.isNotEmpty() }.joinToString("\n")
        val promptWithRule = if (headRules.isNotEmpty()) "$headRules\n\n$prompt\n$headRules" else prompt

        // 速率限制：必要时等待
        val waited = acquireAiRateSlot(ctx)

        // 配置校验与请求前日志
        try {
            if (apiKey.isNullOrBlank()) {
                FileLogger.e(TAG, "AI config error: missing apiKey")
            }
            if (base.isBlank()) {
                FileLogger.e(TAG, "AI config error: missing baseUrl")
            }
            if (model.isBlank()) {
                FileLogger.e(TAG, "AI config warning: empty model, using server default if supported")
            }
            if (waited > 0L) {
                FileLogger.i(TAG, "AI waited=${waited}ms due to rate limit")
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
                "AI prepare: provider=${if (isGoogle) "google" else "openai-compat"}, model=${model}, base=${base}, seg=${seg.id}, merge=${isMerge}, textLen=${textLen}, textLenWithRule=${textLenWithRule}, images=${samples.size}, bytes=${totalImageBytes}, missing=${missingImages}, firstFiles=${firstNames.joinToString("|")}" 
            )
        } catch (_: Exception) {}
        try {
            android.util.Log.i(TAG, "AI prepare: provider=${if (isGoogle) "google" else "openai-compat"}, model=${model}, base=${base}, seg=${seg.id}, merge=${isMerge}, textLen=${textLen}, textLenWithRule=${textLenWithRule}, images=${samples.size}, bytes=${totalImageBytes}, missing=${missingImages}, firstFiles=${firstNames.joinToString("|")}")
        } catch (_: Exception) {}
        try {
            OutputFileLogger.info(ctx, TAG, "AI prepare: provider=${if (isGoogle) "google" else "openai-compat"}, model=${model}, base=${base}, seg=${seg.id}, merge=${isMerge}, textLen=${textLen}, textLenWithRule=${textLenWithRule}, images=${samples.size}, bytes=${totalImageBytes}, missing=${missingImages}, firstFiles=${firstNames.joinToString("|")}")
        } catch (_: Exception) {}

        // 额外打印提示词预览（不含图片/密钥）：Logcat 截断 + 文件完整
        try {
            val promptPreview = truncateForLog(promptWithRule, 800)
            android.util.Log.i(TAG, "AI prompt preview: ${promptPreview}")
        } catch (_: Exception) {}
        try {
            OutputFileLogger.info(ctx, TAG, "AI prompt full BEGIN >>>")
            OutputFileLogger.info(ctx, TAG, promptWithRule)
            OutputFileLogger.info(ctx, TAG, "AI prompt full END <<<")
        } catch (_: Exception) {}

        if (isGoogle) {
            // Gemini REST: POST {base}/v1beta/models/{model}:generateContent?key=API_KEY
            val url = "$base/v1beta/models/$model:generateContent?key=$apiKey"
            try { FileLogger.i(TAG, "AI request: url=$url, model=$model, images=${effSamples.size}") } catch (_: Exception) {}
            try { android.util.Log.i(TAG, "AI request: url=$url, model=$model, images=${effSamples.size}") } catch (_: Exception) {}
            try { OutputFileLogger.info(ctx, TAG, "AI request: url=$url, model=$model, images=${effSamples.size}") } catch (_: Exception) {}

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
            val req = Request.Builder().url(url).post(reqBody).build()
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
                        try { FileLogger.i(TAG, "AI response meta: code=${resp.code}, elapsedMs=${end - start}, attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { android.util.Log.i(TAG, "AI response meta: code=${resp.code}, elapsedMs=${end - start}, attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.info(ctx, TAG, "AI response meta: code=${resp.code}, elapsedMs=${end - start}, attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        if (resp.isSuccessful) {
                            respText = resp.body?.string() ?: ""
                            break
                        } else {
                            lastBody = resp.body?.string()
                            val shouldRetry = resp.code >= 500
                            try { FileLogger.w(TAG, "AI failed(code=${resp.code}) attempt=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { android.util.Log.w(TAG, "AI failed(code=${resp.code}) attempt=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { OutputFileLogger.error(ctx, TAG, "AI failed(code=${resp.code}) attempt=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            if (!shouldRetry) throw IllegalStateException("Request failed: ${resp.code} ${lastBody}")
                        }
                    } catch (e: java.net.SocketTimeoutException) {
                        try { FileLogger.w(TAG, "AI timeout attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { android.util.Log.w(TAG, "AI timeout attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI timeout attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        // 继续重试
                    } catch (e: Exception) {
                        // 其他IO异常：仅第一次尝试记录，仍然重试
                        try { FileLogger.w(TAG, "AI exception attempt=${attempt + 1}/${maxAttempts}: ${e.message}") } catch (_: Exception) {}
                        try { android.util.Log.w(TAG, "AI exception attempt=${attempt + 1}/${maxAttempts}: ${e.message}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI exception attempt=${attempt + 1}/${maxAttempts}: ${e.message}") } catch (_: Exception) {}
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
                FileLogger.d(TAG, "AI response size=${respText.length}")
                val preview = truncateForLog(respText, 2000)
                FileLogger.i(TAG, "AI response preview: ${preview}")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                android.util.Log.i(TAG, "AI response preview: ${preview}")
            } catch (_: Exception) {}
            // 完整响应落盘（分块写入）
            try {
                OutputFileLogger.info(ctx, TAG, "AI response full BEGIN >>>")
                val text = respText
                val chunk = 1800
                var i = 0
                while (i < text.length) {
                    val end = kotlin.math.min(i + chunk, text.length)
                    OutputFileLogger.info(ctx, TAG, text.substring(i, end))
                    i = end
                }
                OutputFileLogger.info(ctx, TAG, "AI response full END <<<")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                OutputFileLogger.info(ctx, TAG, "AI response preview: ${preview}")
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
                    if (low.contains("\"error\"") || low.contains("no candidates returned")) {
                        outputText = "AI response preview(Google): " + respText
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
                    OutputFileLogger.info(ctx, TAG, "AI structured_json BEGIN >>>")
                    val textSJ = pretty
                    val chunkSJ = 1800
                    var p = 0
                    while (p < textSJ.length) {
                        val end = kotlin.math.min(p + chunkSJ, textSJ.length)
                        OutputFileLogger.info(ctx, TAG, textSJ.substring(p, end))
                        p = end
                    }
                    OutputFileLogger.info(ctx, TAG, "AI structured_json END <<<")
                } else {
                    OutputFileLogger.info(ctx, TAG, "AI structured_json is null/empty")
                }
                if (cats != null && cats.trim().isNotEmpty()) {
                    OutputFileLogger.info(ctx, TAG, "AI categories: ${cats}")
                }
            } catch (_: Exception) {}
            return Quad(model, outputText, structured, cats)
        } else {
            // OpenAI 兼容 REST: POST {base}/v1/chat/completions
            val url = "$base/v1/chat/completions"
            try { FileLogger.i(TAG, "AI request (OpenAI compat): url=$url, model=$model, images=${effSamples.size}") } catch (_: Exception) {}
            try { android.util.Log.i(TAG, "AI request (OpenAI compat): url=$url, model=$model, images=${effSamples.size}") } catch (_: Exception) {}
            try { OutputFileLogger.info(ctx, TAG, "AI request (OpenAI compat): url=$url, model=$model, images=${effSamples.size}") } catch (_: Exception) {}

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
                        try { FileLogger.i(TAG, "AI response meta(OpenAI compat): code=${resp.code}, elapsedMs=${end - start}, attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { android.util.Log.i(TAG, "AI response meta(OpenAI compat): code=${resp.code}, elapsedMs=${end - start}, attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.info(ctx, TAG, "AI response meta(OpenAI compat): code=${resp.code}, elapsedMs=${end - start}, attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
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
                                // 记录并视为“带错误负载的成功”，交由下游保存错误预览供前端展示，避免自动重试
                            try { FileLogger.w(TAG, "AI success(200) but error payload(OpenAI) body=${truncateForLog(respText, 800)}") } catch (_: Exception) {}
                            try { OutputFileLogger.error(ctx, TAG, "AI success(200) but error payload(OpenAI) body=${truncateForLog(respText, 800)}") } catch (_: Exception) {}
                                break
                            } else {
                                // 正常成功
                                break
                            }
                        } else {
                            lastBody = resp.body?.string()
                            val shouldRetry = resp.code >= 500
                            try { FileLogger.w(TAG, "AI failed(OpenAI compat) code=${resp.code} attempt=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { android.util.Log.w(TAG, "AI failed(OpenAI compat) code=${resp.code} attempt=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            try { OutputFileLogger.error(ctx, TAG, "AI failed(OpenAI compat) code=${resp.code} attempt=${attempt + 1}/${maxAttempts} body=${truncateForLog(lastBody ?: "", 800)}") } catch (_: Exception) {}
                            if (!shouldRetry) throw IllegalStateException("Request failed: ${resp.code} ${lastBody}")
                        }
                    } catch (e: java.net.SocketTimeoutException) {
                        try { FileLogger.w(TAG, "AI timeout(OpenAI) attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { android.util.Log.w(TAG, "AI timeout(OpenAI) attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI timeout(OpenAI) attempt=${attempt + 1}/${maxAttempts}") } catch (_: Exception) {}
                        // 继续重试
                    } catch (e: Exception) {
                        try { FileLogger.w(TAG, "AI exception(OpenAI) attempt=${attempt + 1}/${maxAttempts}: ${e.message}") } catch (_: Exception) {}
                        try { android.util.Log.w(TAG, "AI exception(OpenAI) attempt=${attempt + 1}/${maxAttempts}: ${e.message}") } catch (_: Exception) {}
                        try { OutputFileLogger.error(ctx, TAG, "AI exception(OpenAI) attempt=${attempt + 1}/${maxAttempts}: ${e.message}") } catch (_: Exception) {}
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
                FileLogger.d(TAG, "AI response size(OpenAI compat)=${respText.length}")
                val preview = truncateForLog(respText, 2000)
                FileLogger.i(TAG, "AI response preview(OpenAI): ${preview}")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                android.util.Log.i(TAG, "AI response preview(OpenAI): ${preview}")
            } catch (_: Exception) {}
            // 完整响应落盘（分块写入）
            try {
                OutputFileLogger.info(ctx, TAG, "AI response full(OpenAI) BEGIN >>>")
                val text2 = respText
                val chunk2 = 1800
                var j = 0
                while (j < text2.length) {
                    val end = kotlin.math.min(j + chunk2, text2.length)
                    OutputFileLogger.info(ctx, TAG, text2.substring(j, end))
                    j = end
                }
                OutputFileLogger.info(ctx, TAG, "AI response full(OpenAI) END <<<")
            } catch (_: Exception) {}
            try {
                val preview = truncateForLog(respText, 2000)
                OutputFileLogger.info(ctx, TAG, "AI response preview(OpenAI): ${preview}")
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
                    if (low.contains("\"error\"") || low.contains("no candidates returned")) {
                        outputText = "AI response preview(OpenAI): " + respText
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
                    OutputFileLogger.info(ctx, TAG, "AI structured_json(OpenAI) BEGIN >>>")
                    val textSJ2 = pretty
                    val chunkSJ2 = 1800
                    var q = 0
                    while (q < textSJ2.length) {
                        val end = kotlin.math.min(q + chunkSJ2, textSJ2.length)
                        OutputFileLogger.info(ctx, TAG, textSJ2.substring(q, end))
                        q = end
                    }
                    OutputFileLogger.info(ctx, TAG, "AI structured_json(OpenAI) END <<<")
                } else {
                    OutputFileLogger.info(ctx, TAG, "AI structured_json(OpenAI) is null/empty")
                }
                if (cats != null && cats.trim().isNotEmpty()) {
                    OutputFileLogger.info(ctx, TAG, "AI categories(OpenAI): ${cats}")
                }
            } catch (_: Exception) {}
            return Quad(model, outputText, structured, cats)
        }
    }

    /**
     * 与上一个已完成段进行“是否为同一事件”的判断，若相同则合并并生成新总结；
     * 合并策略：将时间窗口扩展为 [prev.start, cur.end] 并基于合并后的样本重新请求AI。
     * 图片采样：若合计图片数超过 MAX_COMPARE_IMAGES，则两段各取一半，按时间均匀抽样。
     */
    private fun tryCompareAndMergeBackward(
        ctx: Context,
        cur: SegmentDatabaseHelper.Segment,
        curSamples: List<SegmentDatabaseHelper.Sample>,
        curOutputText: String,
        curStructured: String?
    ) {
        try { FileLogger.i(TAG, "merge: begin compare cur=${cur.id} start=${fmt(cur.startTime)} with previous") } catch (_: Exception) {}
        val prev = SegmentDatabaseHelper.getPreviousCompletedSegmentWithResult(ctx, cur.startTime)
        if (prev == null) {
            try { FileLogger.i(TAG, "merge: no previous completed-with-result segment before ${fmt(cur.startTime)}") } catch (_: Exception) {}
            SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
            return
        }

        // 读取上一个段的样本与文本（用于“已引用图片数”判断）
        val prevSamples = SegmentDatabaseHelper.getSamplesForSegment(ctx, prev.id)
        try { FileLogger.i(TAG, "merge: prev=${prev.id} A=${prevSamples.size} imgs, cur=${cur.id} B=${curSamples.size} imgs") } catch (_: Exception) {}
        // 合并上限前置判断：依据“两事件已引用的图片数（样本数之和）”，而非时间窗总截图数
        val maxImagesPerMergedEvent = getMergeMaxImagesPerEvent(ctx)
        val seenFiles = java.util.HashSet<String>()
        for (s in prevSamples) { seenFiles.add(s.filePath) }
        for (s in curSamples) { seenFiles.add(s.filePath) }
        val referencedCount = prevSamples.size + curSamples.size
        val referencedUnique = seenFiles.size
        try { FileLogger.i(TAG, "merge: referenced images total=${referencedCount} unique=${referencedUnique} limit=${maxImagesPerMergedEvent}") } catch (_: Exception) {}
        if (referencedUnique > maxImagesPerMergedEvent) {
            try { FileLogger.i(TAG, "merge: skip because referenced images would exceed limit=${maxImagesPerMergedEvent}") } catch (_: Exception) {}
            SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
            return
        }

        val prevRes = SegmentDatabaseHelper.getResultForSegment(ctx, prev.id)
        val prevOutput = prevRes.first ?: ""

        // 直接使用合并提示词与采样，首次即生成合并结果（不追加自定义文案）
        val capFinal = (cur.durationSec / cur.sampleIntervalSec).coerceAtLeast(1)
        val finalCap = kotlin.math.min(capFinal, PROVIDER_IMAGE_HARD_LIMIT)
        val picks = pickCompareImages(prevSamples, curSamples, finalCap)
        val limitedMerged = mergeSamples(picks.first, picks.second)
        val mergePrompt = buildMergePrompt(ctx, prev, cur, limitedMerged)
        try { FileLogger.i(TAG, "merge: merging window ${fmt(prev.startTime)}..${fmt(cur.endTime)} samples=${limitedMerged.size} (cap=${finalCap}) using merge prompt") } catch (_: Exception) {}
        val merged = callGeminiWithImages(ctx, cur, limitedMerged, mergePrompt, isMerge = true)
        try { FileLogger.i(TAG, "merge: merged summary saved for seg=${cur.id} outputSize=${merged.second.length}") } catch (_: Exception) {}
        // 仅打印合并“生成新总结”的AI响应
        try {
            val preview2 = truncateForLog(merged.second, 3000)
            FileLogger.i(TAG, "合并总结响应: ${preview2}")
        } catch (_: Exception) {}
        // 同步更新当前段的时间窗口到合并范围
        SegmentDatabaseHelper.updateSegmentWindow(ctx, cur.id, prev.startTime, cur.endTime)
        // 重建并保存合并后的样本，确保前端能够显示两段图片（而非仅当前段）
        try {
            val curAfter = SegmentDatabaseHelper.getSegmentById(ctx, cur.id)
            if (curAfter != null) {
                val rebuilt = buildSamplesForSegment(ctx, curAfter)
                if (rebuilt.isNotEmpty()) {
                    try { SegmentDatabaseHelper.saveSamples(ctx, cur.id, rebuilt) } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
        // 覆写当前段的结果（保持上一个不变），并标记上一个段状态为 completed-merged 可选
        SegmentDatabaseHelper.saveResult(
            ctx,
            cur.id,
            provider = "gemini",
            model = merged.first,
            outputText = merged.second,
            structuredJson = merged.third,
            categories = merged.fourth
        )
        // 标记当前段为“已合并”，用于前端展示
        try { SegmentDatabaseHelper.setMergedFlag(ctx, cur.id, true) } catch (_: Exception) {}
        // 合并成功后：删除被合并的前一事件，避免同时存在
        try {
            SegmentDatabaseHelper.deleteSegmentCascade(ctx, prev.id)
            try { FileLogger.i(TAG, "merge: deleted previous segment id=${prev.id}") } catch (_: Exception) {}
        } catch (_: Exception) {}
        // 递归向前继续尝试合并
        try { FileLogger.i(TAG, "merge: continue backward compare from new start=${fmt(prev.startTime)}") } catch (_: Exception) {}
        SegmentDatabaseHelper.setMergeAttempted(ctx, cur.id, true)
        tryCompareAndMergeBackward(ctx, cur.copy(startTime = prev.startTime), limitedMerged, merged.second, merged.third)
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

    /** 为任意 segment 按“每槽位最近一图 + 最后一槽尝试 end 之后第一张”规则重建样本列表 */
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
        samples: List<SegmentDatabaseHelper.Sample>
    ): String {
        val byApp = LinkedHashMap<String, MutableList<SegmentDatabaseHelper.Sample>>()
        for (s in samples) byApp.getOrPut(s.appPackageName) { ArrayList() }.add(s)

        // 依据应用语言注入“语言强制策略”并选择合并提示词（支持 _zh/_en 与旧键回退）
        val langOpt = try { ctx.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE).getString("flutter.locale_option", "system") } catch (_: Exception) { "system" }
        val sysLang = try { java.util.Locale.getDefault().language?.lowercase() } catch (_: Exception) { "en" } ?: "en"
        val isZhLang = (langOpt == "zh") || (langOpt != "en" && sysLang.startsWith("zh"))

        val customHeaderLang = try { AISettingsNative.readSettingValue(ctx, if (isZhLang) "prompt_merge_zh" else "prompt_merge_en") } catch (_: Exception) { null }
        val customHeaderLegacy = try { AISettingsNative.readSettingValue(ctx, "prompt_merge") } catch (_: Exception) { null }

        val defaultHeaderZh =
            "请基于以下图片产出合并后的总结；必须遵循以下规则（中文输出，结构化JSON，行为导向，禁止逐图/禁止OCR）：\n" +
            "- 禁止使用OCR文本，直接理解图片内容；\n" +
            "- 不要对每张图片逐条描述；请产出用户在该时间段的‘行为总结’，如 浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等，按应用或主题整合；\n" +
            "- 对包含视频标题、作者、品牌等独特信息，按屏幕原样保留；\n" +
            "- 对同一文章/视频/页面的连续图片，归为同一 content_group，做整体总结；\n" +
            "- 开头先输出一段对本时间段的简短总结（纯文本，不使用任何标题；不要出现“## 概览”或“## 总结”等）；随后再使用 Markdown 小节呈现后续内容；\n" +
            "- Markdown 要求：所有“用于展示的文本字段”须使用 Markdown（overall_summary 与 content_groups[].summary），用小标题与项目符号清晰呈现；禁止输出 Markdown 代码块标记（如 ```），仅纯 Markdown 文本；\n" +
            "- 后续小节建议包含：\"## 关键操作\"（按时间的要点清单）、\"## 主要活动\"（按应用/主题的要点清单）、\"## 重点内容\"（可保留的标题/作者/品牌等）；\n" +
            "- 在“## 关键操作”中，将相邻/连续同类行为合并为区间，格式“HH:mm:ss-HH:mm:ss：行为描述”（例如“08:16:41-08:27:21：浏览视频评论”）；仅在行为中断或切换时新起一条；控制 3-8 条精要；\n" +
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

        val languagePolicy = getByLang(ctx, R.string.ai_language_policy_zh, R.string.ai_language_policy_en, isZhLang)

        val header = languagePolicy + "\n\n" + ((customHeaderLang ?: customHeaderLegacy) ?: getByLang(ctx, R.string.merge_prompt_default_zh, R.string.merge_prompt_default_en, isZhLang))

        val sb = StringBuilder()
        val titleLabel = getByLang(ctx, R.string.title_merged_event_summary_zh, R.string.title_merged_event_summary_en, isZhLang)
        val timeRangeLabel = getByLang(ctx, R.string.label_time_range_zh, R.string.label_time_range_en, isZhLang)
        val appLabel = getByLang(ctx, R.string.label_app_zh, R.string.label_app_en, isZhLang)
        val shotLabel = getByLang(ctx, R.string.label_screenshot_at_zh, R.string.label_screenshot_at_en, isZhLang)
        val fileLabel = getByLang(ctx, R.string.label_file_zh, R.string.label_file_en, isZhLang)

        sb.append(titleLabel).append('\n')
            .append(timeRangeLabel).append(fmt(a.startTime)).append(" - ").append(fmt(b.endTime)).append('\n')
            .append(header).append('\n')
        for ((pkg, list) in byApp) {
            list.sortBy { it.captureTime }
            val name = list.firstOrNull()?.appName ?: pkg
            sb.append(appLabel).append(name).append(" (").append(pkg).append(")\n")
            for (s in list) {
                sb.append(shotLabel).append(fmt(s.captureTime)).append(fileLabel).append(File(s.filePath).name).append('\n')
            }
        }
        return sb.toString()
    }

    /**
     * 扫描并补救：仅针对“当天”的 completed 段落，凡无内容（文本与结构化皆空）均尝试补救；
     * 如不存在样本，则按规则即时重建样本后再补救。
     */
    private fun resumeMissingSummaries(ctx: Context, limit: Int = 2) {
        // 默认只补救“当天”
        val since = startOfToday()
        val list = try { SegmentDatabaseHelper.listSegmentsNeedingSummary(ctx, limit = limit, sinceMillis = since) } catch (_: Exception) { emptyList() }
        try {
            if (list.isNotEmpty()) {
                FileLogger.i(TAG, "resumeMissing: candidates=${list.size}, limit=${limit}, since=today")
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
                    try { FileLogger.w(TAG, "resumeMissing: seg=${seg.id} has no samples after rebuild, skip") } catch (_: Exception) {}
                    continue
                }
                // 直接复用 finish 逻辑
                try { FileLogger.i(TAG, "resumeMissing: retry seg=${seg.id} ${fmt(seg.startTime)}-${fmt(seg.endTime)} imgs=${samples.size}") } catch (_: Exception) {}
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
     * - force=true 时无视“已有结果/同窗已有结果”直接重跑并覆盖写入。
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

    private fun getByLang(ctx: Context, zhId: Int, enId: Int, isZh: Boolean): String {
        return ctx.getString(if (isZh) zhId else enId)
    }

    private fun guessMime(path: String): String {
        val lower = path.lowercase()
        return when {
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".png") -> "image/png"
            else -> "image/png"
        }
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


