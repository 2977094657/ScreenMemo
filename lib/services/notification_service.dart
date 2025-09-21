import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

/// 每日提醒通知封装（Android优先）
/// - 默认每天 22:00 触发
/// - 点击通知跳转“每日总结页”，并以当天为统计范围
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _inited = false;

  static const String _channelId = 'daily_summary_channel';
  static const String _channelName = 'Daily Summary';
  static const String _channelDesc = 'Reminds you to check daily summary';

  /// 初始化通知与时区，设置回调
  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_inited) return;
    _navigatorKey = navigatorKey;

    // 时区初始化（设为 Asia/Shanghai；若不可用则回退 UTC）
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initSettings =
        const InitializationSettings(android: androidInit);

    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse resp) {
        _handlePayload(resp.payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Android 渠道
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _inited = true;
  }

  /// 安排每日22:00提醒（可传自定义小时/分钟）
  Future<void> scheduleDailyAt({
    int hour = 22,
    int minute = 0,
    String? payload,
  }) async {
    if (!_inited) return;
    final tz.TZDateTime next =
        _nextInstanceOfTime(hour: hour, minute: minute, from: tz.TZDateTime.now(tz.local));
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        styleInformation: const DefaultStyleInformation(true, true),
      ),
    );
    await _fln.zonedSchedule(
      11001, // 固定ID：每日总结
      'Daily Summary',
      'Tap to view today\'s usage summary',
      next,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // 每日重复
      payload: payload ?? 'daily_summary',
    );
  }

  /// 取消每日提醒
  Future<void> cancelDaily() async {
    if (!_inited) return;
    await _fln.cancel(11001);
  }

  tz.TZDateTime _nextInstanceOfTime({
    required int hour,
    required int minute,
    required tz.TZDateTime from,
  }) {
    tz.TZDateTime scheduled =
        tz.TZDateTime(from.location, from.year, from.month, from.day, hour, minute);
    if (scheduled.isBefore(from)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  void _handlePayload(String? payload) {
    // 点击通知：打开“每日总结”页，并将统计范围设为当天（本地）
    if (_navigatorKey?.currentState == null) return;
    final DateTime now = DateTime.now();
    final int start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final int end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    _navigatorKey!.currentState!.pushNamed(
      '/daily_summary',
      arguments: {
        'dateStartMillis': start,
        'dateEndMillis': end,
      },
    );
  }
}

/// 后台回调（Android）
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // 背景点击暂不处理，由前台 initialize 的回调负责路由
}