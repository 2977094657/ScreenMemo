package com.fqyw.screen_memo

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.app.AlarmManager
import android.app.PendingIntent
import android.os.SystemClock
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.timer
import java.util.Timer

/**
 * AccessibilityService看门狗
 * 用于检测服务真实状态并实现自动重启机制
 */
object AccessibilityServiceWatchdog {
    
    private const val TAG = "AccessibilityWatchdog"
    private const val WATCHDOG_INTERVAL = 30000L // 30秒检查一次
    private const val HEARTBEAT_TIMEOUT = 60000L // 60秒心跳超时
    private const val RESTART_ALARM_REQUEST_CODE = 3000
    
    private var watchdogTimer: Timer? = null
    private var isWatchdogRunning = false
    private val lastHeartbeat = AtomicLong(0)
    private val handler = Handler(Looper.getMainLooper())
    
    /**
     * 服务状态检测结果
     */
    data class ServiceStatus(
        val isSystemEnabled: Boolean,        // 系统设置中是否启用
        val isInstanceExists: Boolean,       // 静态实例是否存在
        val isProcessAlive: Boolean,         // 进程是否存活
        val isHeartbeatValid: Boolean,       // 心跳是否有效
        val isFunctional: Boolean           // 功能是否正常
    ) {
        val isReallyRunning: Boolean
            get() = isSystemEnabled && (isFunctional || isHeartbeatValid)
            
        val needsRestart: Boolean
            get() = isSystemEnabled && !(isFunctional || isHeartbeatValid)
    }
    
    /**
     * 启动看门狗监控
     */
    fun startWatchdog(context: Context) {
        if (isWatchdogRunning) {
            FileLogger.w(TAG, "看门狗已在运行，跳过启动")
            return
        }
        
        try {
            FileLogger.e(TAG, "=== 启动AccessibilityService看门狗 ===")
            isWatchdogRunning = true
            
            // 启动定时检查
            watchdogTimer = timer(
                name = "AccessibilityWatchdog",
                daemon = true,
                period = WATCHDOG_INTERVAL
            ) {
                performHealthCheck(context)
            }
            
            FileLogger.e(TAG, "看门狗启动成功，检查间隔: ${WATCHDOG_INTERVAL / 1000}秒")
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动看门狗失败", e)
            isWatchdogRunning = false
        }
    }
    
    /**
     * 停止看门狗监控
     */
    fun stopWatchdog() {
        try {
            isWatchdogRunning = false
            watchdogTimer?.cancel()
            watchdogTimer = null
            FileLogger.i(TAG, "看门狗已停止")
        } catch (e: Exception) {
            FileLogger.e(TAG, "停止看门狗失败", e)
        }
    }
    
    /**
     * 更新心跳时间戳
     * 应该在AccessibilityService的主要方法中调用
     */
    fun updateHeartbeat() {
        lastHeartbeat.set(System.currentTimeMillis())
        FileLogger.d(TAG, "心跳已更新: ${System.currentTimeMillis()}")
    }
    
    /**
     * 执行健康检查
     */
    private fun performHealthCheck(context: Context) {
        try {
            val status = checkServiceStatus(context)
            
            FileLogger.i(TAG, "=== 服务健康检查 ===")
            FileLogger.i(TAG, "系统启用: ${status.isSystemEnabled}")
            FileLogger.i(TAG, "实例存在: ${status.isInstanceExists}")
            FileLogger.i(TAG, "进程存活: ${status.isProcessAlive}")
            FileLogger.i(TAG, "心跳有效: ${status.isHeartbeatValid}")
            FileLogger.i(TAG, "功能正常: ${status.isFunctional}")
            FileLogger.i(TAG, "真实运行: ${status.isReallyRunning}")
            FileLogger.i(TAG, "需要重启: ${status.needsRestart}")
            
            // 更新状态到ServiceStateManager
            ServiceStateManager.setAccessibilityServiceRunning(context, status.isReallyRunning)
            
            if (status.needsRestart) {
                FileLogger.w(TAG, "检测到服务需要重启，开始重启流程")
                attemptServiceRestart(context, status)
            }
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "健康检查失败", e)
        }
    }
    
    /**
     * 综合检查服务状态
     */
    fun checkServiceStatus(context: Context): ServiceStatus {
        return try {
            val isSystemEnabled = isAccessibilityServiceEnabledInSystem(context)
            val isInstanceExists = ScreenCaptureAccessibilityService.instance != null
            val isProcessAlive = checkProcessAlive(context)
            val isHeartbeatValid = checkHeartbeatValid()
            val isFunctional = checkServiceFunctional(context)
            
            ServiceStatus(
                isSystemEnabled = isSystemEnabled,
                isInstanceExists = isInstanceExists,
                isProcessAlive = isProcessAlive,
                isHeartbeatValid = isHeartbeatValid,
                isFunctional = isFunctional
            )
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查服务状态失败", e)
            ServiceStatus(false, false, false, false, false)
        }
    }
    
    /**
     * 检查AccessibilityService是否在系统中启用
     */
    private fun isAccessibilityServiceEnabledInSystem(context: Context): Boolean {
        return try {
            // 方法1: 通过Settings.Secure检查
            val accessibilityEnabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            ) == 1
            
            if (!accessibilityEnabled) {
                return false
            }
            
            val enabledServicesRaw = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""

            val targetPkg = context.packageName
            val targetCls = ScreenCaptureAccessibilityService::class.java.name

            // 对 Settings 中的条目进行规范化后再比对，避免短类名误判
            var isEnabledInSettings = false
            if (enabledServicesRaw.isNotEmpty()) {
                val colonSplitter = android.text.TextUtils.SimpleStringSplitter(':')
                colonSplitter.setString(enabledServicesRaw)
                while (colonSplitter.hasNext()) {
                    val entry = colonSplitter.next()
                    val cn = ComponentName.unflattenFromString(entry)
                    if (cn != null) {
                        val pkg = cn.packageName
                        val cls = cn.className
                        if (pkg.equals(targetPkg, true) && cls.equals(targetCls, true)) {
                            isEnabledInSettings = true
                            break
                        }
                    } else {
                        val expectedFull = "$targetPkg/$targetCls"
                        val expectedShort = "$targetPkg/.${ScreenCaptureAccessibilityService::class.java.simpleName}"
                        if (entry.equals(expectedFull, true) || entry.equals(expectedShort, true)) {
                            isEnabledInSettings = true
                            break
                        }
                    }
                }
            }

            // 方法2: 通过AccessibilityManager验证
            val accessibilityManager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            val enabledServicesList = accessibilityManager.getEnabledAccessibilityServiceList(
                AccessibilityServiceInfo.FEEDBACK_ALL_MASK
            )
            
            val isEnabledInManager = enabledServicesList.any { serviceInfo ->
                val resolveInfo = serviceInfo.resolveInfo
                resolveInfo.serviceInfo.packageName == context.packageName &&
                resolveInfo.serviceInfo.name == ScreenCaptureAccessibilityService::class.java.name
            }
            
            val result = isEnabledInSettings || isEnabledInManager
            FileLogger.d(TAG, "系统启用检查 - Settings: $isEnabledInSettings, Manager: $isEnabledInManager, 最终: $result")
            
            return result
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查系统启用状态失败", e)
            false
        }
    }
    
    /**
     * 检查进程是否存活
     */
    private fun checkProcessAlive(context: Context): Boolean {
        return try {
            // 获取保存的PID
            val states = ServiceStateManager.getAllStates(context)
            val savedPid = states["processId"] as? Int ?: -1
            
            if (savedPid <= 0) {
                FileLogger.d(TAG, "未找到有效的保存PID")
                return false
            }
            
            // 检查当前进程PID是否匹配
            val currentPid = Process.myPid()
            
            // 通过ActivityManager验证进程存在
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningProcesses = activityManager.runningAppProcesses ?: emptyList()
            
            val processExists = runningProcesses.any { processInfo ->
                processInfo.pid == savedPid && processInfo.processName.startsWith(context.packageName)
            }
            
            // 如果保存的PID与当前PID不一致但进程存在，记录但不直接判死
            if (savedPid != currentPid && processExists) {
                FileLogger.w(TAG, "PID不一致但进程存在 - 保存: $savedPid, 当前: $currentPid")
            }
            
            FileLogger.d(TAG, "进程存活检查 - PID: $savedPid, 存在: $processExists")
            return processExists
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查进程存活失败", e)
            false
        }
    }
    
    /**
     * 检查心跳是否有效
     */
    private fun checkHeartbeatValid(): Boolean {
        val currentTime = System.currentTimeMillis()
        val lastBeat = lastHeartbeat.get()
        
        if (lastBeat == 0L) {
            FileLogger.d(TAG, "尚未收到心跳信号")
            return false
        }
        
        val timeSinceLastBeat = currentTime - lastBeat
        val isValid = timeSinceLastBeat < HEARTBEAT_TIMEOUT
        
        FileLogger.d(TAG, "心跳检查 - 距上次: ${timeSinceLastBeat}ms, 有效: $isValid")
        return isValid
    }
    
    /**
     * 检查服务功能是否正常
     */
    private fun checkServiceFunctional(context: Context): Boolean {
        return try {
            val service = ScreenCaptureAccessibilityService.instance
            if (service == null) {
                FileLogger.d(TAG, "服务实例不存在，功能不正常")
                return false
            }
            
            // 检查服务是否能正常响应
            val isRunning = ScreenCaptureAccessibilityService.isServiceRunning
            
            // 可以添加更多功能性检查，如截屏能力测试等
            FileLogger.d(TAG, "功能检查 - 服务运行标志: $isRunning")
            return isRunning
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "检查服务功能失败", e)
            false
        }
    }
    
    /**
     * 尝试重启服务
     */
    private fun attemptServiceRestart(context: Context, status: ServiceStatus) {
        try {
            FileLogger.e(TAG, "=== 开始服务重启流程 ===")
            
            // 1. 清理当前状态
            if (status.isInstanceExists) {
                try {
                    val service = ScreenCaptureAccessibilityService.instance
                    service?.onDestroy()
                } catch (e: Exception) {
                    FileLogger.w(TAG, "清理服务实例失败: ${e.message}")
                }
            }
            
            // 2. 更新状态
            ServiceStateManager.setAccessibilityServiceRunning(context, false)
            
            // 3. 通过多种方式触发重启
            triggerServiceRestart(context)
            
            // 4. 设置备用重启闹钟
            scheduleRestartAlarm(context)
            
            FileLogger.e(TAG, "=== 服务重启流程已触发 ===")
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "重启服务失败", e)
        }
    }
    
    /**
     * 触发服务重启
     */
    private fun triggerServiceRestart(context: Context) {
        try {
            // 方法1: 启动ScreenCaptureService前台服务
            val serviceIntent = Intent(context, ScreenCaptureService::class.java)
            try {
                context.startForegroundService(serviceIntent)
                FileLogger.i(TAG, "前台服务重启触发成功")
            } catch (e: Exception) {
                FileLogger.w(TAG, "前台服务重启触发失败: ${e.message}")
            }
            
            // 方法2: 发送重启广播
            val restartIntent = Intent(context, RestartReceiver::class.java).apply {
                action = RestartReceiver.ACTION_RESTART_SERVICE
            }
            try {
                context.sendBroadcast(restartIntent)
                FileLogger.i(TAG, "重启广播发送成功")
            } catch (e: Exception) {
                FileLogger.w(TAG, "重启广播发送失败: ${e.message}")
            }
            
            // 方法3: 启动MainActivity进行检查
            val mainIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("check_service_only", true)
            }
            try {
                context.startActivity(mainIntent)
                FileLogger.i(TAG, "MainActivity检查启动成功")
            } catch (e: Exception) {
                FileLogger.w(TAG, "MainActivity检查启动失败: ${e.message}")
            }
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "触发服务重启失败", e)
        }
    }
    
    /**
     * 设置重启闹钟
     */
    private fun scheduleRestartAlarm(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val restartIntent = Intent(context, RestartReceiver::class.java).apply {
                action = RestartReceiver.ACTION_RESTART_SERVICE
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                RESTART_ALARM_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // 30秒后触发重启
            val triggerTime = SystemClock.elapsedRealtime() + 30000
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            }
            
            FileLogger.i(TAG, "重启闹钟已设置，30秒后触发")
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置重启闹钟失败", e)
        }
    }
    
    /**
     * 获取服务状态摘要（用于调试）
     */
    fun getStatusSummary(context: Context): String {
        return try {
            val status = checkServiceStatus(context)
            """
            |=== AccessibilityService状态摘要 ===
            |系统启用: ${status.isSystemEnabled}
            |实例存在: ${status.isInstanceExists}
            |进程存活: ${status.isProcessAlive}
            |心跳有效: ${status.isHeartbeatValid}
            |功能正常: ${status.isFunctional}
            |真实运行: ${status.isReallyRunning}
            |需要重启: ${status.needsRestart}
            |看门狗运行: $isWatchdogRunning
            |最后心跳: ${if (lastHeartbeat.get() > 0) java.util.Date(lastHeartbeat.get()) else "无"}
            |===============================
            """.trimMargin()
        } catch (e: Exception) {
            "获取状态摘要失败: ${e.message}"
        }
    }
}