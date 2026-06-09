package com.fqyw.screen_memo.capture

import com.fqyw.screen_memo.database.ScreenshotDatabaseHelper
import com.fqyw.screen_memo.diagnostics.OEMCompatibilityHelper
import com.fqyw.screen_memo.diagnostics.RuntimeDiagnostics
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.MainActivity
import com.fqyw.screen_memo.mcp.McpServerService
import com.fqyw.screen_memo.segment.SegmentSummaryManager
import com.fqyw.screen_memo.service.RestartReceiver
import com.fqyw.screen_memo.service.ServiceStateManager
import com.fqyw.screen_memo.settings.PerAppSettingsBridge
import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.app.KeyguardManager
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.system.Os
 
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.view.Surface
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.timer
import android.os.IBinder
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.common.InputImage
import com.google.android.gms.tasks.Tasks
import com.fqyw.screen_memo.settings.UserSettingsKeysNative
import com.fqyw.screen_memo.settings.UserSettingsStorage
import org.json.JSONArray
import org.json.JSONObject

class ScreenCaptureAccessibilityService : AccessibilityService() {
    
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val PERF_TAG = "ScreenshotPerf"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "screen_capture_channel"
        private const val REQUEST_CODE = 1000
        private const val RESTART_REQUEST_CODE = 2000

        var instance: ScreenCaptureAccessibilityService? = null
        var isServiceRunning = false
    }

    // ... [existing fields remain unchanged up to line ~280 - keeping all existing code]

    // ===================== Activity 黑名单相关 =====================
    @Volatile private var currentActivityClassName: String? = null

    /**
     * 检查指定应用的当前 Activity 是否在黑名单中。
     * 黑名单存储在每应用设置数据库 settings.db 的 activity_blacklist 键中，
     * 值为 JSONArray of fully-qualified class names。
     */
    private fun isCurrentActivityBlacklisted(packageName: String): Boolean {
        val className = currentActivityClassName ?: return false
        if (className.isBlank()) return false
        val blacklist = PerAppSettingsBridge.readActivityBlacklist(this, packageName)
        if (blacklist.isEmpty()) return false
        val matched = blacklist.any { it == className }
        if (matched) {
            FileLogger.i(TAG, "Activity 黑名单命中: $packageName/$className，跳过截屏")
        }
        return matched
    }
}
