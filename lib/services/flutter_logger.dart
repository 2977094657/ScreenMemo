import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

enum LogLevel { debug, info, warn, error }

/// Flutter 侧日志封装：统一通过原生 FileLogger -> OutputFileLogger 落盘到
/// output/logs/YYYY/MM/DD/{DD}_info.log / {DD}_error.log。
class FlutterLogger {
  // Release 构建：仅 error；Debug 构建：debug
  static LogLevel minLevel = kReleaseMode ? LogLevel.error : LogLevel.debug;
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  // 全局开关（默认开启）+ 持久化键
  static const String _enabledKey = 'logging_enabled';
  static bool _enabled = true;

  static bool get enabled => _enabled;

  /// 初始化：加载开关并应用最小级别
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_enabledKey);
      // 默认开启
      await setEnabled(saved ?? true, persist: false);
    } catch (_) {}
  }

  /// 设置是否启用日志打印（默认持久化）
  static Future<void> setEnabled(bool value, {bool persist = true}) async {
    _enabled = value;
    // 开启时打印所有级别；关闭时虽然 minLevel 仍为 error，但下面 _write/native 会短路
    minLevel = LogLevel.debug;
    if (persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_enabledKey, value);
      } catch (_) {}
    }
  }

  // 兼容旧接口
  static Future<void> log(String message) async => _write(LogLevel.info, message);

  static Future<void> debug(String message) async => _write(LogLevel.debug, message);
  static Future<void> info(String message) async => _write(LogLevel.info, message);
  static Future<void> warn(String message) async => _write(LogLevel.warn, message);
  static Future<void> error(String message) async => _write(LogLevel.error, message);

  // 直接写入原生日志
  static Future<void> native(String level, String tag, String message) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod('nativeLog', {
        'level': level,
        'tag': tag,
        'message': message,
      });
    } catch (_) {}
  }

  static Future<void> nativeDebug(String tag, String message) => native('debug', tag, message);
  static Future<void> nativeInfo(String tag, String message) => native('info', tag, message);
  static Future<void> nativeWarn(String tag, String message) => native('warn', tag, message);
  static Future<void> nativeError(String tag, String message) => native('error', tag, message);

  // ===== 友盟（Umeng）日志/错误上报桥接 =====
  static Future<void> umengSetUserId(String userId) async {
    try {
      await _channel.invokeMethod('umengSetUserId', {
        'userId': userId,
      });
    } catch (_) {}
  }

  static Future<void> umengBreadcrumb(String message, {String tag = 'Flutter'}) async {
    try {
      await _channel.invokeMethod('umengBreadcrumb', {
        'message': message,
        'tag': tag,
      });
    } catch (_) {}
  }

  static Future<void> umengReportError(Object error, [StackTrace? stackTrace]) async {
    try {
      await _channel.invokeMethod('umengReportError', {
        'message': error.toString(),
        'stack': (stackTrace ?? StackTrace.current).toString(),
      });
    } catch (_) {}
  }

  static bool _shouldLog(LogLevel level) => level.index >= minLevel.index;

  static Future<void> _write(LogLevel level, String message) async {
    if (!enabled) return;
    if (!_shouldLog(level)) return;
    try {
      final levelStr = () {
        switch (level) {
          case LogLevel.debug:
            return 'debug';
          case LogLevel.info:
            return 'info';
          case LogLevel.warn:
            return 'warn';
          case LogLevel.error:
            return 'error';
        }
      }();
      await _channel.invokeMethod('nativeLog', {
        'level': levelStr,
        'tag': 'Flutter',
        'message': message,
      });
    } catch (_) {}
  }

  /// 处理 Zone 拦截的 `print` 输出
  static Future<void> handlePrint(String line) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod('nativeLog', {
        'level': 'info',
        'tag': 'print',
        'message': line,
      });
    } catch (_) {}
  }
}

