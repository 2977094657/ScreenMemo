import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

/// 路径服务，提供跨平台的文件路径获取功能
class PathService {
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  /// 获取应用专用的外部存储目录
  /// 在Android上，这对应 Context.getExternalFilesDir()
  /// 在其他平台上，使用path_provider的相应方法
  static Future<Directory?> getExternalFilesDir([String? subDir]) async {
    try {
      if (Platform.isAndroid) {
        // Android平台：使用Method Channel调用原生getExternalFilesDir
        final String? path = await _channel.invokeMethod('getExternalFilesDir', {
          'subDir': subDir,
        });
        
        if (path != null) {
          print('PathService: Android getExternalFilesDir($subDir) = $path');
          return Directory(path);
        } else {
          print('PathService: Android getExternalFilesDir返回null，使用备选方案');
          // 如果失败，使用备选方案
          return await _getFallbackDirectory();
        }
      } else {
        // 其他平台：使用path_provider
        return await _getFallbackDirectory();
      }
    } catch (e) {
      print('PathService: 获取外部文件目录失败: $e');
      // 出错时使用备选方案
      return await _getFallbackDirectory();
    }
  }

  /// 备选目录获取方案
  static Future<Directory?> _getFallbackDirectory() async {
    try {
      // 优先尝试外部存储目录
      try {
        final dir = await path_provider.getExternalStorageDirectory();
        if (dir != null) {
          print('PathService: 使用getExternalStorageDirectory: ${dir.path}');
          return dir;
        }
      } catch (e) {
        print('PathService: getExternalStorageDirectory失败: $e');
      }
      
      // 如果外部存储不可用，使用应用文档目录
      final dir = await path_provider.getApplicationDocumentsDirectory();
      print('PathService: 使用getApplicationDocumentsDirectory: ${dir.path}');
      return dir;
    } catch (e) {
      print('PathService: 所有备选方案都失败: $e');
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
        print('PathService: 无法获取基础目录');
        return null;
      }

      // 创建截图专用目录：output/screen
      final screenshotDir = Directory('${baseDir.path}/output/screen');
      
      // 确保目录存在
      if (!await screenshotDir.exists()) {
        await screenshotDir.create(recursive: true);
        print('PathService: 创建截图目录: ${screenshotDir.path}');
      }

      print('PathService: 截图目录: ${screenshotDir.path}');
      return screenshotDir;
    } catch (e) {
      print('PathService: 获取截图目录失败: $e');
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
        print('PathService: 创建应用截图目录: ${appDir.path}');
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
          paths['android_getExternalFilesDir'] = 'Error: $e';
        }
      }

      // path_provider路径
      try {
        final externalStorage = await path_provider.getExternalStorageDirectory();
        paths['path_provider_externalStorage'] = externalStorage?.path;
      } catch (e) {
        paths['path_provider_externalStorage'] = 'Error: $e';
      }

      try {
        final appDocs = await path_provider.getApplicationDocumentsDirectory();
        paths['path_provider_appDocuments'] = appDocs.path;
      } catch (e) {
        paths['path_provider_appDocuments'] = 'Error: $e';
      }

      try {
        final temp = await path_provider.getTemporaryDirectory();
        paths['path_provider_temporary'] = temp.path;
      } catch (e) {
        paths['path_provider_temporary'] = 'Error: $e';
      }

      // 我们的服务路径
      try {
        final ourExternal = await getExternalFilesDir(null);
        paths['pathService_externalFiles'] = ourExternal?.path;
      } catch (e) {
        paths['pathService_externalFiles'] = 'Error: $e';
      }

      try {
        final screenshotDir = await getScreenshotDirectory();
        paths['pathService_screenshot'] = screenshotDir?.path;
      } catch (e) {
        paths['pathService_screenshot'] = 'Error: $e';
      }

    } catch (e) {
      paths['error'] = 'General error: $e';
    }

    return paths;
  }
}
