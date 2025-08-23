import 'dart:io';
import 'package:path/path.dart' as p;
import 'path_service.dart';

/// Flutter 侧简单文件日志器
/// 将关键调试信息写入外部 files/logs/flutter_debug.log，便于在设备上查看
class FlutterLogger {
  static File? _logFile;

  /// 追加一行日志
  static Future<void> log(String message) async {
    try {
      final file = await _ensureFile();
      final ts = DateTime.now().toIso8601String();
      await file.writeAsString('$ts [FLUTTER] $message\n', mode: FileMode.append, flush: false);
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


