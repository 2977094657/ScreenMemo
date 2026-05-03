package com.fqyw.screen_memo

import com.fqyw.screen_memo.app.AppContextProvider
import com.fqyw.screen_memo.daily.DailySummaryScheduler
import com.fqyw.screen_memo.diagnostics.RuntimeDiagnostics
import com.fqyw.screen_memo.dynamic.DynamicRebuildService
import com.fqyw.screen_memo.importing.ImportOcrRepairService
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.logging.OutputFileLogger

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class ScreenMemoApplication : Application() {
    companion object {
        private const val TAG = "ScreenMemoApplication"
        const val ENGINE_ID = "main_engine"
    }

    override fun onCreate() {
        super.onCreate()
        AppContextProvider.init(this)
        FileLogger.init(this)
        try { FileLogger.syncFromFlutterPrefs(this) } catch (_: Exception) {}
        RuntimeDiagnostics.logProcessStart(this, TAG, "application_onCreate", force = true)

        // 暂不执行 Dart 入口，避免在 Activity 尚未完成通道注册前出现 MissingPluginException。
        // 如需预热引擎，可在此处仅创建并缓存 FlutterEngine（不执行 Dart）。
        try {
                val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
            if (cached == null) {
                val engine = FlutterEngine(this)
                FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
                FileLogger.i(TAG, "FlutterEngine 已缓存（未执行 Dart）：$ENGINE_ID")
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "缓存 FlutterEngine 失败", e)
        }

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

    }
}

