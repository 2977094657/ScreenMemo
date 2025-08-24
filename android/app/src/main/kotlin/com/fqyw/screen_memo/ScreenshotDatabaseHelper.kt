package com.fqyw.screen_memo

/**
 * 数据库操作已迁移到 Flutter 端
 * 原生侧不再直接操作数据库
 */
object ScreenshotDatabaseHelper {
    
    fun insertIfNotExists(
        context: android.content.Context,
        appPackageName: String,
        appName: String,
        absoluteFilePath: String,
        captureTimeMillis: Long
    ) {
        // 数据库操作已迁移到 Flutter 端，原生侧不再处理
        // Flutter 端会通过 MethodChannel 处理所有数据库操作
    }
}