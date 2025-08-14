package com.fqyw.screen_memo

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log

/**
 * 权限引导助手
 * 帮助用户设置必要的权限以确保服务保活
 */
object PermissionGuideHelper {
    
    private const val TAG = "PermissionGuideHelper"
    
    /**
     * 检查是否需要显示权限引导
     */
    fun shouldShowPermissionGuide(context: Context): Boolean {
        val sharedPrefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)

        val needsBatteryOptimization = sharedPrefs.getBoolean("needs_battery_optimization_whitelist", false)
        val needsAutostart = sharedPrefs.getBoolean("needs_autostart_permission", false)
        val needsBackground = sharedPrefs.getBoolean("needs_background_unlimited", false)

        return needsBatteryOptimization || needsAutostart || needsBackground
    }
    
    /**
     * 获取权限设置建议文本
     */
    fun getPermissionGuideText(context: Context): String {
        val suggestions = mutableListOf<String>()
        val sharedPrefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)

        if (sharedPrefs.getBoolean("needs_battery_optimization_whitelist", false)) {
            suggestions.add("1. 电池优化：将应用加入白名单")
        }

        if (sharedPrefs.getBoolean("needs_autostart_permission", false)) {
            suggestions.add("2. 自启动权限：允许应用自启动")
        }

        if (sharedPrefs.getBoolean("needs_background_unlimited", false)) {
            suggestions.add("3. 后台运行：设置为无限制")
        }
        
        val deviceSpecific = when {
            OEMCompatibilityHelper.isXiaomiDevice() -> {
                "\n\n小米设备设置路径：\n" +
                "• 设置 → 应用设置 → 应用管理 → 屏忆\n" +
                "• 点击「省电策略」→ 选择「无限制」\n" +
                "• 点击「自启动」→ 开启\n" +
                "• 设置 → 省电与电池 → 应用省电 → 屏忆 → 无限制"
            }
            OEMCompatibilityHelper.isHuaweiDevice() -> {
                "\n\n华为设备设置路径：\n" +
                "• 设置 → 应用和服务 → 应用管理 → 屏忆\n" +
                "• 点击「电池」→ 选择「允许后台活动」\n" +
                "• 设置 → 应用和服务 → 启动管理 → 屏忆 → 手动管理"
            }
            OEMCompatibilityHelper.isOppoDevice() -> {
                "\n\nOPPO设备设置路径：\n" +
                "• 设置 → 电池 → 应用耗电管理 → 屏忆 → 允许后台运行\n" +
                "• 设置 → 应用管理 → 屏忆 → 权限 → 自启动"
            }
            OEMCompatibilityHelper.isVivoDevice() -> {
                "\n\nVIVO设备设置路径：\n" +
                "• 设置 → 电池 → 后台高耗电 → 屏忆 → 允许\n" +
                "• 设置 → 应用与权限 → 权限管理 → 自启动 → 屏忆"
            }
            else -> "\n\n请在应用设置中关闭电池优化并允许后台运行"
        }
        
        return if (suggestions.isEmpty()) {
            "权限配置完成！"
        } else {
            "为确保截屏服务稳定运行，请完成以下设置：\n\n" +
            suggestions.joinToString("\n") +
            deviceSpecific
        }
    }
    
    /**
     * 打开应用详情页面
     */
    fun openAppDetailsSettings(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开应用详情设置页面")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开应用详情设置失败", e)
            false
        }
    }
    
    /**
     * 打开电池优化设置
     */
    fun openBatteryOptimizationSettings(context: Context): Boolean {
        return OEMCompatibilityHelper.requestIgnoreBatteryOptimizations(context)
    }
    
    /**
     * 根据设备厂商打开对应的自启动设置
     */
    fun openAutoStartSettings(context: Context): Boolean {
        return OEMCompatibilityHelper.openAutoStartSettings(context)
    }
    
    /**
     * 打开小米应用管理页面（推荐方式）
     */
    fun openXiaomiAppManagement(context: Context): Boolean {
        return try {
            // 尝试直接打开应用详情页面
            val intent = Intent().apply {
                action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            FileLogger.e(TAG, "已打开小米应用管理页面")
            true
        } catch (e: Exception) {
            FileLogger.e(TAG, "打开小米应用管理页面失败，尝试备用方案", e)
            return OEMCompatibilityHelper.openXiaomiAutoStartSettings(context)
        }
    }
    
    /**
     * 标记权限设置完成
     */
    fun markPermissionConfigured(context: Context, permissionType: String) {
        val sharedPrefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)
        sharedPrefs.edit().apply {
            when (permissionType) {
                "battery_optimization" -> {
                    // 电池优化权限通过实际检查，不需要手动标记
                    putBoolean("needs_battery_optimization_whitelist", false)
                }
                "autostart" -> {
                    putBoolean("autostart_permission_granted", true)
                    putBoolean("needs_autostart_permission", false)
                }
                "background" -> {
                    putBoolean("background_permission_granted", true)
                    putBoolean("needs_background_unlimited", false)
                }
                "all" -> {
                    putBoolean("autostart_permission_granted", true)
                    putBoolean("background_permission_granted", true)
                    putBoolean("needs_battery_optimization_whitelist", false)
                    putBoolean("needs_autostart_permission", false)
                    putBoolean("needs_background_unlimited", false)
                }
            }
            putLong("permission_configured_time", System.currentTimeMillis())
            apply()
        }
        FileLogger.e(TAG, "权限设置标记已更新: $permissionType")
    }
    
    /**
     * 检查权限配置状态
     */
    fun checkPermissionStatus(context: Context): Map<String, Boolean> {
        FileLogger.e(TAG, "=== 开始检查权限配置状态 ===")
        val sharedPrefs = context.getSharedPreferences("screen_memo_prefs", Context.MODE_PRIVATE)

        // 检查实际的电池优化状态
        val batteryOptimizationGranted = OEMCompatibilityHelper.isIgnoringBatteryOptimizations(context)
        FileLogger.e(TAG, "电池优化白名单检查结果: $batteryOptimizationGranted")

        // 对于自启动和后台权限，我们只能依赖用户手动标记
        // 默认情况下这些权限都是未授权的
        val autostartGranted = sharedPrefs.getBoolean("autostart_permission_granted", false)
        val backgroundGranted = sharedPrefs.getBoolean("background_permission_granted", false)

        FileLogger.e(TAG, "自启动权限状态: $autostartGranted")
        FileLogger.e(TAG, "后台运行权限状态: $backgroundGranted")

        val result = mapOf(
            "battery_optimization" to batteryOptimizationGranted,
            "autostart" to autostartGranted,
            "background" to backgroundGranted,
            "battery_whitelist_actual" to batteryOptimizationGranted
        )

        FileLogger.e(TAG, "最终权限状态结果: $result")
        FileLogger.e(TAG, "=== 权限配置状态检查完成 ===")

        return result
    }
    
    /**
     * 获取权限设置进度
     */
    fun getPermissionProgress(context: Context): Pair<Int, Int> {
        val status = checkPermissionStatus(context)
        val completed = status.values.count { it }
        val total = status.size - 1 // 减去actual状态检查
        return Pair(completed, total)
    }
    
    /**
     * 生成权限设置报告
     */
    fun generatePermissionReport(context: Context): String {
        val status = checkPermissionStatus(context)
        val deviceInfo = OEMCompatibilityHelper.getDeviceInfo()
        val (completed, total) = getPermissionProgress(context)
        
        return """
            权限配置报告
            ============
            设备信息: $deviceInfo
            配置进度: $completed/$total
            
            详细状态:
            • 电池优化白名单: ${if (status["battery_optimization"] == true) "✓ 已配置" else "✗ 需要配置"}
            • 自启动权限: ${if (status["autostart"] == true) "✓ 已配置" else "✗ 需要配置"}
            • 后台运行权限: ${if (status["background"] == true) "✓ 已配置" else "✗ 需要配置"}
            • 实际电池优化状态: ${if (status["battery_whitelist_actual"] == true) "✓ 已生效" else "✗ 未生效"}
            
            ${if (completed == total) "🎉 所有权限配置完成！" else "⚠️ 还有权限需要配置"}
        """.trimIndent()
    }
}
