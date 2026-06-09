package com.fqyw.screen_memo.capture

import android.content.Context
import com.fqyw.screen_memo.logging.FileLogger
import com.fqyw.screen_memo.settings.PerAppSettingsBridge

/**
 * Activity 黑名单辅助类。
 * 判断指定应用的当前 Activity 是否在黑名单中，
 * 黑名单列表由每应用设置数据库（PerAppSettingsBridge）提供。
 */
object ActivityBlacklistHelper {

    private const val TAG = "ActivityBlacklist"

    @Volatile
    var currentActivityClassName: String? = null

    /**
     * 检查指定应用包名的当前 Activity 是否处于黑名单中。
     * 匹配规则：全类名完全匹配。
     * 返回 true 表示应跳过截图（Activity 在黑名单中）。
     */
    fun isBlacklisted(context: Context, packageName: String): Boolean {
        val className = currentActivityClassName ?: return false
        if (className.isBlank()) return false

        val blacklist = PerAppSettingsBridge.readActivityBlacklist(context, packageName)
        if (blacklist.isEmpty()) return false

        val matched = blacklist.any { it == className }
        if (matched) {
            FileLogger.i(TAG, "Activity 黑名单匹配: $packageName/$className, 跳过截屏")
        }
        return matched
    }
}
