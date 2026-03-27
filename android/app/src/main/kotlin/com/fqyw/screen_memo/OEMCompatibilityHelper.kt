package com.fqyw.screen_memo

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
 

/**
 * OEM厂商兼容性助手
 * 处理小米、华为、OPPO、VIVO等厂商的电池优化和自启动权限
 */
object OEMCompatibilityHelper {
    
    private const val TAG = "OEMCompatibilityHelper"
    
    /**
     * 检查是否为小米设备
     */
    fun isXiaomiDevice(): Boolean {
        return Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true) ||
                Build.BRAND.equals("Xiaomi", ignoreCase = true) ||
                Build.BRAND.equals("Redmi", ignoreCase = true)
    }
    
    /**
     * 检查是否为华为设备
     */
    fun isHuaweiDevice(): Boolean {
        return Build.MANUFACTURER.equals("Huawei", ignoreCase = true) ||
                Build.BRAND.equals("Huawei", ignoreCase = true) ||
                Build.BRAND.equals("Honor", ignoreCase = true)
    }
    
    /**
     * 检查是否为OPPO设备
     */
    fun isOppoDevice(): Boolean {
        return Build.MANUFACTURER.equals("OPPO", ignoreCase = true) ||
                Build.BRAND.equals("OPPO", ignoreCase = true)
    }

    /**
     * 检查是否为一加设备
     */
    fun isOnePlusDevice(): Boolean {
        return Build.MANUFACTURER.equals("OnePlus", ignoreCase = true) ||
                Build.BRAND.equals("OnePlus", ignoreCase = true)
    }
    
    /**
     * 检查是否为VIVO设备
     */
    fun isVivoDevice(): Boolean {
        return Build.MANUFACTURER.equals("vivo", ignoreCase = true) ||
                Build.BRAND.equals("vivo", ignoreCase = true)
    }
    
    /**
     * 检查设备厂商信息
     */
    fun getDeviceInfo(): String {
        return "厂商: ${Build.MANUFACTURER}, 品牌: ${Build.BRAND}, 型号: ${Build.MODEL}"
    }
    
    /**
     * 检查是否在电池优化白名单中
     */
    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                val isIgnoring = powerManager.isIgnoringBatteryOptimizations(context.packageName)
                FileLogger.e(TAG, "电池优化白名单检查结果: $isIgnoring (Android ${Build.VERSION.SDK_INT})")
                isIgnoring
            } catch (e: Exception) {
                FileLogger.e(TAG, "检查电池优化状态失败", e)
                false
            }
        } else {
            // Android 6.0以下没有电池优化功能，但不应该显示为已授权
            // 而是应该显示为不需要此权限
            FileLogger.e(TAG, "Android版本 ${Build.VERSION.SDK_INT} 低于6.0，无电池优化功能")
            false
        }
    }
    
    /**
     * 请求忽略电池优化
     */
    fun requestIgnoreBatteryOptimizations(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                FileLogger.e(TAG, "已打开电池优化设置页面")
                true
            } else {
                FileLogger.e(TAG, "Android版本低于6.0，无需电池优化设置")
                true
            }
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开电池优化设置失败", e)
            false
        }
    }
    
    /**
     * 打开小米自启动管理页面
     */
    fun openXiaomiAutoStartSettings(context: Context): Boolean {
        return try {
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开小米自启动管理页面")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开小米自启动管理页面失败，尝试备用方案", e)
            return openXiaomiAutoStartSettingsBackup(context)
        }
    }
    
    /**
     * 小米自启动管理备用方案
     */
    private fun openXiaomiAutoStartSettingsBackup(context: Context): Boolean {
        return try {
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity"
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开小米权限管理页面（备用方案）")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "小米备用方案也失败", e)
            false
        }
    }
    
    /**
     * 打开华为自启动管理页面
     */
    fun openHuaweiAutoStartSettings(context: Context): Boolean {
        return try {
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开华为自启动管理页面")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开华为自启动管理页面失败", e)
            false
        }
    }
    
    /**
     * 打开OPPO自启动管理页面
     */
    fun openOppoAutoStartSettings(context: Context): Boolean {
        return try {
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开OPPO自启动管理页面")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开OPPO自启动管理页面失败", e)
            false
        }
    }
    
    /**
     * 打开VIVO自启动管理页面
     */
    fun openVivoAutoStartSettings(context: Context): Boolean {
        return try {
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开VIVO自启动管理页面")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开VIVO自启动管理页面失败", e)
            false
        }
    }
    
    /**
     * 根据设备厂商打开对应的自启动设置页面
     */
    fun openAutoStartSettings(context: Context): Boolean {
        FileLogger.e(TAG, "准备打开自启动设置页面")
        FileLogger.e(TAG, getDeviceInfo())
        
        return when {
            isXiaomiDevice() -> {
                FileLogger.e(TAG, "检测到小米设备，打开小米自启动设置")
                openXiaomiAutoStartSettings(context)
            }
            isHuaweiDevice() -> {
                FileLogger.e(TAG, "检测到华为设备，打开华为自启动设置")
                openHuaweiAutoStartSettings(context)
            }
            isOppoDevice() -> {
                FileLogger.e(TAG, "检测到OPPO设备，打开OPPO自启动设置")
                openOppoAutoStartSettings(context)
            }
            isOnePlusDevice() -> {
                FileLogger.e(TAG, "检测到OnePlus设备，先打开应用详情页供用户手动设置后台限制")
                openAppSettings(context)
            }
            isVivoDevice() -> {
                FileLogger.e(TAG, "检测到VIVO设备，打开VIVO自启动设置")
                openVivoAutoStartSettings(context)
            }
            else -> {
                FileLogger.e(TAG, "未知设备厂商，打开通用应用设置页面")
                openAppSettings(context)
            }
        }
    }
    
    /**
     * 打开应用设置页面
     */
    fun openAppSettings(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开应用设置页面")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开应用设置页面失败", e)
            false
        }
    }
    
    /**
     * 检查OEM权限状态并提供建议
     */
    fun checkOEMPermissionsAndSuggest(context: Context): String {
        val suggestions = mutableListOf<String>()
        
        // 检查电池优化
        if (!isIgnoringBatteryOptimizations(context)) {
            suggestions.add("请在电池优化中将本应用加入白名单")
        }
        
        // 根据厂商提供具体建议
        when {
            isXiaomiDevice() -> {
                suggestions.add("小米设备：请在自启动管理中允许本应用自启动")
                suggestions.add("小米设备：请在后台应用管理中设置为无限制")
            }
            isHuaweiDevice() -> {
                suggestions.add("华为设备：请在启动管理中允许本应用自启动")
                suggestions.add("华为设备：请在应用启动管理中设置为手动管理")
            }
            isOppoDevice() -> {
                suggestions.add("OPPO设备：请在自启动管理中允许本应用自启动")
                suggestions.add("OPPO设备：请关闭应用冻结功能")
            }
            isOnePlusDevice() -> {
                suggestions.add("OnePlus设备：请在电池或应用管理中允许后台活动或设为不限制")
                suggestions.add("OnePlus设备：请开启自启动；如系统提供最近任务锁定，请锁定本应用")
            }
            isVivoDevice() -> {
                suggestions.add("VIVO设备：请在后台高耗电中允许本应用")
                suggestions.add("VIVO设备：请在自启动管理中允许本应用")
            }
        }
        
        return if (suggestions.isEmpty()) {
            "当前权限配置良好"
        } else {
            "建议进行以下设置：\n" + suggestions.joinToString("\n")
        }
    }
}
