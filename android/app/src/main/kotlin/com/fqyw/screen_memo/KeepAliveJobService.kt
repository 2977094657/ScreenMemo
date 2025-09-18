package com.fqyw.screen_memo

import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Intent
import android.os.Build
import android.util.Log
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
        FileLogger.e(TAG, "=== KeepAliveJobService onStartJob ===")
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
                
                // 启动MainActivity以触发AccessibilityService重新连接
                try {
                    val intent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        putExtra("from_job_service", true)
                    }
                    startActivity(intent)
                    FileLogger.e(TAG, "MainActivity启动成功")
                } catch (e: Exception) {
                    FileLogger.e(TAG, "启动MainActivity失败", e)
                }
            }
            
            // 调用段落补齐逻辑，确保在后台周期任务中也能自动总结
            try {
                // 优先推进所有 collecting 段落并在必要时触发AI
                SegmentSummaryManager.tick(this)
            } catch (e: Exception) {
                FileLogger.e(TAG, "tick 调用失败", e)
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
        FileLogger.e(TAG, "=== KeepAliveJobService onStopJob ===")
        return true // true表示需要重新调度
    }
}