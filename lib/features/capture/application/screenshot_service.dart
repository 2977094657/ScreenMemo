import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_memo/features/capture/data/per_app_screenshot_settings_service.dart';
import 'package:screen_memo/features/permissions/application/permission_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/data/platform/path_service.dart';
import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/core/performance/startup_profiler.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/app/navigation/navigation_service.dart';
import 'package:screen_memo/data/settings/user_settings_service.dart';
import 'package:screen_memo/features/app_health/application/app_health_service.dart';

/// 截屏服务异常类
class ScreenshotServiceException implements Exception {
  final String message;
  const ScreenshotServiceException(this.message);

  @override
  String toString() => message;
}

class ScreenshotRecomputeProgress {
  final String phase;
  final int current;
  final int total;
  final int inserted;
  final int processedFiles;
  final String? packageName;

  const ScreenshotRecomputeProgress({
    required this.phase,
    required this.current,
    required this.total,
    this.inserted = 0,
    this.processedFiles = 0,
    this.packageName,
  });

  double? get value {
    if (total <= 0) return null;
    return current.clamp(0, total).toDouble() / total;
  }
}

/// 截屏服务管理类
class ScreenshotService {
  static ScreenshotService? _instance;
  static ScreenshotService get instance => _instance ??= ScreenshotService._();
  static const String globalCompressionScopeKey = '__global_compression__';

  ScreenshotService._() {
    _setupMethodChannelHandlers();
  }

  final PermissionService _permissionService = PermissionService.instance;
  final ScreenshotDatabase _database = ScreenshotDatabase.instance;

  static const MethodChannel _channel = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

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
  static const String _dayCountCacheKey = 'day_count_cache';
  static const String _dayCountCacheTsKey = 'day_count_cache_ts';
  static const int _dayCountCacheTtlMillis = 10 * 60 * 1000; // 10分钟
  int? _dayCountMemCache;
  int _dayCountMemCacheTs = 0;
  Future<int>? _dayCountRefreshingFuture;
  // 移除全量扫描相关：不再维护文件系统与DB的强制同步节流
  // static const String _lastSyncTsKey = 'stats_last_sync_ts';
  // static const int _syncThrottleSeconds = 120; // 2分钟

  bool _compressionInFlight = false;
  void Function(CompressionProgress)? _compressionProgressListener;
  String? _activeCompressionPackage;
  String? _listenerPackageFilter;
  CompressionProgress? _latestCompressionProgress;
  final Map<String, CompressionProgress> _latestCompressionProgressByPackage =
      <String, CompressionProgress>{};
  int _activeCompressionTotalOverride = 0;
  int _activeCompressionHandledOffset = 0;
  int _activeCompressionSuccessOffset = 0;
  int _activeCompressionSkippedOffset = 0;
  int _activeCompressionFailedOffset = 0;
  int _activeCompressionSavedOffset = 0;

  CompressionProgress? latestCompressionProgressFor(String packageName) {
    return _latestCompressionProgressByPackage[packageName];
  }

  CompressionProgress? get latestGlobalCompressionProgress =>
      latestCompressionProgressFor(globalCompressionScopeKey);

  bool compressionInFlightFor(String packageName) {
    return _compressionInFlight && _activeCompressionPackage == packageName;
  }

  bool get globalCompressionInFlight =>
      compressionInFlightFor(globalCompressionScopeKey);

  void attachCompressionProgressListener(
    void Function(CompressionProgress)? listener, {
    bool replayLatest = true,
    String? packageName,
  }) {
    _compressionProgressListener = listener;
    _listenerPackageFilter = packageName;
    if (listener != null && replayLatest && packageName != null) {
      final CompressionProgress? latest =
          _latestCompressionProgressByPackage[packageName];
      if (latest != null) {
        try {
          listener(latest);
        } catch (e) {
          print('重放压缩进度回调失败: $e');
        }
      }
    }
  }

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
      final ttl =
          prefs.getInt(_statsCacheTtlSecondsKey) ??
          _statsCacheTtlSecondsDefault;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (cached != null && ts > 0 && (now - ts) <= ttl * 1000) {
        final map = _deserializeStats(cached);
        if (!await _isStatsCacheAlignedWithDatabase(map)) {
          final fresh = await getScreenshotStatsFresh();
          await _saveStatsCache(fresh);
          StartupProfiler.end(
            'ScreenshotService.getScreenshotStatsCachedFirst',
          );
          return fresh;
        }
        // 访问即续期：读缓存的同时刷新时间戳，避免频繁过期导致首页闪烁
        try {
          await prefs.setInt(_statsCacheTsKey, now);
        } catch (_) {}
        // 日志：观察续期是否生效
        // ignore: unawaited_futures
        FlutterLogger.log('统计缓存命中，已续期：时间戳=$now，有效期=${ttl}秒');
        // 后台异步刷新缓存
        // ignore: unawaited_futures
        _refreshStatsCacheIfStale();
        StartupProfiler.end('ScreenshotService.getScreenshotStatsCachedFirst');
        return map;
      }
      // 若存在缓存但已过期：先返回陈旧缓存以避免首屏空白，再后台强制刷新
      if (cached != null && ts > 0 && (now - ts) > ttl * 1000) {
        final stale = _deserializeStats(cached);
        if (!await _isStatsCacheAlignedWithDatabase(stale)) {
          final fresh = await getScreenshotStatsFresh();
          await _saveStatsCache(fresh);
          StartupProfiler.end(
            'ScreenshotService.getScreenshotStatsCachedFirst',
          );
          return fresh;
        }
        // ignore: unawaited_futures
        FlutterLogger.log(
          '统计缓存已过期 -> 先返回旧缓存并刷新，缓存年龄=${now - ts}毫秒，有效期=${ttl}秒',
        );
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
      final ttl =
          prefs.getInt(_statsCacheTtlSecondsKey) ??
          _statsCacheTtlSecondsDefault;
      // ignore: unawaited_futures
      FlutterLogger.log(
        '统计缓存未命中 -> 重新计算，now-ts=${DateTime.now().millisecondsSinceEpoch - ts}毫秒，有效期=${ttl}秒',
      );
    } catch (_) {}
    final stats = await getScreenshotStats();
    StartupProfiler.end('ScreenshotService.getScreenshotStatsCachedFirst');
    return stats;
  }

  Future<bool> _isStatsCacheAlignedWithDatabase(
    Map<String, dynamic> cached,
  ) async {
    try {
      final int cachedTotal = (cached['totalScreenshots'] as int?) ?? 0;
      final int cachedLast = (cached['lastScreenshotTime'] as int?) ?? 0;
      final int dbTotal = await _database.getTotalScreenshotCount();
      final int dbLast =
          await _database.getGlobalLatestCaptureTimeMillis() ?? 0;
      return cachedTotal == dbTotal && cachedLast == dbLast;
    } catch (_) {
      // 校验失败时宁愿使用缓存，避免启动阶段因为异常回退到 0。
      return true;
    }
  }

  Future<Map<String, dynamic>> _buildStatsFromAppStats({
    bool includeTodayCount = false,
    bool saveCache = false,
  }) async {
    final statistics = await _database.getScreenshotStatistics();

    int totalCount = 0;
    DateTime? lastScreenshotTime;
    for (final stat in statistics.values) {
      totalCount += (stat['totalCount'] as int?) ?? 0;
      final time = stat['lastCaptureTime'] as DateTime?;
      if (time != null &&
          (lastScreenshotTime == null || time.isAfter(lastScreenshotTime))) {
        lastScreenshotTime = time;
      }
    }

    final int todayCount = includeTodayCount
        ? await _database.getTodayScreenshotCount()
        : 0;
    final stats = {
      'totalScreenshots': totalCount,
      'todayScreenshots': todayCount,
      'lastScreenshotTime': lastScreenshotTime?.millisecondsSinceEpoch,
      'appStatistics': statistics,
    };
    if (saveCache) {
      // ignore: unawaited_futures
      _saveStatsCache(stats);
    }
    return stats;
  }

  /// 启动截屏服务
  Future<bool> startScreenshotService(int intervalSeconds) async {
    try {
      print('=== 开始启动截屏服务 ===');
      // 统一约束：5-60 秒
      final int clampedInterval = intervalSeconds < 5
          ? 5
          : (intervalSeconds > 60 ? 60 : intervalSeconds);
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
          print('第${i + 1}次检查服务状态: $serviceRunning');
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
        await UserSettingsService.instance.setInt(
          UserSettingKeys.screenshotInterval,
          clampedInterval,
          legacyPrefKeys: const <String>[
            'timed_screenshot_interval',
            'flutter.screenshot_interval',
          ],
        );
      } catch (_) {}
      final success = await _permissionService.startTimedScreenshot(
        clampedInterval,
      );

      if (success) {
        _isRunning = true;
        _currentInterval = clampedInterval;
        await _saveServiceState();
        unawaited(
          AppHealthService.instance.recordCaptureServiceStarted(
            intervalSec: clampedInterval,
          ),
        );
        print('=== 截屏服务启动成功，间隔: $clampedInterval秒 ===');
        return true;
      } else {
        throw ScreenshotServiceException(
          '截屏服务启动失败，请检查：\n1. Android版本是否为11.0(API 30)或以上\n2. 无障碍服务是否正常运行\n3. 尝试重新启动应用',
        );
      }
    } on ScreenshotServiceException catch (e) {
      unawaited(
        AppHealthService.instance.recordCaptureFailure(
          errorType: 'capture_start_failed',
          errorMessage: e.message,
        ),
      );
      rethrow;
    } catch (e) {
      print('启动截屏服务异常: $e');
      unawaited(
        AppHealthService.instance.recordCaptureFailure(
          errorType: 'capture_start_failed',
          errorMessage: 'Unexpected capture start error: $e',
        ),
      );
      throw ScreenshotServiceException('启动截屏服务时发生未知错误：$e');
    }
  }

  /// 停止截屏服务
  Future<void> stopScreenshotService() async {
    try {
      await _permissionService.stopTimedScreenshot();
      _isRunning = false;
      await _saveServiceState();
      unawaited(AppHealthService.instance.recordCaptureServiceStopped());
    } catch (e) {
      print('停止截屏服务失败: $e');
      unawaited(
        AppHealthService.instance.recordCaptureFailure(
          errorType: 'capture_stop_failed',
          errorMessage: 'Failed to stop screenshot service: $e',
        ),
      );
    }
  }

  /// 更新截屏间隔
  Future<bool> updateInterval(int intervalSeconds) async {
    try {
      // 统一约束：5-60 秒
      final int clampedInterval = intervalSeconds < 5
          ? 5
          : (intervalSeconds > 60 ? 60 : intervalSeconds);
      if (_isRunning) {
        // 重新启动服务以应用新间隔
        await _permissionService.stopTimedScreenshot();
        // 启动前先持久化一次间隔，避免原生侧读到旧值
        try {
          await UserSettingsService.instance.setInt(
            UserSettingKeys.screenshotInterval,
            clampedInterval,
            legacyPrefKeys: const <String>[
              'timed_screenshot_interval',
              'flutter.screenshot_interval',
            ],
          );
        } catch (_) {}
        final success = await _permissionService.startTimedScreenshot(
          clampedInterval,
        );
        if (success) {
          _currentInterval = clampedInterval;
          await _saveServiceState();
        }
        return success;
      } else {
        _currentInterval = clampedInterval;
        await _saveServiceState();
        try {
          await UserSettingsService.instance.setInt(
            UserSettingKeys.screenshotInterval,
            clampedInterval,
            legacyPrefKeys: const <String>[
              'timed_screenshot_interval',
              'flutter.screenshot_interval',
            ],
          );
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
      unawaited(
        AppHealthService.instance.recordCaptureFailure(
          errorType: 'manual_capture_failed',
          errorMessage: 'Manual capture failed: $e',
        ),
      );
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
    print('=== 设置截图服务 方法通道处理器 ===');
    _channel.setMethodCallHandler((call) async {
      print('=== 收到方法通道调用: ${call.method} ===');

      try {
        // 安全地检查参数
        if (call.arguments == null) {
          print('=== 参数为空 ===');
        } else {
          print('=== 参数类型: ${call.arguments.runtimeType} ===');
          print('=== 参数内容: ${call.arguments} ===');
        }
        switch (call.method) {
          case 'onScreenshotSaved':
            print('=== 开始处理截图保存回调 ===');

            // 安全地转换参数
            if (call.arguments == null) {
              print('=== 错误：参数为空 ===');
              return;
            }

            if (call.arguments is! Map) {
              print('=== 错误：参数不是Map类型，实际类型：${call.arguments.runtimeType} ===');
              return;
            }

            final arguments = Map<String, dynamic>.from(call.arguments as Map);
            print('=== 参数转换成功，开始处理 ===');

            await _handleScreenshotSaved(arguments);
            print('=== 截图保存回调处理完成 ===');
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
              FlutterLogger.nativeInfo(
                'Navigation',
                '通知点击：dateKey=${dk ?? '空'}',
              );
              // 不阻塞当前 handler
              // ignore: unawaited_futures
              NavigationService.instance.openDailySummary(dk);
            } catch (e) {
              print('处理通知点击失败: $e');
            }
            break;
          case 'onDynamicRebuildNotificationTap':
            try {
              await FlutterLogger.nativeInfo('Navigation', '通知点击：打开动态页');
              await NavigationService.instance.openSegmentStatus();
            } catch (e) {
              print('处理动态重建通知点击失败: $e');
            }
            break;
          case 'onMemoryRebuildNotificationTap':
            try {
              await FlutterLogger.nativeInfo('Navigation', '通知点击：打开记忆重建页');
              await NavigationService.instance.openNocturneMemory(
                initialTabIndex: 1,
              );
            } catch (e) {
              print('处理记忆重建通知点击失败: $e');
            }
            break;
          case 'onCompressionProgress':
            if (call.arguments is Map) {
              _handleCompressionProgress(
                Map<String, dynamic>.from(call.arguments as Map),
              );
            }
            break;
          default:
            print('未处理的方法调用: ${call.method}');
        }
      } catch (e, stackTrace) {
        print('=== 方法通道处理异常: $e ===');
        print('=== 堆栈跟踪: $stackTrace ===');
      }
    });
    print('=== 截图服务 方法通道处理器设置完成 ===');
  }

  /// 允许其他服务（如 PermissionService）转发平台事件至此处统一处理
  Future<void> handleScreenshotSavedFromPlatform(
    Map<String, dynamic> data,
  ) async {
    await _handleScreenshotSaved(data);
  }

  void _handleCompressionProgress(Map<String, dynamic> raw) {
    try {
      final int rawTotal = _coerceToInt(raw['total']);
      final int total = _activeCompressionTotalOverride > 0
          ? _activeCompressionTotalOverride
          : rawTotal;
      int capHandled(int value) {
        if (total <= 0) return value < 0 ? 0 : value;
        if (value < 0) return 0;
        return value > total ? total : value;
      }

      final progress = CompressionProgress(
        total: total,
        handled: capHandled(
          _activeCompressionHandledOffset + _coerceToInt(raw['handled']),
        ),
        success: _activeCompressionSuccessOffset + _coerceToInt(raw['success']),
        skipped: _activeCompressionSkippedOffset + _coerceToInt(raw['skipped']),
        failed: _activeCompressionFailedOffset + _coerceToInt(raw['failed']),
        savedBytes:
            _activeCompressionSavedOffset + _coerceToInt(raw['savedBytes']),
      );
      _latestCompressionProgress = progress;
      final String? activePackage = _activeCompressionPackage;
      if (activePackage != null) {
        _latestCompressionProgressByPackage[activePackage] = progress;
      }

      final listener = _compressionProgressListener;
      if (listener != null) {
        final String? filter = _listenerPackageFilter;
        if (filter == null || filter == activePackage) {
          listener(progress);
        }
      }
    } catch (e) {
      print('处理压缩进度回调失败: $e');
    }
  }

  int _coerceToInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  bool _coerceToBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String normalized = value.toLowerCase().trim();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
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
      final captureTime =
          data['captureTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      print('收到截图保存通知: $appName - $relativePath');

      if (packageName.isNotEmpty &&
          appName.isNotEmpty &&
          relativePath.isNotEmpty) {
        // 将相对路径转换为绝对路径
        final baseDir = await PathService.getInternalAppDir(null);
        if (baseDir == null) {
          print('无法获取基础目录，跳过数据库插入');
          unawaited(
            AppHealthService.instance.recordScreenshotSaveFailure(
              errorType: 'storage_dir_missing',
              errorMessage: 'Internal storage directory is unavailable',
            ),
          );
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
          unawaited(
            AppHealthService.instance.recordScreenshotSaved(
              packageName: packageName,
              inserted: id != null,
            ),
          );
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
        unawaited(
          AppHealthService.instance.recordScreenshotSaveFailure(
            errorType: 'invalid_screenshot_callback',
            errorMessage: 'Screenshot callback payload is incomplete',
          ),
        );
      }
    } catch (e) {
      print('处理截图保存通知失败: $e');
      unawaited(
        AppHealthService.instance.recordScreenshotSaveFailure(
          errorType: 'screenshot_save_failed',
          errorMessage: 'Screenshot save callback failed: $e',
        ),
      );
    }
  }

  /// 获取截屏统计信息
  Future<Map<String, dynamic>> getScreenshotStats() async {
    StartupProfiler.begin('ScreenshotService.getScreenshotStats');
    try {
      // 首页和应用列表只依赖 app_stats；不扫描分库统计 today，避免大库启动慢。
      return await _buildStatsFromAppStats(saveCache: true);
    } catch (e) {
      print('获取截屏统计信息失败: $e');
      return {
        'totalScreenshots': 0,
        'todayScreenshots': 0,
        'lastScreenshotTime': null,
        'appStatistics': <String, Map<String, dynamic>>{},
      };
    } finally {
      StartupProfiler.end('ScreenshotService.getScreenshotStats');
    }
  }

  /// 获取汇总统计数据
  Future<Map<String, dynamic>> getTotals() async {
    return await _database.getTotals();
  }

  /// 重新计算指定应用的统计信息，并刷新缓存
  Future<void> recomputeAppStats(String packageName) async {
    await _database.recomputeAppStatsForPackage(packageName);
    await _refreshStatsCache(force: true);
  }

  /// 重新计算汇总统计（用于数据迁移或修复）
  Future<void> recalculateTotals() async {
    await _database.recalculateTotals();
    await _refreshStatsCache(force: true);
  }

  bool _isRecomputeCanceled(bool Function()? shouldCancel) {
    try {
      return shouldCancel?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 重新计算所有应用的统计信息，然后刷新全局统计与缓存
  Future<bool> recomputeAllAppStats({
    void Function(ScreenshotRecomputeProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    onProgress?.call(
      const ScreenshotRecomputeProgress(
        phase: 'scan_prepare',
        current: 0,
        total: 0,
      ),
    );
    final int repaired = await syncMissingScreenshotsFromFiles(
      refreshAfter: false,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
    if (_isRecomputeCanceled(shouldCancel)) return false;
    final List<String> packages = await _database.listRegisteredPackages();
    final int totalSteps = packages.length + 3;
    int step = 0;
    for (final String pkg in packages) {
      if (_isRecomputeCanceled(shouldCancel)) return false;
      onProgress?.call(
        ScreenshotRecomputeProgress(
          phase: 'recompute_app',
          current: step,
          total: totalSteps,
          inserted: repaired,
          packageName: pkg,
        ),
      );
      await _database.recomputeAppStatsForPackage(pkg);
      step++;
      if (_isRecomputeCanceled(shouldCancel)) return false;
      onProgress?.call(
        ScreenshotRecomputeProgress(
          phase: 'recompute_app',
          current: step,
          total: totalSteps,
          inserted: repaired,
          packageName: pkg,
        ),
      );
    }
    if (_isRecomputeCanceled(shouldCancel)) return false;
    onProgress?.call(
      ScreenshotRecomputeProgress(
        phase: 'recalculate_totals',
        current: step,
        total: totalSteps,
        inserted: repaired,
      ),
    );
    await _database.recalculateTotals();
    step++;
    onProgress?.call(
      ScreenshotRecomputeProgress(
        phase: 'refresh_cache',
        current: step,
        total: totalSteps,
        inserted: repaired,
      ),
    );
    await _refreshStatsCache(force: true);
    step++;
    await _invalidateAvailableDayCountCacheAsync();
    onProgress?.call(
      ScreenshotRecomputeProgress(
        phase: 'refresh_days',
        current: step,
        total: totalSteps,
        inserted: repaired,
      ),
    );
    await _refreshDayCount();
    step++;
    onProgress?.call(
      ScreenshotRecomputeProgress(
        phase: 'done',
        current: step,
        total: totalSteps,
        inserted: repaired,
      ),
    );
    if (repaired > 0) {
      _screenshotStreamController.add(null);
    }
    return true;
  }

  /// 获取最新统计（不使用统计缓存，可选择强制全量文件同步）
  Future<Map<String, dynamic>> getScreenshotStatsFresh({
    bool forceFullSync = true,
    bool includeTodayCount = false,
  }) async {
    StartupProfiler.begin('ScreenshotService.getScreenshotStatsFresh');
    try {
      return await _buildStatsFromAppStats(
        includeTodayCount: includeTodayCount,
      );
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
      return await _buildStatsFromAppStats();
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
    FlutterLogger.log('统计缓存已快速刷新(数据库)并保存，用时 ${sw.elapsedMilliseconds}毫秒');
  }

  /// 根据应用包名获取截屏记录（支持分页）
  Future<List<ScreenshotRecord>> getScreenshotsByApp(
    String appPackageName, {
    int? limit,
    int? offset,
  }) async {
    try {
      // 直接从数据库查询，不再进行任何文件系统同步
      return await _database.getScreenshotsByApp(
        appPackageName,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      print('获取应用截屏记录失败: $e');
      return [];
    }
  }

  /// 通过全局ID(gid)与包名获取单条截图记录
  Future<ScreenshotRecord?> getScreenshotById(
    int gid,
    String appPackageName,
  ) async {
    try {
      return await _database.getScreenshotById(gid, appPackageName);
    } catch (e) {
      print('通过ID获取截图失败: $e');
      return null;
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

  /// 全局：按 bucket 抽样获取给定时间范围内的截图帧（所有应用，按时间正序）
  Future<List<ScreenshotRecord>> getGlobalScreenshotsBucketedBetween({
    required int startMillis,
    required int endMillis,
    required int bucketMillis,
  }) async {
    try {
      return await _database.getGlobalScreenshotsBucketedBetween(
        startMillis: startMillis,
        endMillis: endMillis,
        bucketMillis: bucketMillis,
      );
    } catch (e) {
      print('获取全局 bucket 抽样截图失败: $e');
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

  /// 对指定应用的历史截图执行批量压缩（仅压缩大于目标大小的文件）。
  Future<CompressionResult> compressAppScreenshots({
    required String packageName,
    required int days,
    required int targetSizeKb,
    String? imageFormat,
    int? imageQuality,
    bool useTargetSize = true,
    void Function(CompressionProgress progress)? onProgress,
  }) async {
    if (_compressionInFlight) {
      throw ScreenshotServiceException('已有压缩任务正在执行');
    }
    if (targetSizeKb < 1) {
      const result = CompressionResult.empty();
      onProgress?.call(result);
      return result;
    }

    final DateTime now = DateTime.now();
    final DateTime start = now.subtract(Duration(days: days < 1 ? 1 : days));
    final List<ScreenshotRecord> records = await getScreenshotsByAppBetween(
      packageName,
      startMillis: start.millisecondsSinceEpoch,
      endMillis: now.millisecondsSinceEpoch,
    );
    if (records.isEmpty) {
      const result = CompressionResult.empty();
      onProgress?.call(result);
      return result;
    }

    final List<Map<String, dynamic>> tasks = <Map<String, dynamic>>[];
    int aggregatedOriginalBytes = 0;
    for (final ScreenshotRecord record in records) {
      final int? gid = record.id;
      if (gid == null) {
        continue;
      }
      final int originalSize = record.fileSize;
      tasks.add({
        'filePath': record.filePath,
        'gid': gid,
        'originalSize': originalSize,
      });
      aggregatedOriginalBytes += originalSize;
    }

    if (tasks.isEmpty) {
      const result = CompressionResult.empty();
      onProgress?.call(result);
      return result;
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    final int targetBytes = ((targetSizeKb * 1024).clamp(
      1024,
      1024 * 1024 * 20,
    )).toInt();
    final String normalizedFormat = (imageFormat ?? 'webp_lossy')
        .toLowerCase()
        .trim();
    final bool wantTarget = useTargetSize;
    final bool formatIsLossy =
        normalizedFormat == 'webp_lossy' ||
        normalizedFormat == 'webp' ||
        normalizedFormat == 'jpeg' ||
        normalizedFormat == 'jpg';
    final String finalFormat = wantTarget && !formatIsLossy
        ? 'webp_lossy'
        : normalizedFormat;
    final bool finalUseTarget =
        wantTarget &&
        (finalFormat == 'webp_lossy' ||
            finalFormat == 'webp' ||
            finalFormat == 'jpeg' ||
            finalFormat == 'jpg');
    final int finalQuality = (imageQuality ?? 90).clamp(1, 100);

    _activeCompressionTotalOverride = 0;
    _activeCompressionHandledOffset = 0;
    _activeCompressionSuccessOffset = 0;
    _activeCompressionSkippedOffset = 0;
    _activeCompressionFailedOffset = 0;
    _activeCompressionSavedOffset = 0;
    _activeCompressionPackage = packageName;
    _compressionInFlight = true;
    final CompressionProgress initialProgress = CompressionProgress(
      total: tasks.length,
      handled: 0,
      success: 0,
      skipped: 0,
      failed: 0,
      savedBytes: 0,
    );
    _latestCompressionProgress = initialProgress;
    _latestCompressionProgressByPackage[packageName] = initialProgress;
    attachCompressionProgressListener(
      onProgress,
      replayLatest: false,
      packageName: packageName,
    );
    onProgress?.call(initialProgress);

    Map<String, dynamic> response = const <String, dynamic>{};
    try {
      final Map<String, dynamic>? raw = await _channel
          .invokeMapMethod<String, dynamic>(
            'compressScreenshotsBatch',
            <String, dynamic>{
              'tasks': tasks,
              'format': finalFormat,
              'targetBytes': targetBytes,
              'quality': finalQuality,
              'useTargetSize': finalUseTarget,
            },
          );
      if (raw != null) {
        response = raw;
      }
    } finally {
      attachCompressionProgressListener(null, replayLatest: false);
      _compressionInFlight = false;
      _activeCompressionPackage = null;
      _activeCompressionTotalOverride = 0;
      _activeCompressionHandledOffset = 0;
      _activeCompressionSuccessOffset = 0;
      _activeCompressionSkippedOffset = 0;
      _activeCompressionFailedOffset = 0;
      _activeCompressionSavedOffset = 0;
    }

    final List<dynamic> successesRaw =
        (response['successes'] as List?) ?? const <dynamic>[];
    final List<dynamic> failuresRaw =
        (response['failures'] as List?) ?? const <dynamic>[];
    final List<dynamic> skippedRaw =
        (response['skippedEntries'] as List?) ?? const <dynamic>[];

    final int successCount = successesRaw.length;
    final int skippedCount = skippedRaw.length;
    final int failedCount = failuresRaw.length;
    final int handledCount = _coerceToInt(response['handled']);
    final int totalCount = _coerceToInt(response['total']);
    final int rawSavedBytes = _coerceToInt(response['savedBytes']);
    final int rawTotalBefore = _coerceToInt(response['totalBeforeBytes']);
    final int rawTotalAfter = _coerceToInt(response['totalAfterBytes']);
    final int durationMillis = _coerceToInt(response['durationMillis']);

    for (final dynamic entry in successesRaw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final int gid = _coerceToInt(map['gid']);
      final int newSize = _coerceToInt(map['newSize']);
      if (gid > 0 && newSize > 0) {
        await _database.updateFileSizeByGid(
          packageName: packageName,
          gid: gid,
          newSize: newSize,
        );
      }
    }

    if (successCount > 0) {
      try {
        await _database.recomputeAppStatsForPackage(packageName);
        await _database.recalculateTotals();
        await _refreshStatsCache(force: true);
      } catch (e) {
        print('压缩后刷新统计失败: $e');
      }
      _screenshotStreamController.add(null);
    }

    stopwatch.stop();

    final int fallbackBefore = successesRaw.fold<int>(0, (
      previousValue,
      element,
    ) {
      if (element is! Map) return previousValue;
      return previousValue + _coerceToInt(element['originalSize']);
    });
    final int totalBeforeBytes = rawTotalBefore > 0
        ? rawTotalBefore
        : (fallbackBefore > 0 ? fallbackBefore : aggregatedOriginalBytes);
    final int fallbackAfter = totalBeforeBytes - rawSavedBytes;
    final int totalAfterBytes = rawTotalAfter > 0
        ? rawTotalAfter
        : (fallbackAfter < 0 ? 0 : fallbackAfter);
    final int computedSaved = totalBeforeBytes - totalAfterBytes;
    final int safeSavedBytes = computedSaved < 0 ? 0 : computedSaved;

    final CompressionResult result = CompressionResult(
      total: totalCount == 0 ? tasks.length : totalCount,
      handled: handledCount == 0
          ? successCount + skippedCount + failedCount
          : handledCount,
      success: successCount,
      skipped: skippedCount,
      failed: failedCount,
      savedBytes: safeSavedBytes,
      durationMillis: durationMillis == 0
          ? stopwatch.elapsedMilliseconds
          : durationMillis,
      totalBeforeBytes: totalBeforeBytes,
      totalAfterBytes: totalAfterBytes,
    );
    _latestCompressionProgress = result;
    _latestCompressionProgressByPackage[packageName] = result;
    onProgress?.call(result);
    return result;
  }

  /// 对所有应用的历史截图执行批量压缩。
  ///
  /// 该任务使用全局互斥锁，避免和单应用压缩同时修改同一批图片。
  ///
  /// 这里仍保持较大的 Dart 批次以减少通道开销；取消时会通知原生侧停止
  /// 领取新图片，已经开始编码的少量图片会自然完成。
  Future<CompressionResult> compressAllAppScreenshots({
    required int days,
    required int targetSizeKb,
    String? imageFormat,
    int? imageQuality,
    bool useTargetSize = true,
    CompressionCancellationToken? cancellationToken,
    void Function(CompressionProgress progress)? onProgress,
  }) async {
    if (_compressionInFlight) {
      throw ScreenshotServiceException('已有压缩任务正在执行');
    }
    if (targetSizeKb < 1) {
      const result = CompressionResult.empty();
      onProgress?.call(result);
      return result;
    }

    final DateTime now = DateTime.now();
    final bool allHistory = days < 1;
    final DateTime start = allHistory
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : now.subtract(Duration(days: days));
    final int startMillis = allHistory ? 0 : start.millisecondsSinceEpoch;
    final int endMillis = now.millisecondsSinceEpoch;
    final int estimatedTotal = await getGlobalScreenshotCountBetween(
      startMillis: startMillis,
      endMillis: endMillis,
    );
    if (estimatedTotal <= 0) {
      const result = CompressionResult.empty();
      onProgress?.call(result);
      return result;
    }

    final List<String> packages = await _database
        .listPackagesWithScreenshotShards();
    if (packages.isEmpty) {
      const result = CompressionResult.empty();
      onProgress?.call(result);
      return result;
    }
    if (cancellationToken?.isCancelled ?? false) {
      const result = CompressionResult.empty();
      onProgress?.call(result);
      return result;
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    final int targetBytes = ((targetSizeKb * 1024).clamp(
      1024,
      1024 * 1024 * 20,
    )).toInt();
    final String normalizedFormat = (imageFormat ?? 'webp_lossy')
        .toLowerCase()
        .trim();
    final bool wantTarget = useTargetSize;
    final bool formatIsLossy =
        normalizedFormat == 'webp_lossy' ||
        normalizedFormat == 'webp' ||
        normalizedFormat == 'jpeg' ||
        normalizedFormat == 'jpg';
    final String finalFormat = wantTarget && !formatIsLossy
        ? 'webp_lossy'
        : normalizedFormat;
    final bool finalUseTarget =
        wantTarget &&
        (finalFormat == 'webp_lossy' ||
            finalFormat == 'webp' ||
            finalFormat == 'jpeg' ||
            finalFormat == 'jpg');
    final int finalQuality = (imageQuality ?? 90).clamp(1, 100);

    int handledTotal = 0;
    int successTotal = 0;
    int skippedTotal = 0;
    int failedTotal = 0;
    int savedTotal = 0;
    int beforeTotal = 0;
    int afterTotal = 0;
    int durationTotal = 0;
    int taskTotal = 0;
    bool cancelled = false;
    final Set<String> changedPackages = <String>{};

    _activeCompressionTotalOverride = estimatedTotal;
    _activeCompressionHandledOffset = 0;
    _activeCompressionSuccessOffset = 0;
    _activeCompressionSkippedOffset = 0;
    _activeCompressionFailedOffset = 0;
    _activeCompressionSavedOffset = 0;
    _activeCompressionPackage = globalCompressionScopeKey;
    _compressionInFlight = true;
    final CompressionProgress initialProgress = CompressionProgress(
      total: estimatedTotal,
      handled: 0,
      success: 0,
      skipped: 0,
      failed: 0,
      savedBytes: 0,
    );
    _latestCompressionProgress = initialProgress;
    _latestCompressionProgressByPackage[globalCompressionScopeKey] =
        initialProgress;
    attachCompressionProgressListener(
      onProgress,
      replayLatest: false,
      packageName: globalCompressionScopeKey,
    );
    onProgress?.call(initialProgress);

    final String compressionJobId =
        'global_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}';
    final Future<void> Function() nativeCancelHandler = () async {
      try {
        await _channel.invokeMethod<void>('cancelCompressionBatch', {
          'jobId': compressionJobId,
        });
      } catch (e) {
        print('通知原生取消压缩失败: $e');
      }
    };

    cancellationToken?.addCancelHandler(nativeCancelHandler);

    const int chunkSize = 500;
    try {
      for (final String packageName in packages) {
        if (cancellationToken?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        final List<ScreenshotRecord> records = await getScreenshotsByAppBetween(
          packageName,
          startMillis: startMillis,
          endMillis: endMillis,
        );
        if (cancellationToken?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        if (records.isEmpty) continue;

        final List<Map<String, dynamic>> tasks = <Map<String, dynamic>>[];
        for (final ScreenshotRecord record in records) {
          final int? gid = record.id;
          if (gid == null) continue;
          if (cancellationToken?.isCancelled ?? false) {
            cancelled = true;
            break;
          }
          final int originalSize = record.fileSize;
          if (targetBytes > 0 &&
              originalSize > 0 &&
              originalSize <= targetBytes) {
            taskTotal += 1;
            handledTotal += 1;
            skippedTotal += 1;
            final progress = CompressionProgress(
              total: estimatedTotal,
              handled: handledTotal,
              success: successTotal,
              skipped: skippedTotal,
              failed: failedTotal,
              savedBytes: savedTotal,
            );
            _latestCompressionProgress = progress;
            _latestCompressionProgressByPackage[globalCompressionScopeKey] =
                progress;
            onProgress?.call(progress);
            continue;
          }
          tasks.add(<String, dynamic>{
            'filePath': record.filePath,
            'gid': gid,
            'originalSize': originalSize,
          });
        }
        if (cancelled) break;
        if (tasks.isEmpty) continue;
        taskTotal += tasks.length;

        for (
          int startIndex = 0;
          startIndex < tasks.length;
          startIndex += chunkSize
        ) {
          final int endIndex = (startIndex + chunkSize) > tasks.length
              ? tasks.length
              : startIndex + chunkSize;
          final List<Map<String, dynamic>> chunk = tasks.sublist(
            startIndex,
            endIndex,
          );
          if (cancellationToken?.isCancelled ?? false) {
            cancelled = true;
            break;
          }

          _activeCompressionHandledOffset = handledTotal;
          _activeCompressionSuccessOffset = successTotal;
          _activeCompressionSkippedOffset = skippedTotal;
          _activeCompressionFailedOffset = failedTotal;
          _activeCompressionSavedOffset = savedTotal;

          final Stopwatch chunkStopwatch = Stopwatch()..start();
          Map<String, dynamic> response = const <String, dynamic>{};
          final Map<String, dynamic>? raw = await _channel
              .invokeMapMethod<String, dynamic>(
                'compressScreenshotsBatch',
                <String, dynamic>{
                  'tasks': chunk,
                  'format': finalFormat,
                  'targetBytes': targetBytes,
                  'quality': finalQuality,
                  'useTargetSize': finalUseTarget,
                  'jobId': compressionJobId,
                },
              );
          if (raw != null) {
            response = raw;
          }
          chunkStopwatch.stop();

          final List<dynamic> successesRaw =
              (response['successes'] as List?) ?? const <dynamic>[];
          final List<dynamic> failuresRaw =
              (response['failures'] as List?) ?? const <dynamic>[];
          final List<dynamic> skippedRaw =
              (response['skippedEntries'] as List?) ?? const <dynamic>[];

          final int successCount = successesRaw.length;
          final int skippedCount = skippedRaw.length;
          final int failedCount = failuresRaw.length;
          final int handledCount = _coerceToInt(response['handled']);
          final int rawSavedBytes = _coerceToInt(response['savedBytes']);
          final int rawTotalBefore = _coerceToInt(response['totalBeforeBytes']);
          final int rawTotalAfter = _coerceToInt(response['totalAfterBytes']);
          final int durationMillis = _coerceToInt(response['durationMillis']);
          final bool nativeCancelled = _coerceToBool(response['cancelled']);

          for (final dynamic entry in successesRaw) {
            if (entry is! Map) continue;
            final map = Map<String, dynamic>.from(entry);
            final int gid = _coerceToInt(map['gid']);
            final int newSize = _coerceToInt(map['newSize']);
            if (gid > 0 && newSize > 0) {
              await _database.updateFileSizeByGid(
                packageName: packageName,
                gid: gid,
                newSize: newSize,
              );
              changedPackages.add(packageName);
            }
          }

          final int fallbackBefore = successesRaw.fold<int>(0, (
            previousValue,
            element,
          ) {
            if (element is! Map) return previousValue;
            return previousValue + _coerceToInt(element['originalSize']);
          });
          final int totalBeforeBytes = rawTotalBefore > 0
              ? rawTotalBefore
              : fallbackBefore;
          final int fallbackAfter = totalBeforeBytes - rawSavedBytes;
          final int totalAfterBytes = rawTotalAfter > 0
              ? rawTotalAfter
              : (fallbackAfter < 0 ? 0 : fallbackAfter);
          final int computedSaved = totalBeforeBytes - totalAfterBytes;
          final int safeSavedBytes = computedSaved < 0 ? 0 : computedSaved;

          handledTotal += handledCount == 0
              ? successCount + skippedCount + failedCount
              : handledCount;
          successTotal += successCount;
          skippedTotal += skippedCount;
          failedTotal += failedCount;
          savedTotal += safeSavedBytes;
          beforeTotal += totalBeforeBytes;
          afterTotal += totalAfterBytes;
          durationTotal += durationMillis == 0
              ? chunkStopwatch.elapsedMilliseconds
              : durationMillis;
          if (nativeCancelled || (cancellationToken?.isCancelled ?? false)) {
            cancelled = true;
            break;
          }
        }
        if (cancelled) break;
      }
    } finally {
      cancellationToken?.removeCancelHandler(nativeCancelHandler);
      attachCompressionProgressListener(null, replayLatest: false);
      _compressionInFlight = false;
      _activeCompressionPackage = null;
      _activeCompressionTotalOverride = 0;
      _activeCompressionHandledOffset = 0;
      _activeCompressionSuccessOffset = 0;
      _activeCompressionSkippedOffset = 0;
      _activeCompressionFailedOffset = 0;
      _activeCompressionSavedOffset = 0;
    }

    if (changedPackages.isNotEmpty) {
      try {
        for (final String packageName in changedPackages) {
          await _database.recomputeAppStatsForPackage(packageName);
        }
        await _database.recalculateTotals();
        await _refreshStatsCache(force: true);
      } catch (e) {
        print('全局压缩后刷新统计失败: $e');
      }
      _screenshotStreamController.add(null);
    }

    stopwatch.stop();
    final int resultTotal = taskTotal > 0
        ? (cancelled && estimatedTotal > 0 ? estimatedTotal : taskTotal)
        : (estimatedTotal > handledTotal ? estimatedTotal : handledTotal);
    final CompressionResult result = CompressionResult(
      total: resultTotal,
      handled: handledTotal,
      success: successTotal,
      skipped: skippedTotal,
      failed: failedTotal,
      savedBytes: savedTotal,
      durationMillis: durationTotal == 0
          ? stopwatch.elapsedMilliseconds
          : durationTotal,
      totalBeforeBytes: beforeTotal,
      totalAfterBytes: afterTotal,
    );
    _latestCompressionProgress = result;
    _latestCompressionProgressByPackage[globalCompressionScopeKey] = result;
    onProgress?.call(result);
    return result;
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

  /// 全局按 OCR 文本搜索（支持时间与大小过滤）
  Future<List<ScreenshotRecord>> searchScreenshotsByOcr(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    try {
      return await _database.searchScreenshotsByOcr(
        query,
        limit: limit,
        offset: offset,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (e) {
      print('OCR 搜索失败: $e');
      return [];
    }
  }

  /// 统计全局按 OCR 文本匹配的总数量（强制使用 FTS）
  Future<int> countScreenshotsByOcr(
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    try {
      return await _database.countScreenshotsByOcr(
        query,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (e) {
      print('统计 OCR 总数失败: $e');
      return 0;
    }
  }

  /// 指定应用按 OCR 文本搜索（支持时间与大小过滤）
  Future<List<ScreenshotRecord>> searchScreenshotsByOcrForApp(
    String appPackageName,
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    try {
      return await _database.searchScreenshotsByOcrForApp(
        appPackageName,
        query,
        limit: limit,
        offset: offset,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (e) {
      print('应用内 OCR 搜索失败: $e');
      return [];
    }
  }

  /// 统计指定应用按 OCR 文本匹配的总数量（强制使用 FTS）
  Future<int> countScreenshotsByOcrForApp(
    String appPackageName,
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    try {
      return await _database.countScreenshotsByOcrForApp(
        appPackageName,
        query,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (e) {
      print('统计应用内 OCR 总数失败: $e');
      return 0;
    }
  }

  /// 索引可用性：检测 SQLite 是否支持 FTS（fts5/fts4）。
  Future<bool> isOcrIndexAvailable() async {
    try {
      return await _database.isOcrIndexAvailable();
    } catch (e) {
      return false;
    }
  }

  bool _isLikelyCjkNoSpacesQuery(String query) {
    final String q = query.trim();
    if (q.isEmpty || RegExp(r'\s').hasMatch(q)) return false;
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
  }

  // ========== 带回退的全局 OCR 搜索与计数 ==========
  Future<List<ScreenshotRecord>> searchScreenshotsByOcrWithFallback(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    try {
      bool indexAvailable = false;
      try {
        indexAvailable = await _database.isOcrIndexAvailable();
      } catch (_) {}
      if (_isLikelyCjkNoSpacesQuery(query)) {
        int? likeCount;
        if (indexAvailable) {
          try {
            likeCount = await _database.countScreenshotsByOcrLike(
              query,
              startMillis: startMillis,
              endMillis: endMillis,
              minSize: minSize,
              maxSize: maxSize,
            );
          } catch (_) {}
        }
        List<ScreenshotRecord> likeResults = <ScreenshotRecord>[];
        try {
          likeResults = await _database.searchScreenshotsByOcrLike(
            query,
            limit: limit,
            offset: offset,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
        } catch (_) {}
        if (!indexAvailable ||
            likeResults.isNotEmpty ||
            (likeCount != null && likeCount > 0)) {
          return likeResults;
        }
        try {
          final List<ScreenshotRecord> ftsResults = await _database
              .searchScreenshotsByOcr(
                query,
                limit: limit,
                offset: offset,
                startMillis: startMillis,
                endMillis: endMillis,
                minSize: minSize,
                maxSize: maxSize,
              );
          return ftsResults.isNotEmpty ? ftsResults : likeResults;
        } catch (_) {
          return likeResults;
        }
      }
      if (indexAvailable) {
        try {
          final List<ScreenshotRecord> ftsResults = await _database
              .searchScreenshotsByOcr(
                query,
                limit: limit,
                offset: offset,
                startMillis: startMillis,
                endMillis: endMillis,
                minSize: minSize,
                maxSize: maxSize,
              );
          if (ftsResults.isNotEmpty) {
            return ftsResults;
          }
        } catch (_) {}
      }
      return await _database.searchScreenshotsByOcrLike(
        query,
        limit: limit,
        offset: offset,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (_) {
      return <ScreenshotRecord>[];
    }
  }

  Future<int> countScreenshotsByOcrWithFallback(
    String query, {
    int? startMillis,
    int? endMillis,
    int? minSize,
    int? maxSize,
  }) async {
    try {
      bool indexAvailable = false;
      try {
        indexAvailable = await _database.isOcrIndexAvailable();
      } catch (_) {}
      if (_isLikelyCjkNoSpacesQuery(query)) {
        int likeCount = 0;
        try {
          likeCount = await _database.countScreenshotsByOcrLike(
            query,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
        } catch (_) {}
        if (likeCount > 0 || !indexAvailable) {
          return likeCount;
        }
        try {
          final int ftsCount = await _database.countScreenshotsByOcr(
            query,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
          return ftsCount > 0 ? ftsCount : likeCount;
        } catch (_) {
          return likeCount;
        }
      }
      if (indexAvailable) {
        try {
          final int ftsCount = await _database.countScreenshotsByOcr(
            query,
            startMillis: startMillis,
            endMillis: endMillis,
            minSize: minSize,
            maxSize: maxSize,
          );
          if (ftsCount > 0) {
            return ftsCount;
          }
        } catch (_) {}
      }
      return await _database.countScreenshotsByOcrLike(
        query,
        startMillis: startMillis,
        endMillis: endMillis,
        minSize: minSize,
        maxSize: maxSize,
      );
    } catch (_) {
      return 0;
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
      FlutterLogger.info(
        'SERVICE.deleteAllScreenshotsForApp 开始 包名=$appPackageName',
      );
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo(
        'SERVICE',
        'deleteAllScreenshotsForApp 开始 包名=' + appPackageName,
      );
      final baseDir = await PathService.getInternalAppDir(null);
      if (baseDir == null) {
        // ignore: unawaited_futures
        FlutterLogger.warn('SERVICE.deleteAllScreenshotsForApp 未获取到 baseDir');
        return false;
      }

      // 删除应用文件夹
      final appDir = Directory(
        p.join(baseDir.path, 'output', 'screen', appPackageName),
      );
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
        print('已删除应用文件夹: ${appDir.path}');
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('FS', '已删除应用目录：' + appDir.path);
      }

      // 清理数据库中的记录
      final deletedCount = await _database.deleteAllScreenshotsForApp(
        appPackageName,
      );
      print('已从数据库删除 $deletedCount 条记录');

      if (deletedCount > 0) {
        // 优先快速刷新缓存，不阻塞UI，然后后台再做可能的全量刷新
        await _refreshStatsCacheQuick();
        _screenshotStreamController.add(null);
        // ignore: unawaited_futures
        _refreshStatsCache(force: true);
      }

      // ignore: unawaited_futures
      FlutterLogger.info(
        'SERVICE.deleteAllScreenshotsForApp 成功 包名=$appPackageName 删除数=$deletedCount',
      );
      return true;
    } catch (e) {
      print('删除应用所有截图失败: $e');
      // ignore: unawaited_futures
      FlutterLogger.error('SERVICE.deleteAllScreenshotsForApp 异常: $e');
      // ignore: unawaited_futures
      FlutterLogger.nativeError('SERVICE', 'deleteAllScreenshotsForApp 异常: $e');
      return false;
    }
  }

  /// 删除截屏记录
  ///
  /// [filePath] 用于删除返回 false 或后续缓存刷新异常时做读回校验：
  /// 只要数据库里已经查不到这张图，就应视为删除成功，避免 UI 误报失败。
  Future<bool> deleteScreenshot(
    int id,
    String packageName, {
    String? filePath,
  }) async {
    try {
      // ignore: unawaited_futures
      FlutterLogger.info('SERVICE.deleteScreenshot 开始 id=$id 包名=$packageName');
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('SERVICE', 'deleteScreenshot 开始 id=$id');
      final bool dbOk = await _database.deleteScreenshot(id, packageName);
      bool ok = dbOk;

      // 某些清理/统计链路可能在记录已删除后仍返回 false。
      // 读回确认记录不存在时，将本次操作修正为成功，避免“刷新后已删除但提示失败”。
      if (!ok) {
        ok = await _isScreenshotGoneAfterDelete(
          id,
          packageName,
          filePath: filePath,
        );
        if (ok) {
          // ignore: unawaited_futures
          FlutterLogger.warn(
            'SERVICE.deleteScreenshot 数据已不存在，修正为成功 id=$id 包名=$packageName',
          );
          // ignore: unawaited_futures
          FlutterLogger.nativeWarn(
            'SERVICE',
            'deleteScreenshot readback missing, treat as success id=$id',
          );
        }
      }

      if (!ok) {
        return false;
      }

      await _notifyScreenshotDataChangedAfterDelete();
      // ignore: unawaited_futures
      FlutterLogger.info('SERVICE.deleteScreenshot 成功 id=$id 包名=$packageName');
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo('SERVICE', 'deleteScreenshot 成功 id=$id');
      return true;
    } catch (e) {
      final bool actuallyGone = await _isScreenshotGoneAfterDelete(
        id,
        packageName,
        filePath: filePath,
      );
      if (actuallyGone) {
        await _notifyScreenshotDataChangedAfterDelete();
        // ignore: unawaited_futures
        FlutterLogger.warn(
          'SERVICE.deleteScreenshot 异常后读回确认已删除，修正为成功 id=$id 包名=$packageName 异常=$e',
        );
        // ignore: unawaited_futures
        FlutterLogger.nativeWarn(
          'SERVICE',
          'deleteScreenshot exception but record missing id=$id',
        );
        return true;
      }
      print('删除截屏记录失败: $e');
      // ignore: unawaited_futures
      FlutterLogger.error('SERVICE.deleteScreenshot 异常: $e');
      // ignore: unawaited_futures
      FlutterLogger.nativeError('SERVICE', 'deleteScreenshot 异常: $e');
      return false;
    }
  }

  Future<bool> _isScreenshotGoneAfterDelete(
    int id,
    String packageName, {
    String? filePath,
  }) async {
    try {
      final String normalizedPath = (filePath ?? '').trim();
      if (normalizedPath.isNotEmpty) {
        final byPath = await _database.getScreenshotByPath(normalizedPath);
        return byPath == null;
      }
      final byId = await _database.getScreenshotById(id, packageName);
      return byId == null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _notifyScreenshotDataChangedAfterDelete() async {
    try {
      invalidateAvailableDayCountCache();
    } catch (e) {
      // ignore: unawaited_futures
      FlutterLogger.warn('SERVICE.deleteScreenshot 失效日期缓存失败: $e');
    }
    try {
      await _refreshStatsCacheQuick();
    } catch (e) {
      // ignore: unawaited_futures
      FlutterLogger.warn('SERVICE.deleteScreenshot 快速刷新统计缓存失败: $e');
    }
    try {
      _screenshotStreamController.add(null);
    } catch (e) {
      // ignore: unawaited_futures
      FlutterLogger.warn('SERVICE.deleteScreenshot 通知截图变更失败: $e');
    }
    // 后台触发可能的全量同步（不等待），不能影响删除结果。
    // ignore: unawaited_futures
    _refreshStatsCache(force: true);
  }

  /// 批量删除截屏记录：避免逐条重算与多次缓存刷新
  Future<int> deleteScreenshotsBatch(String packageName, List<int> ids) async {
    try {
      if (ids.isEmpty) return 0;
      final sw = Stopwatch()..start();
      final deleted = await _database.deleteScreenshotsByIds(packageName, ids);
      sw.stop();
      // ignore: unawaited_futures
      FlutterLogger.info(
        'SERVICE.批量删除完成 包名=$packageName 个数=${ids.length} 耗时=${sw.elapsedMilliseconds}毫秒 实际删除=$deleted',
      );
      if (deleted > 0) {
        // 批量删除后优先进行快速统计缓存刷新并通知，再后台全量刷新
        invalidateAvailableDayCountCache();
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

      final baseDir = await PathService.getInternalAppDir(null);
      if (baseDir == null) return false;
      final appDir = Directory(
        p.join(baseDir.path, 'output', 'screen', packageName),
      );
      if (!await appDir.exists()) {
        // 若文件夹不存在，仅做DB侧删除非保留记录即可
        await _database.deleteAllExcept(packageName, keepIds);
        invalidateAvailableDayCountCache();
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
      final tempDir = Directory(
        p.join(
          appDir.parent.path,
          '${packageName}_keep_tmp_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
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
      invalidateAvailableDayCountCache();
      await _refreshStatsCache(force: true);
      _screenshotStreamController.add(null);
      return true;
    } catch (e) {
      print('fastDeleteKeepOnly 失败: $e');
      return false;
    }
  }

  /// 扫描本地截图目录，将未入库的图片补录到数据库。
  ///
  /// 主要用于“重新统计所有数据”修复：如果截图文件已经落盘，但之前因为
  /// 数据库锁等原因没有写入分库，这里会按文件路径去重后补录。
  Future<int> syncMissingScreenshotsFromFiles({
    bool refreshAfter = true,
    void Function(ScreenshotRecomputeProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    int inserted = 0;
    final Set<String> affectedPackages = <String>{};
    try {
      final Directory? screenRoot = await PathService.getInternalAppDir(
        'output/screen',
      );
      if (screenRoot == null || !await screenRoot.exists()) {
        return 0;
      }

      final List<Directory> appDirs =
          (await screenRoot.list(followLinks: false).toList())
              .whereType<Directory>()
              .toList(growable: false);
      onProgress?.call(
        ScreenshotRecomputeProgress(
          phase: 'scan_files',
          current: 0,
          total: appDirs.length,
        ),
      );
      for (int i = 0; i < appDirs.length; i++) {
        if (_isRecomputeCanceled(shouldCancel)) break;
        final Directory entity = appDirs[i];
        final String packageName = p.basename(entity.path).trim();
        if (packageName.isEmpty) continue;
        onProgress?.call(
          ScreenshotRecomputeProgress(
            phase: 'scan_files',
            current: i,
            total: appDirs.length,
            inserted: inserted,
            packageName: packageName,
          ),
        );
        final int count = await _scanAppDirectory(
          entity,
          packageName,
          packageIndex: i,
          packageTotal: appDirs.length,
          insertedBefore: inserted,
          onProgress: onProgress,
          shouldCancel: shouldCancel,
        );
        if (count > 0) {
          inserted += count;
          affectedPackages.add(packageName);
        }
        if (_isRecomputeCanceled(shouldCancel)) break;
        onProgress?.call(
          ScreenshotRecomputeProgress(
            phase: 'scan_files',
            current: i + 1,
            total: appDirs.length,
            inserted: inserted,
            packageName: packageName,
          ),
        );
      }

      if ((refreshAfter || _isRecomputeCanceled(shouldCancel)) &&
          inserted > 0) {
        for (final String packageName in affectedPackages) {
          await _database.recomputeAppStatsForPackage(packageName);
        }
        await _database.recalculateTotals();
        await _refreshStatsCache(force: true);
        invalidateAvailableDayCountCache();
        await _refreshDayCount();
        _screenshotStreamController.add(null);
      }

      if (inserted > 0) {
        // ignore: unawaited_futures
        FlutterLogger.log('本地截图补录完成：inserted=$inserted');
      }
      return inserted;
    } catch (e) {
      print('本地截图补录失败: $e');
      return inserted;
    }
  }

  /// 递归扫描应用目录（包含年月/日期子目录）
  Future<int> _scanAppDirectory(
    Directory appDir,
    String packageName, {
    int packageIndex = 0,
    int packageTotal = 0,
    int insertedBefore = 0,
    void Function(ScreenshotRecomputeProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    int inserted = 0;
    int processedFiles = 0;

    try {
      await for (final FileSystemEntity entity in appDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (_isRecomputeCanceled(shouldCancel)) break;
        if (entity is! File || !_isSupportedScreenshotFile(entity.path)) {
          continue;
        }
        processedFiles++;
        if (processedFiles == 1 || processedFiles % 25 == 0) {
          onProgress?.call(
            ScreenshotRecomputeProgress(
              phase: 'scan_files',
              current: packageIndex,
              total: packageTotal,
              inserted: insertedBefore + inserted,
              processedFiles: processedFiles,
              packageName: packageName,
            ),
          );
        }
        try {
          final FileStat stat = await entity.stat();
          if (stat.size <= 0) continue;
          final record = ScreenshotRecord(
            appPackageName: packageName,
            appName: packageName, // 无法可靠获取时用包名占位；已有应用名不会被覆盖
            filePath: entity.path, // 数据库存绝对路径
            captureTime:
                _inferCaptureTimeFromPath(entity.path) ?? stat.modified,
            fileSize: stat.size,
          );

          final id = await _database.insertScreenshotIfNotExists(record);
          if (id != null) inserted++;
        } catch (e) {
          print('补录截图文件失败: ${entity.path}, 错误: $e');
        }
      }
    } catch (e) {
      print('扫描应用目录失败: ${appDir.path}, 错误: $e');
    }

    return inserted;
  }

  DateTime? _inferCaptureTimeFromPath(String filePath) {
    try {
      final String day = p.basename(p.dirname(filePath));
      final String yearMonth = p.basename(p.dirname(p.dirname(filePath)));
      final RegExpMatch? ym = RegExp(
        r'^(\d{4})-(\d{2})$',
      ).firstMatch(yearMonth);
      final RegExpMatch? d = RegExp(r'^(\d{1,2})$').firstMatch(day);
      final RegExpMatch? time = RegExp(
        r'^(\d{2})(\d{2})(\d{2})(?:_(\d{1,3}))?',
      ).firstMatch(p.basenameWithoutExtension(filePath));
      if (ym == null || d == null || time == null) return null;
      return DateTime(
        int.parse(ym.group(1)!),
        int.parse(ym.group(2)!),
        int.parse(d.group(1)!),
        int.parse(time.group(1)!),
        int.parse(time.group(2)!),
        int.parse(time.group(3)!),
        int.parse((time.group(4) ?? '0').padRight(3, '0')),
      );
    } catch (_) {
      return null;
    }
  }

  bool _isSupportedScreenshotFile(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
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
        if (ts is int)
          m['lastCaptureTime'] = DateTime.fromMillisecondsSinceEpoch(ts);
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
        final ttl =
            prefs.getInt(_statsCacheTtlSecondsKey) ??
            _statsCacheTtlSecondsDefault;
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
      // 合并写入，减少多次磁盘操作
      final batchTs = DateTime.now().millisecondsSinceEpoch;
      final ser = _serializeStats(stats);
      await prefs.setString(_statsCacheKey, ser);
      await prefs.setInt(_statsCacheTsKey, batchTs);
      if (!prefs.containsKey(_statsCacheTtlSecondsKey)) {
        await prefs.setInt(
          _statsCacheTtlSecondsKey,
          _statsCacheTtlSecondsDefault,
        );
      }
      // ignore: unawaited_futures
      FlutterLogger.log('统计缓存已保存 (ttl=${await _readTtl(prefs)})');
    } catch (_) {}
  }

  Future<int> _readTtl(SharedPreferences prefs) async {
    try {
      return prefs.getInt(_statsCacheTtlSecondsKey) ??
          _statsCacheTtlSecondsDefault;
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
          final perApp = await PerAppScreenshotSettingsService.instance
              .getExpireSettings(pkg);
          final useCustom = await PerAppScreenshotSettingsService.instance
              .getUseCustom(pkg);
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
        } catch (e) {}
      }

      await _refreshStatsCache(force: true);
      try {
        await prefs.setInt(_expireLastTsKey, now);
      } catch (_) {}
      // 通知 UI 刷新
      if (totalDeleted > 0) {
        _screenshotStreamController.add(null);
      }
      FlutterLogger.info(
        'SERVICE.cleanupExpired done: days=' +
            globalDays.toString() +
            ' deleted=' +
            totalDeleted.toString(),
      );
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

  /// 全局列出所有有数据的日期（本地时区），按日期倒序
  Future<List<Map<String, dynamic>>> listAvailableDaysGlobal() async {
    try {
      return await _database.listAvailableDaysGlobal();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 获取全局最新截图时间戳（毫秒）
  Future<int?> getGlobalLatestCaptureTimeMillis() async {
    try {
      return await _database.getGlobalLatestCaptureTimeMillis();
    } catch (_) {
      return null;
    }
  }

  /// 全局列出指定时间范围内所有有数据的日期（本地时区），按日期倒序
  Future<List<Map<String, dynamic>>> listAvailableDaysGlobalRange({
    required int startMillis,
    required int endMillis,
  }) async {
    try {
      return await _database.listAvailableDaysGlobalRange(
        startMillis: startMillis,
        endMillis: endMillis,
      );
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 获取全局可用日期数量（缓存优先，避免频繁全库统计）
  Future<int> getAvailableDayCountCachedFirst({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      return await _refreshDayCount();
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? initializedDbCount = await _database
        .getInitializedDayStatsCount();
    if (initializedDbCount != null) {
      _dayCountMemCache = initializedDbCount;
      _dayCountMemCacheTs = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_dayCountCacheKey, initializedDbCount);
        await prefs.setInt(_dayCountCacheTsKey, now);
      } catch (_) {}
      return initializedDbCount;
    }

    final int ageInMemory = now - _dayCountMemCacheTs;
    if (_dayCountMemCache != null) {
      if (ageInMemory <= _dayCountCacheTtlMillis) {
        return _dayCountMemCache!;
      }
      _refreshDayCountInBackground();
      return _dayCountMemCache!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt(_dayCountCacheKey);
      final ts = prefs.getInt(_dayCountCacheTsKey) ?? 0;
      if (cached != null) {
        _dayCountMemCache = cached;
        _dayCountMemCacheTs = ts;
        if (now - ts > _dayCountCacheTtlMillis) {
          _refreshDayCountInBackground();
        } else {
          _rebuildDayStatsInBackgroundIfNeeded();
        }
        return cached;
      }
    } catch (_) {}

    return await _refreshDayCount();
  }

  /// 清除内存缓存（例如在数据发生较大调整后调用）
  void invalidateAvailableDayCountCache() {
    _dayCountMemCache = null;
    _dayCountMemCacheTs = 0;
    unawaited(_database.invalidateDayStatsCompleteness());
  }

  Future<void> _invalidateAvailableDayCountCacheAsync() async {
    _dayCountMemCache = null;
    _dayCountMemCacheTs = 0;
    await _database.invalidateDayStatsCompleteness();
  }

  Future<int> _refreshDayCount() {
    _dayCountRefreshingFuture ??= _doRefreshDayCount();
    return _dayCountRefreshingFuture!;
  }

  Future<int> _doRefreshDayCount() async {
    try {
      int? count = await _database.getInitializedDayStatsCount();
      count ??= await _database.recalculateDayStats();
      final int now = DateTime.now().millisecondsSinceEpoch;
      _dayCountMemCache = count;
      _dayCountMemCacheTs = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_dayCountCacheKey, count);
        await prefs.setInt(_dayCountCacheTsKey, now);
      } catch (_) {}
      return count;
    } catch (_) {
      return _dayCountMemCache ?? 0;
    } finally {
      _dayCountRefreshingFuture = null;
    }
  }

  void _refreshDayCountInBackground() {
    if (_dayCountRefreshingFuture != null) {
      return;
    }
    // ignore: discarded_futures
    _refreshDayCount();
  }

  void _rebuildDayStatsInBackgroundIfNeeded() {
    // ignore: discarded_futures
    (() async {
      final int? count = await _database.getInitializedDayStatsCount();
      if (count != null) return;
      await _refreshDayCount();
    })();
  }

  /// 指定应用列出所有有数据的日期（本地时区），按日期倒序
  Future<List<Map<String, dynamic>>> listAvailableDaysForApp(
    String appPackageName,
  ) async {
    try {
      return await _database.listAvailableDaysForApp(appPackageName);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}

class CompressionProgress {
  final int total;
  final int handled;
  final int success;
  final int skipped;
  final int failed;
  final int savedBytes;

  const CompressionProgress({
    required this.total,
    required this.handled,
    required this.success,
    required this.skipped,
    required this.failed,
    required this.savedBytes,
  });

  double get ratio => total == 0 ? 0 : handled / total;
}

class CompressionResult extends CompressionProgress {
  final int durationMillis;
  final int totalBeforeBytes;
  final int totalAfterBytes;

  const CompressionResult({
    required super.total,
    required super.handled,
    required super.success,
    required super.skipped,
    required super.failed,
    required super.savedBytes,
    required this.durationMillis,
    required this.totalBeforeBytes,
    required this.totalAfterBytes,
  });

  const CompressionResult.empty()
    : durationMillis = 0,
      totalBeforeBytes = 0,
      totalAfterBytes = 0,
      super(
        total: 0,
        handled: 0,
        success: 0,
        skipped: 0,
        failed: 0,
        savedBytes: 0,
      );
}

class CompressionCancellationToken {
  bool _cancelled = false;
  final List<FutureOr<void> Function()> _cancelHandlers =
      <FutureOr<void> Function()>[];

  bool get isCancelled => _cancelled;

  void addCancelHandler(FutureOr<void> Function() handler) {
    if (_cancelled) {
      _runCancelHandler(handler);
      return;
    }
    _cancelHandlers.add(handler);
  }

  void removeCancelHandler(FutureOr<void> Function() handler) {
    _cancelHandlers.remove(handler);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final handlers = List<FutureOr<void> Function()>.of(_cancelHandlers);
    for (final handler in handlers) {
      _runCancelHandler(handler);
    }
  }

  void _runCancelHandler(FutureOr<void> Function() handler) {
    unawaited(
      Future<void>.sync(handler).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        print('压缩取消回调失败: $error');
      }),
    );
  }
}
