import 'dart:convert';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_info.dart';

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

  List<AppInfo> _allApps = [];
  List<AppInfo> _selectedApps = [];
  String _displayMode = 'grid'; // 'grid' or 'list'
  String _sortMode = 'lastScreenshot'; // 'lastScreenshot' or 'screenshotCount'
  int _screenshotInterval = 5; // 默认5秒
  bool _screenshotEnabled = false;

  /// 获取所有已安装的应用
  Future<List<AppInfo>> getAllInstalledApps() async {
    try {
      final apps = await InstalledApps.getInstalledApps(
        true, // excludeSystemApps
        true, // withIcon
        '', // packageNamePrefix
      );

      _allApps = apps.map((app) => AppInfo.fromInstalledApp(app)).toList();
      
      // 按应用名称排序
      _allApps.sort((a, b) => a.appName.compareTo(b.appName));
      
      return _allApps;
    } catch (e) {
      print('获取应用列表失败: $e');
      return [];
    }
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
      final appsJson = selectedApps.map((app) => app.toJson()).toList();
      await prefs.setString(_selectedAppsKey, jsonEncode(appsJson));
      _selectedApps = selectedApps;
    } catch (e) {
      print('保存选中应用失败: $e');
    }
  }

  /// 获取选中的应用
  Future<List<AppInfo>> getSelectedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appsJsonString = prefs.getString(_selectedAppsKey);
      
      if (appsJsonString != null) {
        final appsJson = jsonDecode(appsJsonString) as List;
        _selectedApps = appsJson.map((json) => AppInfo.fromJson(json)).toList();
      }
      
      return _selectedApps;
    } catch (e) {
      print('获取选中应用失败: $e');
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
    } catch (e) {
      print('保存截屏间隔失败: $e');
    }
  }

  /// 获取截屏间隔
  Future<int> getScreenshotInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _screenshotInterval = prefs.getInt(_screenshotIntervalKey) ?? 5;
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
