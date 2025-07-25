import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题服务 - 管理应用的主题模式
class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  ThemeService() {
    _loadTheme();
  }
  
  /// 加载保存的主题设置
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_themeKey) ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeModeIndex];
    notifyListeners();
  }
  
  /// 切换主题模式
  Future<void> toggleTheme() async {
    // 循环切换：系统 -> 浅色 -> 深色 -> 系统
    switch (_themeMode) {
      case ThemeMode.system:
        _themeMode = ThemeMode.light;
        break;
      case ThemeMode.light:
        _themeMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _themeMode = ThemeMode.system;
        break;
    }
    
    // 保存到本地存储
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, _themeMode.index);
    
    notifyListeners();
  }
  
  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    
    _themeMode = mode;
    
    // 保存到本地存储
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, _themeMode.index);
    
    notifyListeners();
  }
  
  /// 获取当前主题模式的图标
  IconData get themeModeIcon {
    switch (_themeMode) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.brightness_high;
      case ThemeMode.dark:
        return Icons.brightness_4;
    }
  }
  
  /// 获取当前主题模式的描述
  String get themeModeDescription {
    switch (_themeMode) {
      case ThemeMode.system:
        return 'Auto';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}