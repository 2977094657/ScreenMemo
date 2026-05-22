package com.fqyw.screen_memo.service

import com.fqyw.screen_memo.capture.ScreenCaptureAccessibilityService
import com.fqyw.screen_memo.capture.ScreenCaptureService
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.mcp.McpServerService
import com.fqyw.screen_memo.segment.SegmentSummaryManager
import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Intent
import android.os.Build
 
import androidx.annotation.RequiresApi

/**
 * 使用JobScheduler实现的保活服务
 * 在应用被杀死后仍能工作
 */
@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class KeepAliveJobService : JobService() {
    
    companion object {
        private const val TAG = "KeepAliveJobService"
        const val JOB_ID = 1001
    }
    
    override fun onStartJob(params: JobParameters?): Boolean {
        FileLogger.init(this)
        FileLogger.e(TAG, "=== KeepAliveJobService 开始任务 ===")
        FileLogger.e(TAG, "任务ID: ${params?.jobId}")
        FileLogger.e(TAG, "当前进程ID: ${android.os.Process.myPid()}")
        
        try {
            // 检查AccessibilityService状态
            val isSystemEnabled = ServiceDebugHelper.isAccessibilityServiceEnabledInSystem(this)
            val instanceExists = ScreenCaptureAccessibilityService.instance != null
            
            FileLogger.e(TAG, "系统中AccessibilityService启用状态: $isSystemEnabled")
            FileLogger.e(TAG, "服务实例存在状态: $instanceExists")
            
            if (isSystemEnabled && !instanceExists) {
                FileLogger.e(TAG, "服务在系统中已启用但实例不存在，尝试重启")
                
                // 启动前台服务
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
                
                // 不再从后台 JobService 拉起可见 MainActivity。
                // 更新安装失败/任务被划掉后，前台服务仍会保活进程；后台强行拉起 Activity
                // 在部分 ROM 上会留下黑色任务窗口，并把旧 Flutter UI 状态继续复用。
                // 改为只发送重启广播，让服务侧自检；需要用户交互时由通知/设置页引导。
                try {
                    val restartIntent = Intent(this, RestartReceiver::class.java).apply {
                        action = RestartReceiver.ACTION_RESTART_SERVICE
                    }
                    sendBroadcast(restartIntent)
                    FileLogger.e(TAG, "Sent service restart broadcast; skipped background MainActivity launch")
                } catch (e: Exception) {
                    FileLogger.e(TAG, "Failed to send service restart broadcast", e)
                }
            }
            
            // 调用段落补齐逻辑，确保在后台周期任务中也能自动总结
            try {
                // 优先推进所有 collecting 段落并在必要时触发AI
                SegmentSummaryManager.tick(this)
            } catch (e: Exception) {
                FileLogger.e(TAG, "tick 调用失败", e)
            }

            try {
                McpServerService.restoreIfEnabled(this)
            } catch (e: Exception) {
                FileLogger.e(TAG, "恢复 MCP 服务失败", e)
            }

            // 任务执行完成
            jobFinished(params, true) // true表示需要重新调度
            
        } catch (e: Exception) {
            FileLogger.e(TAG, "KeepAliveJobService执行失败", e)
            jobFinished(params, true)
        }
        
        return true // 表示任务还在进行中
    }
    
    override fun onStopJob(params: JobParameters?): Boolean {
        FileLogger.e(TAG, "=== KeepAliveJobService 结束任务 ===")
        return true // true表示需要重新调度
    }
}
