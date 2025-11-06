import 'package:flutter/material.dart';
import '../pages/daily_summary_page.dart';
import '../pages/weekly_summary_page.dart';
import '../pages/segment_status_page.dart';
import 'flutter_logger.dart';

/// 全局导航服务：用于无 context 的页面跳转（如通知点击）
/// 通过 MaterialApp.navigatorKey 进行导航
class NavigationService {
  NavigationService._();
  static final NavigationService instance = NavigationService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 打开每日总结页面；dateKey 为空则使用今日
  Future<void> openDailySummary(String? dateKey) async {
    final dk = (dateKey == null || dateKey.trim().isEmpty) ? _todayKey() : dateKey.trim();
    try {
      // 记录到原生日志，便于核查
      await FlutterLogger.nativeInfo('Navigation', 'openDailySummary dateKey=$dk');
    } catch (_) {}
    final nav = navigatorKey.currentState;
    if (nav == null) {
      try { await FlutterLogger.nativeWarn('Navigation', 'navigator not ready, drop openDailySummary dateKey=$dk'); } catch (_) {}
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => DailySummaryPage(dateKey: dk)));
  }

  Future<void> openWeeklySummary(String? weekStartDate) async {
    final String? wk = weekStartDate?.trim().isEmpty == true ? null : weekStartDate?.trim();
    try {
      await FlutterLogger.nativeInfo('Navigation', 'openWeeklySummary weekStart=${wk ?? 'latest'}');
    } catch (_) {}
    final nav = navigatorKey.currentState;
    if (nav == null) {
      try {
        await FlutterLogger.nativeWarn('Navigation', 'navigator not ready, drop openWeeklySummary weekStart=${wk ?? 'latest'}');
      } catch (_) {}
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => WeeklySummaryPage(weekStart: wk)));
  }

  Future<void> openSegmentStatus() async {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      try { await FlutterLogger.nativeWarn('Navigation', 'navigator not ready, drop openSegmentStatus'); } catch (_) {}
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => SegmentStatusPage()));
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${_two(now.month)}-${_two(now.day)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}