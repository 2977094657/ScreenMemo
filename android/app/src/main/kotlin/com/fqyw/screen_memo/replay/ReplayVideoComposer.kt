package com.fqyw.screen_memo.replay

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.GLES20
import android.opengl.GLUtils
import android.os.SystemClock
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.fqyw.screen_memo.logging.FileLogger
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.FileReader
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object ReplayVideoComposer {
    private const val TAG = "ReplayVideoComposer"
    private const val MIME_TYPE = "video/avc"
    private const val I_FRAME_INTERVAL_SEC = 1
    private const val TIMEOUT_USEC = 10_000L

    @Volatile private var cachedMaterialIconsTypeface: Typeface? = null
    @Volatile private var cachedMaterialIconsTypefaceTried: Boolean = false

    private fun getMaterialIconsTypeface(context: Context): Typeface? {
        if (cachedMaterialIconsTypefaceTried) return cachedMaterialIconsTypeface
        synchronized(this) {
            if (cachedMaterialIconsTypefaceTried) return cachedMaterialIconsTypeface
            val candidates = arrayOf(
                "flutter_assets/fonts/MaterialIcons-Regular.otf",
                "flutter_assets/fonts/MaterialIcons-Regular.ttf",
                "flutter_assets/MaterialIcons-Regular.otf",
                "flutter_assets/MaterialIcons-Regular.ttf",
            )
            var tf: Typeface? = null
            for (path in candidates) {
                try {
                    tf = Typeface.createFromAsset(context.assets, path)
                    break
                } catch (_: Exception) {
                }
            }
            cachedMaterialIconsTypeface = tf
            cachedMaterialIconsTypefaceTried = true
            return tf
        }
    }

    data class Frame(
        val path: String,
        val tsMillis: Long,
        val app: String,
        val pkg: String,
        val nsfw: Boolean,
    )

    data class IconInfo(
        val icon: Bitmap?,
        val dominantColor: Int,
    )

    data class AppRun(
        val pkg: String,
        val startIndex: Int,
        val length: Int,
        val color: Int,
    )

    private enum class AppProgressBarPosition {
        TOP,
        RIGHT,
        BOTTOM,
        LEFT;

        companion object {
            fun parse(raw: String?): AppProgressBarPosition {
                return when (raw?.trim()?.lowercase(Locale.ROOT)) {
                    "top" -> TOP
                    "bottom" -> BOTTOM
                    "left" -> LEFT
                    "right" -> RIGHT
                    else -> RIGHT
                }
            }
        }
    }

    private enum class ReplayNsfwMode {
        MASK,
        SHOW,
        HIDE;

        companion object {
            fun parse(raw: String?): ReplayNsfwMode {
                return when (raw?.trim()?.lowercase(Locale.ROOT)) {
                    "show" -> SHOW
                    "hide" -> HIDE
                    "mask" -> MASK
                    else -> MASK
                }
            }
        }
    }

    fun compose(
        context: Context,
        framesJsonlPath: String,
        outputPath: String,
        fps: Int,
        shortSide: Int,
        quality: String,
        overlayEnabled: Boolean,
        appProgressBarEnabled: Boolean,
        appProgressBarPosition: String,
        nsfwMode: String,
        nsfwTitle: String?,
        nsfwSubtitle: String?,
        onProgress: ((processed: Int, total: Int) -> Unit)? = null,
    ): Map<String, Any> {
        val started = SystemClock.elapsedRealtime()
        val frames = readFrames(framesJsonlPath)
        if (frames.isEmpty()) throw RuntimeException("frames is empty")

        val bounds = findFirstBounds(frames)
        val baseW = bounds.first
        val baseH = bounds.second
        if (baseW <= 0 || baseH <= 0) throw RuntimeException("invalid first frame bounds")

        val out = computeOutputSize(baseW, baseH, shortSide)
        val outW = out.first
        val outH = out.second

        val bitrate = computeBitrate(outW, outH, fps, quality)
        val replayNsfwMode = ReplayNsfwMode.parse(nsfwMode)
        FileLogger.i(TAG, "compose start frames=${frames.size} out=${outW}x${outH} fps=$fps bitrate=$bitrate overlay=$overlayEnabled progressBar=$appProgressBarEnabled nsfwMode=$replayNsfwMode")
        onProgress?.invoke(0, frames.size)

        val outFile = File(outputPath)
        outFile.parentFile?.mkdirs()
        if (outFile.exists()) {
            try {
                outFile.delete()
            } catch (_: Exception) {
            }
        }

        val bufferInfo = MediaCodec.BufferInfo()
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var inputSurface: android.view.Surface? = null
        var eglCore: EglCore? = null
        var windowSurface: WindowSurface? = null
        var renderer: TextureRenderer? = null

        var trackIndex = -1
        var muxerStarted = false
        var textureId = 0
        var firstTex = true

        val outputBitmap = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(outputBitmap)
        val imagePaint = Paint(Paint.FILTER_BITMAP_FLAG)

        val density = try {
            android.content.res.Resources.getSystem().displayMetrics.density
        } catch (_: Exception) {
            1.0f
        }
        val overlayPadding = 12f * density
        val overlayTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 14f * density
        }
        val overlayBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x80000000.toInt()
        }
        val timeFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        val nsfwLabelTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            textSize = 18f * density
        }
        val nsfwLabelBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x66000000
        }

        val nsfwTitleValue = nsfwTitle?.trim().takeUnless { it.isNullOrEmpty() }
            ?: "Content Warning: Adult Content"
        val nsfwSubtitleValue = nsfwSubtitle?.trim().takeUnless { it.isNullOrEmpty() }
            ?: "This content has been marked as adult content"

        val nsfwDimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            // Match Flutter: Colors.black.withValues(alpha: 0.35)
            color = 0x59000000
        }
        val nsfwTitlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 14f * density
            typeface = Typeface.DEFAULT_BOLD
        }
        val nsfwSubtitlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xB3FFFFFF.toInt()
            textSize = 12f * density
        }

        val nsfwHorizontalPaddingPx = 12f * density
        val nsfwIconSizePx = 28f * density
        val nsfwGapIconTitlePx = 8f * density
        val nsfwGapTitleSubtitlePx = 4f * density

        val nsfwTextMaxWidth = (outW - 2f * nsfwHorizontalPaddingPx)
            .roundToInt()
            .coerceAtLeast(1)
        val nsfwTitleLayout = StaticLayout(
            nsfwTitleValue,
            nsfwTitlePaint,
            nsfwTextMaxWidth,
            Layout.Alignment.ALIGN_CENTER,
            1f,
            0f,
            false,
        )
        val nsfwSubtitleLayout = StaticLayout(
            nsfwSubtitleValue,
            nsfwSubtitlePaint,
            nsfwTextMaxWidth,
            Layout.Alignment.ALIGN_CENTER,
            1f,
            0f,
            false,
        )

        val nsfwIconGlyph = try {
            String(Character.toChars(0xF0292))
        } catch (_: Exception) {
            null
        }
        val materialIconsTypeface = getMaterialIconsTypeface(context)
        val nsfwIconTextPaint = if (materialIconsTypeface != null && nsfwIconGlyph != null) {
            TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xB3FFFFFF.toInt()
                textAlign = Paint.Align.CENTER
                textSize = nsfwIconSizePx
                typeface = materialIconsTypeface
            }
        } else {
            null
        }
        val showNsfwIcon = nsfwIconTextPaint != null && nsfwIconGlyph != null
        val iconBlockH = if (showNsfwIcon) nsfwIconSizePx else 0f
        val gapIconTitle = if (showNsfwIcon) nsfwGapIconTitlePx else 0f

        val nsfwTotalHeightPx = iconBlockH +
            gapIconTitle +
            nsfwTitleLayout.height.toFloat() +
            nsfwGapTitleSubtitlePx +
            nsfwSubtitleLayout.height.toFloat()
        val nsfwTopPx = ((outH.toFloat() - nsfwTotalHeightPx) / 2f).coerceAtLeast(0f)
        val nsfwIconX = outW.toFloat() / 2f
        val nsfwIconCenterY = nsfwTopPx + (iconBlockH / 2f)
        val nsfwIconBaselineY = if (showNsfwIcon) {
            val fm = nsfwIconTextPaint!!.fontMetrics
            nsfwIconCenterY - (fm.ascent + fm.descent) / 2f
        } else {
            0f
        }
        val nsfwTitleTopPx = nsfwTopPx + iconBlockH + gapIconTitle
        val nsfwSubtitleTopPx = nsfwTitleTopPx + nsfwTitleLayout.height + nsfwGapTitleSubtitlePx
        val nsfwTextLeftPx = ((outW - nsfwTextMaxWidth).toFloat() / 2f).coerceAtLeast(0f)

        val blurTargetShortSidePx = 16
        val shortSidePx = min(outW, outH).coerceAtLeast(1)
        val blurScale = min(1f, blurTargetShortSidePx.toFloat() / shortSidePx.toFloat())
        val blurW = max(1, (outW.toFloat() * blurScale).roundToInt())
        val blurH = max(1, (outH.toFloat() * blurScale).roundToInt())
        val nsfwBlurBitmap = Bitmap.createBitmap(blurW, blurH, Bitmap.Config.ARGB_8888)
        val nsfwBlurCanvas = Canvas(nsfwBlurBitmap)
        val nsfwBlurPaint = Paint(Paint.FILTER_BITMAP_FLAG)

        val progressBarPosition = AppProgressBarPosition.parse(appProgressBarPosition)
        val progressBarHorizontal = progressBarPosition == AppProgressBarPosition.TOP ||
            progressBarPosition == AppProgressBarPosition.BOTTOM

        val appProgressBarThicknessPx = 5
        val appIconSizePx = 18f * density
        val appProgressBarMaskPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xAA000000.toInt()
        }

        val fallbackAppColor = try {
            Color.parseColor("#4CAF50")
        } catch (_: Exception) {
            Color.GREEN
        }

        val iconInfoByPkg: Map<String, IconInfo> = if (appProgressBarEnabled || overlayEnabled) {
            buildIconInfoByPkg(
                context = context,
                frames = frames,
                iconSizePx = appIconSizePx.roundToInt().coerceAtLeast(1),
                fallbackColor = fallbackAppColor,
            )
        } else {
            emptyMap()
        }

        val appProgressBarBitmap: Bitmap? = if (appProgressBarEnabled) {
            buildAppProgressBarBitmap(
                frames = frames,
                iconInfoByPkg = iconInfoByPkg,
                fallbackColor = fallbackAppColor,
                thicknessPx = appProgressBarThicknessPx,
                axisPx = if (progressBarHorizontal) outW else outH,
                horizontal = progressBarHorizontal,
            )
        } else {
            null
        }

        try {
            val format = MediaFormat.createVideoFormat(MIME_TYPE, outW, outH)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, max(1, fps))
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL_SEC)

            val encoderLocal = MediaCodec.createEncoderByType(MIME_TYPE)
            encoder = encoderLocal
            encoderLocal.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

            inputSurface = encoderLocal.createInputSurface()
            encoderLocal.start()

            val muxerLocal = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = muxerLocal

            val eglLocal = EglCore(null)
            eglCore = eglLocal
            val wsLocal = WindowSurface(eglLocal, inputSurface!!)
            windowSurface = wsLocal
            wsLocal.makeCurrent()

            val rendererLocal = TextureRenderer()
            renderer = rendererLocal
            rendererLocal.init()
            textureId = rendererLocal.createTextureObject()

            GLES20.glViewport(0, 0, outW, outH)

            var frameIndex = 0
            var lastProgressDispatch = 0L
            for (f in frames) {
                drawFrameToBitmap(
                    canvas = canvas,
                    outputW = outW,
                    outputH = outH,
                    frame = f,
                    overlayEnabled = overlayEnabled,
                    timeFmt = timeFmt,
                    overlayPadding = overlayPadding,
                    overlayTextPaint = overlayTextPaint,
                    overlayBgPaint = overlayBgPaint,
                    iconInfoByPkg = iconInfoByPkg,
                    appIconSizePx = appIconSizePx,
                    imagePaint = imagePaint,
                    nsfwMode = replayNsfwMode,
                    nsfwLabelTextPaint = nsfwLabelTextPaint,
                    nsfwLabelBgPaint = nsfwLabelBgPaint,
                    nsfwDimPaint = nsfwDimPaint,
                    nsfwTitleLayout = nsfwTitleLayout,
                    nsfwSubtitleLayout = nsfwSubtitleLayout,
                    nsfwTextLeftPx = nsfwTextLeftPx,
                    nsfwTitleTopPx = nsfwTitleTopPx,
                    nsfwSubtitleTopPx = nsfwSubtitleTopPx,
                    nsfwIconGlyph = nsfwIconGlyph,
                    nsfwIconX = nsfwIconX,
                    nsfwIconBaselineY = nsfwIconBaselineY,
                    nsfwIconTextPaint = nsfwIconTextPaint,
                    nsfwBlurCanvas = nsfwBlurCanvas,
                    nsfwBlurBitmap = nsfwBlurBitmap,
                    nsfwBlurPaint = nsfwBlurPaint,
                )

                if (appProgressBarEnabled) {
                    drawSegmentedAppProgressBar(
                        canvas = canvas,
                        outputW = outW,
                        outputH = outH,
                        position = progressBarPosition,
                        frameIndex = frameIndex,
                        totalFrames = frames.size,
                        barBitmap = appProgressBarBitmap,
                        maskPaint = appProgressBarMaskPaint,
                    )
                }

                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
                if (firstTex) {
                    GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, outputBitmap, 0)
                    firstTex = false
                } else {
                    GLUtils.texSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, outputBitmap)
                }
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)

                rendererLocal.draw(textureId)

                val ptsNs = (frameIndex.toLong() * 1_000_000_000L) / max(1, fps)
                wsLocal.setPresentationTime(ptsNs)
                wsLocal.swapBuffers()

                drainEncoder(
                    encoder = encoderLocal,
                    muxer = muxerLocal,
                    bufferInfo = bufferInfo,
                    endOfStream = false,
                    onFormatChanged = { fmt ->
                        if (muxerStarted) throw RuntimeException("format changed twice")
                        trackIndex = muxerLocal.addTrack(fmt)
                        muxerLocal.start()
                        muxerStarted = true
                    },
                    onSample = { data, info ->
                        if (!muxerStarted) throw RuntimeException("muxer not started")
                        muxerLocal.writeSampleData(trackIndex, data, info)
                    }
                )

                frameIndex++
                val now = SystemClock.elapsedRealtime()
                if (
                    frameIndex >= frames.size ||
                    frameIndex == 1 ||
                    now - lastProgressDispatch >= 180L
                ) {
                    onProgress?.invoke(frameIndex, frames.size)
                    lastProgressDispatch = now
                }
            }

            drainEncoder(
                encoder = encoderLocal,
                muxer = muxerLocal,
                bufferInfo = bufferInfo,
                endOfStream = true,
                onFormatChanged = { fmt ->
                    if (muxerStarted) throw RuntimeException("format changed twice")
                    trackIndex = muxerLocal.addTrack(fmt)
                    muxerLocal.start()
                    muxerStarted = true
                },
                onSample = { data, info ->
                    if (!muxerStarted) throw RuntimeException("muxer not started")
                    muxerLocal.writeSampleData(trackIndex, data, info)
                }
            )
        } finally {
            try {
                renderer?.release()
            } catch (_: Exception) {
            }
            try {
                if (textureId != 0) {
                    GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
                }
            } catch (_: Exception) {
            }
            try {
                windowSurface?.release()
            } catch (_: Exception) {
            }
            try {
                inputSurface?.release()
            } catch (_: Exception) {
            }
            try {
                eglCore?.release()
            } catch (_: Exception) {
            }
            try {
                encoder?.stop()
            } catch (_: Exception) {
            }
            try {
                encoder?.release()
            } catch (_: Exception) {
            }
            try {
                if (muxerStarted) {
                    muxer?.stop()
                }
            } catch (_: Exception) {
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            try {
                for (info in iconInfoByPkg.values) {
                    try {
                        val bmp = info.icon
                        if (bmp != null && !bmp.isRecycled) bmp.recycle()
                    } catch (_: Exception) {
                    }
                }
            } catch (_: Exception) {
            }
            try {
                if (appProgressBarBitmap != null && !appProgressBarBitmap.isRecycled) {
                    appProgressBarBitmap.recycle()
                }
            } catch (_: Exception) {
            }
            try {
                outputBitmap.recycle()
            } catch (_: Exception) {
            }
        }

        val framesOut = frames.size
        val durationMs = (framesOut.toLong() * 1000L) / max(1, fps)
        val size = try {
            outFile.length()
        } catch (_: Exception) {
            0L
        }
        val elapsed = SystemClock.elapsedRealtime() - started
        FileLogger.i(TAG, "compose done frames=$framesOut durationMs=$durationMs size=$size elapsedMs=$elapsed")

        return mapOf(
            "outputPath" to outputPath,
            "width" to outW,
            "height" to outH,
            "frames" to framesOut,
            "durationMs" to durationMs.toInt(),
            "fileSize" to size.toInt(),
        )
    }

    private fun readFrames(path: String): List<Frame> {
        val out = ArrayList<Frame>()
        val file = File(path)
        if (!file.exists()) return out
        BufferedReader(FileReader(file)).use { br ->
            while (true) {
                val line = br.readLine() ?: break
                val s = line.trim()
                if (s.isEmpty()) continue
                try {
                    val obj = JSONObject(s)
                    val p = obj.optString("path", "")
                    val ts = obj.optLong("ts", 0L)
                    val app = obj.optString("app", "")
                    val pkg = obj.optString("pkg", "")
                    val nsfw = obj.optBoolean("nsfw", false)
                    if (p.isBlank()) continue
                    out.add(Frame(path = p, tsMillis = ts, app = app, pkg = pkg, nsfw = nsfw))
                } catch (_: Exception) {
                }
            }
        }
        return out
    }

    private fun findFirstBounds(frames: List<Frame>): Pair<Int, Int> {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        for (f in frames) {
            try {
                BitmapFactory.decodeFile(f.path, opts)
                if (opts.outWidth > 0 && opts.outHeight > 0) {
                    return Pair(opts.outWidth, opts.outHeight)
                }
            } catch (_: Exception) {
            }
        }
        return Pair(0, 0)
    }

    private fun computeOutputSize(baseW: Int, baseH: Int, shortSide: Int): Pair<Int, Int> {
        var w: Int
        var h: Int
        if (shortSide <= 0) {
            w = baseW
            h = baseH
        } else if (baseW >= baseH) {
            h = shortSide
            w = (shortSide * (baseW.toDouble() / baseH.toDouble())).roundToInt()
        } else {
            w = shortSide
            h = (shortSide * (baseH.toDouble() / baseW.toDouble())).roundToInt()
        }
        if (w % 2 != 0) w += 1
        if (h % 2 != 0) h += 1
        w = max(2, w)
        h = max(2, h)
        return Pair(w, h)
    }

    private fun computeBitrate(w: Int, h: Int, fps: Int, quality: String): Int {
        val q = quality.lowercase(Locale.getDefault())
        val baseBpp = when (q) {
            "low" -> 0.07
            "high" -> 0.14
            else -> 0.10
        }
        val bits = (w.toLong() * h.toLong() * max(1, fps).toLong()).toDouble() * baseBpp
        val raw = bits.toLong()
        val clamped = raw.coerceIn(800_000L, 16_000_000L)
        return clamped.toInt()
    }

    private fun buildIconInfoByPkg(
        context: Context,
        frames: List<Frame>,
        iconSizePx: Int,
        fallbackColor: Int,
    ): Map<String, IconInfo> {
        val out = HashMap<String, IconInfo>()
        val seen = HashSet<String>()
        val bucketCounts = IntArray(32 * 32 * 32)
        val touched = IntArray(1024)

        for (f in frames) {
            val pkg = f.pkg
            if (pkg.isBlank()) continue
            if (!seen.add(pkg)) continue

            val icon = try {
                loadAppIconBitmap(context, pkg, iconSizePx)
            } catch (_: Exception) {
                null
            }
            val color = if (icon != null) {
                dominantColorFromIcon(
                    icon = icon,
                    fallbackColor = fallbackColor,
                    bucketCounts = bucketCounts,
                    touched = touched,
                )
            } else {
                fallbackColor
            }
            out[pkg] = IconInfo(icon = icon, dominantColor = color)
        }

        return out
    }

    private fun loadAppIconBitmap(
        context: Context,
        packageName: String,
        sizePx: Int,
    ): Bitmap? {
        val pm = context.packageManager
        val drawable = try {
            pm.getApplicationIcon(packageName)
        } catch (_: Exception) {
            null
        } ?: return null

        return drawableToBitmap(drawable, sizePx, sizePx)
    }

    private fun drawableToBitmap(
        drawable: Drawable,
        width: Int,
        height: Int,
    ): Bitmap {
        val bmp = Bitmap.createBitmap(
            max(1, width),
            max(1, height),
            Bitmap.Config.ARGB_8888,
        )
        val c = Canvas(bmp)
        drawable.setBounds(0, 0, c.width, c.height)
        drawable.draw(c)
        return bmp
    }

    private fun dominantColorFromIcon(
        icon: Bitmap,
        fallbackColor: Int,
        bucketCounts: IntArray,
        touched: IntArray,
    ): Int {
        val scaled = try {
            Bitmap.createScaledBitmap(icon, 24, 24, true)
        } catch (_: Exception) {
            null
        } ?: return fallbackColor

        var touchedCount = 0
        var bestKey = -1
        var bestCount = 0

        try {
            val w = scaled.width
            val h = scaled.height
            for (y in 0 until h) {
                for (x in 0 until w) {
                    val c = try {
                        scaled.getPixel(x, y)
                    } catch (_: Exception) {
                        continue
                    }
                    val a = (c ushr 24) and 0xFF
                    if (a < 128) continue

                    val r = (c ushr 16) and 0xFF
                    val g = (c ushr 8) and 0xFF
                    val b = c and 0xFF

                    val rq = r shr 3
                    val gq = g shr 3
                    val bq = b shr 3

                    val key = (rq shl 10) or (gq shl 5) or bq
                    if (bucketCounts[key] == 0 && touchedCount < touched.size) {
                        touched[touchedCount++] = key
                    }
                    val n = bucketCounts[key] + 1
                    bucketCounts[key] = n
                    if (n > bestCount) {
                        bestCount = n
                        bestKey = key
                    }
                }
            }
        } catch (_: Exception) {
            return fallbackColor
        } finally {
            try {
                scaled.recycle()
            } catch (_: Exception) {
            }
            for (i in 0 until touchedCount) {
                bucketCounts[touched[i]] = 0
            }
        }

        if (bestKey < 0) return fallbackColor

        val rq = (bestKey shr 10) and 0x1F
        val gq = (bestKey shr 5) and 0x1F
        val bq = bestKey and 0x1F

        val r = (rq shl 3) or (rq shr 2)
        val g = (gq shl 3) or (gq shr 2)
        val b = (bq shl 3) or (bq shr 2)

        return Color.rgb(r, g, b)
    }

    private fun drawSegmentedAppProgressBar(
        canvas: Canvas,
        outputW: Int,
        outputH: Int,
        position: AppProgressBarPosition,
        frameIndex: Int,
        totalFrames: Int,
        barBitmap: Bitmap?,
        maskPaint: Paint,
    ) {
        val bmp = barBitmap ?: return
        if (bmp.isRecycled) return

        val barW = bmp.width
        val barH = bmp.height
        if (barW <= 0 || barH <= 0) return

        val drawX = when (position) {
            AppProgressBarPosition.LEFT -> 0f
            AppProgressBarPosition.RIGHT -> (outputW - barW).toFloat()
            AppProgressBarPosition.TOP -> 0f
            AppProgressBarPosition.BOTTOM -> 0f
        }.coerceAtLeast(0f)
        val drawY = when (position) {
            AppProgressBarPosition.TOP -> 0f
            AppProgressBarPosition.BOTTOM -> (outputH - barH).toFloat()
            AppProgressBarPosition.LEFT -> 0f
            AppProgressBarPosition.RIGHT -> 0f
        }.coerceAtLeast(0f)

        canvas.drawBitmap(bmp, drawX, drawY, null)

        val total = max(1, totalFrames)
        val progress = (frameIndex + 1).toFloat() / total.toFloat()
        if (position == AppProgressBarPosition.TOP || position == AppProgressBarPosition.BOTTOM) {
            val filledX = (barW.toFloat() * progress).roundToInt().coerceIn(0, barW)
            if (filledX >= barW) return
            canvas.drawRect(
                drawX + filledX.toFloat(),
                drawY,
                drawX + barW.toFloat(),
                drawY + barH.toFloat(),
                maskPaint,
            )
        } else {
            val filledY = (barH.toFloat() * progress).roundToInt().coerceIn(0, barH)
            if (filledY >= barH) return
            canvas.drawRect(
                drawX,
                drawY + filledY.toFloat(),
                drawX + barW.toFloat(),
                drawY + barH.toFloat(),
                maskPaint,
            )
        }
    }

    private fun buildAppProgressBarBitmap(
        frames: List<Frame>,
        iconInfoByPkg: Map<String, IconInfo>,
        fallbackColor: Int,
        thicknessPx: Int,
        axisPx: Int,
        horizontal: Boolean,
    ): Bitmap {
        val thickness = max(1, thicknessPx)
        val axis = max(1, axisPx)
        val w = if (horizontal) axis else thickness
        val h = if (horizontal) thickness else axis
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)

        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x80000000.toInt()
        }
        c.drawRect(0f, 0f, w.toFloat(), h.toFloat(), bgPaint)

        val totalFrames = frames.size
        if (totalFrames <= 0) return bmp

        val runs = buildAppRuns(frames, iconInfoByPkg, fallbackColor)
        if (runs.isEmpty()) return bmp

        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        val dividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            // ~15% white, used as thin separators between segments.
            color = 0x26FFFFFF
        }

        val axisLen = if (horizontal) w else h
        if (runs.size <= axisLen) {
            val runPx = allocateRunPixels(runs, axisLen, totalFrames)
            var pos = 0
            for (i in runs.indices) {
                val seg = runPx[i].coerceAtLeast(1)
                val start = pos
                val end = (pos + seg).coerceAtMost(axisLen)
                if (end <= start) break

                fillPaint.color = runs[i].color or (0xFF shl 24)
                if (horizontal) {
                    c.drawRect(
                        start.toFloat(),
                        0f,
                        end.toFloat(),
                        h.toFloat(),
                        fillPaint,
                    )
                    if (i > 0) {
                        c.drawRect(
                            start.toFloat(),
                            0f,
                            (start + 1).toFloat().coerceAtMost(w.toFloat()),
                            h.toFloat(),
                            dividerPaint,
                        )
                    }
                } else {
                    c.drawRect(
                        0f,
                        start.toFloat(),
                        w.toFloat(),
                        end.toFloat(),
                        fillPaint,
                    )
                    if (i > 0) {
                        c.drawRect(
                            0f,
                            start.toFloat(),
                            w.toFloat(),
                            (start + 1).toFloat().coerceAtMost(h.toFloat()),
                            dividerPaint,
                        )
                    }
                }

                pos = end
                if (pos >= axisLen) break
            }
        } else {
            // Too many runs to guarantee 1px each: fall back to per-pixel sampling.
            if (horizontal) {
                for (x in 0 until w) {
                    val idx = ((x.toLong() * totalFrames.toLong()) / w.toLong())
                        .toInt()
                        .coerceIn(0, totalFrames - 1)
                    val pkg = frames[idx].pkg
                    val color = iconInfoByPkg[pkg]?.dominantColor ?: fallbackColor
                    fillPaint.color = color or (0xFF shl 24)
                    c.drawRect(x.toFloat(), 0f, (x + 1).toFloat(), h.toFloat(), fillPaint)
                }
            } else {
                for (y in 0 until h) {
                    val idx = ((y.toLong() * totalFrames.toLong()) / h.toLong())
                        .toInt()
                        .coerceIn(0, totalFrames - 1)
                    val pkg = frames[idx].pkg
                    val color = iconInfoByPkg[pkg]?.dominantColor ?: fallbackColor
                    fillPaint.color = color or (0xFF shl 24)
                    c.drawRect(0f, y.toFloat(), w.toFloat(), (y + 1).toFloat(), fillPaint)
                }
            }
        }

        return bmp
    }

    private fun buildAppRuns(
        frames: List<Frame>,
        iconInfoByPkg: Map<String, IconInfo>,
        fallbackColor: Int,
    ): List<AppRun> {
        if (frames.isEmpty()) return emptyList()

        val out = ArrayList<AppRun>()
        var curPkg = frames[0].pkg
        var startIndex = 0

        for (i in 1..frames.size) {
            val nextPkg = if (i < frames.size) frames[i].pkg else null
            if (i == frames.size || nextPkg != curPkg) {
                val len = i - startIndex
                val color = iconInfoByPkg[curPkg]?.dominantColor ?: fallbackColor
                out.add(
                    AppRun(
                        pkg = curPkg,
                        startIndex = startIndex,
                        length = len,
                        color = color,
                    )
                )
                if (i < frames.size) {
                    curPkg = frames[i].pkg
                    startIndex = i
                }
            }
        }

        return out
    }

    private fun allocateRunPixels(
        runs: List<AppRun>,
        axisPx: Int,
        totalFrames: Int,
    ): IntArray {
        val n = runs.size
        val axis = max(1, axisPx)
        if (n <= 0) return IntArray(0)
        if (n >= axis) return IntArray(n) { 1 }

        val out = IntArray(n) { 1 }
        val remain = axis - n
        if (remain <= 0) return out

        val total = max(1, totalFrames)
        val frac = DoubleArray(n)
        var used = 0

        for (i in 0 until n) {
            val desired = remain.toDouble() * (runs[i].length.toDouble() / total.toDouble())
            val extra = desired.toInt()
            out[i] += extra
            used += extra
            frac[i] = desired - extra.toDouble()
        }

        var left = remain - used
        if (left > 0) {
            val idxs = (0 until n).toMutableList()
            idxs.sortWith { a, b ->
                val da = frac[a]
                val db = frac[b]
                when {
                    da < db -> 1
                    da > db -> -1
                    else -> 0
                }
            }

            var j = 0
            while (left > 0) {
                out[idxs[j % n]] += 1
                left--
                j++
            }
        }

        return out
    }

    private fun drawFrameToBitmap(
        canvas: Canvas,
        outputW: Int,
        outputH: Int,
        frame: Frame,
        overlayEnabled: Boolean,
        timeFmt: SimpleDateFormat,
        overlayPadding: Float,
        overlayTextPaint: Paint,
        overlayBgPaint: Paint,
        iconInfoByPkg: Map<String, IconInfo>,
        appIconSizePx: Float,
        imagePaint: Paint,
        nsfwMode: ReplayNsfwMode,
        nsfwLabelTextPaint: Paint,
        nsfwLabelBgPaint: Paint,
        nsfwDimPaint: Paint,
        nsfwTitleLayout: StaticLayout,
        nsfwSubtitleLayout: StaticLayout,
        nsfwTextLeftPx: Float,
        nsfwTitleTopPx: Float,
        nsfwSubtitleTopPx: Float,
        nsfwIconGlyph: String?,
        nsfwIconX: Float,
        nsfwIconBaselineY: Float,
        nsfwIconTextPaint: TextPaint?,
        nsfwBlurCanvas: Canvas,
        nsfwBlurBitmap: Bitmap,
        nsfwBlurPaint: Paint,
    ) {
        canvas.drawColor(Color.BLACK)

        if (frame.nsfw && nsfwMode == ReplayNsfwMode.MASK) {
            drawNsfwBlurMask(
                canvas = canvas,
                outputW = outputW,
                outputH = outputH,
                frame = frame,
                imagePaint = imagePaint,
                dimPaint = nsfwDimPaint,
                titleLayout = nsfwTitleLayout,
                subtitleLayout = nsfwSubtitleLayout,
                textLeftPx = nsfwTextLeftPx,
                titleTopPx = nsfwTitleTopPx,
                subtitleTopPx = nsfwSubtitleTopPx,
                iconGlyph = nsfwIconGlyph,
                iconX = nsfwIconX,
                iconBaselineY = nsfwIconBaselineY,
                iconTextPaint = nsfwIconTextPaint,
                blurCanvas = nsfwBlurCanvas,
                blurBitmap = nsfwBlurBitmap,
                blurPaint = nsfwBlurPaint,
            )
        } else {
            val shouldDrawSource = !(frame.nsfw && nsfwMode == ReplayNsfwMode.HIDE)
            if (shouldDrawSource) {
                val src = tryDecode(frame.path, outputW, outputH)
                if (src != null) {
                    try {
                        val sw = src.width.toFloat()
                        val sh = src.height.toFloat()
                        val scale = min(outputW / sw, outputH / sh)
                        val dw = sw * scale
                        val dh = sh * scale
                        val left = (outputW - dw) / 2f
                        val top = (outputH - dh) / 2f
                        val dst = RectF(left, top, left + dw, top + dh)
                        canvas.drawBitmap(src, null, dst, imagePaint)
                    } catch (_: Exception) {
                    } finally {
                        try {
                            src.recycle()
                        } catch (_: Exception) {
                        }
                    }
                }
            }

            if (frame.nsfw && nsfwMode == ReplayNsfwMode.HIDE) {
                drawNsfwLabel(
                    canvas = canvas,
                    outputW = outputW,
                    outputH = outputH,
                    text = "NSFW Hidden",
                    textPaint = nsfwLabelTextPaint,
                    bgPaint = nsfwLabelBgPaint,
                )
            }
        }

        if (overlayEnabled) {
            try {
                val tsStr = try {
                    timeFmt.format(java.util.Date(frame.tsMillis))
                } catch (_: Exception) {
                    frame.tsMillis.toString()
                }
                val icon = try {
                    iconInfoByPkg[frame.pkg]?.icon?.takeIf { !it.isRecycled }
                } catch (_: Exception) {
                    null
                }

                val showIcon = icon != null
                val text = if (showIcon) tsStr else if (frame.app.isBlank()) tsStr else "$tsStr  •  ${frame.app}"

                val textW = overlayTextPaint.measureText(text)
                val fm = overlayTextPaint.fontMetrics
                val textH = fm.descent - fm.ascent

                val outerPad = overlayPadding
                val innerPad = (overlayPadding / 2f).coerceAtLeast(1f)
                val gap = (overlayPadding / 2f).coerceAtLeast(2f)
                val iconSize = appIconSizePx.coerceAtLeast(1f)

                val contentH = max(textH, if (showIcon) iconSize else 0f)
                val contentW = textW + if (showIcon) (gap + iconSize) else 0f

                val bg = RectF(
                    outerPad,
                    outerPad,
                    outerPad + innerPad + contentW + innerPad,
                    outerPad + innerPad + contentH + innerPad,
                )

                val r = 8f * (overlayPadding / 12f)
                canvas.drawRoundRect(bg, r, r, overlayBgPaint)

                val contentLeft = bg.left + innerPad
                val contentTop = bg.top + innerPad
                val textY = contentTop + ((contentH - textH) / 2f) - fm.ascent
                canvas.drawText(text, contentLeft, textY, overlayTextPaint)

                if (icon != null) {
                    val iconLeft = contentLeft + textW + gap
                    val iconTop = contentTop + ((contentH - iconSize) / 2f)
                    val dst = RectF(iconLeft, iconTop, iconLeft + iconSize, iconTop + iconSize)
                    canvas.drawBitmap(icon, null, dst, null)
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun drawNsfwLabel(
        canvas: Canvas,
        outputW: Int,
        outputH: Int,
        text: String,
        textPaint: Paint,
        bgPaint: Paint,
    ) {
        val value = text.ifBlank { "NSFW" }
        val textW = textPaint.measureText(value)
        val fm = textPaint.fontMetrics
        val textH = fm.descent - fm.ascent
        val padX = (textPaint.textSize * 0.9f).coerceAtLeast(8f)
        val padY = (textPaint.textSize * 0.55f).coerceAtLeast(6f)
        val boxW = textW + padX * 2f
        val boxH = textH + padY * 2f
        val left = ((outputW.toFloat() - boxW) / 2f).coerceAtLeast(0f)
        val top = ((outputH.toFloat() - boxH) / 2f).coerceAtLeast(0f)
        val right = (left + boxW).coerceAtMost(outputW.toFloat())
        val bottom = (top + boxH).coerceAtMost(outputH.toFloat())
        val rect = RectF(left, top, right, bottom)
        val radius = (textPaint.textSize * 0.55f).coerceAtLeast(10f)

        canvas.drawRoundRect(rect, radius, radius, bgPaint)
        val baseline = rect.centerY() - (fm.ascent + fm.descent) / 2f
        canvas.drawText(value, rect.centerX(), baseline, textPaint)
    }

    private fun drawNsfwBlurMask(
        canvas: Canvas,
        outputW: Int,
        outputH: Int,
        frame: Frame,
        imagePaint: Paint,
        dimPaint: Paint,
        titleLayout: StaticLayout,
        subtitleLayout: StaticLayout,
        textLeftPx: Float,
        titleTopPx: Float,
        subtitleTopPx: Float,
        iconGlyph: String?,
        iconX: Float,
        iconBaselineY: Float,
        iconTextPaint: TextPaint?,
        blurCanvas: Canvas,
        blurBitmap: Bitmap,
        blurPaint: Paint,
    ) {
        blurCanvas.drawColor(Color.BLACK)

        val blurW = blurBitmap.width
        val blurH = blurBitmap.height
        val src = tryDecode(frame.path, blurW, blurH)
        if (src != null) {
            try {
                val sw = src.width.toFloat()
                val sh = src.height.toFloat()
                val scale = min(blurW / sw, blurH / sh)
                val dw = sw * scale
                val dh = sh * scale
                val left = (blurW - dw) / 2f
                val top = (blurH - dh) / 2f
                val dst = RectF(left, top, left + dw, top + dh)
                blurCanvas.drawBitmap(src, null, dst, imagePaint)
            } catch (_: Exception) {
            } finally {
                try {
                    src.recycle()
                } catch (_: Exception) {
                }
            }
        }

        canvas.drawBitmap(
            blurBitmap,
            null,
            RectF(0f, 0f, outputW.toFloat(), outputH.toFloat()),
            blurPaint,
        )
        canvas.drawRect(0f, 0f, outputW.toFloat(), outputH.toFloat(), dimPaint)

        if (iconGlyph != null && iconTextPaint != null) {
            canvas.drawText(iconGlyph, iconX, iconBaselineY, iconTextPaint)
        }

        canvas.save()
        try {
            canvas.translate(textLeftPx, titleTopPx)
            titleLayout.draw(canvas)
        } finally {
            canvas.restore()
        }

        canvas.save()
        try {
            canvas.translate(textLeftPx, subtitleTopPx)
            subtitleLayout.draw(canvas)
        } finally {
            canvas.restore()
        }
    }

    private fun tryDecode(path: String, targetW: Int, targetH: Int): Bitmap? {
        try {
            val b = File(path)
            if (!b.exists()) return null

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            val sample = calculateInSampleSize(bounds.outWidth, bounds.outHeight, targetW, targetH)
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            return BitmapFactory.decodeFile(path, opts)
        } catch (_: Exception) {
            return null
        }
    }

    private fun calculateInSampleSize(sw: Int, sh: Int, tw: Int, th: Int): Int {
        var inSample = 1
        if (sh > th || sw > tw) {
            var halfH = sh / 2
            var halfW = sw / 2
            while ((halfH / inSample) >= th && (halfW / inSample) >= tw) {
                inSample *= 2
            }
        }
        return max(1, inSample)
    }

    private fun drainEncoder(
        encoder: MediaCodec,
        muxer: MediaMuxer,
        bufferInfo: MediaCodec.BufferInfo,
        endOfStream: Boolean,
        onFormatChanged: (MediaFormat) -> Unit,
        onSample: (java.nio.ByteBuffer, MediaCodec.BufferInfo) -> Unit,
    ) {
        if (endOfStream) {
            try {
                encoder.signalEndOfInputStream()
            } catch (_: Exception) {
            }
        }
        while (true) {
            val status = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_USEC)
            when {
                status == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) break
                }
                status == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    onFormatChanged(encoder.outputFormat)
                }
                status >= 0 -> {
                    val encodedData = encoder.getOutputBuffer(status)
                    if (encodedData == null) {
                        encoder.releaseOutputBuffer(status, false)
                        continue
                    }
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        bufferInfo.size = 0
                    }
                    if (bufferInfo.size != 0) {
                        encodedData.position(bufferInfo.offset)
                        encodedData.limit(bufferInfo.offset + bufferInfo.size)
                        onSample(encodedData, bufferInfo)
                    }
                    encoder.releaseOutputBuffer(status, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                }
                else -> {
                    // ignore
                }
            }
        }
    }
}
