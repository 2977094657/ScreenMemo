import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'permission_service.dart';
import 'screenshot_database.dart';
import 'path_service.dart';
import '../models/screenshot_record.dart';
import 'startup_profiler.dart';

/// 截屏服务异常类
class ScreenshotServiceException implements Exception {
  final String message;
  const ScreenshotServiceException(this.message);
  
  @override
  String toString() => message;
}

/// 截屏服务管理类
class ScreenshotService {
  static ScreenshotService? _instance;
  static ScreenshotService get instance => _instance ??= ScreenshotService._();
  
  ScreenshotService._() {
    _setupMethodChannelHandlers();
  }
  
  final PermissionService _permissionService = PermissionService.instance;
  final ScreenshotDatabase _database = ScreenshotDatabase.instance;
  
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  final _screenshotStreamController = StreamController<void>.broadcast();
  Stream<void> get onScreenshotSaved => _screenshotStreamController.stream;
  
  bool _isRunning = false;
  int _currentInterval = 5;
  // 统计缓存键与节流
  static const String _statsCacheKey = 'stats_cache';
  static const String _statsCacheTsKey = 'stats_cache_ts';
  static const String _statsCacheTtlSecondsKey = 'stats_cache_ttl';
  static const int _statsCacheTtlSecondsDefault = 600; // 10分钟
  static const String _lastSyncTsKey = 'stats_last_sync_ts';
  static const int _syncThrottleSeconds = 120; // 2分钟
  
  /// 检查截屏服务是否正在运行
  bool get isRunning => _isRunning;
  
  /// 获取当前截屏间隔
  int get currentInterval => _currentInterval;

  /// 兼容方法名：优先使用缓存，缓存失效则重新计算
  Future<Map<String, dynamic>> getScreenshotStatsCachedFirst() async {
    StartupProfiler.begin('ScreenshotService.getScreenshotStatsCachedFirst');
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_statsCacheKey);
      final ts = prefs.getInt(_statsCacheTsKey) ?? 0;
      final ttl = prefs.getInt(_statsCacheTtlSecondsKey) ?? _statsCacheTtlSecondsDefault;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (cached != null && ts > 0 && (now - ts) <= ttl * 1000) {
        final map = _deserializeStats(cached);
        // 后台异步刷新缓存
        // ignore: unawaited_futures
        _refreshStatsCacheIfStale();
        StartupProfiler.end('ScreenshotService.getScreenshotStatsCachedFirst');
        return map;
      }
    } catch (_) {}
    // 缓存不存在或已过期，重新计算
    final stats = await getScreenshotStats();
    StartupProfiler.end('ScreenshotService.getScreenshotStatsCachedFirst');
    return stats;
  }
  
  /// 启动截屏服务
  Future<bool> startScreenshotService(int intervalSeconds) async {
    try {
      print('=== 开始启动截屏服务 ===');
      print('截屏间隔: $intervalSeconds秒');
      
      // 首先检查权限
      final permissions = await _permissionService.checkAllPermissions();
      final accessibilityEnabled = permissions['accessibility'] ?? false;
      final storageGranted = permissions['storage'] ?? false;
      final notificationGranted = permissions['notification'] ?? false;

      print('权限检查结果:');
      print('- 无障碍服务: $accessibilityEnabled');
      print('- 存储权限: $storageGranted');
      print('- 通知权限: $notificationGranted');

      if (!accessibilityEnabled) {
        throw ScreenshotServiceException('无障碍服务未启用，请前往设置中启用无障碍服务');
      }

      if (!storageGranted) {
        throw ScreenshotServiceException('存储权限未授予，无法保存截图文件');
      }

      // 检查服务是否运行
      bool serviceRunning = await _permissionService.isServiceRunning();
      print('- 服务运行状态: $serviceRunning');
      
      // 如果服务未运行，但系统中已启用，尝试等待服务启动
      if (!serviceRunning && accessibilityEnabled) {
        print('服务在系统中已启用但实例未就绪，等待服务启动...');
        
        // 等待最多3秒，检查服务状态
        for (int i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          serviceRunning = await _permissionService.isServiceRunning();
          print('第${i+1}次检查服务状态: $serviceRunning');
          if (serviceRunning) {
            print('服务已启动！');
            break;
          }
        }
      }
      
      if (!serviceRunning) {
        throw ScreenshotServiceException('无障碍服务未运行，请尝试重新启动应用或重新启用无障碍服务');
      }

      // 直接尝试启动截屏服务（使用无障碍截屏，无需MediaProjection权限）
      print('尝试启动定时截屏服务...');
      // 启动前先持久化一次间隔，确保原生端读取到一致值
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('timed_screenshot_interval', intervalSeconds);
      } catch (_) {}
      final success = await _permissionService.startTimedScreenshot(intervalSeconds);
      
      if (success) {
        _isRunning = true;
        _currentInterval = intervalSeconds;
        await _saveServiceState();
        print('=== 截屏服务启动成功，间隔: $intervalSeconds秒 ===');
        return true;
      } else {
        throw ScreenshotServiceException('截屏服务启动失败，请检查：\n1. Android版本是否为11.0(API 30)或以上\n2. 无障碍服务是否正常运行\n3. 尝试重新启动应用');
      }
    } on ScreenshotServiceException {
      rethrow;
    } catch (e) {
      print('启动截屏服务异常: $e');
      throw ScreenshotServiceException('启动截屏服务时发生未知错误：$e');
    }
  }
  
  /// 停止截屏服务
  Future<void> stopScreenshotService() async {
    try {
      await _permissionService.stopTimedScreenshot();
      _isRunning = false;
      await _saveServiceState();
    } catch (e) {
      print('停止截屏服务失败: $e');
    }
  }
  
  /// 更新截屏间隔
  Future<bool> updateInterval(int intervalSeconds) async {
    try {
      if (_isRunning) {
        // 重新启动服务以应用新间隔
        await _permissionService.stopTimedScreenshot();
        // 启动前先持久化一次间隔，避免原生侧读到旧值
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('timed_screenshot_interval', intervalSeconds);
        } catch (_) {}
        final success = await _permissionService.startTimedScreenshot(intervalSeconds);
        if (success) {
          _currentInterval = intervalSeconds;
          await _saveServiceState();
        }
        return success;
      } else {
        _currentInterval = intervalSeconds;
        await _saveServiceState();
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('timed_screenshot_interval', intervalSeconds);
        } catch (_) {}
        return true;
      }
    } catch (e) {
      print('更新截屏间隔失败: $e');
      return false;
    }
  }
  
  /// 手动截屏
  Future<String?> captureScreenManually() async {
    try {
      return await _permissionService.captureScreen();
    } catch (e) {
      print('手动截屏失败: $e');
      return null;
    }
  }
  
  /// 保存服务状态
  Future<void> _saveServiceState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('screenshot_service_running', _isRunning);
      await prefs.setInt('screenshot_interval', _currentInterval);
    } catch (e) {
      print('保存截屏服务状态失败: $e');
    }
  }
  
  /// 恢复服务状态
  Future<void> restoreServiceState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isRunning = prefs.getBool('screenshot_service_running') ?? false;
      _currentInterval = prefs.getInt('screenshot_interval') ?? 5;
      
      // 如果之前服务在运行，尝试重新启动
      if (_isRunning) {
        final success = await startScreenshotService(_currentInterval);
        if (!success) {
          _isRunning = false;
          await _saveServiceState();
        }
      }
    } catch (e) {
      print('恢复截屏服务状态失败: $e');
    }
  }
  
  /// 设置方法通道处理器
  void _setupMethodChannelHandlers() {
    print('=== 设置ScreenshotService Method Channel Handler ===');
    _channel.setMethodCallHandler((call) async {
      print('=== 收到Method Channel调用: ${call.method} ===');

      try {
        // 安全地检查参数
        if (call.arguments == null) {
          print('=== 参数为null ===');
        } else {
          print('=== 参数类型: ${call.arguments.runtimeType} ===');
          print('=== 参数内容: ${call.arguments} ===');
        }
        switch (call.method) {
          case 'onScreenshotSaved':
            print('=== 开始处理onScreenshotSaved ===');

            // 安全地转换参数
            if (call.arguments == null) {
              print('=== 错误：参数为null ===');
              return;
            }

            if (call.arguments is! Map) {
              print('=== 错误：参数不是Map类型，实际类型：${call.arguments.runtimeType} ===');
              return;
            }

            final arguments = Map<String, dynamic>.from(call.arguments as Map);
            print('=== 参数转换成功，开始处理 ===');

            await _handleScreenshotSaved(arguments);
            print('=== onScreenshotSaved处理完成 ===');
            break;
          default:
            print('未处理的方法调用: ${call.method}');
        }
      } catch (e, stackTrace) {
        print('=== Method Channel处理异常: $e ===');
        print('=== 堆栈跟踪: $stackTrace ===');
      }
    });
    print('=== ScreenshotService Method Channel Handler设置完成 ===');
  }

  /// 允许其他服务（如 PermissionService）转发平台事件至此处统一处理
  Future<void> handleScreenshotSavedFromPlatform(Map<String, dynamic> data) async {
    await _handleScreenshotSaved(data);
  }
  
  // 用于跟踪正在处理的文件路径，防止重复处理
  final Set<String> _processingPaths = <String>{};

  /// 处理截图保存通知
  Future<void> _handleScreenshotSaved(Map<String, dynamic> data) async {
    try {
      final packageName = data['packageName'] as String? ?? '';
      final appName = data['appName'] as String? ?? '';
      final relativePath = data['filePath'] as String? ?? '';
      final captureTime = data['captureTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      print('收到截图保存通知: $appName - $relativePath');

      if (packageName.isNotEmpty && appName.isNotEmpty && relativePath.isNotEmpty) {
        // 将相对路径转换为绝对路径
        final baseDir = await PathService.getExternalFilesDir(null);
        if (baseDir == null) {
          print('无法获取基础目录，跳过数据库插入');
          return;
        }

        final absolutePath = '${baseDir.path}/$relativePath';
        print('转换后的绝对路径: $absolutePath');

        // 检查是否正在处理相同的文件路径
        if (_processingPaths.contains(absolutePath)) {
          print('文件路径正在处理中，跳过重复处理: $absolutePath');
          return;
        }

        // 添加到处理中集合
        _processingPaths.add(absolutePath);

        try {
          // 创建截图记录
          final record = ScreenshotRecord(
            appPackageName: packageName,
            appName: appName,
            filePath: absolutePath,
            captureTime: DateTime.fromMillisecondsSinceEpoch(captureTime),
            fileSize: 0, // 文件大小将在数据库服务中计算
          );

          // 使用新的去重插入方法
          final id = await _database.insertScreenshotIfNotExists(record);
          if (id != null) {
            print('截图记录已插入数据库，ID: $id');
          } else {
            print('截图记录已存在，未重复插入');
          }
          // 刷新统计缓存后再通知监听者，避免先读到旧缓存
          await _refreshStatsCache(force: true);
          _screenshotStreamController.add(null);
        } finally {
          // 从处理中集合移除
          _processingPaths.remove(absolutePath);
        }
      } else {
        print('截图保存通知数据不完整，跳过数据库插入');
      }
    } catch (e) {
      print('处理截图保存通知失败: $e');
    }
  }
  
  /// 获取截屏统计信息
  Future<Map<String, dynamic>> getScreenshotStats() async {
    StartupProfiler.begin('ScreenshotService.getScreenshotStats');
    try {
      // 节流同步，避免每次都全量扫目录
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt(_lastSyncTsKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lastSync == 0 || (now - lastSync) > _syncThrottleSeconds * 1000) {
        await syncDatabaseWithFiles();
        await prefs.setInt(_lastSyncTsKey, now);
      }

      final totalCount = await _database.getTotalScreenshotCount();
      final todayCount = await _database.getTodayScreenshotCount();
      final statistics = await _database.getScreenshotStatistics();
      
      // 获取最近的截图时间
      DateTime? lastScreenshotTime;
      if (statistics.isNotEmpty) {
        for (final stat in statistics.values) {
          final time = stat['lastCaptureTime'] as DateTime?;
          if (time != null && (lastScreenshotTime == null || time.isAfter(lastScreenshotTime))) {
            lastScreenshotTime = time;
          }
        }
      }
      
      final stats = {
        'totalScreenshots': totalCount,
        'todayScreenshots': todayCount,
        'lastScreenshotTime': lastScreenshotTime?.millisecondsSinceEpoch,
        'appStatistics': statistics,
      };
      // 保存到缓存
      // ignore: unawaited_futures
      _saveStatsCache(stats);
      return stats;
    } catch (e) {
      print('获取截屏统计信息失败: $e');
      return {
        'totalScreenshots': 0,
        'todayScreenshots': 0,
        'lastScreenshotTime': null,
        'appStatistics': <String, Map<String, dynamic>>{},
      };
    }
    finally {
      StartupProfiler.end('ScreenshotService.getScreenshotStats');
    }
  }

  /// 获取最新统计（不使用统计缓存，可选择强制全量文件同步）
  Future<Map<String, dynamic>> getScreenshotStatsFresh({bool forceFullSync = true}) async {
    StartupProfiler.begin('ScreenshotService.getScreenshotStatsFresh');
    try {
      if (forceFullSync) {
        // 无视节流，强制与文件系统同步，确保数据库为最新
        await syncDatabaseWithFiles();
      }

      final totalCount = await _database.getTotalScreenshotCount();
      final todayCount = await _database.getTodayScreenshotCount();
      final statistics = await _database.getScreenshotStatistics();

      DateTime? lastScreenshotTime;
      if (statistics.isNotEmpty) {
        for (final stat in statistics.values) {
          final time = stat['lastCaptureTime'] as DateTime?;
          if (time != null && (lastScreenshotTime == null || time.isAfter(lastScreenshotTime))) {
            lastScreenshotTime = time;
          }
        }
      }

      return {
        'totalScreenshots': totalCount,
        'todayScreenshots': todayCount,
        'lastScreenshotTime': lastScreenshotTime?.millisecondsSinceEpoch,
        'appStatistics': statistics,
      };
    } catch (e) {
      print('获取最新截屏统计失败: $e');
      return {
        'totalScreenshots': 0,
        'todayScreenshots': 0,
        'lastScreenshotTime': null,
        'appStatistics': <String, Map<String, dynamic>>{},
      };
    } finally {
      StartupProfiler.end('ScreenshotService.getScreenshotStatsFresh');
    }
  }
  
  /// 根据应用包名获取截屏记录
  Future<List<ScreenshotRecord>> getScreenshotsByApp(String appPackageName, {int? limit}) async {
    try {
      // 先做一次增量同步，确保本地文件已入库
      await syncDatabaseWithFiles(packageName: appPackageName);
      return await _database.getScreenshotsByApp(appPackageName, limit: limit);
    } catch (e) {
      print('获取应用截屏记录失败: $e');
      return [];
    }
  }
  
  /// 删除截屏记录
  Future<bool> deleteScreenshot(int id) async {
    try {
      final ok = await _database.deleteScreenshot(id);
      if (ok) {
        // 先刷新统计缓存，再通知监听者，确保读取到新缓存
        await _refreshStatsCache(force: true);
        _screenshotStreamController.add(null);
      }
      return ok;
    } catch (e) {
      print('删除截屏记录失败: $e');
      return false;
    }
  }

  /// 扫描本地截图目录，将未入库的图片补录到数据库
  Future<int> syncDatabaseWithFiles({String? packageName}) async {
    try {
      final baseDir = await PathService.getExternalFilesDir(null);
      if (baseDir == null) {
        return 0;
      }

      final screenRoot = Directory(p.join(baseDir.path, 'output', 'screen'));
      if (!await screenRoot.exists()) {
        return 0;
      }

      int inserted = 0;
      final List<Directory> appDirs = [];
      if (packageName != null) {
        final dir = Directory(p.join(screenRoot.path, packageName));
        if (await dir.exists()) appDirs.add(dir);
      } else {
        for (final entity in await screenRoot.list(followLinks: false).toList()) {
          if (entity is Directory) appDirs.add(entity);
        }
      }

      for (final appDir in appDirs) {
        final pkg = p.basename(appDir.path);
        final files = await appDir
            .list(followLinks: false)
            .where((e) => e is File && (e.path.toLowerCase().endsWith('.jpg') || e.path.toLowerCase().endsWith('.png')))
            .toList();

        for (final entity in files) {
          final file = entity as File;
          final absolutePath = file.path;
          final exists = await _database.isFilePathExists(absolutePath);
          if (exists) continue;

          final stat = await file.stat();
          final record = ScreenshotRecord(
            appPackageName: pkg,
            appName: pkg, // 无法可靠获取时用包名占位
            filePath: absolutePath, // 数据库存绝对路径
            captureTime: stat.modified,
            fileSize: stat.size,
          );

          final id = await _database.insertScreenshotIfNotExists(record);
          if (id != null) {
            inserted++;
          }
        }
      }

      if (inserted > 0) {
        // 刷新统计缓存后再通知监听者
        await _refreshStatsCache(force: true);
        _screenshotStreamController.add(null);
      }
      return inserted;
    } catch (e) {
      print('同步截图文件到数据库失败: $e');
      return 0;
    }
  }

  // ===== 统计缓存实现 =====
  String _serializeStats(Map<String, dynamic> stats) {
    final copy = Map<String, dynamic>.from(stats);
    final appStats = copy['appStatistics'] as Map<String, dynamic>?;
    if (appStats != null) {
      final out = <String, dynamic>{};
      appStats.forEach((pkg, map) {
        final m = Map<String, dynamic>.from(map as Map);
        final dt = m['lastCaptureTime'];
        if (dt is DateTime) m['lastCaptureTime'] = dt.millisecondsSinceEpoch;
        out[pkg] = m;
      });
      copy['appStatistics'] = out;
    }
    return jsonEncode(copy);
  }

  Map<String, dynamic> _deserializeStats(String jsonStr) {
    final map = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    final appStats = map['appStatistics'] as Map<String, dynamic>?;
    if (appStats != null) {
      final out = <String, Map<String, dynamic>>{};
      appStats.forEach((pkg, val) {
        final m = Map<String, dynamic>.from(val as Map);
        final ts = m['lastCaptureTime'];
        if (ts is int) m['lastCaptureTime'] = DateTime.fromMillisecondsSinceEpoch(ts);
        out[pkg] = m;
      });
      map['appStatistics'] = out;
    }
    return map;
  }

  Future<void> _refreshStatsCache({bool force = false}) async {
    try {
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final ts = prefs.getInt(_statsCacheTsKey) ?? 0;
        final ttl = prefs.getInt(_statsCacheTtlSecondsKey) ?? _statsCacheTtlSecondsDefault;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (ts > 0 && (now - ts) <= ttl * 1000) return;
      }
      final stats = await getScreenshotStats();
      await _saveStatsCache(stats);
    } catch (_) {}
  }

  Future<void> _saveStatsCache(Map<String, dynamic> stats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statsCacheKey, _serializeStats(stats));
      await prefs.setInt(_statsCacheTsKey, DateTime.now().millisecondsSinceEpoch);
      if (!prefs.containsKey(_statsCacheTtlSecondsKey)) {
        await prefs.setInt(_statsCacheTtlSecondsKey, _statsCacheTtlSecondsDefault);
      }
    } catch (_) {}
  }

  /// 对外暴露：立即将传入的统计结果写入缓存（用于首页比对后同步缓存，避免下次看到旧缓存）
  Future<void> updateStatsCache(Map<String, dynamic> stats) async {
    await _saveStatsCache(stats);
  }

  Future<void> _refreshStatsCacheIfStale() async {
    await _refreshStatsCache();
  }

  /// 主动失效统计缓存（用于手动刷新）
  Future<void> invalidateStatsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_statsCacheKey);
      await prefs.remove(_statsCacheTsKey);
    } catch (_) {}
  }
}
