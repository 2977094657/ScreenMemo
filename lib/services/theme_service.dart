import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题服务 - 管理应用的主题模式
class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _seedKey = 'theme_seed_color';
  
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF09090B); // 与 AppTheme.primary 保持一致的默认值
  
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  
  ThemeService() {
    _loadTheme();
  }
  
  /// 加载保存的主题设置
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_themeKey) ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeModeIndex];
    final savedSeed = prefs.getInt(_seedKey);
    if (savedSeed != null) {
      _seedColor = Color(savedSeed);
    }
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

  /// 设置主题主色（seed color）
  Future<void> setSeedColor(Color color) async {
    if (_seedColor.value == color.value) return;
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedKey, _seedColor.value);
    notifyListeners();
  }

  /// 重置主题主色为默认（与设计基色一致）
  Future<void> resetSeedColor() async {
    _seedColor = const Color(0xFF09090B);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedKey, _seedColor.value);
    notifyListeners();
  }
  
  /// 获取当前主题模式的图标
  IconData get themeModeIcon {
    switch (_themeMode) {
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
      case ThemeMode.light:
        return Icons.brightness_high_outlined;
      case ThemeMode.dark:
        return Icons.brightness_4_outlined;
    }
  }
  
  /// 获取当前主题模式的描述
  String get themeModeDescription {
    switch (_themeMode) {
      case ThemeMode.system:
        return 'Auto'; // 文案由 UI 侧使用本地化
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}