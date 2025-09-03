import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'path_service.dart';

/// Flutter 侧简单文件日志器
/// 将关键调试信息写入外部 files/logs/flutter_debug.log，便于在设备上查看
enum LogLevel { debug, info, warn, error }

/// Flutter 侧简单文件日志器（支持日志级别与编译模式配置）
class FlutterLogger {
  static File? _logFile;
  static LogLevel minLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  /// 追加一行 INFO 日志（兼容原接口）
  static Future<void> log(String message) async {
    await _write(LogLevel.info, message);
  }

  static Future<void> debug(String message) async {
    await _write(LogLevel.debug, message);
  }

  static Future<void> info(String message) async {
    await _write(LogLevel.info, message);
  }

  static Future<void> warn(String message) async {
    await _write(LogLevel.warn, message);
  }

  static Future<void> error(String message) async {
    await _write(LogLevel.error, message);
  }

  // 写入到 Android 原生 FileLogger（screen_memo_debug.log）
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

  static bool _shouldLog(LogLevel level) {
    return level.index >= minLevel.index;
  }

  static Future<void> _write(LogLevel level, String message) async {
    if (!_shouldLog(level)) return;
    try {
      final file = await _ensureFile();
      final ts = DateTime.now().toIso8601String();
      final tag = () {
        switch (level) {
          case LogLevel.debug:
            return 'DEBUG';
          case LogLevel.info:
            return 'INFO';
          case LogLevel.warn:
            return 'WARN';
          case LogLevel.error:
            return 'ERROR';
        }
      }();
      await file.writeAsString('$ts [$tag] $message\n', mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  /// 读取全部日志
  static Future<String> readAll() async {
    try {
      final file = await _ensureFile();
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 读取日志尾部 N 行（简易实现：按行拆分后截尾）
  static Future<String> readTail(int lines) async {
    try {
      final all = await readAll();
      final arr = all.split('\n');
      if (arr.length <= lines) return all;
      return arr.sublist(arr.length - lines).join('\n');
    } catch (_) {
      return '';
    }
  }

  /// 返回日志文件绝对路径
  static Future<String?> getLogFilePath() async {
    try {
      final f = await _ensureFile();
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// 清空日志文件
  static Future<void> clear() async {
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        await f.writeAsString('');
      }
    } catch (_) {}
  }

  static Future<File> _ensureFile() async {
    if (_logFile != null) return _logFile!;
    final baseDir = await PathService.getExternalFilesDir(null);
    if (baseDir == null) {
      // 回退到临时目录
      final tmp = Directory.systemTemp;
      _logFile = File(p.join(tmp.path, 'flutter_debug.log'));
      return _logFile!;
    }
    final logsDir = Directory(p.join(baseDir.path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    _logFile = File(p.join(logsDir.path, 'flutter_debug.log'));
    return _logFile!;
  }
}


