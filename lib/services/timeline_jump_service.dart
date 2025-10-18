import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'navigation_service.dart';
import 'flutter_logger.dart';
import 'app_lifecycle_service.dart';

/// 时间线跳转请求
class TimelineJumpRequest {
  final String filePath;
  final DateTime createdAt;

  const TimelineJumpRequest({required this.filePath, required this.createdAt});
}

/// 提供从任意位置发起“跳转到时间线对应截图”的统一入口
class TimelineJumpService {
  TimelineJumpService._();
  static final TimelineJumpService instance = TimelineJumpService._();

  /// 最近一次跳转请求（ValueNotifier 便于多处监听）
  final ValueNotifier<TimelineJumpRequest?> requestNotifier = ValueNotifier<TimelineJumpRequest?>(null);

  /// 构造时订阅 timelineShown 事件：当时间线页被展示时，如存在待处理请求，则重新广播一次
  static bool _initialized = false;
  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    try {
      AppLifecycleService.instance.events.listen((e) {
        if (e == AppLifecycleEvent.timelineShown) {
          final req = requestNotifier.value;
          if (req != null) {
            try { FlutterLogger.nativeDebug('TimelineJump', 'timelineShown 事件触发，重发跳转请求 path=' + req.filePath); } catch (_) {}
            // 通过赋同值触发监听方刷新处理
            requestNotifier.value = TimelineJumpRequest(filePath: req.filePath, createdAt: DateTime.now());
          }
        }
      });
    } catch (_) {}
  }

  /// 对外：按截图绝对路径发起跳转
  Future<void> jumpToFilePath(String filePath) async {
    try { await FlutterLogger.info('JumpService: jumpToFilePath path=' + filePath); } catch (_) {}
    _ensureInitialized();
    // 尽可能回到根页面，展示底部主导航
    try {
      final nav = NavigationService.instance.navigatorKey.currentState;
      nav?.popUntil((route) => route.isFirst);
    } catch (_) {}

    // 分发跳转请求：MainNavigationPage 将切换到时间线 Tab；TimelinePage 负责滚动与高亮
    requestNotifier.value = TimelineJumpRequest(filePath: filePath, createdAt: DateTime.now());
  }
}


