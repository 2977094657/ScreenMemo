package com.fqyw.screen_memo.mcp

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
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.fqyw.screen_memo.MainActivity
import com.fqyw.screen_memo.R
import com.fqyw.screen_memo.logging.FileLogger
import java.net.NetworkInterface
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean

class McpServerService : Service() {
    companion object {
        private const val TAG = "McpServerService"
        const val PORT = 37621
        private const val ACTION_START = "com.fqyw.screen_memo.mcp.START"
        private const val ACTION_STOP = "com.fqyw.screen_memo.mcp.STOP"
        private const val PREFS_NAME = "screenmemo_mcp"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_TOKEN = "token"
        private const val KEY_LAST_ERROR = "last_error"
        private const val KEY_LAST_STARTED_AT = "last_started_at"
        private const val NOTIFICATION_ID = 37621
        private const val CHANNEL_ID = "screenmemo_mcp_server"

        private val running = AtomicBoolean(false)

        @Volatile
        private var currentServer: McpHttpServer? = null

        fun startServer(context: Context): Map<String, Any?> {
            val appCtx = context.applicationContext
            ensureToken(appCtx)
            prefs(appCtx).edit()
                .putBoolean(KEY_ENABLED, true)
                .remove(KEY_LAST_ERROR)
                .apply()
            val intent = Intent(appCtx, McpServerService::class.java).apply {
                action = ACTION_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appCtx.startForegroundService(intent)
                } else {
                    appCtx.startService(intent)
                }
            } catch (e: Exception) {
                prefs(appCtx).edit()
                    .putBoolean(KEY_ENABLED, false)
                    .putString(KEY_LAST_ERROR, e.message ?: e.javaClass.simpleName)
                    .apply()
            }
            return getStatus(appCtx)
        }

        fun restoreIfEnabled(context: Context) {
            val appCtx = context.applicationContext
            if (!prefs(appCtx).getBoolean(KEY_ENABLED, false)) return
            try {
                val intent = Intent(appCtx, McpServerService::class.java).apply {
                    action = ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appCtx.startForegroundService(intent)
                } else {
                    appCtx.startService(intent)
                }
            } catch (e: Exception) {
                FileLogger.e(TAG, "Restore MCP server failed: ${e.message}")
                prefs(appCtx).edit()
                    .putString(KEY_LAST_ERROR, e.message ?: e.javaClass.simpleName)
                    .apply()
            }
        }

        fun stopServer(context: Context): Map<String, Any?> {
            val appCtx = context.applicationContext
            prefs(appCtx).edit().putBoolean(KEY_ENABLED, false).apply()
            try {
                appCtx.startService(Intent(appCtx, McpServerService::class.java).apply { action = ACTION_STOP })
            } catch (_: Exception) {
                currentServer?.stop()
                currentServer = null
                running.set(false)
            }
            return getStatus(appCtx)
        }

        fun getStatus(context: Context): Map<String, Any?> {
            val appCtx = context.applicationContext
            val token = ensureToken(appCtx)
            val ip = localLanIp()
            val isRunning = running.get() && currentServer?.isRunning() == true
            return mapOf(
                "enabled" to prefs(appCtx).getBoolean(KEY_ENABLED, false),
                "running" to isRunning,
                "port" to PORT,
                "endpoint" to if (ip.isNotBlank()) "http://$ip:$PORT/mcp" else "",
                "lanIp" to ip,
                "token" to token,
                "lastError" to prefs(appCtx).getString(KEY_LAST_ERROR, null),
                "lastStartedAt" to prefs(appCtx).getLong(KEY_LAST_STARTED_AT, 0L),
            )
        }

        fun statusForTool(context: Context): Map<String, Any?> {
            val status = getStatus(context).toMutableMap()
            status["token"] = "***"
            return status
        }

        fun resetToken(context: Context): Map<String, Any?> {
            val appCtx = context.applicationContext
            val token = generateToken()
            prefs(appCtx).edit()
                .putString(KEY_TOKEN, token)
                .remove(KEY_LAST_ERROR)
                .apply()
            return getStatus(appCtx)
        }

        private fun ensureToken(context: Context): String {
            val sp = prefs(context)
            val existing = sp.getString(KEY_TOKEN, null)?.trim().orEmpty()
            if (existing.isNotEmpty()) return existing
            val next = generateToken()
            sp.edit().putString(KEY_TOKEN, next).apply()
            return next
        }

        private fun prefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

        private fun generateToken(): String {
            val bytes = ByteArray(24)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString(separator = "") { "%02x".format(it) }
        }

        private fun localLanIp(): String {
            return try {
                val interfaces = NetworkInterface.getNetworkInterfaces()
                for (networkInterface in interfaces) {
                    if (!networkInterface.isUp || networkInterface.isLoopback) continue
                    val addresses = networkInterface.inetAddresses
                    for (address in addresses) {
                        if (address.isLoopbackAddress || address.isLinkLocalAddress) continue
                        val host = address.hostAddress ?: continue
                        if (!host.contains(":") && isPrivateIpv4(host)) return host
                    }
                }
                ""
            } catch (_: Exception) {
                ""
            }
        }

        private fun isPrivateIpv4(host: String): Boolean {
            val nums = host.split('.').map { it.toIntOrNull() ?: return false }
            if (nums.size != 4 || nums.any { it !in 0..255 }) return false
            return nums[0] == 10 ||
                nums[0] == 192 && nums[1] == 168 ||
                nums[0] == 172 && nums[1] in 16..31
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_STOP -> {
                stopInternal()
                stopSelf()
                START_NOT_STICKY
            }
            else -> {
                startInternal()
                START_STICKY
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopInternal()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        FileLogger.i(TAG, "MCP foreground service task removed; keep service state enabled")
        if (prefs(this).getBoolean(KEY_ENABLED, false)) {
            try {
                val intent = Intent(applicationContext, McpServerService::class.java).apply {
                    action = ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(intent)
                } else {
                    applicationContext.startService(intent)
                }
            } catch (e: Exception) {
                FileLogger.e(TAG, "MCP restart after task removed failed: ${e.message}")
                prefs(this).edit()
                    .putString(KEY_LAST_ERROR, e.message ?: e.javaClass.simpleName)
                    .apply()
            }
        }
    }

    private fun startInternal() {
        try {
            startAsForeground()
            if (currentServer?.isRunning() == true) {
                running.set(true)
                updateNotification()
                return
            }
            val server = McpHttpServer(
                context = applicationContext,
                port = PORT,
                tokenProvider = { prefs(applicationContext).getString(KEY_TOKEN, "").orEmpty() },
            )
            server.start()
            currentServer = server
            running.set(true)
            prefs(this).edit()
                .putBoolean(KEY_ENABLED, true)
                .remove(KEY_LAST_ERROR)
                .putLong(KEY_LAST_STARTED_AT, System.currentTimeMillis())
                .apply()
            updateNotification()
        } catch (e: Exception) {
            val message = e.message ?: e.javaClass.simpleName
            FileLogger.e(TAG, "MCP server start failed: $message")
            prefs(this).edit()
                .putBoolean(KEY_ENABLED, false)
                .putString(KEY_LAST_ERROR, message)
                .apply()
            running.set(false)
            try {
                currentServer?.stop()
            } catch (_: Exception) {
            }
            currentServer = null
            stopSelf()
        }
    }

    private fun stopInternal() {
        try {
            currentServer?.stop()
        } catch (_: Exception) {
        }
        currentServer = null
        running.set(false)
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {
        }
    }

    private fun buildNotification(): Notification {
        val status = getStatus(this)
        val endpoint = (status["endpoint"] as? String).orEmpty()
        val text = if (endpoint.isNotBlank()) {
            endpoint
        } else {
            getString(R.string.mcp_server_notification_port_text, PORT)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            },
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.mcp_server_notification_title))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.mcp_server_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.mcp_server_channel_desc)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }
}
