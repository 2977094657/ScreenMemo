package com.fqyw.screen_memo

import android.content.Context
import android.content.SharedPreferences
 

/**
 * 服务状态管理器
 * 用于在不同进程间共享服务状态信息
 */
object ServiceStateManager {
    
    private const val TAG = "ServiceStateManager"
    private const val PREFS_NAME = "screen_memo_service_state"
    
    // 状态键
    private const val KEY_ACCESSIBILITY_SERVICE_RUNNING = "accessibility_service_running"
    private const val KEY_ACCESSIBILITY_SERVICE_ENABLED = "accessibility_service_enabled"
    private const val KEY_FOREGROUND_SERVICE_RUNNING = "foreground_service_running"
    private const val KEY_LAST_UPDATE_TIME = "last_update_time"
    private const val KEY_PROCESS_ID = "process_id"
    private const val KEY_ACCESSIBILITY_PROCESS_NAME = "accessibility_process_name"
    
    /**
     * 获取SharedPreferences实例
     */
    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    
    /**
     * 设置AccessibilityService运行状态
     */
    fun setAccessibilityServiceRunning(context: Context, isRunning: Boolean) {
        try {
            val prefs = getPrefs(context)
            val procName = try {
                val am = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                val pid = android.os.Process.myPid()
                am.runningAppProcesses?.firstOrNull { it.pid == pid }?.processName ?: ""
            } catch (_: Exception) { "" }
            prefs.edit()
                .putBoolean(KEY_ACCESSIBILITY_SERVICE_RUNNING, isRunning)
                .putLong(KEY_LAST_UPDATE_TIME, System.currentTimeMillis())
                .putInt(KEY_PROCESS_ID, android.os.Process.myPid())
                .putString(KEY_ACCESSIBILITY_PROCESS_NAME, procName)
                .apply()
            
            FileLogger.d(TAG, "AccessibilityService状态已更新: $isRunning, PID: ${android.os.Process.myPid()}")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置AccessibilityService状态失败", e)
        }
    }
    
    /**
     * 获取AccessibilityService运行状态
     */
    fun isAccessibilityServiceRunning(context: Context): Boolean {
        return try {
            val prefs = getPrefs(context)
            val isRunning = prefs.getBoolean(KEY_ACCESSIBILITY_SERVICE_RUNNING, false)
            val lastUpdate = prefs.getLong(KEY_LAST_UPDATE_TIME, 0)
            val processId = prefs.getInt(KEY_PROCESS_ID, -1)
            
            FileLogger.d(TAG, "AccessibilityService状态: $isRunning, 最后更新: $lastUpdate, PID: $processId")
            isRunning
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取AccessibilityService状态失败", e)
            false
        }
    }
    
    /**
     * 设置AccessibilityService启用状态
     */
    fun setAccessibilityServiceEnabled(context: Context, isEnabled: Boolean) {
        try {
            val prefs = getPrefs(context)
            prefs.edit()
                .putBoolean(KEY_ACCESSIBILITY_SERVICE_ENABLED, isEnabled)
                .putLong(KEY_LAST_UPDATE_TIME, System.currentTimeMillis())
                .apply()
            
            FileLogger.d(TAG, "AccessibilityService启用状态已更新: $isEnabled")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置AccessibilityService启用状态失败", e)
        }
    }
    
    /**
     * 获取AccessibilityService启用状态
     */
    fun isAccessibilityServiceEnabled(context: Context): Boolean {
        return try {
            val prefs = getPrefs(context)
            prefs.getBoolean(KEY_ACCESSIBILITY_SERVICE_ENABLED, false)
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取AccessibilityService启用状态失败", e)
            false
        }
    }
    
    /**
     * 设置前台服务运行状态
     */
    fun setForegroundServiceRunning(context: Context, isRunning: Boolean) {
        try {
            val prefs = getPrefs(context)
            prefs.edit()
                .putBoolean(KEY_FOREGROUND_SERVICE_RUNNING, isRunning)
                .putLong(KEY_LAST_UPDATE_TIME, System.currentTimeMillis())
                .apply()
            
            FileLogger.d(TAG, "前台服务状态已更新: $isRunning")
        } catch (e: Exception) {
            FileLogger.e(TAG, "设置前台服务状态失败", e)
        }
    }
    
    /**
     * 获取前台服务运行状态
     */
    fun isForegroundServiceRunning(context: Context): Boolean {
        return try {
            val prefs = getPrefs(context)
            prefs.getBoolean(KEY_FOREGROUND_SERVICE_RUNNING, false)
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取前台服务状态失败", e)
            false
        }
    }
    
    /**
     * 获取所有状态信息
     */
    fun getAllStates(context: Context): Map<String, Any> {
        return try {
            val prefs = getPrefs(context)
            mapOf(
                "accessibilityServiceRunning" to prefs.getBoolean(KEY_ACCESSIBILITY_SERVICE_RUNNING, false),
                "accessibilityServiceEnabled" to prefs.getBoolean(KEY_ACCESSIBILITY_SERVICE_ENABLED, false),
                "foregroundServiceRunning" to prefs.getBoolean(KEY_FOREGROUND_SERVICE_RUNNING, false),
                "lastUpdateTime" to prefs.getLong(KEY_LAST_UPDATE_TIME, 0),
                "processId" to prefs.getInt(KEY_PROCESS_ID, -1),
                "accessibilityProcessName" to (prefs.getString(KEY_ACCESSIBILITY_PROCESS_NAME, "") ?: "")
            )
        } catch (e: Exception) {
            FileLogger.e(TAG, "获取所有状态失败", e)
            emptyMap()
        }
    }
    
    /**
     * 清除所有状态
     */
    fun clearAllStates(context: Context) {
        try {
            val prefs = getPrefs(context)
            prefs.edit().clear().apply()
            FileLogger.d(TAG, "所有状态已清除")
        } catch (e: Exception) {
            FileLogger.e(TAG, "清除状态失败", e)
        }
    }
    
    /**
     * 打印当前所有状态（用于调试）
     */
    fun printAllStates(context: Context) {
        try {
            val states = getAllStates(context)
            FileLogger.writeSeparator("当前服务状态")
            states.forEach { (key, value) ->
                FileLogger.d(TAG, "$key: $value")
            }
            FileLogger.writeSeparator()
        } catch (e: Exception) {
            FileLogger.e(TAG, "打印状态失败", e)
        }
    }
}
