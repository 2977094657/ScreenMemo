import 'dart:async';
import 'package:flutter/services.dart';
import '../models/app_info.dart';

/// 输入法(IME)排除与说明服务
class ImeExclusionService {
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  // 兜底正则：常见输入法/键盘包名关键词
  static final List<RegExp> _imeRegexes = <RegExp>[
    RegExp('inputmethod', caseSensitive: false),
    RegExp(r'(^|\.)ime(\.|$)', caseSensitive: false),
    RegExp('keyboard', caseSensitive: false),
    RegExp('pinyin', caseSensitive: false),
    RegExp('sogou', caseSensitive: false),
    RegExp(r'baidu\.input', caseSensitive: false),
    RegExp('iflytek', caseSensitive: false),
    RegExp('swiftkey', caseSensitive: false),
    RegExp(r'qq(input|\.input)', caseSensitive: false),
    RegExp(r'google\.android\.inputmethod', caseSensitive: false),
  ];

  // 自动跳过广告/浮层类辅助应用前缀（需要排除，防止截屏归属错误）
  static final Set<String> _automationAssistPrefixes = <String>{
    'li.gkd',
    'li.songe.gkd',
  };

  static bool _isImeByRegex(String pkg) => _imeRegexes.any((re) => re.hasMatch(pkg));

  static bool _isAutomationAssist(String pkg) {
    final lower = pkg.toLowerCase();
    for (final prefix in _automationAssistPrefixes) {
      if (lower == prefix || lower.startsWith('$prefix.')) {
        return true;
      }
    }
    return false;
  }

  static bool _shouldExclude(String pkg) => _isImeByRegex(pkg) || _isAutomationAssist(pkg);

  /// 获取系统当前已启用的输入法包名集合
  static Future<Set<String>> getEnabledImePackages() async {
    try {
      final List<dynamic>? list = await _channel.invokeMethod<List<dynamic>>('getEnabledImeList');
      if (list == null) return <String>{};
      final pkgs = <String>{};
      for (final item in list) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final pkg = (map['packageName'] as String?) ?? '';
          if (pkg.isNotEmpty) pkgs.add(pkg);
        }
      }
      return pkgs;
    } catch (_) {
      return <String>{};
    }
  }

  /// 获取启用的输入法详细信息（含名称），用于展示
  static Future<List<Map<String, String>>> getEnabledImeList() async {
    try {
      final List<dynamic>? list = await _channel.invokeMethod<List<dynamic>>('getEnabledImeList');
      if (list == null) return const [];
      return list.map((e) => Map<String, String>.from(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 获取系统默认输入法信息（可能返回null）
  static Future<Map<String, String>?> getDefaultImeInfo() async {
    try {
      final Map<dynamic, dynamic>? m = await _channel.invokeMethod('getDefaultInputMethod');
      if (m == null) return null;
      final map = Map<String, dynamic>.from(m);
      return {
        'id': (map['id'] as String?) ?? '',
        'packageName': (map['packageName'] as String?) ?? '',
        'appName': (map['appName'] as String?) ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  /// 过滤掉输入法应用（启用IME + 正则兜底）
  static Future<List<AppInfo>> filterOutImeApps(List<AppInfo> input) async {
    final enabledImes = await getEnabledImePackages();
    return input.where((a) {
      final pkg = a.packageName;
      if (enabledImes.contains(pkg)) return false;
      if (_shouldExclude(pkg)) return false;
      return true;
    }).toList();
  }

  /// 基于已有应用列表，计算被排除的输入法条目（仅用于提示）
  static Future<List<AppInfo>> computeExcludedImeFrom(List<AppInfo> input) async {
    final enabledImes = await getEnabledImePackages();
    final excluded = <AppInfo>[];
    for (final a in input) {
      final pkg = a.packageName;
      if (enabledImes.contains(pkg) || _shouldExclude(pkg)) {
        excluded.add(a);
      }
    }
    // 去重
    final seen = <String>{};
    final dedup = <AppInfo>[];
    for (final a in excluded) {
      if (seen.add(a.packageName)) dedup.add(a);
    }
    return dedup;
  }
}
