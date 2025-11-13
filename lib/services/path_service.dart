import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'startup_profiler.dart';
import 'flutter_logger.dart';

/// 路径服务，提供跨平台的文件路径获取功能
class PathService {
  static const MethodChannel _channel = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  /// 获取应用内部私有目录（files）
  static Future<Directory?> getInternalAppDir([String? subDir]) async {
    StartupProfiler.begin('PathService.getInternalAppDir');
    try {
      if (Platform.isAndroid) {
        final String? path = await _channel.invokeMethod(
          'getInternalFilesDir',
          {'subDir': subDir},
        );
        if (path != null) {
          return _ensureDirectory(Directory(path));
        } else {
          try {
            await FlutterLogger.nativeWarn(
              'PathService',
              'getInternalFilesDir returned null, fallback',
            );
          } catch (_) {}
        }
      }

      final fallback = await _getInternalFallbackDirectory();
      if (fallback == null) return null;
      return _resolveSubDir(fallback, subDir);
    } catch (e) {
      try {
        await FlutterLogger.error(
          'PathService.getInternalAppDir failed: ${e.toString()}',
        );
      } catch (_) {}
      final fallback = await _getInternalFallbackDirectory();
      if (fallback == null) return null;
      return _resolveSubDir(fallback, subDir);
    } finally {
      StartupProfiler.end('PathService.getInternalAppDir');
    }
  }

  /// 兼容旧命名，内部已转向 getInternalAppDir
  @Deprecated('请改用 getInternalAppDir')
  static Future<Directory?> getExternalFilesDir([String? subDir]) =>
      getInternalAppDir(subDir);

  /// 历史外部存储目录（仅用于迁移/日志）
  static Future<Directory?> getLegacyExternalFilesDir([String? subDir]) async {
    StartupProfiler.begin('PathService.getLegacyExternalFilesDir');
    try {
      if (Platform.isAndroid) {
        final String? path = await _channel.invokeMethod(
          'getExternalFilesDir',
          {'subDir': subDir},
        );
        if (path != null) {
          return Directory(path);
        }
      }

      final fallback = await _getExternalFallbackDirectory();
      if (fallback == null) return null;
      return _resolveSubDir(fallback, subDir);
    } catch (e) {
      try {
        await FlutterLogger.error(
          'PathService.getLegacyExternalFilesDir failed: ${e.toString()}',
        );
      } catch (_) {}
      final fallback = await _getExternalFallbackDirectory();
      if (fallback == null) return null;
      return _resolveSubDir(fallback, subDir);
    } finally {
      StartupProfiler.end('PathService.getLegacyExternalFilesDir');
    }
  }

  /// 内部目录备选方案
  static Future<Directory?> _getInternalFallbackDirectory() async {
    try {
      final dir = await path_provider.getApplicationSupportDirectory();
      try {
        await FlutterLogger.debug(
          'PathService.fallback internalSupport: ${dir.path}',
        );
      } catch (_) {}
      return dir;
    } catch (e) {
      try {
        final dir = await path_provider.getApplicationDocumentsDirectory();
        try {
          await FlutterLogger.nativeWarn(
            'PathService',
            'fallback support failed, use documents: ${dir.path}',
          );
        } catch (_) {}
        return dir;
      } catch (e2) {
        try {
          await FlutterLogger.error(
            'PathService.internalFallback failed: ${e2.toString()}',
          );
        } catch (_) {}
        return null;
      }
    }
  }

  /// 外部目录备选方案（仅用于历史数据）
  static Future<Directory?> _getExternalFallbackDirectory() async {
    try {
      // 优先尝试外部存储目录
      try {
        final dir = await path_provider.getExternalStorageDirectory();
        if (dir != null) {
          try {
            await FlutterLogger.debug(
              'PathService.fallback externalStorage: ' + dir.path,
            );
          } catch (_) {}
          return dir;
        }
      } catch (e) {
        try {
          await FlutterLogger.nativeWarn(
            'PathService',
            'externalStorageDirectory failed: ' + e.toString(),
          );
        } catch (_) {}
      }

      // 如果外部存储不可用，使用应用文档目录
      final dir = await path_provider.getApplicationDocumentsDirectory();
      try {
        await FlutterLogger.debug(
          'PathService.fallback appDocuments: ' + dir.path,
        );
      } catch (_) {}
      return dir;
    } catch (e) {
      try {
        await FlutterLogger.error(
          'PathService.fallback failed: ' + e.toString(),
        );
      } catch (_) {}
      return null;
    }
  }

  /// 获取截图存储目录
  /// 这个方法专门用于获取截图文件的存储位置
  static Future<Directory?> getScreenshotDirectory() async {
    try {
      final dir = await getInternalAppDir('output/screen');
      if (dir == null) {
        try {
          await FlutterLogger.nativeWarn(
            'PathService',
            'screenshot dir is null',
          );
        } catch (_) {}
        return null;
      }
      try {
        await FlutterLogger.debug('PathService screenshot dir: ${dir.path}');
      } catch (_) {}
      return dir;
    } catch (e) {
      try {
        await FlutterLogger.error(
          'PathService.getScreenshotDirectory failed: ' + e.toString(),
        );
      } catch (_) {}
      return null;
    }
  }

  /// 获取特定应用的截图目录
  static Future<Directory?> getAppScreenshotDirectory(
    String packageName,
  ) async {
    try {
      final dir = await getInternalAppDir('output/screen/$packageName');
      if (dir == null) {
        try {
          await FlutterLogger.nativeWarn(
            'PathService',
            'app screenshot dir null: $packageName',
          );
        } catch (_) {}
        return null;
      }
      try {
        await FlutterLogger.info('PathService app dir: ${dir.path}');
      } catch (_) {}
      return dir;
    } catch (e) {
      print('PathService: 获取应用截图目录失败: $e');
      return null;
    }
  }

  /// 调试方法：获取所有可能的路径信息
  static Future<Map<String, String?>> getAllPaths() async {
    final paths = <String, String?>{};

    try {
      // Android专用路径
      if (Platform.isAndroid) {
        try {
          final androidPath = await _channel.invokeMethod(
            'getExternalFilesDir',
            {'subDir': null},
          );
          paths['android_getExternalFilesDir'] = androidPath;
        } catch (e) {
          paths['android_getExternalFilesDir'] = '错误: $e';
        }
        try {
          final androidInternal = await _channel.invokeMethod(
            'getInternalFilesDir',
            {'subDir': null},
          );
          paths['android_getInternalFilesDir'] = androidInternal;
        } catch (e) {
          paths['android_getInternalFilesDir'] = '错误: $e';
        }
      }

      // path_provider路径
      try {
        final externalStorage = await path_provider
            .getExternalStorageDirectory();
        paths['path_provider_externalStorage'] = externalStorage?.path;
      } catch (e) {
        paths['path_provider_externalStorage'] = '错误: $e';
      }

      try {
        final appDocs = await path_provider.getApplicationDocumentsDirectory();
        paths['path_provider_appDocuments'] = appDocs.path;
      } catch (e) {
        paths['path_provider_appDocuments'] = '错误: $e';
      }

      try {
        final temp = await path_provider.getTemporaryDirectory();
        paths['path_provider_temporary'] = temp.path;
      } catch (e) {
        paths['path_provider_temporary'] = '错误: $e';
      }

      // 我们的服务路径
      try {
        final internal = await getInternalAppDir(null);
        paths['pathService_internalApp'] = internal?.path;
      } catch (e) {
        paths['pathService_internalApp'] = '错误: $e';
      }

      try {
        final legacy = await getLegacyExternalFilesDir(null);
        paths['pathService_legacyExternal'] = legacy?.path;
      } catch (e) {
        paths['pathService_legacyExternal'] = '错误: $e';
      }

      try {
        final screenshotDir = await getScreenshotDirectory();
        paths['pathService_screenshot'] = screenshotDir?.path;
      } catch (e) {
        paths['pathService_screenshot'] = '错误: $e';
      }
    } catch (e) {
      paths['error'] = '通用错误: $e';
    }

    return paths;
  }

  static Future<Directory?> _resolveSubDir(
    Directory base,
    String? subDir,
  ) async {
    if (subDir == null || subDir.isEmpty) {
      return _ensureDirectory(base);
    }
    final dir = Directory('${base.path}/$subDir');
    return _ensureDirectory(dir);
  }

  static Future<Directory?> _ensureDirectory(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
