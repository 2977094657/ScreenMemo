import 'dart:async';
import 'flutter_logger.dart';

/// 应用生命周期事件
enum AppLifecycleEvent { resumed, firstUiResumed, timelineShown }

/// 简单的应用生命周期事件服务（单例，广播流）
class AppLifecycleService {
  AppLifecycleService._internal();
  static final AppLifecycleService instance = AppLifecycleService._internal();

  final StreamController<AppLifecycleEvent> _controller =
      StreamController<AppLifecycleEvent>.broadcast();

  /// 是否已发出“首次UI进入”事件（用于补偿刷新）
  bool firstUiResumedEmitted = false;

  /// 订阅事件流
  Stream<AppLifecycleEvent> get events => _controller.stream;

  /// 发送 resumed（应用回到前台）
  void emitResumed() {
    _log('emitResumed');
    _safeAdd(AppLifecycleEvent.resumed);
  }

  /// 发送 firstUiResumed（冷启动或首次进入UI，仅一次）
  void emitFirstUiResumed() {
    if (firstUiResumedEmitted) {
      _log('emitFirstUiResumed skipped (already emitted)');
      return;
    }
    firstUiResumedEmitted = true;
    _log('emitFirstUiResumed');
    _safeAdd(AppLifecycleEvent.firstUiResumed);
  }

  /// 发送 timelineShown（时间线页被展示）
  void emitTimelineShown() {
    _log('emitTimelineShown');
    _safeAdd(AppLifecycleEvent.timelineShown);
  }

  void _safeAdd(AppLifecycleEvent e) {
    try {
      if (!_controller.isClosed) _controller.add(e);
    } catch (_) {}
  }

  void dispose() {
    try {
      if (!_controller.isClosed) _controller.close();
    } catch (_) {}
  }

  void _log(String msg) {
    // 使用原生日志以便统一收集
    // ignore: discarded_futures
    FlutterLogger.nativeDebug('AppLifecycle', msg);
  }
}