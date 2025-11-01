import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

/// 语言服务 - 管理应用的语言设置（跟随系统 / zh / en / ja / ko）
/// 单例 + ChangeNotifier，供 MaterialApp 和设置页订阅
class LocaleService extends ChangeNotifier {
  static final LocaleService instance = LocaleService._internal();
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  LocaleService._internal() {
    _load();
  }

  static const String _key = 'locale_option'; // 'system' | 'zh' | 'en' | 'ja' | 'ko'

  String _option = 'system'; // 当前选择
  Locale? _locale; // 为 null 表示跟随系统

  /// 当前选项：'system' | 'zh' | 'en' | 'ja' | 'ko'
  String get option => _option;

  /// 当前 Locale：为 null 表示跟随系统
  Locale? get locale => _locale;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key) ?? 'system';
    _applyOption(saved, notify: false);
    
    // 检查是否首次启动（确保启动器别名与语言设置一致）
    final isFirstInit = prefs.getBool('launcher_alias_initialized') ?? false;
    if (!isFirstInit) {
      await _updateLauncherAlias();
      await prefs.setBool('launcher_alias_initialized', true);
      return;
    }
    
    // 检查是否需要更新启动器别名（应用启动时更新）
    final needsUpdate = prefs.getBool('launcher_alias_needs_update') ?? false;
    if (needsUpdate) {
      await _updateLauncherAlias();
      await prefs.setBool('launcher_alias_needs_update', false);
    }
  }

  Future<void> setOption(String option) async {
    if (option != 'system' && option != 'zh' && option != 'en' && option != 'ja' && option != 'ko') return;
    if (_option == option) return;
    _applyOption(option, notify: true);
    // 不立即更新启动器别名，避免应用退出到桌面
    // 保存待更新标记，下次启动时更新
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _option);
    await prefs.setBool('launcher_alias_needs_update', true);
  }

  void _applyOption(String option, {required bool notify}) {
    _option = option;
    switch (option) {
      case 'system':
        _locale = null;
        break;
      case 'zh':
        _locale = const Locale('zh');
        break;
      case 'en':
        _locale = const Locale('en');
        break;
      case 'ja':
        _locale = const Locale('ja');
        break;
      case 'ko':
        _locale = const Locale('ko');
        break;
    }
    if (notify) notifyListeners();
  }

  Future<void> _updateLauncherAlias() async {
    // 仅 Android 支持通过 activity-alias 动态更新桌面名称
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid) return;
    } catch (_) {
      // 在部分平台（如测试环境）Platform 不可用，直接返回
      return;
    }
    try {
      // 计算要切换的目标语言
      String target = 'zh';
      if (_option == 'en' || _option == 'ja' || _option == 'ko') {
        target = _option;
      } else if (_option == 'system') {
        final sysLang = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
        if (sysLang.startsWith('zh')) {
          target = 'zh';
        } else if (sysLang.startsWith('ja')) {
          target = 'ja';
        } else if (sysLang.startsWith('ko')) {
          target = 'ko';
        } else {
          target = 'en';
        }
      }
      await _channel.invokeMethod('switchLauncherAlias', {'lang': target});
    } catch (_) {
      // 忽略异常，避免影响主流程
    }
  }
}