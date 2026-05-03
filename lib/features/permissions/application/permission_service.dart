import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';
import 'package:screen_memo/core/performance/startup_profiler.dart';

/// 权限管理服务
class PermissionService with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  static PermissionService? _instance;
  static PermissionService get instance => _instance ??= PermissionService._();

  // 权限状态监听定时器
  Timer? _permissionCheckTimer;
  bool _isMonitoring = false;

  PermissionService._() {
    _setupMethodCallHandler();
    WidgetsBinding.instance.addObserver(this);
    // 监控改为延后启动，避免冷启动时频繁检查
  }

  // 权限状态回调
  Function(bool)? onAccessibilityChanged;
  Function(bool)? onMediaProjectionChanged;
  Function()? onPermissionsUpdated;

  /// 设置方法调用处理器
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAccessibilityResult':
          final enabled = call.arguments['enabled'] as bool;
          await _saveAccessibilityStatus(enabled);
          onAccessibilityChanged?.call(enabled);
          break;
        case 'onScreenshotSaved':
          try {
            // 将截图保存事件转发给 ScreenshotService 处理并入库
            final Map<String, dynamic> args = Map<String, dynamic>.from(
              call.arguments as Map,
            );
            // 允许包含可选的 pageUrl 字段
            await ScreenshotService.instance.handleScreenshotSavedFromPlatform(
              args,
            );
          } catch (e) {
            // 忽略异常，避免阻断其他事件
            // print('转发onScreenshotSaved失败: $e');
          }
          break;
        case 'onMediaProjectionResult':
          // 废弃的MediaProjection处理，现在不再需要
          break;
      }
    });
  }

  /// 检查所有必要权限
  Future<Map<String, bool>> checkAllPermissions() async {
    StartupProfiler.begin('PermissionService.checkAllPermissions');
    final results = <String, bool>{};

    // 检查基础权限
    results['storage'] = await _checkStoragePermission();
    results['notification'] = await _checkNotificationPermission();

    // 检查无障碍服务权限
    results['accessibility'] = await checkAccessibilityPermission();

    // 检查使用统计权限
    results['usage_stats'] = await checkUsageStatsPermission();

    StartupProfiler.end('PermissionService.checkAllPermissions');
    return results;
  }

  /// 检查存储权限
  Future<bool> _checkStoragePermission() async {
    // 应用仅写入 app 私有外部目录并在 Android 10+ 使用 MediaStore 导出，
    // 不再需要传统 READ/WRITE_EXTERNAL_STORAGE 运行时权限，统一视为“已授权”。
    return true;
  }

  /// 检查通知权限
  Future<bool> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// 请求基础权限
  Future<bool> requestBasicPermissions() async {
    try {
      // 存储权限在 Android 10+ 默认无需；统一视为已授权
      await _saveStorageStatus(true);

      // 仅请求通知权限
      final notificationStatus = await Permission.notification.request();

      // 立即强制刷新权限状态并通知UI
      await forceRefreshPermissions();
      onPermissionsUpdated?.call();

      return notificationStatus.isGranted;
    } catch (e) {
      print('请求基础权限失败: $e');
      return false;
    }
  }

  /// 更新所有权限状态
  Future<void> _updatePermissionStates() async {
    final permissions = await checkAllPermissions();

    // 触发状态更新回调
    if (permissions['accessibility'] != null) {
      onAccessibilityChanged?.call(permissions['accessibility']!);
    }
    if (permissions['mediaProjection'] != null) {
      onMediaProjectionChanged?.call(permissions['mediaProjection']!);
    }
  }

  /// 从系统设置返回时检查权限状态
  Future<void> refreshPermissionStates() async {
    await _updatePermissionStates();
  }

  /// 立即检查并更新所有权限状态（用于权限授权后的即时刷新）
  Future<void> forceRefreshPermissions() async {
    print('强制刷新权限状态...');
    try {
      // 立即检查所有权限状态
      await _checkPermissionChanges();

      // 触发UI更新
      onPermissionsUpdated?.call();

      print('权限状态强制刷新完成');
    } catch (e) {
      print('强制刷新权限状态失败: $e');
    }
  }

  /// 应用生命周期状态改变时的回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台时，刷新权限状态
      refreshPermissionStates();
      onPermissionsUpdated?.call();
    }
  }

  /// 请求通知权限
  Future<bool> requestNotificationPermission() async {
    try {
      print('开始请求通知权限...');

      // 检查当前状态
      final currentStatus = await Permission.notification.status;
      print('当前通知权限状态: $currentStatus');

      if (currentStatus.isGranted) {
        print('通知权限已授权');
        return true;
      }

      // 请求权限
      final status = await Permission.notification.request();
      print('请求通知权限结果: $status');

      // 立即更新权限状态
      await _updatePermissionStates();
      onPermissionsUpdated?.call();

      return status.isGranted;
    } catch (e) {
      print('请求通知权限失败: $e');
      return false;
    }
  }

  /// 请求存储权限（默认通过）
  Future<bool> requestStoragePermission() async {
    try {
      // 不再弹系统对话框，直接视为已授权
      await _saveStorageStatus(true);

      // 立即强制刷新权限状态并通知UI
      await forceRefreshPermissions();
      onPermissionsUpdated?.call();

      return true;
    } catch (e) {
      print('请求存储权限失败: $e');
      // 为避免阻断首启流程，保守返回 true
      return true;
    }
  }

  /// 开始权限状态监听
  /// 显式启动权限状态监听（降低为每3秒，且由调用方按需触发）
  void startMonitoring({Duration interval = const Duration(seconds: 3)}) {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _permissionCheckTimer = Timer.periodic(interval, (timer) {
      _checkPermissionChanges();
    });
    print('权限状态监听已启动');
  }

  /// 停止权限状态监听
  void _stopPermissionMonitoring() {
    _permissionCheckTimer?.cancel();
    _permissionCheckTimer = null;
    _isMonitoring = false;
    print('权限状态监听已停止');
  }

  /// 检查权限变化
  Future<void> _checkPermissionChanges() async {
    try {
      // 检查无障碍服务权限
      final currentAccessibilityStatus = await checkAccessibilityPermission();
      final savedAccessibilityStatus = await getAccessibilityStatus();

      if (currentAccessibilityStatus != savedAccessibilityStatus) {
        print(
          '检测到无障碍权限状态变化: $savedAccessibilityStatus -> $currentAccessibilityStatus',
        );
        await _saveAccessibilityStatus(currentAccessibilityStatus);
        onAccessibilityChanged?.call(currentAccessibilityStatus);
        onPermissionsUpdated?.call();
      }

      // 检查其他权限状态变化
      await _checkOtherPermissionChanges();
    } catch (e) {
      print('检查权限变化失败: $e');
    }
  }

  /// 检查其他权限状态变化
  Future<void> _checkOtherPermissionChanges() async {
    try {
      final currentPermissions = await checkAllPermissions();

      // 检查存储权限
      final currentStorage = currentPermissions['storage'] ?? false;
      final savedStorage = await _getStorageStatus();
      if (currentStorage != savedStorage) {
        print('检测到存储权限状态变化: $savedStorage -> $currentStorage');
        await _saveStorageStatus(currentStorage);
        onPermissionsUpdated?.call();
      }

      // 检查通知权限
      final currentNotification = currentPermissions['notification'] ?? false;
      final savedNotification = await _getNotificationStatus();
      if (currentNotification != savedNotification) {
        print('检测到通知权限状态变化: $savedNotification -> $currentNotification');
        await _saveNotificationStatus(currentNotification);
        onPermissionsUpdated?.call();
      }
    } catch (e) {
      print('检查其他权限变化失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _stopPermissionMonitoring();
    WidgetsBinding.instance.removeObserver(this);
  }

  /// 检查无障碍服务权限
  Future<bool> checkAccessibilityPermission() async {
    try {
      final result = await _channel.invokeMethod(
        'checkAccessibilityPermission',
      );
      return result as bool;
    } catch (e) {
      print('检查无障碍权限失败: $e');
      return false;
    }
  }

  /// 请求无障碍服务权限
  Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      print('请求无障碍权限失败: $e');
    }
  }

  /// 检查服务是否运行
  Future<bool> isServiceRunning() async {
    try {
      StartupProfiler.begin('PermissionService.isServiceRunning');
      final result = await _channel.invokeMethod('isServiceRunning');
      StartupProfiler.end('PermissionService.isServiceRunning');
      return result as bool;
    } catch (e) {
      print('检查服务状态失败: $e');
      StartupProfiler.end('PermissionService.isServiceRunning');
      return false;
    }
  }

  /// 启动前台服务
  Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (e) {
      print('启动前台服务失败: $e');
    }
  }

  /// 停止前台服务
  Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (e) {
      print('停止前台服务失败: $e');
    }
  }

  /// 开始屏幕截图服务
  Future<bool> startScreenCapture() async {
    try {
      final result = await _channel.invokeMethod('startScreenCapture');
      return result as bool;
    } catch (e) {
      print('开始屏幕截图失败: $e');
      return false;
    }
  }

  /// 停止屏幕截图服务
  Future<void> stopScreenCapture() async {
    try {
      await _channel.invokeMethod('stopScreenCapture');
    } catch (e) {
      print('停止屏幕截图失败: $e');
    }
  }

  /// 启动定时截屏
  Future<bool> startTimedScreenshot(int intervalSeconds) async {
    try {
      final result = await _channel.invokeMethod('startTimedScreenshot', {
        'interval': intervalSeconds,
      });
      return result as bool;
    } catch (e) {
      print('启动定时截屏失败: $e');
      return false;
    }
  }

  /// 停止定时截屏
  Future<void> stopTimedScreenshot() async {
    try {
      await _channel.invokeMethod('stopTimedScreenshot');
    } catch (e) {
      print('停止定时截屏失败: $e');
    }
  }

  /// 手动截取屏幕
  Future<String?> captureScreen() async {
    try {
      final result = await _channel.invokeMethod('captureScreen');
      return result as String?; // 返回保存的文件路径
    } catch (e) {
      print('截取屏幕失败: $e');
      return null;
    }
  }

  /// 保存无障碍服务状态
  Future<void> _saveAccessibilityStatus(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('accessibility_enabled', enabled);
  }

  /// 获取无障碍服务状态
  Future<bool> getAccessibilityStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('accessibility_enabled') ?? false;
  }

  /// 保存存储权限状态
  Future<void> _saveStorageStatus(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('storage_permission_granted', granted);
  }

  /// 获取存储权限状态
  Future<bool> _getStorageStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('storage_permission_granted') ?? false;
  }

  /// 保存通知权限状态
  Future<void> _saveNotificationStatus(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_permission_granted', granted);
  }

  /// 获取通知权限状态
  Future<bool> _getNotificationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notification_permission_granted') ?? false;
  }

  /// 保存首次启动标记
  Future<void> setFirstLaunch(bool isFirst) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', isFirst);
  }

  /// 检查是否首次启动
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_first_launch') ?? true;
  }

  /// 保存引导完成标记
  Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', completed);
  }

  /// 检查引导是否已完成
  Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_completed') ?? false;
  }

  /// 检查所有权限是否已授予
  Future<bool> areAllPermissionsGranted() async {
    final permissions = await checkAllPermissions();
    return permissions.values.every((granted) => granted);
  }

  /// 获取未授予的权限列表
  Future<List<String>> getMissingPermissions() async {
    final permissions = await checkAllPermissions();
    return permissions.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  /// 检查使用统计权限
  Future<bool> checkUsageStatsPermission() async {
    try {
      // 调用原生方法检查UsageStats权限
      final result = await _channel.invokeMethod('checkUsageStatsPermission');
      return result == true;
    } catch (e) {
      print('检查使用统计权限失败: $e');
      return false;
    }
  }

  /// 请求使用统计权限
  Future<bool> requestUsageStatsPermission() async {
    try {
      // 调用原生方法请求UsageStats权限
      final result = await _channel.invokeMethod('requestUsageStatsPermission');

      // 立即强制刷新权限状态
      await forceRefreshPermissions();

      return result == true;
    } catch (e) {
      print('请求使用统计权限失败: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getPendingRuntimeDiagnostic() async {
    try {
      final result = await _channel.invokeMethod('getPendingRuntimeDiagnostic');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      print('获取待处理运行诊断失败: $e');
      return null;
    }
  }

  Future<void> markRuntimeDiagnosticHandled([String? id]) async {
    try {
      await _channel.invokeMethod('markRuntimeDiagnosticHandled', {
        if (id != null) 'id': id,
      });
    } catch (e) {
      print('标记运行诊断已处理失败: $e');
    }
  }

  Future<bool> openDiagnosticFile(String path) async {
    try {
      final result = await _channel.invokeMethod('openDiagnosticFile', {
        'path': path,
      });
      return result == true;
    } catch (e) {
      print('打开诊断文件失败: $e');
      return false;
    }
  }

  Future<String?> getPermissionReport() async {
    try {
      final result = await _channel.invokeMethod<String>('getPermissionReport');
      return result;
    } catch (e) {
      print('获取权限报告失败: $e');
      return null;
    }
  }
}
