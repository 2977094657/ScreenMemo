import 'dart:math';

import '../models/screenshot_record.dart';
import 'screenshot_service.dart';

/// 每日总结结果（基于“时间线同一应用连续段落：结束-开始”算法）
class DailySummaryResult {
  final int startMillis;
  final int endMillis;

  /// 总使用时长（所有段落求和）
  final int totalDurationMs;

  /// 应用用时（key=packageName, value=毫秒）
  final Map<String, AppUsage> appUsages;

  /// 按小时的堆叠分布：hour(0-23) -> package -> 毫秒
  final Map<int, Map<String, int>> hourAppDurationsMs;

  /// 连续段列表（用于“最长专注段”等）
  final List<BlockUsage> blocks;

  /// 应用切换次数（段落数-1）
  final int switchCount;

  /// 当天最早/最晚活跃时间（基于截图）
  final DateTime? firstActive;
  final DateTime? lastActive;

  /// 深夜使用（23:00~23:59:59），单位：毫秒
  final int deepNightDurationMs;

  DailySummaryResult({
    required this.startMillis,
    required this.endMillis,
    required this.totalDurationMs,
    required this.appUsages,
    required this.hourAppDurationsMs,
    required this.blocks,
    required this.switchCount,
    required this.firstActive,
    required this.lastActive,
    required this.deepNightDurationMs,
  });

  List<AppUsage> topApps({int topN = 5}) {
    final list = appUsages.values.toList()
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
    if (list.length <= topN) return list;
    return list.sublist(0, topN);
  }

  BlockUsage? longestBlock() {
    if (blocks.isEmpty) return null;
    return blocks.reduce((a, b) =>
        (a.durationMs >= b.durationMs) ? a : b);
  }
}

/// 应用用时实体
class AppUsage {
  final String packageName;
  final String appName;
  final int durationMs;

  const AppUsage({
    required this.packageName,
    required this.appName,
    required this.durationMs,
  });

  AppUsage copyAdd(int deltaMs) => AppUsage(
        packageName: packageName,
        appName: appName,
        durationMs: durationMs + deltaMs,
      );
}

/// 连续段（同一应用的连续时间块）
class BlockUsage {
  final String packageName;
  final String appName;
  final int startMs;
  final int endMs;

  BlockUsage({
    required this.packageName,
    required this.appName,
    required this.startMs,
    required this.endMs,
  });

  int get durationMs => max(0, endMs - startMs);
}

class DailySummaryService {
  DailySummaryService._();
  static final DailySummaryService instance = DailySummaryService._();

  /// 计算给定日期范围内（含边界）的每日总结。
  /// 算法：
  /// - 按时间升序遍历全局截图；
  /// - 将“同一应用的连续段”划为一个 Block；
  /// - 段落开始=本段第一张截图时间，结束=本段最后一张截图时间（严格“结束-开始”），并裁剪到统计窗口；
  /// - 应用用时=各自段落时长累加；小时分布按段落时间切分累计。
  Future<DailySummaryResult> compute({
    required int startMillis,
    required int endMillis,
  }) async {
    if (endMillis <= startMillis) {
      return DailySummaryResult(
        startMillis: startMillis,
        endMillis: endMillis,
        totalDurationMs: 0,
        appUsages: <String, AppUsage>{},
        hourAppDurationsMs: <int, Map<String, int>>{},
        blocks: const <BlockUsage>[],
        switchCount: 0,
        firstActive: null,
        lastActive: null,
        deepNightDurationMs: 0,
      );
    }

    // 读取当天所有截图（按时间倒序返回，需升序用于切分）
    final List<ScreenshotRecord> shots =
        await ScreenshotService.instance.getGlobalScreenshotsBetween(
      startMillis: startMillis,
      endMillis: endMillis,
    );
    if (shots.isEmpty) {
      return DailySummaryResult(
        startMillis: startMillis,
        endMillis: endMillis,
        totalDurationMs: 0,
        appUsages: <String, AppUsage>{},
        hourAppDurationsMs: _initHourBuckets(),
        blocks: const <BlockUsage>[],
        switchCount: 0,
        firstActive: null,
        lastActive: null,
        deepNightDurationMs: 0,
      );
    }

    // 升序
    shots.sort(
        (a, b) => a.captureTime.millisecondsSinceEpoch.compareTo(b.captureTime.millisecondsSinceEpoch));

    final Map<String, String> appNameByPkg = <String, String>{};
    for (final s in shots) {
      appNameByPkg.putIfAbsent(s.appPackageName, () => s.appName);
    }

    final List<BlockUsage> blocks = <BlockUsage>[];
    int i = 0;
    while (i < shots.length) {
      final ScreenshotRecord first = shots[i];
      final String pkg = first.appPackageName;
      final String name = appNameByPkg[pkg] ?? pkg;

      // 找到同一应用的连续区间 [i, j-1]
      int j = i + 1;
      while (j < shots.length && shots[j].appPackageName == pkg) {
        j++;
      }

      // 段开始=本段第一张截图时间；段结束=本段最后一张截图时间（严格“结束-开始”）
      final int rawStart = first.captureTime.millisecondsSinceEpoch;
      final int rawEnd = shots[j - 1].captureTime.millisecondsSinceEpoch;

      final int blockStart = max(rawStart, startMillis);
      final int blockEnd = min(rawEnd, endMillis);

      if (blockEnd > blockStart) {
        blocks.add(BlockUsage(
          packageName: pkg,
          appName: name,
          startMs: blockStart,
          endMs: blockEnd,
        ));
      }

      // 下一段
      i = j;
    }

    // 汇总
    final Map<String, AppUsage> appUsages = <String, AppUsage>{};
    final Map<int, Map<String, int>> hourStacks = _initHourBuckets();
    int total = 0;
    int deepNightMs = 0;

    final DateTime startDt = DateTime.fromMillisecondsSinceEpoch(startMillis);
    final DateTime deepStart = DateTime(startDt.year, startDt.month, startDt.day, 23, 0, 0);
    final int deepStartMs = deepStart.millisecondsSinceEpoch;
    final int deepEndMs = min(endMillis, DateTime(startDt.year, startDt.month, startDt.day, 23, 59, 59, 999).millisecondsSinceEpoch);

    for (final b in blocks) {
      final int dur = b.durationMs;
      if (dur <= 0) continue;
      total += dur;

      // 应用累计
      final prev = appUsages[b.packageName];
      if (prev == null) {
        appUsages[b.packageName] = AppUsage(packageName: b.packageName, appName: b.appName, durationMs: dur);
      } else {
        appUsages[b.packageName] = prev.copyAdd(dur);
      }

      // 深夜(当天23:00~23:59:59)重叠
      deepNightMs += _overlapMs(b.startMs, b.endMs, deepStartMs, deepEndMs);

      // 按小时堆叠
      _accumulateToHours(hourStacks, b.packageName, b.startMs, b.endMs);
    }

    final firstActive = shots.first.captureTime;
    final lastActive = shots.last.captureTime;

    return DailySummaryResult(
      startMillis: startMillis,
      endMillis: endMillis,
      totalDurationMs: total,
      appUsages: appUsages,
      hourAppDurationsMs: hourStacks,
      blocks: blocks,
      switchCount: blocks.isEmpty ? 0 : (blocks.length - 1),
      firstActive: firstActive,
      lastActive: lastActive,
      deepNightDurationMs: deepNightMs,
    );
  }

  static Map<int, Map<String, int>> _initHourBuckets() {
    final Map<int, Map<String, int>> m = <int, Map<String, int>>{};
    for (int h = 0; h < 24; h++) {
      m[h] = <String, int>{};
    }
    return m;
  }

  static void _accumulateToHours(
    Map<int, Map<String, int>> hourStacks,
    String pkg,
    int startMs,
    int endMs,
  ) {
    if (endMs <= startMs) return;
    DateTime cur = DateTime.fromMillisecondsSinceEpoch(startMs);
    DateTime end = DateTime.fromMillisecondsSinceEpoch(endMs);

    while (cur.isBefore(end)) {
      final DateTime hourEnd = DateTime(cur.year, cur.month, cur.day, cur.hour, 59, 59, 999);
      final DateTime sliceEnd = hourEnd.isBefore(end) ? hourEnd : end;

      final int delta = sliceEnd.millisecondsSinceEpoch - cur.millisecondsSinceEpoch;
      if (delta > 0) {
        final Map<String, int> stack = hourStacks[cur.hour] ?? <String, int>{};
        final int prev = stack[pkg] ?? 0;
        stack[pkg] = prev + delta;
        hourStacks[cur.hour] = stack;
      }

      // 下一小时起点
      cur = DateTime(cur.year, cur.month, cur.day, cur.hour + 1, 0, 0, 0);
    }
  }

  static int _overlapMs(int aStart, int aEnd, int bStart, int bEnd) {
    if (aEnd <= aStart || bEnd <= bStart) return 0;
    final int s = max(aStart, bStart);
    final int e = min(aEnd, bEnd);
    return max(0, e - s);
  }

  /// 工具：将毫秒格式化为 "xh ym"
  static String formatHm(int ms) {
    final int totalMin = (ms / 60000).floor();
    final int h = totalMin ~/ 60;
    final int m = totalMin % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}