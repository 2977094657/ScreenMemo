import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'startup_profiler.dart';
import 'flutter_logger.dart';

/// 路径服务，提供跨平台的文件路径获取功能
class PathService {
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  /// 获取应用专用的外部存储目录
  /// 在Android上，这对应 Context.getExternalFilesDir()
  /// 在其他平台上，使用path_provider的相应方法
  static Future<Directory?> getExternalFilesDir([String? subDir]) async {
    try {
      StartupProfiler.begin('PathService.getExternalFilesDir');
      if (Platform.isAndroid) {
        // Android平台：使用Method Channel调用原生getExternalFilesDir
        final String? path = await _channel.invokeMethod('getExternalFilesDir', {
          'subDir': subDir,
        });
        
        if (path != null) {
          StartupProfiler.end('PathService.getExternalFilesDir');
          return Directory(path);
        } else {
          try { await FlutterLogger.nativeWarn('PathService', 'getExternalFilesDir returned null, fallback'); } catch (_) {}
          // 如果失败，使用备选方案
          final dir = await _getFallbackDirectory();
          StartupProfiler.end('PathService.getExternalFilesDir');
          return dir;
        }
      } else {
        // 其他平台：使用path_provider
        final dir = await _getFallbackDirectory();
        StartupProfiler.end('PathService.getExternalFilesDir');
        return dir;
      }
    } catch (e) {
      try { await FlutterLogger.error('PathService.getExternalFilesDir failed: '+e.toString()); } catch (_) {}
      // 出错时使用备选方案
      final dir = await _getFallbackDirectory();
      StartupProfiler.end('PathService.getExternalFilesDir');
      return dir;
    }
  }

  /// 备选目录获取方案
  static Future<Directory?> _getFallbackDirectory() async {
    try {
      // 优先尝试外部存储目录
      try {
        final dir = await path_provider.getExternalStorageDirectory();
        if (dir != null) {
          try { await FlutterLogger.debug('PathService.fallback externalStorage: '+dir.path); } catch (_) {}
          return dir;
        }
      } catch (e) {
        try { await FlutterLogger.nativeWarn('PathService', 'externalStorageDirectory failed: '+e.toString()); } catch (_) {}
      }
      
      // 如果外部存储不可用，使用应用文档目录
      final dir = await path_provider.getApplicationDocumentsDirectory();
      try { await FlutterLogger.debug('PathService.fallback appDocuments: '+dir.path); } catch (_) {}
      return dir;
    } catch (e) {
      try { await FlutterLogger.error('PathService.fallback failed: '+e.toString()); } catch (_) {}
      return null;
    }
  }

  /// 获取截图存储目录
  /// 这个方法专门用于获取截图文件的存储位置
  static Future<Directory?> getScreenshotDirectory() async {
    try {
      // 获取应用专用外部存储目录
      final baseDir = await getExternalFilesDir(null);
      if (baseDir == null) {
        try { await FlutterLogger.nativeWarn('PathService', 'baseDir is null'); } catch (_) {}
        return null;
      }

      // 创建截图专用目录：output/screen
      final screenshotDir = Directory('${baseDir.path}/output/screen');
      
      // 确保目录存在
      if (!await screenshotDir.exists()) {
        await screenshotDir.create(recursive: true);
        try { await FlutterLogger.info('PathService created screenshot dir: '+screenshotDir.path); } catch (_) {}
      }

      try { await FlutterLogger.debug('PathService screenshot dir: '+screenshotDir.path); } catch (_) {}
      return screenshotDir;
    } catch (e) {
      try { await FlutterLogger.error('PathService.getScreenshotDirectory failed: '+e.toString()); } catch (_) {}
      return null;
    }
  }

  /// 获取特定应用的截图目录
  static Future<Directory?> getAppScreenshotDirectory(String packageName) async {
    try {
      final screenshotDir = await getScreenshotDirectory();
      if (screenshotDir == null) {
        return null;
      }

      final appDir = Directory('${screenshotDir.path}/$packageName');
      
      // 确保目录存在
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
        try { await FlutterLogger.info('PathService created app dir: '+appDir.path); } catch (_) {}
      }

      return appDir;
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
          final androidPath = await _channel.invokeMethod('getExternalFilesDir', {'subDir': null});
          paths['android_getExternalFilesDir'] = androidPath;
        } catch (e) {
          paths['android_getExternalFilesDir'] = '错误: $e';
        }
      }

      // path_provider路径
      try {
        final externalStorage = await path_provider.getExternalStorageDirectory();
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
        final ourExternal = await getExternalFilesDir(null);
        paths['pathService_externalFiles'] = ourExternal?.path;
      } catch (e) {
        paths['pathService_externalFiles'] = '错误: $e';
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
}
