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
      final enabled = saved ?? true;
      await setEnabled(enabled, persist: false);
      // 同步原生文件落盘与级别（确保 Release 下也能写文件）
      try {
        await _channel.invokeMethod('setFileLoggingEnabled', {
          'enabled': enabled,
        });
        await _channel.invokeMethod('setNativeLogLevel', {
          'level': enabled ? 'debug' : 'error',
        });
      } catch (_) {}
    } catch (_) {}
  }

  /// 设置是否启用日志打印（默认持久化）
  static Future<void> setEnabled(bool value, {bool persist = true}) async {
    _enabled = value;
    // 开启时打印所有级别；关闭时虽然 minLevel 仍为 error，但下面 _write/native 会短路
    minLevel = LogLevel.debug;
    // 立刻同步原生落盘与级别
    try {
      await _channel.invokeMethod('setFileLoggingEnabled', {
        'enabled': value,
      });
      await _channel.invokeMethod('setNativeLogLevel', {
        'level': value ? 'debug' : 'error',
      });
    } catch (_) {}
    if (persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_enabledKey, value);
      } catch (_) {}
    }
  }

  /// 返回今天的日志目录绝对路径（Android 原生 output/logs/yyyy/MM/dd）
  static Future<String?> getTodayLogsDir() async {
    try {
      final path = await _channel.invokeMethod<String>('getOutputLogsDirToday');
      return path;
    } catch (_) {
      return null;
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

  // ===== 友盟（Umeng）日志/错误上报桥接（已移除 SDK，方法保持为空实现以兼容旧调用） =====
  static Future<void> umengSetUserId(String userId) async {
    // no-op: Umeng SDK 已移除
  }

  static Future<void> umengBreadcrumb(String message, {String tag = 'Flutter'}) async {
    // no-op: Umeng SDK 已移除
  }

  static Future<void> umengReportError(Object error, [StackTrace? stackTrace]) async {
    // no-op: Umeng SDK 已移除
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

  // ===== 模块化日志分类开关（原生实现） =====
  static Future<void> setCategoryEnabled(String category, bool enabled) async {
    try {
      await _channel.invokeMethod('setCategoryLoggingEnabled', {
        'category': category,
        'enabled': enabled,
      });
      // 本地同步一份，便于 UI 立即读取
      try {
        final prefs = await SharedPreferences.getInstance();
        switch (category) {
          case 'ai':
            await prefs.setBool('logging_ai_enabled', enabled);
            break;
          case 'screenshot':
            await prefs.setBool('logging_screenshot_enabled', enabled);
            break;
          default:
            break;
        }
      } catch (_) {}
    } catch (_) {}
  }

  static Future<bool> getCategoryEnabled(String category) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (category) {
        case 'ai':
          return prefs.getBool('logging_ai_enabled') ?? false;
        case 'screenshot':
          return prefs.getBool('logging_screenshot_enabled') ?? false;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }
}

