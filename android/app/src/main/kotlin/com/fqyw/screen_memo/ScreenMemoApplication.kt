package com.fqyw.screen_memo

import android.app.Application
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class ScreenMemoApplication : Application() {
    companion object {
        private const val TAG = "ScreenMemoApplication"
        const val ENGINE_ID = "main_engine"
    }

    override fun onCreate() {
        super.onCreate()

        // 暂不执行 Dart 入口，避免在 Activity 尚未完成通道注册前出现 MissingPluginException。
        // 如需预热引擎，可在此处仅创建并缓存 FlutterEngine（不执行 Dart）。
        try {
            val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
            if (cached == null) {
                val engine = FlutterEngine(this)
                FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
                Log.d(TAG, "FlutterEngine cached without executing Dart: $ENGINE_ID")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cache FlutterEngine", e)
        }
    }
}


