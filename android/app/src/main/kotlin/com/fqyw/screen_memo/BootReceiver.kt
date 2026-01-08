package com.fqyw.screen_memo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.fqyw.screen_memo.memory.service.MemoryProcessingScheduler
import com.fqyw.screen_memo.memory.service.MemoryProcessingReceiver

class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        FileLogger.d(TAG, "收到广播: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                FileLogger.d(TAG, "系统启动或应用更新，准备启动服务")

                // 启动辅助功能状态监听
                try {
                    val monitor = AccessibilityStateMonitor(context)
                    monitor.startMonitoring()
                    FileLogger.d(TAG, "辅助功能状态监听已启动")
                } catch (e: Exception) {
                    FileLogger.e(TAG, "启动辅助功能状态监听失败", e)
                }

                // 检查是否需要启动前台服务
                val sharedPrefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
                val wasServiceRunning = sharedPrefs.getBoolean("accessibility_service_running", false)

                if (wasServiceRunning) {
                    FileLogger.d(TAG, "服务之前在运行，启动前台服务")

                    try {
                        val serviceIntent = Intent(context, ScreenCaptureService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                    } catch (e: Exception) {
                        FileLogger.e(TAG, "启动前台服务失败", e)
                    }
                } else {
                    FileLogger.d(TAG, "服务之前未运行，跳过启动")
                }
                // 恢复每日提醒调度
                try {
                    DailySummaryScheduler.restore(context)
                    FileLogger.d(TAG, "每日提醒调度已恢复")
                    // 同时安排固定时段
                    val ok = DailySummaryScheduler.scheduleFixedSlots(context)
                    FileLogger.d(TAG, "固定时段调度结果: $ok")
                } catch (e: Exception) {
                    FileLogger.e(TAG, "恢复每日提醒调度失败", e)
                }

                // 安排每日记忆解析调度
                try {
                    MemoryProcessingScheduler.scheduleNext(context.applicationContext)
                    FileLogger.d(TAG, "每日记忆解析调度已设置")
                } catch (e: Exception) {
                    FileLogger.e(TAG, "设置每日记忆解析调度失败", e)
                }

                // 兜底：开机/更新后检查一次周总结是否到期
                try {
                    MemoryProcessingReceiver.enqueueWeeklySummaryIfDue(context.applicationContext)
                    FileLogger.d(TAG, "周总结检查已触发")
                } catch (e: Exception) {
                    FileLogger.e(TAG, "周总结检查触发失败", e)
                }
            }
        }
    }
}
