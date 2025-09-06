package com.fqyw.screen_memo

import android.app.Application
import android.util.Log
import android.content.Context
import android.content.pm.PackageManager
import com.umeng.commonsdk.UMConfigure
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

        // Initialize Umeng (Analytics base) and APM/Crash
        try {
            val appKey = getMetaData("UMENG_APPKEY")?.trim().orEmpty()
            val channel = getMetaData("UMENG_CHANNEL") ?: "official"
            if (appKey.isNotEmpty()) {
                val isDebug = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
                UMConfigure.setLogEnabled(isDebug)
                UMConfigure.preInit(this, appKey, channel)
                UMConfigure.init(this, appKey, channel, UMConfigure.DEVICE_TYPE_PHONE, null)
                try {
                    val clazz = Class.forName("com.umeng.umcrash.UMCrash")
                    val m = clazz.getMethod("init", Context::class.java)
                    m.invoke(null, this)
                    Log.d(TAG, "UMCrash initialized")
                    // 写一条初始化 info 到 output/logs/yyyy/MM/dd/
                    OutputFileLogger.info(this, TAG, "Umeng initialized, channel=$channel")
                } catch (e: Exception) {
                    Log.w(TAG, "UMCrash init not available", e)
                }
            } else {
                Log.w(TAG, "UMENG_APPKEY is empty; skipped Umeng init")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Umeng init failed", e)
            OutputFileLogger.error(this, TAG, "Umeng init failed: ${e.message}")
        }

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

    private fun getMetaData(key: String): String? {
        return try {
            val ai = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            ai.metaData?.getString(key)
        } catch (_: Exception) {
            null
        }
    }
}


