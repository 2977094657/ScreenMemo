import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'per_app_screenshot_settings_service.dart';
import 'permission_service.dart';
import 'screenshot_database.dart';
import 'path_service.dart';
import '../models/screenshot_record.dart';
import 'startup_profiler.dart';
import 'flutter_logger.dart';
import 'navigation_service.dart';

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
  static const String _expireEnabledKey = 'screenshot_expire_enabled';
  static const String _expireDaysKey = 'screenshot_expire_days';
  static const String _expireLastTsKey = 'screenshot_expire_last_ts';
  bool _cleanupRunning = false;
  static const String _statsCacheKey = 'stats_cache';
  static const String _statsCacheTsKey = 'stats_cache_ts';
  static const String _statsCacheTtlSecondsKey = 'stats_cache_ttl';
  static const int _statsCacheTtlSecondsDefault = 600; // 10分钟
  // 移除全量扫描相关：不再维护文件系统与DB的强制同步节流
  // static const String _lastSyncTsKey = 'stats_last_sync_ts';
  // static const int _syncThrottleSeconds = 120; // 2分钟

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
        // 访问即续期：读缓存的同时刷新时间戳，避免频繁过期导致首页闪烁
        try {
          await prefs.setInt(_statsCacheTsKey, now);
        } catch (_) {}
        // 日志：观察续期是否生效
        // ignore: unawaited_futures
        FlutterLogger.log('stats cache hit, renewed ts=$now, ttl=$ttl');
        final map = _deserializeStats(cached);
        // 后台异步刷新缓存
        // ignore: unawaited_futures
        _refreshStatsCacheIfStale();
        StartupProfiler.end('ScreenshotService.getScreenshotStatsCachedFirst');
        return map;
      }
      // 若存在缓存但已过期：先返回陈旧缓存以避免首屏空白，再后台强制刷新
      if (cached != null && ts > 0 && (now - ts) > ttl * 1000) {
        final stale = _deserializeStats(cached);
        // ignore: unawaited_futures
        FlutterLogger.log('stats cache stale -> serve stale and refresh, ageMs=${now - ts}, ttl=$ttl');
        // ignore: unawaited_futures
        _refreshStatsCache(force: true);
        StartupProfiler.end('ScreenshotService.getScreenshotStatsCachedFirst');
        return stale;
      }
    } catch (_) {}
    // 缓存不存在或已过期，重新计算
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_statsCacheTsKey) ?? 0;
      final ttl = prefs.getInt(_statsCacheTtlSecondsKey) ?? _statsCacheTtlSecondsDefault;
      // ignore: unawaited_futures
      FlutterLogger.log('stats cache miss -> compute fresh, now-ts=${DateTime.now().millisecondsSinceEpoch - ts}ms, ttl=$ttl');
    } catch (_) {}
    final stats = await getScreenshotStats();
    StartupProfiler.end('ScreenshotService.getScreenshotStatsCachedFirst');
    return stats;
  }

  /// 启动截屏服务
  Future<bool> startScreenshotService(int intervalSeconds) async {
    try {
      print('=== 开始启动截屏服务 ===');
      // 统一约束：5-60 秒
      final int clampedInterval = intervalSeconds < 5 ? 5 : (intervalSeconds > 60 ? 60 : intervalSeconds);
      if (clampedInterval != intervalSeconds) {
        print('截屏间隔超出范围，自动调整为: $clampedInterval秒 (原输入: $intervalSeconds)');
      }
      print('截屏间隔: $clampedInterval秒');

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
        await prefs.setInt('timed_screenshot_interval', clampedInterval);
        // 同步 UI 侧读取的键
        await prefs.setInt('screenshot_interval', clampedInterval);
      } catch (_) {}
      final success = await _permissionService.startTimedScreenshot(clampedInterval);

      if (success) {
        _isRunning = true;
        _currentInterval = clampedInterval;
        await _saveServiceState();
        print('=== 截屏服务启动成功，间隔: $clampedInterval秒 ===');
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
      // 统一约束：5-60 秒
      final int clampedInterval = intervalSeconds < 5 ? 5 : (intervalSeconds > 60 ? 60 : intervalSeconds);
      if (_isRunning) {
        // 重新启动服务以应用新间隔
        await _permissionService.stopTimedScreenshot();
        // 启动前先持久化一次间隔，避免原生侧读到旧值
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('timed_screenshot_interval', clampedInterval);
          // 同步写入UI侧读取的键，避免不同键值不同步
          await prefs.setInt('screenshot_interval', clampedInterval);
        } catch (_) {}
        final success = await _permissionService.startTimedScreenshot(clampedInterval);
        if (success) {
          _currentInterval = clampedInterval;
          await _saveServiceState();
        }
        return success;
      } else {
        _currentInterval = clampedInterval;
        await _saveServiceState();
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('timed_screenshot_interval', clampedInterval);
          await prefs.setInt('screenshot_interval', clampedInterval);
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
      final saved = prefs.getInt('screenshot_interval') ?? 5;
      _currentInterval = saved < 5 ? 5 : (saved > 60 ? 60 : saved);

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
          case 'onDailySummaryNotificationTap':
            // 通知点击：打开每日总结页面
            try {
              String? dk;
              if (call.arguments is Map) {
                final args = Map<String, dynamic>.from(call.arguments as Map);
                final v = args['dateKey'];
                if (v is String) dk = v.trim().isEmpty ? null : v.trim();
              }
              // 记录日志并跳转
              // ignore: discarded_futures
              FlutterLogger.nativeInfo('Navigation', 'onTap notification dateKey=${dk ?? 'null'}');
              // 不阻塞当前 handler
              // ignore: unawaited_futures
              NavigationService.instance.openDailySummary(dk);
            } catch (e) {
              print('处理通知点击失败: $e');
            }
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
      final pageUrl = data['pageUrl'] as String?;
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
            pageUrl: pageUrl,
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
          cleanupExpiredScreenshotsIfNeeded();
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
      // 改为仅DB统计，不触发文件系统扫描

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

  /// 获取汇总统计数据
  Future<Map<String, dynamic>> getTotals() async {
    return await _database.getTotals();
  }

  /// 重新计算汇总统计（用于数据迁移或修复）
  Future<void> recalculateTotals() async {
    await _database.recalculateTotals();
  }

  /// 获取最新统计（不使用统计缓存，可选择强制全量文件同步）
  Future<Map<String, dynamic>> getScreenshotStatsFresh({bool forceFullSync = true}) async {
    StartupProfiler.begin('ScreenshotService.getScreenshotStatsFresh');
    try {
      // 仅DB统计，不进行文件系统同步

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

  // 仅从数据库读取统计（不触发文件系统全量扫描），用于快速更新缓存
  Future<Map<String, dynamic>> _getStatsDbOnly() async {
    try {
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
    } catch (_) {
      return {
        'totalScreenshots': 0,
        'todayScreenshots': 0,
        'lastScreenshotTime': null,
        'appStatistics': <String, Map<String, dynamic>>{},
      };
    }
  }

  // 快速刷新统计缓存（DB-only），避免阻塞UI；必要时再后台执行可能的全量同步
  Future<void> _refreshStatsCacheQuick() async {
    final sw = Stopwatch()..start();
    final stats = await _getStatsDbOnly();
    await _saveStatsCache(stats);
    sw.stop();
    // ignore: unawaited_futures
    FlutterLogger.log('统计缓存已快速刷新(DB)并保存，用时 ${sw.elapsedMilliseconds}ms');
  }

  /// 根据应用包名获取截屏记录（支持分页）
  Future<List<ScreenshotRecord>> getScreenshotsByApp(String appPackageName, {int? limit, int? offset}) async {
    try {
      // 直接从数据库查询，不再进行任何文件系统同步
      return await _database.getScreenshotsByApp(appPackageName, limit: limit, offset: offset);
    } catch (e) {
      print('获取应用截屏记录失败: $e');
      return [];
    }
  }

  /// 获取指定应用在时间范围内的截屏数量（包含边界，毫秒）
  Future<int> getScreenshotCountByAppBetween(
    String appPackageName, {
    required int startMillis,
    required int endMillis,
  }) async {
    try {
      return await _database.getScreenshotCountByAppBetween(
        appPackageName,
        startMillis: startMillis,
        endMillis: endMillis,
      );
    } catch (e) {
      print('获取区间截图数量失败: $e');
      return 0;
    }
  }

  /// 全局：获取给定日期范围内的截图总数（所有应用）
  Future<int> getGlobalScreenshotCountBetween({
    required int startMillis,
    required int endMillis,
  }) async {
    try {
      return await _database.getGlobalScreenshotCountBetween(
        startMillis: startMillis,
        endMillis: endMillis,
      );
    } catch (e) {
      print('获取全局区间截图数量失败: $e');
      return 0;
    }
  }

  /// 全局：获取给定日期范围内的截图列表（所有应用，按时间倒序，支持分页）
  Future<List<ScreenshotRecord>> getGlobalScreenshotsBetween({
    required int startMillis,
    required int endMillis,
    int? limit,
    int? offset,
  }) async {
    try {
      return await _database.getGlobalScreenshotsBetween(
        startMillis: startMillis,
        endMillis: endMillis,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      print('获取全局区间截图列表失败: $e');
      return [];
    }
  }

  /// 获取指定应用在时间范围内的截图列表（按时间倒序，支持分页）
  Future<List<ScreenshotRecord>> getScreenshotsByAppBetween(
    String appPackageName, {
    required int startMillis,
    required int endMillis,
    int? limit,
    int? offset,
  }) async {
    try {
      return await _database.getScreenshotsByAppBetween(
        appPackageName,
        startMillis: startMillis,
        endMillis: endMillis,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      print('获取区间截图列表失败: $e');
      return [];
    }
  }

  /// 获取 OCR 匹配框（原图坐标系）
  Future<Map<String, dynamic>?> getOcrMatchBoxes({
    required String filePath,
    required String query,
  }) async {
    try {
      final res = await _channel.invokeMethod('getOcrMatchBoxes', {
        'filePath': filePath,
        'query': query,
      });
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      print('getOcrMatchBoxes 调用失败: $e');
      return null;
    }
  }

  /// 全局按 OCR 文本搜索
  Future<List<ScreenshotRecord>> searchScreenshotsByOcr(String query, {int? limit, int? offset}) async {
    try {
      return await _database.searchScreenshotsByOcr(query, limit: limit, offset: offset);
    } catch (e) {
      print('OCR 搜索失败: $e');
      return [];
    }
  }

  /// 指定应用按 OCR 文本搜索
  Future<List<ScreenshotRecord>> searchScreenshotsByOcrForApp(String appPackageName, String query, {int? limit, int? offset}) async {
    try {
      return await _database.searchScreenshotsByOcrForApp(appPackageName, query, limit: limit, offset: offset);
    } catch (e) {
      print('应用内 OCR 搜索失败: $e');
      return [];
    }
  }

  /// 获取指定应用的截屏总数量
  Future<int> getScreenshotCountByApp(String appPackageName) async {
    try {
      return await _database.getScreenshotCountByApp(appPackageName);
    } catch (e) {
      print('获取应用截屏数量失败: $e');
      return 0;
    }
  }

  /// 删除整个应用的所有截图（高效文件夹删除）
  Future<bool> deleteAllScreenshotsForApp(String appPackageName) async {
    try {
      // ignore: unawaited_futures
      FlutterLogger.info('SERVICE.deleteAllScreenshotsForApp start package=$appPackageName');
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('SERVICE', 'deleteAllScreenshotsForApp start package='+appPackageName);
      final baseDir = await PathService.getExternalFilesDir(null);
      if (baseDir == null) {
        // ignore: unawaited_futures
        FlutterLogger.warn('SERVICE.deleteAllScreenshotsForApp no baseDir');
        return false;
      }

      // 删除应用文件夹
      final appDir = Directory(p.join(baseDir.path, 'output', 'screen', appPackageName));
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
        print('已删除应用文件夹: ${appDir.path}');
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('FS', 'deleted app dir: '+appDir.path);
      }

      // 清理数据库中的记录
      final deletedCount = await _database.deleteAllScreenshotsForApp(appPackageName);
      print('已从数据库删除 $deletedCount 条记录');

      if (deletedCount > 0) {
        // 优先快速刷新缓存，不阻塞UI，然后后台再做可能的全量刷新
        await _refreshStatsCacheQuick();
        _screenshotStreamController.add(null);
        // ignore: unawaited_futures
        _refreshStatsCache(force: true);
      }

      // ignore: unawaited_futures
      FlutterLogger.info('SERVICE.deleteAllScreenshotsForApp success package=$appPackageName deletedCount=$deletedCount');
      return true;
    } catch (e) {
      print('删除应用所有截图失败: $e');
      // ignore: unawaited_futures
      FlutterLogger.error('SERVICE.deleteAllScreenshotsForApp exception: $e');
      // ignore: unawaited_futures
      FlutterLogger.nativeError('SERVICE', 'deleteAllScreenshotsForApp exception: $e');
      return false;
    }
  }

  /// 删除截屏记录
  Future<bool> deleteScreenshot(int id, String packageName) async {
    try {
      // ignore: unawaited_futures
      FlutterLogger.info('SERVICE.deleteScreenshot start id=$id package=$packageName');
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('SERVICE', 'deleteScreenshot start id='+id.toString());
      final ok = await _database.deleteScreenshot(id, packageName);
      if (ok) {
        // 先快速刷新统计缓存（DB-only），再通知监听者
        await _refreshStatsCacheQuick();
        _screenshotStreamController.add(null);
        // 后台触发可能的全量同步（不等待）
        // ignore: unawaited_futures
        _refreshStatsCache(force: true);
        // ignore: unawaited_futures
        FlutterLogger.info('SERVICE.deleteScreenshot success id=$id package=$packageName');
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('SERVICE', 'deleteScreenshot success id='+id.toString());
      }
      return ok;
    } catch (e) {
      print('删除截屏记录失败: $e');
      // ignore: unawaited_futures
      FlutterLogger.error('SERVICE.deleteScreenshot exception: $e');
      // ignore: unawaited_futures
      FlutterLogger.nativeError('SERVICE', 'deleteScreenshot exception: $e');
      return false;
    }
  }

  /// 批量删除截屏记录：避免逐条重算与多次缓存刷新
  Future<int> deleteScreenshotsBatch(String packageName, List<int> ids) async {
    try {
      if (ids.isEmpty) return 0;
      final sw = Stopwatch()..start();
      final deleted = await _database.deleteScreenshotsByIds(packageName, ids);
      sw.stop();
      // ignore: unawaited_futures
      FlutterLogger.info('SERVICE.批量删除完成 包名=$packageName 个数=${ids.length} 耗时=${sw.elapsedMilliseconds}ms 实际删除=$deleted');
      if (deleted > 0) {
        // 批量删除后优先进行快速统计缓存刷新并通知，再后台全量刷新
        await _refreshStatsCacheQuick();
        _screenshotStreamController.add(null);
        // ignore: unawaited_futures
        _refreshStatsCache(force: true);
      }
      return deleted;
    } catch (e) {
      print('批量删除截屏记录失败: $e');
      return 0;
    }
  }

  /// 基于“仅保留所选”的高速删除：
  /// - keepIds: 要保留的数据库ID集合
  /// - packageName: 应用包名
  /// - thresholdKeepRatio: 触发该策略的保留占比阈值（例如 0.1 表示保留比例 <=10% 时启用）
  /// 返回：是否采用并完成了“仅保留”策略；若未达阈值则返回false（应回退到普通逐条删除）
  Future<bool> fastDeleteKeepOnly({
    required String packageName,
    required List<int> keepIds,
    double thresholdKeepRatio = 0.1,
  }) async {
    try {
      // 预检查：总数 & 比例
      final totalCount = await _database.getScreenshotCountByApp(packageName);
      if (totalCount <= 0) return false;
      final keepCount = keepIds.length;
      final keepRatio = keepCount / totalCount;
      if (keepRatio <= 0 || keepRatio > thresholdKeepRatio) {
        // 不满足阈值条件，由上层走普通删除
        return false;
      }

      final baseDir = await PathService.getExternalFilesDir(null);
      if (baseDir == null) return false;
      final appDir = Directory(p.join(baseDir.path, 'output', 'screen', packageName));
      if (!await appDir.exists()) {
        // 若文件夹不存在，仅做DB侧删除非保留记录即可
        await _database.deleteAllExcept(packageName, keepIds);
        await _refreshStatsCache(force: true);
        _screenshotStreamController.add(null);
        return true;
      }

      // 查询保留记录以获得文件路径
      final keepRows = await _database.getRecordsByIds(packageName, keepIds);
      if (keepRows.isEmpty && keepCount > 0) {
        // DB未查到，回退
        return false;
      }

      // 1) 将保留文件复制到临时目录（仅复制少量保留文件）
      final tempDir = Directory(p.join(appDir.parent.path, '${packageName}_keep_tmp_${DateTime.now().millisecondsSinceEpoch}'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // 建立原路径 -> 临时路径的映射，便于后续按原路径还原
      final Map<String, String> originalToTempPath = <String, String>{};
      for (final row in keepRows) {
        final filePath = row['file_path'] as String?;
        if (filePath == null || filePath.isEmpty) continue;
        final src = File(filePath);
        if (!await src.exists()) continue;
        final dest = File(p.join(tempDir.path, p.basename(filePath)));
        try {
          await src.copy(dest.path);
          originalToTempPath[filePath] = dest.path;
        } catch (e) {
          // 若单个复制失败，不中断整体流程
          print('复制保留文件失败: $e, ${src.path}');
        }
      }

      // 2) 删除整个应用目录（极快）
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }

      // 3) 仅保留数据库记录：删除除 keepIds 外的全部行
      await _database.deleteAllExcept(packageName, keepIds);

      // 4) 逐个将临时文件按原绝对路径还原（保持与DB中的file_path一致）
      for (final entry in originalToTempPath.entries) {
        final originalPath = entry.key;
        final tempPath = entry.value;
        final originalParent = Directory(p.dirname(originalPath));
        try {
          if (!await originalParent.exists()) {
            await originalParent.create(recursive: true);
          }
        } catch (e) {
          print('创建原目录失败: $e, $originalParent');
        }

        final tempFile = File(tempPath);
        if (!await tempFile.exists()) continue;
        try {
          await tempFile.rename(originalPath);
        } catch (e) {
          try {
            await tempFile.copy(originalPath);
            await tempFile.delete();
          } catch (e2) {
            print('还原保留文件失败: $e2, $originalPath');
          }
        }
      }

      // 5) 清理临时目录
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}

      // 6) 刷新统计缓存并通知
      await _refreshStatsCache(force: true);
      _screenshotStreamController.add(null);
      return true;
    } catch (e) {
      print('fastDeleteKeepOnly 失败: $e');
      return false;
    }
  }

  /// 扫描本地截图目录，将未入库的图片补录到数据库
  // 已移除：全量扫描文件系统并补录到DB的逻辑

  /// 递归扫描应用目录（包含年月/日期子目录）
  Future<int> _scanAppDirectory(Directory appDir, String packageName) async {
    int inserted = 0;

    try {
      final entities = await appDir.list(followLinks: false).toList();

      for (final entity in entities) {
        if (entity is Directory) {
          // 这是年月目录（如 2024-01）
          final yearMonthEntities = await entity.list(followLinks: false).toList();

          for (final dayEntity in yearMonthEntities) {
            if (dayEntity is Directory) {
              // 这是日期目录（如 15）
              final files = await dayEntity
                  .list(followLinks: false)
                  .where((e) => e is File && (e.path.toLowerCase().endsWith('.jpg') || e.path.toLowerCase().endsWith('.png')))
                  .toList();

              for (final fileEntity in files) {
                final file = fileEntity as File;
                final absolutePath = file.path;
                final exists = await _database.isFilePathExists(absolutePath);
                if (exists) continue;

                final stat = await file.stat();
                final record = ScreenshotRecord(
                  appPackageName: packageName,
                  appName: packageName, // 无法可靠获取时用包名占位
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
          }
        } else if (entity is File) {
          // 兼容旧的扁平结构文件
          if (entity.path.toLowerCase().endsWith('.jpg') || entity.path.toLowerCase().endsWith('.png')) {
            final absolutePath = entity.path;
            final exists = await _database.isFilePathExists(absolutePath);
            if (!exists) {
              final stat = await entity.stat();
              final record = ScreenshotRecord(
                appPackageName: packageName,
                appName: packageName,
                filePath: absolutePath,
                captureTime: stat.modified,
                fileSize: stat.size,
              );

              final id = await _database.insertScreenshotIfNotExists(record);
              if (id != null) {
                inserted++;
              }
            }
          }
        }
      }
    } catch (e) {
      print('扫描应用目录失败: ${appDir.path}, 错误: $e');
    }

    return inserted;
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
        if (ts > 0 && (now - ts) <= ttl * 1000) {
          // ignore: unawaited_futures
          FlutterLogger.log('统计缓存刷新跳过：仍在新鲜窗口内 (ageMs=${now - ts}, ttl=$ttl)');
          return;
        }
      }
      final stats = await getScreenshotStats();
      await _saveStatsCache(stats);
      // ignore: unawaited_futures
      FlutterLogger.log('统计缓存已刷新并保存');
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
      // ignore: unawaited_futures
      FlutterLogger.log('统计缓存已保存 (ttl=${await _readTtl(prefs)})');
    } catch (_) {}
  }

  Future<int> _readTtl(SharedPreferences prefs) async {
    try {
      return prefs.getInt(_statsCacheTtlSecondsKey) ?? _statsCacheTtlSecondsDefault;
    } catch (_) {
      return _statsCacheTtlSecondsDefault;
    }
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

  Future<void> cleanupExpiredScreenshotsIfNeeded({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 全局默认设置（当某应用未开启自定义时使用）
      final globalEnabled = prefs.getBool(_expireEnabledKey) ?? false;
      int globalDays = prefs.getInt(_expireDaysKey) ?? 30;
      if (globalDays < 1) globalDays = 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_expireLastTsKey) ?? 0;
      // 节流：12 小时内最多执行一次
      const int throttleMs = 12 * 60 * 60 * 1000;
      if (!force && last > 0 && (now - last) < throttleMs) {
        return;
      }
      if (_cleanupRunning) return;
      _cleanupRunning = true;
      // 读取数据库 app_stats 统计，遍历所有包名（按应用生效各自过期策略）
      final stats = await _database.getScreenshotStatistics();
      final packages = stats.keys.toList();
      int totalDeleted = 0;
      for (final pkg in packages) {
        try {
          // 读取每应用自定义设置
          final perApp = await PerAppScreenshotSettingsService.instance.getExpireSettings(pkg);
          final useCustom = await PerAppScreenshotSettingsService.instance.getUseCustom(pkg);
          final bool effectiveEnabled = useCustom
              ? (perApp['enabled'] as bool? ?? false)
              : globalEnabled;
          if (!effectiveEnabled) {
            continue;
          }
          int effectiveDays = useCustom
              ? ((perApp['days'] as int?) ?? globalDays)
              : globalDays;
          if (effectiveDays < 1) effectiveDays = 1;
          final threshold = now - effectiveDays * 24 * 60 * 60 * 1000;

          final ids = await _database.getScreenshotIdsByAppBetween(
            pkg,
            startMillis: 0,
            endMillis: threshold,
          );
          if (ids.isEmpty) continue;
          final deleted = await deleteScreenshotsBatch(pkg, ids);
          totalDeleted += deleted;
        } catch (e) {
        }
      }

      await _refreshStatsCache(force: true);
      try {
        await prefs.setInt(_expireLastTsKey, now);
      } catch (_) {}
      // 通知 UI 刷新
      if (totalDeleted > 0) {
        _screenshotStreamController.add(null);
      }
      FlutterLogger.info('SERVICE.cleanupExpired done: days=' + globalDays.toString() + ' deleted=' + totalDeleted.toString());
    } catch (e) {
    } finally {
      _cleanupRunning = false;
    }
  }

  Future<List<int>> getAllScreenshotIdsForApp(String appPackageName) async {
    try {
      return await _database.getAllScreenshotIdsForApp(appPackageName);
    } catch (e) {
      print('获取应用全部截图ID失败: $e');
      return <int>[];
    }
  }

  /// 获取某个应用在日期范围内的截图ID（不分页）
  Future<List<int>> getScreenshotIdsByAppBetween(
    String appPackageName, {
    required int startMillis,
    required int endMillis,
  }) async {
    try {
      return await _database.getScreenshotIdsByAppBetween(
        appPackageName,
        startMillis: startMillis,
        endMillis: endMillis,
      );
    } catch (e) {
      print('按日期范围获取截图ID失败: $e');
      return <int>[];
    }
  }
}
