package com.fqyw.screen_memo

import com.fqyw.screen_memo.app.AppContextProvider
import com.fqyw.screen_memo.daily.DailySummaryScheduler
import com.fqyw.screen_memo.diagnostics.RuntimeDiagnostics
import com.fqyw.screen_memo.dynamic.DynamicRebuildService
import com.fqyw.screen_memo.health.AppHealthNativeRecorder
import com.fqyw.screen_memo.health.AppHealthScheduler
import com.fqyw.screen_memo.importing.ImportOcrRepairService
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.logging.OutputFileLogger

import android.app.Application

class ScreenMemoApplication : Application() {
    companion object {
        private const val TAG = "ScreenMemoApplication"
    }

    override fun onCreate() {
        super.onCreate()
        AppContextProvider.init(this)
        FileLogger.init(this)
        try { FileLogger.syncFromFlutterPrefs(this) } catch (_: Exception) {}
        RuntimeDiagnostics.logProcessStart(this, TAG, "application_onCreate", force = true)

        // 不再在 Application 级别缓存 FlutterEngine。
        // 前台采集服务会让进程长时间存活，复用同一个 Engine 会把上一次 Activity 的
        // Navigator/页面状态一并保留下来。若更新安装器取消、任务被划掉或页面处于异常状态，
        // 再次打开时可能直接复用旧的黑屏/查看器状态，只有强停才能恢复。
        // 让 MainActivity 使用默认 Engine 生命周期，可以在每次用户可见启动时重建干净的 Flutter UI。
        FileLogger.i(TAG, "FlutterEngine pre-cache disabled; MainActivity will use a standalone Engine")

        // 应用启动时恢复每日提醒调度（读取 SharedPreferences 中的上次设置）
        try {
            DailySummaryScheduler.restore(this)
            OutputFileLogger.info(this, TAG, "应用启动时已恢复每日总结调度")
        } catch (e: Exception) {
            FileLogger.w(TAG, "恢复每日总结调度失败：${e.message}")
        }

        try {
            ImportOcrRepairService.ensureResumedIfPending(this, "application_on_create")
        } catch (e: Exception) {
            FileLogger.w(TAG, "恢复导入 OCR 修复任务失败：${e.message}")
        }

        try {
            DynamicRebuildService.ensureResumedIfPending(this, "application_on_create")
        } catch (e: Exception) {
            FileLogger.w(TAG, "恢复动态重建任务失败：${e.message}")
        }

        try {
            AppHealthScheduler.restore(this)
            AppHealthNativeRecorder.recordSnapshot(this, "application_on_create")
        } catch (e: Exception) {
            FileLogger.w(TAG, "恢复 App 运行状态调度失败：${e.message}")
        }

    }
}

