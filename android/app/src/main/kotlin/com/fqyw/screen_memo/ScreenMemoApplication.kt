package com.fqyw.screen_memo

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import com.fqyw.screen_memo.memory.service.MemoryProcessingScheduler

class ScreenMemoApplication : Application() {
    companion object {
        private const val TAG = "ScreenMemoApplication"
        const val ENGINE_ID = "main_engine"
    }

    override fun onCreate() {
        super.onCreate()
        AppContextProvider.init(this)

        // 暂不执行 Dart 入口，避免在 Activity 尚未完成通道注册前出现 MissingPluginException。
        // 如需预热引擎，可在此处仅创建并缓存 FlutterEngine（不执行 Dart）。
        try {
            val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
            if (cached == null) {
                val engine = FlutterEngine(this)
                FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
                FileLogger.i(TAG, "FlutterEngine cached without executing Dart: $ENGINE_ID")
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "Failed to cache FlutterEngine", e)
        }

        // 应用启动时恢复每日提醒调度（读取 SharedPreferences 中的上次设置）
        try {
            DailySummaryScheduler.restore(this)
            OutputFileLogger.info(this, TAG, "Daily summary schedule restored at app start")
        } catch (e: Exception) {
            FileLogger.w(TAG, "Daily schedule restore failed: ${e.message}")
        }

        try {
            MemoryProcessingScheduler.scheduleNext(this)
            FileLogger.i(TAG, "Memory processing schedule prepared on app start")
        } catch (e: Exception) {
            FileLogger.w(TAG, "Memory processing schedule failed: ${e.message}")
        }
    }
}


