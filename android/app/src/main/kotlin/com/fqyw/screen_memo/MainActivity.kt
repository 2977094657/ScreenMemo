package com.fqyw.screen_memo

import android.app.Activity
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.database.ContentObserver
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.fqyw.screen_memo/accessibility"
        private const val REQUEST_MEDIA_PROJECTION = 1001
        private const val REQUEST_ACCESSIBILITY_SETTINGS = 1002
    }

    private lateinit var methodChannel: MethodChannel
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var accessibilityObserver: ContentObserver? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var accessibilityStateMonitor: AccessibilityStateMonitor? = null
    private var mediaProjectionRequestReceiver: BroadcastReceiver? = null
    private var screenshotSavedReceiver: BroadcastReceiver? = null
    private var accessibilityServiceBinder: IAccessibilityServiceAidl? = null
    
    private val accessibilityServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            FileLogger.e(TAG, "AccessibilityService连接成功")
            accessibilityServiceBinder = IAccessibilityServiceAidl.Stub.asInterface(service)
        }
        
        override fun onServiceDisconnected(name: ComponentName?) {
            FileLogger.e(TAG, "AccessibilityService连接断开")
            accessibilityServiceBinder = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 初始化文件日志
        FileLogger.init(this)
        FileLogger.writeSystemInfo(this)

        // 添加基础日志输出
        FileLogger.e(TAG, "=== MainActivity configureFlutterEngine 开始 ===")
        FileLogger.e(TAG, "当前进程ID: ${android.os.Process.myPid()}")
        FileLogger.e(TAG, "当前时间: ${System.currentTimeMillis()}")
        FileLogger.e(TAG, "日志文件路径: ${FileLogger.getLogFilePath()}")

        // 初始化媒体投影管理器
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // 创建方法通道
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAccessibilityPermission" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibilityPermission" -> {
                    requestAccessibilityPermission()
                    result.success(null)
                }
                "checkUsageStatsPermission" -> {
                    result.success(isUsageStatsPermissionGranted())
                }
                "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission()
                    result.success(null)
                }
                "isServiceRunning" -> {
                    // 使用增强的看门狗状态检测
                    val watchdogStatus = AccessibilityServiceWatchdog.checkServiceStatus(this)
                    val running = watchdogStatus.isReallyRunning
                    
                    FileLogger.i(TAG, AccessibilityServiceWatchdog.getStatusSummary(this))
                    
                    // 如果系统中已启用但实际不运行，记录详细信息并尝试触发连接
                    if (watchdogStatus.needsRestart) {
                        FileLogger.e(TAG, "检测到服务需要重启，状态详情：")
                        FileLogger.e(TAG, "- 系统启用: ${watchdogStatus.isSystemEnabled}")
                        FileLogger.e(TAG, "- 实例存在: ${watchdogStatus.isInstanceExists}")
                        FileLogger.e(TAG, "- 进程存活: ${watchdogStatus.isProcessAlive}")
                        FileLogger.e(TAG, "- 心跳有效: ${watchdogStatus.isHeartbeatValid}")
                        FileLogger.e(TAG, "- 功能正常: ${watchdogStatus.isFunctional}")
                        
                        triggerAccessibilityServiceConnection()
                    }
                    
                    result.success(running)
                }
                "startForegroundService" -> {
                    startForegroundService()
                    result.success(null)
                }
                "stopForegroundService" -> {
                    stopForegroundService()
                    result.success(null)
                }
                "startScreenCapture" -> {
                    FileLogger.e(TAG, "=== 收到startScreenCapture请求 ===")
                    val success = startScreenCapture()
                    FileLogger.e(TAG, "=== startScreenCapture结果: $success ===")
                    result.success(success)
                }
                "stopScreenCapture" -> {
                    FileLogger.e(TAG, "=== 收到stopScreenCapture请求 ===")
                    stopScreenCapture()
                    result.success(null)
                }
                "startTimedScreenshot" -> {
                    val interval = call.argument<Int>("interval") ?: 5
                    FileLogger.e(TAG, "=== 收到startTimedScreenshot请求，间隔: ${interval}秒 ===")
                    val success = startTimedScreenshot(interval)
                    FileLogger.e(TAG, "=== startTimedScreenshot结果: $success ===")
                    result.success(success)
                }
                "stopTimedScreenshot" -> {
                    FileLogger.e(TAG, "=== 收到stopTimedScreenshot请求 ===")
                    stopTimedScreenshot()
                    result.success(null)
                }
                "captureScreen" -> {
                    FileLogger.e(TAG, "=== 收到captureScreen请求 ===")
                    val filePath = captureScreen()
                    FileLogger.e(TAG, "=== captureScreen结果: $filePath ===")
                    result.success(filePath)
                }
                "checkPermissionGuideNeeded" -> {
                    result.success(PermissionGuideHelper.shouldShowPermissionGuide(this))
                }
                "getPermissionGuideText" -> {
                    result.success(PermissionGuideHelper.getPermissionGuideText(this))
                }
                "openAppDetailsSettings" -> {
                    result.success(PermissionGuideHelper.openAppDetailsSettings(this))
                }
                "openBatteryOptimizationSettings" -> {
                    result.success(PermissionGuideHelper.openBatteryOptimizationSettings(this))
                }
                "openAutoStartSettings" -> {
                    result.success(PermissionGuideHelper.openAutoStartSettings(this))
                }
                "markPermissionConfigured" -> {
                    val permissionType = call.argument<String>("type") ?: "all"
                    PermissionGuideHelper.markPermissionConfigured(this, permissionType)
                    result.success(true)
                }
                "getPermissionStatus" -> {
                    result.success(PermissionGuideHelper.checkPermissionStatus(this))
                }
                "getPermissionReport" -> {
                    result.success(PermissionGuideHelper.generatePermissionReport(this))
                }
                "getDeviceInfo" -> {
                    result.success(OEMCompatibilityHelper.getDeviceInfo())
                }
                "insertScreenshotRecord" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: ""
                    val filePath = call.argument<String>("filePath") ?: ""
                    val captureTime = call.argument<Long>("captureTime") ?: System.currentTimeMillis()
                    
                    FileLogger.i(TAG, "收到截图记录插入请求: $appName - $filePath")
                    
                    // 通知Flutter端插入数据库记录
                    methodChannel.invokeMethod("onScreenshotSaved", mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "filePath" to filePath,
                        "captureTime" to captureTime
                    ))
                    
                    result.success(true)
                }
                "testAutoStartPermission" -> {
                    result.success(testAutoStartPermission())
                }
                "isServiceRunning" -> {
                    // 使用增强的看门狗状态检测
                    val watchdogStatus = AccessibilityServiceWatchdog.checkServiceStatus(this)
                    val running = watchdogStatus.isReallyRunning
                    
                    FileLogger.i(TAG, AccessibilityServiceWatchdog.getStatusSummary(this))
                    
                    // 如果系统中已启用但实际不运行，记录详细信息并尝试触发连接
                    if (watchdogStatus.needsRestart) {
                        FileLogger.e(TAG, "检测到服务需要重启，状态详情：")
                        FileLogger.e(TAG, "- 系统启用: ${watchdogStatus.isSystemEnabled}")
                        FileLogger.e(TAG, "- 实例存在: ${watchdogStatus.isInstanceExists}")
                        FileLogger.e(TAG, "- 进程存活: ${watchdogStatus.isProcessAlive}")
                        FileLogger.e(TAG, "- 心跳有效: ${watchdogStatus.isHeartbeatValid}")
                        FileLogger.e(TAG, "- 功能正常: ${watchdogStatus.isFunctional}")
                        
                        triggerAccessibilityServiceConnection()
                    }
                    
                    result.success(running)
                }
                "getExternalFilesDir" -> {
                    val subDir = call.argument<String>("subDir")
                    val path = getExternalFilesDirPath(subDir)
                    result.success(path)
                }
                "checkServiceHealth" -> {
                    // 手动触发看门狗健康检查
                    val watchdogStatus = AccessibilityServiceWatchdog.checkServiceStatus(this)
                    val statusSummary = AccessibilityServiceWatchdog.getStatusSummary(this)
                    
                    FileLogger.i(TAG, "手动健康检查结果：")
                    FileLogger.i(TAG, statusSummary)
                    
                    result.success(mapOf(
                        "isReallyRunning" to watchdogStatus.isReallyRunning,
                        "needsRestart" to watchdogStatus.needsRestart,
                        "isSystemEnabled" to watchdogStatus.isSystemEnabled,
                        "isInstanceExists" to watchdogStatus.isInstanceExists,
                        "isProcessAlive" to watchdogStatus.isProcessAlive,
                        "isHeartbeatValid" to watchdogStatus.isHeartbeatValid,
                        "isFunctional" to watchdogStatus.isFunctional,
                        "statusSummary" to statusSummary
                    ))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 设置无障碍权限监听
        setupAccessibilityObserver()

        // 设置MediaProjection权限请求广播接收器
        setupMediaProjectionRequestReceiver()

        // 设置截图保存通知广播接收器
        setupScreenshotSavedReceiver()

        // 启动辅助功能状态监听
        accessibilityStateMonitor = AccessibilityStateMonitor(this)
        accessibilityStateMonitor?.startMonitoring()

        // 启动调试监控
        FileLogger.e(TAG, "=== 准备启动调试监控 ===")
        try {
            ServiceDebugHelper.performFullStatusCheck(this)

            // 检查AccessibilityService是否在系统中启用
            if (!ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(this)) {
                FileLogger.e(TAG, "=== AccessibilityService未在系统中启用，需要手动启用 ===")
                // 只记录日志，不自动打开设置页面
                FileLogger.e(TAG, "=== 请手动在设置中启用AccessibilityService ===")
            } else {
                FileLogger.e(TAG, "=== AccessibilityService已在系统中启用 ===")
            }

            FileLogger.e(TAG, "=== 调试监控启动成功 ===")
        } catch (e: Exception) {
            FileLogger.e(TAG, "=== 调试监控启动失败 ===", e)
        }
        // ServiceDebugHelper.startStatusMonitoring(this, 30000) // 每30秒检查一次（可选）
        
        // 调度JobService保活
        scheduleKeepAliveJob()
        
        // 启动守护服务
        startDaemonService()
        
        // 绑定AccessibilityService
        bindAccessibilityService()
        
        // 检查是否是静默启动
        if (intent?.getBooleanExtra("check_service_only", false) == true) {
            FileLogger.e(TAG, "静默启动模式，仅检查服务")
            finish()
        }

        FileLogger.e(TAG, "=== MainActivity configureFlutterEngine 完成 ===")
    }

    /**
     * 检查无障碍服务是否已启用
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        val accessibilityEnabled = try {
            Settings.Secure.getInt(
                contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED
            )
        } catch (e: Settings.SettingNotFoundException) {
            0
        }

        if (accessibilityEnabled == 1) {
            val services = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            // 简化版本，检查包名即可
            val serviceName = packageName
            return services?.contains(serviceName) == true
        }

        return false
    }

    /**
     * 请求无障碍服务权限
     */
    private fun requestAccessibilityPermission() {
        try {
            FileLogger.e(TAG, "=== 准备打开AccessibilityService设置页面 ===")
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            startActivityForResult(intent, REQUEST_ACCESSIBILITY_SETTINGS)
            FileLogger.e(TAG, "=== AccessibilityService设置页面已打开 ===")
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开AccessibilityService设置页面失败", e)
        }
    }

    /**
     * 请求媒体投影权限
     */
    private fun requestMediaProjectionPermission() {
        val intent = mediaProjectionManager?.createScreenCaptureIntent()
        if (intent != null) {
            startActivityForResult(intent, REQUEST_MEDIA_PROJECTION)
        }
    }

    /**
     * 启动前台服务
     */
    private fun startForegroundService() {
        Log.d(TAG, "启动前台服务（简化版本）")
        // 简化版本，只记录日志
    }

    /**
     * 停止前台服务
     */
    private fun stopForegroundService() {
        Log.d(TAG, "停止前台服务（简化版本）")
        // 简化版本，只记录日志
    }

    /**
     * 设置无障碍权限监听
     */
    private fun setupAccessibilityObserver() {
        accessibilityObserver = object : ContentObserver(mainHandler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                Log.d(TAG, "检测到无障碍设置变化: $uri")

                // 延迟检查，确保设置已经生效
                mainHandler.postDelayed({
                    checkAndNotifyAccessibilityChange()
                }, 500)
            }
        }

        // 监听无障碍服务启用状态
        contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.ACCESSIBILITY_ENABLED),
            false,
            accessibilityObserver!!
        )

        // 监听启用的无障碍服务列表
        contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES),
            false,
            accessibilityObserver!!
        )

        Log.d(TAG, "无障碍权限监听已设置")
    }

    /**
     * 检查并通知无障碍权限变化
     */
    private fun checkAndNotifyAccessibilityChange() {
        val currentEnabled = isAccessibilityServiceEnabled()
        val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
        val previousEnabled = sharedPrefs.getBoolean("accessibility_enabled", false)

        if (currentEnabled != previousEnabled) {
            Log.d(TAG, "无障碍权限状态变化: $previousEnabled -> $currentEnabled")

            // 保存新状态
            sharedPrefs.edit().putBoolean("accessibility_enabled", currentEnabled).apply()

            // 通知Flutter端
            methodChannel.invokeMethod("onAccessibilityResult", mapOf(
                "enabled" to currentEnabled
            ))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQUEST_MEDIA_PROJECTION -> {
                Log.d(TAG, "媒体投影权限结果: resultCode=$resultCode")
                if (resultCode == Activity.RESULT_OK && data != null) {
                    // 保存权限状态
                    val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                    sharedPrefs.edit().putBoolean("media_projection_granted", true).apply()

                    // 将权限数据传递给AccessibilityService
                    val service = ScreenCaptureAccessibilityService.instance
                    if (service != null) {
                        service.setMediaProjectionData(resultCode, data)
                        Log.d(TAG, "媒体投影权限数据已传递给AccessibilityService")
                    } else {
                        Log.w(TAG, "AccessibilityService未运行，无法传递媒体投影权限数据")
                    }

                    // 通知Flutter端
                    methodChannel.invokeMethod("onMediaProjectionResult", mapOf(
                        "granted" to true
                    ))
                } else {
                    methodChannel.invokeMethod("onMediaProjectionResult", mapOf(
                        "granted" to false
                    ))
                }
            }
            REQUEST_ACCESSIBILITY_SETTINGS -> {
                // 延迟检查，确保从设置页面返回后状态已更新
                mainHandler.postDelayed({
                    checkAndNotifyAccessibilityChange()
                }, 1000)
            }
        }
    }

    /**
     * 设置MediaProjection权限请求广播接收器
     */
    private fun setupMediaProjectionRequestReceiver() {
        try {
            mediaProjectionRequestReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "com.fqyw.screen_memo.REQUEST_MEDIA_PROJECTION") {
                        FileLogger.e(TAG, "收到MediaProjection权限请求广播，重新请求权限")
                        requestMediaProjectionPermission()
                    }
                }
            }
            
            val filter = IntentFilter("com.fqyw.screen_memo.REQUEST_MEDIA_PROJECTION")
            registerReceiver(mediaProjectionRequestReceiver, filter)
            FileLogger.e(TAG, "MediaProjection权限请求广播接收器已注册")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置MediaProjection权限请求广播接收器失败", e)
        }
    }


    /**
     * 设置截图保存通知广播接收器
     */
    private fun setupScreenshotSavedReceiver() {
        try {
            screenshotSavedReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "com.fqyw.screen_memo.SCREENSHOT_SAVED") {
                        val packageName = intent.getStringExtra("packageName") ?: ""
                        val appName = intent.getStringExtra("appName") ?: ""
                        val filePath = intent.getStringExtra("filePath") ?: ""
                        val captureTime = intent.getLongExtra("captureTime", System.currentTimeMillis())
                        
                        FileLogger.i(TAG, "收到截图保存通知: $appName - $filePath")
                        
                        // 通知Flutter端更新数据库
                        methodChannel.invokeMethod("onScreenshotSaved", mapOf(
                            "packageName" to packageName,
                            "appName" to appName,
                            "filePath" to filePath,
                            "captureTime" to captureTime
                        ))
                    }
                }
            }
            
            val filter = IntentFilter("com.fqyw.screen_memo.SCREENSHOT_SAVED")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenshotSavedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(screenshotSavedReceiver, filter)
            }
            FileLogger.e(TAG, "截图保存通知广播接收器已注册")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置截图保存通知广播接收器失败", e)
        }
    }

    /**
     * 测试自启动权限（通过尝试启动服务）
     */
    private fun testAutoStartPermission(): Boolean {
        return try {
            Log.d(TAG, "测试自启动权限...")

            // 尝试启动无障碍服务来测试权限
            val intent = Intent(this, ScreenCaptureAccessibilityService::class.java)
            startService(intent)

            Log.d(TAG, "服务启动命令已发送")
            true
        } catch (e: Exception) {
            Log.e(TAG, "测试自启动权限失败", e)
            false
        }
    }

    /**
     * 检查服务是否正在运行
     */
    private fun isServiceRunning(): Boolean {
        return try {
            // 先尝试通过AIDL检查
            val aidlRunning = try {
                accessibilityServiceBinder?.isServiceRunning() ?: false
            } catch (e: Exception) {
                FileLogger.w(TAG, "AIDL检查失败: ${e.message}")
                false
            }
            
            // 再检查本地实例（如果在同一进程）
            val instanceExists = ScreenCaptureAccessibilityService.instance != null
            val isServiceRunning = ScreenCaptureAccessibilityService.isServiceRunning
            val isAccessibilityEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(this)

            Log.d(TAG, "服务状态检查:")
            Log.d(TAG, "- AIDL服务运行: $aidlRunning")
            Log.d(TAG, "- AccessibilityService实例存在: $instanceExists")
            Log.d(TAG, "- 服务运行标志: $isServiceRunning")
            Log.d(TAG, "- 系统中启用状态: $isAccessibilityEnabled")

            // 综合判断
            val result = aidlRunning || (instanceExists && isAccessibilityEnabled)
            Log.d(TAG, "最终服务运行状态: $result")

            return result
        } catch (e: Exception) {
            Log.e(TAG, "检查服务状态失败", e)
            false
        }
    }

    /**
     * 验证MediaProjection权限是否真实有效
     */
    private fun validateMediaProjectionPermission(): Boolean {
        return try {
            // 检查SharedPreferences中的权限状态
            val sharedPrefs = getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
            val savedPermission = sharedPrefs.getBoolean("media_projection_granted", false)

            Log.d(TAG, "MediaProjection权限验证:")
            Log.d(TAG, "- SharedPreferences中的状态: $savedPermission")

            // MediaProjection权限是独立的，不依赖AccessibilityService的运行状态
            // 只要用户授予了权限，就认为是有效的
            if (savedPermission) {
                Log.d(TAG, "MediaProjection权限验证通过")
                return true
            } else {
                Log.d(TAG, "MediaProjection权限未授予")
                return false
            }
        } catch (e: Exception) {
            Log.e(TAG, "验证MediaProjection权限失败", e)
            false
        }
    }

    /**
     * 开始屏幕截图
     */
    private fun startScreenCapture(): Boolean {
        return try {
            val service = ScreenCaptureAccessibilityService.instance
            if (service != null) {
                service.startScreenCapture()
            } else {
                Log.e(TAG, "无障碍服务未运行")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "开始屏幕截图失败", e)
            false
        }
    }

    /**
     * 停止屏幕截图
     */
    private fun stopScreenCapture() {
        try {
            val service = ScreenCaptureAccessibilityService.instance
            service?.stopScreenCapture()
        } catch (e: Exception) {
            Log.e(TAG, "停止屏幕截图失败", e)
        }
    }

    /**
     * 启动定时截屏
     */
    private fun startTimedScreenshot(intervalSeconds: Int): Boolean {
        return try {
            FileLogger.e(TAG, "=== 开始定时截屏流程 ===")
            FileLogger.e(TAG, "截屏间隔: ${intervalSeconds}秒")

            // 检查服务状态
            val service = ScreenCaptureAccessibilityService.instance
            val isServiceRunning = service != null
            val isSystemEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(this)

            FileLogger.e(TAG, "服务状态检查:")
            FileLogger.e(TAG, "- AccessibilityService实例: ${if (service != null) "存在" else "不存在"}")
            FileLogger.e(TAG, "- 系统中启用状态: $isSystemEnabled")

            // 如果系统中已启用但实例不存在，等待服务启动
            if (isSystemEnabled && service == null) {
                FileLogger.e(TAG, "系统中已启用但服务实例不存在，等待服务启动...")
                
                // 等待服务实例可用，最多等待5秒
                var waitedService: ScreenCaptureAccessibilityService? = null
                for (i in 1..10) {
                    Thread.sleep(500) // 等待0.5秒
                    waitedService = ScreenCaptureAccessibilityService.instance
                    if (waitedService != null) {
                        FileLogger.e(TAG, "服务实例已可用，等待时间: ${i * 500}ms")
                        break
                    }
                    FileLogger.e(TAG, "等待服务实例，第${i}次检查...")
                }
                
                if (waitedService != null) {
                    FileLogger.e(TAG, "调用AccessibilityService.startTimedScreenshot")
                    val result = waitedService.startTimedScreenshot(intervalSeconds)
                    FileLogger.e(TAG, "AccessibilityService.startTimedScreenshot返回: $result")
                    return result
                } else {
                    FileLogger.e(TAG, "等待超时，服务实例仍不可用")
                    return false
                }
            }

            if (service != null) {
                FileLogger.e(TAG, "调用AccessibilityService.startTimedScreenshot")
                val result = service.startTimedScreenshot(intervalSeconds)
                FileLogger.e(TAG, "AccessibilityService.startTimedScreenshot返回: $result")
                return result
            } else {
                FileLogger.e(TAG, "无障碍服务未运行")
                if (!isSystemEnabled) {
                    FileLogger.e(TAG, "无障碍服务未在系统中启用，需要用户手动启用")
                }
                return false
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动定时截屏失败", e)
            false
        }
    }

    /**
     * 停止定时截屏
     */
    private fun stopTimedScreenshot() {
        try {
            val service = ScreenCaptureAccessibilityService.instance
            service?.stopTimedScreenshot()
        } catch (e: Exception) {
            Log.e(TAG, "停止定时截屏失败", e)
        }
    }

    /**
     * 手动截取屏幕
     */
    private fun captureScreen(): String? {
        return try {
            val service = ScreenCaptureAccessibilityService.instance
            if (service != null) {
                service.captureScreenSync()
            } else {
                Log.e(TAG, "无障碍服务未运行")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "截取屏幕失败", e)
            null
        }
    }

    /**
     * 获取应用专用外部存储目录路径
     */
    private fun getExternalFilesDirPath(subDir: String?): String? {
        return try {
            val externalFilesDir = if (subDir != null) {
                getExternalFilesDir(subDir)
            } else {
                getExternalFilesDir(null)
            }

            val path = externalFilesDir?.absolutePath
            Log.d(TAG, "getExternalFilesDir($subDir) = $path")
            FileLogger.i(TAG, "getExternalFilesDir($subDir) = $path")

            path
        } catch (e: Exception) {
            Log.e(TAG, "获取外部文件目录失败", e)
            FileLogger.e(TAG, "获取外部文件目录失败", e)
            null
        }
    }

    /**
     * 检查使用统计权限是否已授予
     */
    private fun isUsageStatsPermissionGranted(): Boolean {
        return try {
            val appOpsManager = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e(TAG, "检查使用统计权限失败", e)
            false
        }
    }

    /**
     * 请求使用统计权限
     */
    private fun requestUsageStatsPermission() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "请求使用统计权限失败", e)
            // 如果无法打开特定应用的设置页面，打开通用设置页面
            try {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                startActivity(intent)
            } catch (e2: Exception) {
                Log.e(TAG, "打开使用统计设置页面失败", e2)
            }
        }
    }
    
    /**
     * 调度JobService保活任务
     */
    private fun scheduleKeepAliveJob() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                FileLogger.e(TAG, "准备调度JobService保活任务")
                
                val jobScheduler = getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
                val componentName = ComponentName(this, KeepAliveJobService::class.java)
                
                val jobInfo = JobInfo.Builder(KeepAliveJobService.JOB_ID, componentName).apply {
                    // 设置任务执行条件
                    setPeriodic(15 * 60 * 1000) // 每15分钟执行一次
                    setPersisted(true) // 设备重启后仍然执行
                    setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE) // 不需要网络
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setRequiresBatteryNotLow(false) // 电量低时也执行
                        setRequiresStorageNotLow(false) // 存储空间低时也执行
                    }
                }.build()
                
                val result = jobScheduler.schedule(jobInfo)
                if (result == JobScheduler.RESULT_SUCCESS) {
                    FileLogger.e(TAG, "JobService保活任务调度成功")
                } else {
                    FileLogger.e(TAG, "JobService保活任务调度失败")
                }
                
            } catch (e: Exception) {
                FileLogger.e(TAG, "调度JobService保活任务失败", e)
            }
        } else {
            FileLogger.w(TAG, "Android版本过低，不支持JobScheduler")
        }
    }
    
    /**
     * 触发AccessibilityService连接
     */
    private fun triggerAccessibilityServiceConnection() {
        try {
            FileLogger.e(TAG, "开始触发AccessibilityService连接")
            
            // 方法1: 启动前台服务
            try {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                FileLogger.e(TAG, "前台服务启动成功")
            } catch (e: Exception) {
                FileLogger.e(TAG, "启动前台服务失败", e)
            }
            
            // 方法2: 重新检查和更新状态
            ServiceDebugHelper.performFullStatusCheck(this)
            
            // 方法3: 尝试通过禁用/启用无障碍服务来触发连接
            // 注意：这需要系统权限，一般应用无法执行
            // val accessibilityManager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "触发AccessibilityService连接失败", e)
        }
    }
    
    /**
     * 启动守护服务
     */
    private fun startDaemonService() {
        try {
            val serviceIntent = Intent(this, DaemonService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            FileLogger.e(TAG, "守护服务启动成功")
        } catch (e: Exception) {
            FileLogger.e(TAG, "启动守护服务失败", e)
        }
    }
    
    /**
     * 绑定AccessibilityService
     */
    private fun bindAccessibilityService() {
        try {
            val intent = Intent().apply {
                component = ComponentName(packageName, "$packageName.ScreenCaptureAccessibilityService")
            }
            bindService(intent, accessibilityServiceConnection, Context.BIND_AUTO_CREATE)
            FileLogger.e(TAG, "开始绑定AccessibilityService")
        } catch (e: Exception) {
            FileLogger.e(TAG, "绑定AccessibilityService失败", e)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // 尝试解绑AccessibilityService
        try {
            unbindService(accessibilityServiceConnection)
        } catch (e: Exception) {
            // 忽略解绑错误
        }
        
        // 调用原有的onDestroy逻辑
        onDestroyOriginal()
    }
    
    private fun onDestroyOriginal() {
        // 原有onDestroy代码
        // 取消注册ContentObserver
        accessibilityObserver?.let {
            contentResolver.unregisterContentObserver(it)
        }

        // 取消注册广播接收器
        mediaProjectionRequestReceiver?.let {
            try {
                unregisterReceiver(it)
                FileLogger.e(TAG, "MediaProjection权限请求广播接收器已取消注册")
            } catch (e: Exception) {
                FileLogger.e(TAG, "取消注册广播接收器失败", e)
            }
        }
        
        screenshotSavedReceiver?.let {
            try {
                unregisterReceiver(it)
                FileLogger.e(TAG, "截图保存通知广播接收器已取消注册")
            } catch (e: Exception) {
                FileLogger.e(TAG, "取消注册截图保存广播接收器失败", e)
            }
        }

        // 停止辅助功能状态监听
        accessibilityStateMonitor?.stopMonitoring()
    }
}
