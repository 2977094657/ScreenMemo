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

    // 活动段落缓存（仅存ID，其他实时查库）
    @Volatile private var activeSegmentId: Long = -1L

    // 并发窗口去重：按 “start|end” 标识正在创建中的段落，避免同时间段重复创建
    private val creatingWindows: MutableSet<String> = Collections.synchronizedSet(HashSet())
    // 并发完成去重：避免同一 segment 被重复 finish/AI 调用
    private val finishingSegments: MutableSet<Long> = Collections.synchronizedSet(HashSet())
    // 窗口级完成去重：同一 (start,end) 仅允许一次 finish 流程
    private val finishingWindows: MutableSet<String> = Collections.synchronizedSet(HashSet())

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

    private fun finishSegment(ctx: Context, seg: SegmentDatabaseHelper.Segment, samples: List<SegmentDatabaseHelper.Sample>) {
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
                try { FileLogger.i(TAG, "finish: begin segment=${seg.id}, samples=${samples.size}") } catch (_: Exception) {}
                // 兜底：无样本则不进行AI
                if (samples.isEmpty()) {
                    try { FileLogger.w(TAG, "finish: no samples, skip ai seg=${seg.id}") } catch (_: Exception) {}
                    SegmentDatabaseHelper.updateSegmentStatus(ctx, seg.id, "completed")
                    return@Thread
                }
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
                // 聚合应用与时间片，组织提示
                val byApp = LinkedHashMap<String, MutableList<SegmentDatabaseHelper.Sample>>()
                for (s in samples) {
                    byApp.getOrPut(s.appPackageName) { ArrayList() }.add(s)
                }
                // 构造描述（仅时间点与应用，不包含OCR文本），要求中文输出
                val sb = StringBuilder()
                sb.append("时间段：")
                    .append(fmt(seg.startTime)).append(" - ").append(fmt(seg.endTime)).append('\n')
                    .append("请基于以下多张屏幕图片进行中文总结，并输出结构化结果：\n")
                    .append("- 禁止使用OCR文本，直接理解图片内容；\n")
                    .append("- 不要对每张图片逐条描述；请产出用户在该时间段的‘行为总结’，如 浏览/观看/聊天/购物/办公/设置/下载/分享/游戏 等，按应用或主题整合；\n")
                    .append("- 对包含视频标题、作者、品牌等独特信息，按屏幕原样保留；\n")
                    .append("- 对同一文章/视频/页面的连续图片，归为同一 content_group，做整体总结，不必逐图总结；\n")
                    .append("- 识别关键操作（支付/下单、登录/注册、权限授权或系统权限弹窗、账号绑定/解绑、验证码、人脸/指纹、应用内购买等），仅描述已发生的事实，不要输出敏感信息；\n")
                    .append("- 输出一个 overall_summary（中等长度，2-4句，避免过度简略），聚焦该时间段用户主要行为与意图；\n")
                    .append("- 以 JSON 输出以下字段（在原有字段基础上新增，不要删除）：apps[], categories[], timeline[], key_actions[], content_groups[], overall_summary；\n")
                    .append("字段约定：\n")
                    .append("key_actions[]: [{\"type\":\"pay|login|register|permission_grant|oauth_authorize|purchase|bind_account|unbind_account|captcha|biometric|other\",\"app\":\"应用名\",\"ref_image\":\"文件名\",\"ref_time\":\"HH:mm:ss\",\"detail\":\"简要说明（避免敏感信息）\",\"confidence\":0.0}],\n")
                    .append("content_groups[]: [{\"group_type\":\"article|video|page|playlist|feed\",\"title\":\"可为空\",\"app\":\"应用名\",\"start_time\":\"HH:mm:ss\",\"end_time\":\"HH:mm:ss\",\"image_count\":1,\"representative_images\":[\"文件名1\",\"文件名2\"],\"summary\":\"本组内容中文总结\"}],\n")
                    .append("timeline[]: [{\"time\":\"HH:mm:ss\",\"app\":\"应用名\",\"action\":\"浏览|观看|聊天|购物|搜索|编辑|游戏|设置|下载|分享|其他\",\"summary\":\"一句话行为\"}],\n")
                    .append("overall_summary: \"2-4句的中等长度概述，避免流水账与过度简略\"\n")
                for ((pkg, list) in byApp) {
                    list.sortBy { it.captureTime }
                    val name = list.firstOrNull()?.appName ?: pkg
                    sb.append("应用：").append(name).append(" (").append(pkg).append(")\n")
                    for (s in list) {
                        sb.append("  - 截图时间=").append(fmt(s.captureTime)).append(" -> 文件=").append(File(s.filePath).name).append('\n')
                    }
                }

                val prompt = sb.toString()
                try { FileLogger.i(TAG, "finish: calling Gemini with ${samples.size} images") } catch (_: Exception) {}
                val result = callGeminiWithImages(ctx, seg, samples, prompt)
                try { FileLogger.i(TAG, "finish: ai model=${result.first}, outputSize=${result.second.length}") } catch (_: Exception) {}
                SegmentDatabaseHelper.saveResult(
                    ctx,
                    seg.id,
                    provider = "gemini",
                    model = result.first,
                    outputText = result.second,
                    structuredJson = result.third,
                    categories = result.fourth
                )
            } catch (e: Exception) {
                Log.w(TAG, "finishSegment ai error: ${e.message}")
                try { FileLogger.w(TAG, "finishSegment ai error: ${e.message}") } catch (_: Exception) {}
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
        prompt: String
    ): Quad<String, String, String?, String?> {
        val cfg = AISettingsNative.readConfig(ctx)
        val apiKey = cfg.apiKey
        val client = OkHttpClient()

        val model = cfg.model
        val base = if (cfg.baseUrl.endsWith('/')) cfg.baseUrl.dropLast(1) else cfg.baseUrl
        val isGoogle = base.contains("googleapis.com") || base.contains("generativelanguage")

        if (isGoogle) {
            // Gemini REST: POST {base}/v1beta/models/{model}:generateContent?key=API_KEY
            val url = "$base/v1beta/models/$model:generateContent?key=$apiKey"
            try { FileLogger.i(TAG, "AI request: url=$url, model=$model, images=${samples.size}") } catch (_: Exception) {}

            val parts = JSONArray()
            parts.put(JSONObject().put("text", prompt))
            for (s in samples) {
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
            val resp = client.newCall(req).execute()
            if (!resp.isSuccessful) {
                val err = resp.body?.string()
                try { FileLogger.e(TAG, "AI request failed: code=${resp.code}, body=${err}") } catch (_: Exception) {}
                throw IllegalStateException("Request failed: ${resp.code} ${err}")
            }
            val respText = resp.body?.string() ?: ""
            try { FileLogger.d(TAG, "AI response size=${respText.length}") } catch (_: Exception) {}

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
            val (structured, cats) = extractJsonBlocks(outputText)
            return Quad(model, outputText, structured, cats)
        } else {
            // OpenAI 兼容 REST: POST {base}/v1/chat/completions
            val url = "$base/v1/chat/completions"
            try { FileLogger.i(TAG, "AI request (OpenAI compat): url=$url, model=$model, images=${samples.size}") } catch (_: Exception) {}

            val contentArr = JSONArray()
            contentArr.put(JSONObject().put("type", "text").put("text", prompt))
            for (s in samples) {
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
            val resp = client.newCall(req).execute()
            if (!resp.isSuccessful) {
                val err = resp.body?.string()
                try { FileLogger.e(TAG, "AI request failed(OpenAI compat): code=${resp.code}, body=${err}") } catch (_: Exception) {}
                throw IllegalStateException("Request failed: ${resp.code} ${err}")
            }
            val respText = resp.body?.string() ?: ""
            try { FileLogger.d(TAG, "AI response size(OpenAI compat)=${respText.length}") } catch (_: Exception) {}
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
            val (structured, cats) = extractJsonBlocks(outputText)
            return Quad(model, outputText, structured, cats)
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


