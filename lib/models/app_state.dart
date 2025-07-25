import 'package:flutter/foundation.dart';

/// 应用状态管理
class AppState extends ChangeNotifier {
  static AppState? _instance;
  static AppState get instance => _instance ??= AppState._();
  
  AppState._();
  
  // 权限状态
  bool _accessibilityEnabled = false;
  bool _mediaProjectionGranted = false;
  bool _storagePermissionGranted = false;
  bool _notificationPermissionGranted = false;
  bool _usageStatsPermissionGranted = false;
  
  // 服务状态
  bool _isServiceRunning = false;
  bool _isCapturing = false;
  
  // 应用状态
  bool _isFirstLaunch = true;
  bool _isLoading = false;
  String? _errorMessage;
  
  // Getters
  bool get accessibilityEnabled => _accessibilityEnabled;
  bool get mediaProjectionGranted => _mediaProjectionGranted;
  bool get storagePermissionGranted => _storagePermissionGranted;
  bool get notificationPermissionGranted => _notificationPermissionGranted;
  bool get usageStatsPermissionGranted => _usageStatsPermissionGranted;
  bool get isServiceRunning => _isServiceRunning;
  bool get isCapturing => _isCapturing;
  bool get isFirstLaunch => _isFirstLaunch;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  /// 检查所有权限是否已授予
  bool get allPermissionsGranted =>
      _accessibilityEnabled &&
      _mediaProjectionGranted &&
      _storagePermissionGranted &&
      _notificationPermissionGranted &&
      _usageStatsPermissionGranted;
  
  /// 获取权限完成度百分比
  double get permissionProgress {
    int granted = 0;
    int total = 5;

    if (_accessibilityEnabled) granted++;
    if (_mediaProjectionGranted) granted++;
    if (_storagePermissionGranted) granted++;
    if (_notificationPermissionGranted) granted++;
    if (_usageStatsPermissionGranted) granted++;

    return granted / total;
  }
  
  /// 获取未授予的权限列表
  List<String> get missingPermissions {
    final missing = <String>[];

    if (!_storagePermissionGranted) missing.add('存储权限');
    if (!_notificationPermissionGranted) missing.add('通知权限');
    if (!_accessibilityEnabled) missing.add('无障碍服务');
    if (!_mediaProjectionGranted) missing.add('屏幕录制权限');
    if (!_usageStatsPermissionGranted) missing.add('使用统计权限');

    return missing;
  }
  
  // Setters
  void setAccessibilityEnabled(bool enabled) {
    if (_accessibilityEnabled != enabled) {
      _accessibilityEnabled = enabled;
      notifyListeners();
    }
  }
  
  void setMediaProjectionGranted(bool granted) {
    if (_mediaProjectionGranted != granted) {
      _mediaProjectionGranted = granted;
      notifyListeners();
    }
  }
  
  void setStoragePermissionGranted(bool granted) {
    if (_storagePermissionGranted != granted) {
      _storagePermissionGranted = granted;
      notifyListeners();
    }
  }
  
  void setNotificationPermissionGranted(bool granted) {
    if (_notificationPermissionGranted != granted) {
      _notificationPermissionGranted = granted;
      notifyListeners();
    }
  }

  void setUsageStatsPermissionGranted(bool granted) {
    if (_usageStatsPermissionGranted != granted) {
      _usageStatsPermissionGranted = granted;
      notifyListeners();
    }
  }
  
  void setServiceRunning(bool running) {
    if (_isServiceRunning != running) {
      _isServiceRunning = running;
      notifyListeners();
    }
  }
  
  void setCapturing(bool capturing) {
    if (_isCapturing != capturing) {
      _isCapturing = capturing;
      notifyListeners();
    }
  }
  
  void setFirstLaunch(bool isFirst) {
    if (_isFirstLaunch != isFirst) {
      _isFirstLaunch = isFirst;
      notifyListeners();
    }
  }
  
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }
  
  void setError(String? error) {
    if (_errorMessage != error) {
      _errorMessage = error;
      notifyListeners();
    }
  }
  
  /// 清除错误信息
  void clearError() {
    setError(null);
  }
  
  /// 更新所有权限状态
  void updatePermissions({
    bool? accessibility,
    bool? mediaProjection,
    bool? storage,
    bool? notification,
    bool? usageStats,
  }) {
    bool changed = false;
    
    if (accessibility != null && _accessibilityEnabled != accessibility) {
      _accessibilityEnabled = accessibility;
      changed = true;
    }
    
    if (mediaProjection != null && _mediaProjectionGranted != mediaProjection) {
      _mediaProjectionGranted = mediaProjection;
      changed = true;
    }
    
    if (storage != null && _storagePermissionGranted != storage) {
      _storagePermissionGranted = storage;
      changed = true;
    }
    
    if (notification != null && _notificationPermissionGranted != notification) {
      _notificationPermissionGranted = notification;
      changed = true;
    }

    if (usageStats != null && _usageStatsPermissionGranted != usageStats) {
      _usageStatsPermissionGranted = usageStats;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }
  
  /// 重置所有状态
  void reset() {
    _accessibilityEnabled = false;
    _mediaProjectionGranted = false;
    _storagePermissionGranted = false;
    _notificationPermissionGranted = false;
    _usageStatsPermissionGranted = false;
    _isServiceRunning = false;
    _isCapturing = false;
    _isFirstLaunch = true;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
