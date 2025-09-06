import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum LogLevel { debug, info, warn, error }

/// Flutter 侧日志封装：统一通过原生 FileLogger -> OutputFileLogger 落盘到
/// output/logs/YYYY/MM/DD/{DD}_info.log / {DD}_error.log。
class FlutterLogger {
  static LogLevel minLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  // 兼容旧接口
  static Future<void> log(String message) async => _write(LogLevel.info, message);

  static Future<void> debug(String message) async => _write(LogLevel.debug, message);
  static Future<void> info(String message) async => _write(LogLevel.info, message);
  static Future<void> warn(String message) async => _write(LogLevel.warn, message);
  static Future<void> error(String message) async => _write(LogLevel.error, message);

  // 直接写入原生日志
  static Future<void> native(String level, String tag, String message) async {
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
}

