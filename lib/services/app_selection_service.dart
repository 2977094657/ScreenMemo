import 'dart:convert';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_info.dart';
import 'startup_profiler.dart';

/// 应用选择服务
class AppSelectionService {
  static final AppSelectionService _instance = AppSelectionService._internal();
  static AppSelectionService get instance => _instance;
  AppSelectionService._internal();

  static const String _selectedAppsKey = 'selected_apps';
  static const String _displayModeKey = 'display_mode';
  static const String _sortModeKey = 'sort_mode';
  static const String _screenshotIntervalKey = 'screenshot_interval';
  static const String _screenshotEnabledKey = 'screenshot_enabled';
  static const String _appsCacheKey = 'all_apps_cache';
  static const String _appsCacheTsKey = 'all_apps_cache_ts';
  static const int _appsCacheTtlSeconds = 28800; // 8小时TTL（秒）

  List<AppInfo> _allApps = [];
  List<AppInfo> _selectedApps = [];
  String _displayMode = 'grid'; // 'grid' or 'list'
  String _sortMode = 'lastScreenshot'; // 'lastScreenshot' or 'screenshotCount'
  int _screenshotInterval = 5; // 默认5秒
  bool _screenshotEnabled = false;

  /// 获取所有已安装的应用（带内存/本地缓存，避免每次进入都全量扫描）
  Future<List<AppInfo>> getAllInstalledApps({bool forceRefresh = false}) async {
    try {
      StartupProfiler.begin('AppSelectionService.getAllInstalledApps');
      // 1) 首选内存缓存
      if (!forceRefresh && _allApps.isNotEmpty) {
        StartupProfiler.end('AppSelectionService.getAllInstalledApps');
        return _allApps;
      }

      final prefs = await SharedPreferences.getInstance();

      // 2) 本地缓存（带TTL）
      if (!forceRefresh) {
        final ts = prefs.getInt(_appsCacheTsKey) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final isFresh = ts > 0 && (now - ts) <= _appsCacheTtlSeconds * 1000;
        final cached = prefs.getString(_appsCacheKey);
        if (isFresh && cached != null && cached.isNotEmpty) {
          try {
            final List<dynamic> list = jsonDecode(cached);
            _allApps = list
                .whereType<Map<String, dynamic>>()
                .map((m) => AppInfo.fromJson(m))
                .toList();
            // 排除本应用自身
            _allApps = _allApps.where((a) => a.packageName != 'com.fqyw.screen_memo').toList();
            // 确保排序一致
            _allApps.sort((a, b) => a.appName.compareTo(b.appName));
            // 如果即将过期（<60秒），提前后台续期
            final remainingMs = _appsCacheTtlSeconds * 1000 - (now - ts);
            if (remainingMs <= 60000) {
              // ignore: unawaited_futures
              getAllInstalledApps(forceRefresh: true).catchError((_) {});
            }
            StartupProfiler.end('AppSelectionService.getAllInstalledApps');
            return _allApps;
          } catch (e) {
            // 缓存解析失败，继续走全量扫描
          }
        }
      }

      // 3) 全量扫描（较慢）
      StartupProfiler.begin('InstalledApps.getInstalledApps');
      final apps = await InstalledApps.getInstalledApps(
        true, // excludeSystemApps
        true, // withIcon
        '', // packageNamePrefix
      );
      StartupProfiler.end('InstalledApps.getInstalledApps');

      _allApps = apps.map((app) => AppInfo.fromInstalledApp(app)).toList();
      // 排除本应用自身
      _allApps = _allApps.where((a) => a.packageName != 'com.fqyw.screen_memo').toList();
      _allApps.sort((a, b) => a.appName.compareTo(b.appName));

      // 4) 保存至本地缓存
      try {
        final encoded = jsonEncode(_allApps.map((a) => a.toJson()).toList());
        await prefs.setString(_appsCacheKey, encoded);
        await prefs.setInt(_appsCacheTsKey, DateTime.now().millisecondsSinceEpoch);
      } catch (e) {
        // 忽略缓存失败
      }

      StartupProfiler.end('AppSelectionService.getAllInstalledApps');
      return _allApps;
    } catch (e) {
      print('获取应用列表失败: $e');
      StartupProfiler.end('AppSelectionService.getAllInstalledApps');
      return _allApps; // 返回已有内存数据，尽量不中断
    }
  }

  /// 如果缓存过期则在后台刷新应用列表（不影响当前UI）
  Future<void> refreshAppsInBackgroundIfStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_appsCacheTsKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final isFresh = ts > 0 && (now - ts) <= _appsCacheTtlSeconds * 1000;
      if (!isFresh) {
        // 后台刷新，但不抛出异常
        // ignore: unawaited_futures
        getAllInstalledApps(forceRefresh: true).catchError((_) {});
      }
    } catch (_) {}
  }

  /// 快速获取已选择应用（优先返回内存缓存）
  Future<List<AppInfo>> getSelectedAppsFast() async {
    if (_selectedApps.isNotEmpty) return _selectedApps;
    return getSelectedApps();
  }

  /// 搜索应用
  List<AppInfo> searchApps(String query) {
    if (query.isEmpty) return _allApps;
    
    final lowerQuery = query.toLowerCase();
    return _allApps.where((app) {
      return app.appName.toLowerCase().contains(lowerQuery) ||
             app.packageName.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// 保存选中的应用
  Future<void> saveSelectedApps(List<AppInfo> selectedApps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 保存前排除本应用自身
      final filtered = selectedApps.where((a) => a.packageName != 'com.fqyw.screen_memo').toList();
      final appsJson = filtered.map((app) => app.toJson()).toList();
      await prefs.setString(_selectedAppsKey, jsonEncode(appsJson));
      _selectedApps = filtered;
    } catch (e) {
      print('保存选中应用失败: $e');
    }
  }

  /// 获取选中的应用
  Future<List<AppInfo>> getSelectedApps() async {
    try {
      StartupProfiler.begin('AppSelectionService.getSelectedApps');
      final prefs = await SharedPreferences.getInstance();
      final appsJsonString = prefs.getString(_selectedAppsKey);
      
      if (appsJsonString != null) {
        final appsJson = jsonDecode(appsJsonString) as List;
        _selectedApps = appsJson.map((json) => AppInfo.fromJson(json)).toList();
      }
      StartupProfiler.end('AppSelectionService.getSelectedApps');
      return _selectedApps;
    } catch (e) {
      print('获取选中应用失败: $e');
      StartupProfiler.end('AppSelectionService.getSelectedApps');
      return [];
    }
  }

  /// 保存显示模式
  Future<void> saveDisplayMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_displayModeKey, mode);
      _displayMode = mode;
    } catch (e) {
      print('保存显示模式失败: $e');
    }
  }

  /// 获取显示模式
  Future<String> getDisplayMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _displayMode = prefs.getString(_displayModeKey) ?? 'grid';
      return _displayMode;
    } catch (e) {
      print('获取显示模式失败: $e');
      return 'grid';
    }
  }

  /// 保存排序模式
  Future<void> saveSortMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortModeKey, mode);
      _sortMode = mode;
    } catch (e) {
      print('保存排序模式失败: $e');
    }
  }

  /// 获取排序模式
  Future<String> getSortMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sortMode = prefs.getString(_sortModeKey) ?? 'lastScreenshot';
      return _sortMode;
    } catch (e) {
      print('获取排序模式失败: $e');
      return 'lastScreenshot';
    }
  }

  /// 保存截屏间隔
  Future<void> saveScreenshotInterval(int interval) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_screenshotIntervalKey, interval);
      _screenshotInterval = interval;
      // 同步写入原生读取的偏好，避免跨端读取不一致
      await prefs.setInt('timed_screenshot_interval', interval);
      await prefs.setInt('screenshot_interval', interval);
    } catch (e) {
      print('保存截屏间隔失败: $e');
    }
  }

  /// 获取截屏间隔
  Future<int> getScreenshotInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 优先读通用键，确保与原生一致
      _screenshotInterval =
          prefs.getInt('timed_screenshot_interval') ??
          prefs.getInt('screenshot_interval') ??
          prefs.getInt(_screenshotIntervalKey) ??
          5;
      return _screenshotInterval;
    } catch (e) {
      print('获取截屏间隔失败: $e');
      return 5;
    }
  }

  /// 保存截屏开关状态
  Future<void> saveScreenshotEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_screenshotEnabledKey, enabled);
      _screenshotEnabled = enabled;
    } catch (e) {
      print('保存截屏开关状态失败: $e');
    }
  }

  /// 获取截屏开关状态
  Future<bool> getScreenshotEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _screenshotEnabled = prefs.getBool(_screenshotEnabledKey) ?? false;
      return _screenshotEnabled;
    } catch (e) {
      print('获取截屏开关状态失败: $e');
      return false;
    }
  }

  // Getters for current values
  List<AppInfo> get allApps => _allApps;
  List<AppInfo> get selectedApps => _selectedApps;
  String get displayMode => _displayMode;
  String get sortMode => _sortMode;
  int get screenshotInterval => _screenshotInterval;
  bool get screenshotEnabled => _screenshotEnabled;
}
