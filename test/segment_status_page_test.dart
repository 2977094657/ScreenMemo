import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/features/timeline/presentation/pages/segment_status_page.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const MethodChannel _platformChannel = MethodChannel(
  'com.fqyw.screen_memo/accessibility',
);
Map<String, Object?> _mockDynamicRebuildStatus = <String, Object?>{
  'taskId': '',
  'status': 'idle',
  'startedAt': 0,
  'updatedAt': 0,
  'completedAt': 0,
  'dayConcurrency': 1,
  'totalSegments': 0,
  'processedSegments': 0,
  'failedSegments': 0,
  'totalDays': 0,
  'completedDays': 0,
  'pendingDays': 0,
  'failedDays': 0,
  'currentDayKey': '',
  'timelineCutoffDayKey': '',
  'currentSegmentId': 0,
  'currentRangeLabel': '',
  'currentStage': '',
  'currentStageLabel': '',
  'currentStageDetail': '',
  'lastError': null,
  'isActive': false,
  'progressPercent': '0%',
  'aiModel': '',
  'recentLogs': <String>[],
  'workers': <Object?>[],
};
String? _mockTodayLogsDir;

String _dateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _summaryText(DateTime date) => 'summary ${_dateKey(date)}';

String _tabLabel(DateTime date) => '${date.month}月${date.day}日 1';

Future<void> _prepareDesktopDbRoot(Directory root) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
}

Future<void> _seedTimelineDays(List<DateTime> days) async {
  final db = await ScreenshotDatabase.instance.database;
  final batch = db.batch();
  for (final DateTime day in days) {
    final DateTime start = DateTime(day.year, day.month, day.day, 12);
    final int startMs = start.millisecondsSinceEpoch;
    final int endMs = start
        .add(const Duration(minutes: 30))
        .millisecondsSinceEpoch;
    batch.insert('segments', <String, Object?>{
      'start_time': startMs,
      'end_time': endMs,
      'duration_sec': 30 * 60,
      'sample_interval_sec': 60,
      'status': 'done',
      'segment_kind': 'global',
      'app_packages': 'pkg.test',
    });
  }
  final List<Object?> result = await batch.commit();
  final db2 = await ScreenshotDatabase.instance.database;
  final detailBatch = db2.batch();
  for (int i = 0; i < days.length; i++) {
    final int segmentId = result[i] as int;
    final DateTime start = DateTime(
      days[i].year,
      days[i].month,
      days[i].day,
      12,
    );
    final int startMs = start.millisecondsSinceEpoch;
    detailBatch.insert('segment_samples', <String, Object?>{
      'segment_id': segmentId,
      'capture_time': startMs,
      'file_path': '/tmp/sample_$segmentId.png',
      'app_package_name': 'pkg.test',
      'app_name': 'Pkg Test',
      'position_index': i,
    });
    detailBatch.insert('segment_results', <String, Object?>{
      'segment_id': segmentId,
      'structured_json': jsonEncode(<String, Object?>{
        'overall_summary': _summaryText(days[i]),
      }),
      'output_text': _summaryText(days[i]),
    });
  }
  await detailBatch.commit(noResult: true);
}

Widget _buildHarness() {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const SegmentStatusPage(),
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_platformChannel, (MethodCall call) async {
          switch (call.method) {
            case 'getDynamicRebuildTaskStatus':
              return _mockDynamicRebuildStatus;
            case 'getOutputLogsDirToday':
              return _mockTodayLogsDir;
            case 'triggerSegmentTick':
              return false;
            default:
              return null;
          }
        });
  });

  setUp(() {
    _mockDynamicRebuildStatus = <String, Object?>{
      'taskId': '',
      'status': 'idle',
      'startedAt': 0,
      'updatedAt': 0,
      'completedAt': 0,
      'dayConcurrency': 1,
      'totalSegments': 0,
      'processedSegments': 0,
      'failedSegments': 0,
      'totalDays': 0,
      'completedDays': 0,
      'pendingDays': 0,
      'failedDays': 0,
      'currentDayKey': '',
      'timelineCutoffDayKey': '',
      'currentSegmentId': 0,
      'currentRangeLabel': '',
      'currentStage': '',
      'currentStageLabel': '',
      'currentStageDetail': '',
      'lastError': null,
      'isActive': false,
      'progressPercent': '0%',
      'aiModel': '',
      'recentLogs': <String>[],
      'workers': <Object?>[],
    };
    _mockTodayLogsDir = null;
  });

  tearDown(() async {
    try {
      await ScreenshotDatabase.instance.disposeDesktop();
    } catch (_) {}
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_platformChannel, null);
  });

  testWidgets(
    'auto loads older tabs when current tab reaches the visible tail',
    (WidgetTester tester) async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_segment_page_auto_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        final DateTime latest = DateTime(2024, 4, 10);
        final List<DateTime> days = List<DateTime>.generate(
          33,
          (int index) => latest.subtract(Duration(days: index)),
        );
        await _seedTimelineDays(days);

        await tester.pumpWidget(_buildHarness());
        await _pumpUntilFound(tester, find.text(_summaryText(latest)));

        final DateTime lastVisibleDay = latest.subtract(
          const Duration(days: 29),
        );
        await tester.ensureVisible(find.text(_tabLabel(lastVisibleDay)));
        await tester.tap(find.text(_tabLabel(lastVisibleDay)));
        await tester.pump();

        final DateTime autoLoadedDay = latest.subtract(
          const Duration(days: 32),
        );
        await _pumpUntilFound(tester, find.text(_tabLabel(autoLoadedDay)));
        expect(find.text(_tabLabel(autoLoadedDay)), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  testWidgets('refresh keeps the currently selected older tab', (
    WidgetTester tester,
  ) async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_segment_page_refresh_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root);
      final DateTime latest = DateTime(2024, 4, 10);
      final List<DateTime> days = List<DateTime>.generate(
        33,
        (int index) => latest.subtract(Duration(days: index)),
      );
      await _seedTimelineDays(days);

      await tester.pumpWidget(_buildHarness());
      await _pumpUntilFound(tester, find.text(_summaryText(latest)));

      final DateTime lastVisibleDay = latest.subtract(const Duration(days: 29));
      await tester.ensureVisible(find.text(_tabLabel(lastVisibleDay)));
      await tester.tap(find.text(_tabLabel(lastVisibleDay)));
      await tester.pump();

      final DateTime olderSelectedDay = latest.subtract(
        const Duration(days: 32),
      );
      await _pumpUntilFound(tester, find.text(_tabLabel(olderSelectedDay)));
      await tester.ensureVisible(find.text(_tabLabel(olderSelectedDay)));
      await tester.tap(find.text(_tabLabel(olderSelectedDay)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(_summaryText(olderSelectedDay)), findsWidgets);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await _pumpUntilFound(tester, find.text(_summaryText(olderSelectedDay)));
      expect(find.text(_summaryText(olderSelectedDay)), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  testWidgets('paused rebuild hides newer unreconstructed tabs', (
    WidgetTester tester,
  ) async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_segment_page_cutoff_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root);
      final DateTime latest = DateTime(2024, 4, 10);
      final List<DateTime> days = List<DateTime>.generate(
        6,
        (int index) => latest.subtract(Duration(days: index)),
      );
      await _seedTimelineDays(days);
      final DateTime cutoffDay = latest.subtract(const Duration(days: 2));
      _mockDynamicRebuildStatus = <String, Object?>{
        'taskId': 'dynamic_rebuild_test',
        'status': 'cancelled',
        'startedAt': DateTime(2024, 4, 8, 9).millisecondsSinceEpoch,
        'updatedAt': DateTime(2024, 4, 8, 9, 30).millisecondsSinceEpoch,
        'completedAt': DateTime(2024, 4, 8, 9, 31).millisecondsSinceEpoch,
        'dayConcurrency': 1,
        'totalSegments': 6,
        'processedSegments': 2,
        'failedSegments': 0,
        'totalDays': 6,
        'completedDays': 2,
        'pendingDays': 4,
        'failedDays': 0,
        'currentDayKey': _dateKey(cutoffDay),
        'timelineCutoffDayKey': _dateKey(cutoffDay),
        'currentSegmentId': 0,
        'currentRangeLabel': '12:00:00-12:30:00',
        'currentStage': 'cancelled',
        'currentStageLabel': '已停止',
        'currentStageDetail': '已停止后台重建，当前进度可稍后继续',
        'lastError': null,
        'isActive': false,
        'progressPercent': '33.3%',
        'aiModel': 'gemini-2.0-flash',
        'recentLogs': <String>['09:30:00 已停止：已停止后台重建，当前进度可稍后继续'],
        'workers': <Object?>[],
      };

      await tester.pumpWidget(_buildHarness());
      await _pumpUntilFound(tester, find.text(_summaryText(cutoffDay)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_tabLabel(cutoffDay)), findsWidgets);
      expect(find.text(_tabLabel(latest)), findsNothing);
      expect(find.text(_summaryText(latest)), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  testWidgets('dynamic rebuild sheet shows native request logs', (
    WidgetTester tester,
  ) async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_segment_page_logs_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      final Directory logsDir = Directory(
        p.join(tmp.path, 'output', 'logs', '2026', '03', '12'),
      );
      await root.create(recursive: true);
      await logsDir.create(recursive: true);
      await _prepareDesktopDbRoot(root);
      await _seedTimelineDays(<DateTime>[DateTime(2024, 4, 10)]);
      final File infoLog = File(p.join(logsDir.path, '12_info.log'));
      await infoLog.writeAsString('''
2026-03-12 09:00:00.000 [INFO] SegmentSummaryManager: AIREQ PROMPT_BEGIN id=seg101
2026-03-12 09:00:00.001 [INFO] SegmentSummaryManager: AI 提示词完整内容开始 >>>
2026-03-12 09:00:00.002 [INFO] SegmentSummaryManager: prompt 101
2026-03-12 09:00:00.003 [INFO] SegmentSummaryManager: AI 提示词完整内容结束 <<<
2026-03-12 09:00:00.004 [INFO] SegmentSummaryManager: AIREQ PROMPT_END id=seg101
2026-03-12 09:00:00.005 [INFO] SegmentSummaryManager: AIREQ START id=seg101 provider=google segment_id=101 is_merge=false url=https://api.example.com/v1beta/models/gemini:streamGenerateContent?alt=sse model=gemini-2.0 images_attached=2 images_total=2 prompt_len=100
2026-03-12 09:00:01.000 [INFO] SegmentSummaryManager: AIREQ RESP id=seg101 code=200 took_ms=995 attempt=1/3
2026-03-12 09:00:01.001 [INFO] SegmentSummaryManager: AIREQ DONE id=seg101 content_len=10 response_len=20
2026-03-12 09:05:00.000 [INFO] SegmentSummaryManager: AIREQ START id=seg102 provider=openai-compat segment_id=102 is_merge=false url=https://relay.example.com/v1/chat/completions model=gpt-4.1 images_attached=3 images_total=3 prompt_len=120
2026-03-12 09:05:01.000 [INFO] SegmentSummaryManager: AIREQ RESP id=seg102 code=200 took_ms=1000 attempt=1/3
2026-03-12 09:05:01.001 [INFO] SegmentSummaryManager: AIREQ DONE id=seg102 content_len=12 response_len=24
''');
      _mockTodayLogsDir = logsDir.path;
      _mockDynamicRebuildStatus = <String, Object?>{
        'taskId': 'dynamic_rebuild_1710205200000',
        'status': 'running',
        'startedAt': DateTime(2026, 3, 12, 9).millisecondsSinceEpoch,
        'updatedAt': DateTime(2026, 3, 12, 9, 5, 1).millisecondsSinceEpoch,
        'completedAt': 0,
        'dayConcurrency': 1,
        'totalSegments': 2,
        'processedSegments': 1,
        'failedSegments': 0,
        'totalDays': 1,
        'completedDays': 0,
        'pendingDays': 1,
        'failedDays': 0,
        'currentDayKey': '2026-03-12',
        'timelineCutoffDayKey': '2026-03-12',
        'currentSegmentId': 102,
        'currentRangeLabel': '09:05-09:35',
        'currentStage': 'summary_wait_ai',
        'currentStageLabel': '等待 AI 总结',
        'currentStageDetail': '已准备请求模型，总图片 3 张',
        'lastError': null,
        'isActive': true,
        'progressPercent': '50%',
        'aiModel': 'gpt-4.1',
        'recentLogs': <String>[
          '09:05:00 开始重建当前动态：第 2/2 条 · 2026-03-12 09:05-09:35',
          '09:05:00 构建总结提示词：为段落 #102 组织 3 张样本图片',
          '09:05:01 等待 AI 总结：已准备请求模型，总图片 3 张',
        ],
        'workers': <Object?>[
          <String, Object?>{
            'slotId': 1,
            'status': 'running',
            'dayKey': '2026-03-12',
            'totalSegments': 2,
            'processedSegments': 1,
            'currentRangeLabel': '09:05-09:35',
            'currentStageLabel': '等待 AI 总结',
            'currentStageDetail': '已准备请求模型，总图片 3 张',
            'currentSegmentId': 102,
            'retryCount': 0,
            'retryLimit': 3,
          },
        ],
      };

      await tester.pumpWidget(_buildHarness());
      await _pumpUntilFound(
        tester,
        find.text(_summaryText(DateTime(2024, 4, 10))),
      );

      await tester.tap(find.byTooltip('重建动态'));
      await tester.pumpAndSettle();

      expect(find.text('当前模型：gpt-4.1'), findsOneWidget);
      expect(find.text('重建请求'), findsOneWidget);
      expect(find.textContaining('AIRequestGateway'), findsOneWidget);
      expect(find.textContaining('segment=102'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  testWidgets(
    'dynamic rebuild sheet shows concurrency controls and worker cards',
    (WidgetTester tester) async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_segment_page_concurrency_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        await _seedTimelineDays(<DateTime>[DateTime(2024, 4, 10)]);
        _mockDynamicRebuildStatus = <String, Object?>{
          'taskId': 'dynamic_rebuild_parallel',
          'status': 'running',
          'startedAt': DateTime(2026, 3, 12, 9).millisecondsSinceEpoch,
          'updatedAt': DateTime(2026, 3, 12, 9, 6).millisecondsSinceEpoch,
          'completedAt': 0,
          'dayConcurrency': 3,
          'totalSegments': 7,
          'processedSegments': 3,
          'failedSegments': 0,
          'totalDays': 4,
          'completedDays': 1,
          'pendingDays': 3,
          'failedDays': 1,
          'currentDayKey': '2026-03-12',
          'timelineCutoffDayKey': '2026-03-12',
          'currentSegmentId': 302,
          'currentRangeLabel': '09:30:00-10:00:00',
          'currentStage': 'summary_wait_ai',
          'currentStageLabel': '等待 AI 总结',
          'currentStageDetail': '线程正在并发处理缺失日期',
          'lastError': null,
          'isActive': true,
          'progressPercent': '42.9%',
          'aiModel': 'gpt-4.1',
          'recentLogs': <String>[
            '09:05:00 [T1][2026-03-12] 领取日期任务：准备处理 2026-03-12 的 3 条动态',
            '09:05:01 [T2][2026-03-10] 领取日期任务：准备处理 2026-03-10 的 2 条动态',
          ],
          'workers': <Object?>[
            <String, Object?>{
              'slotId': 1,
              'status': 'running',
              'dayKey': '2026-03-12',
              'totalSegments': 3,
              'processedSegments': 1,
              'currentRangeLabel': '09:30:00-10:00:00',
              'currentStageLabel': '等待 AI 总结',
              'currentStageDetail': '线程 1 正在处理 2026-03-12',
              'currentSegmentId': 302,
              'retryCount': 0,
              'retryLimit': 3,
              'recentStreamChunks': <String>[
                '最旧流式预览',
                '第一条流式预览',
                '第二条流式预览',
                '第三条流式预览',
              ],
            },
            <String, Object?>{
              'slotId': 2,
              'status': 'retrying',
              'dayKey': '2026-03-10',
              'totalSegments': 2,
              'processedSegments': 1,
              'currentRangeLabel': '14:00:00-14:30:00',
              'currentStageLabel': '恢复失败日期',
              'currentStageDetail': '准备从失败位置继续第 1/3 次续跑',
              'currentSegmentId': 401,
              'retryCount': 1,
              'retryLimit': 3,
              'recentStreamChunks': <String>[],
            },
            <String, Object?>{
              'slotId': 3,
              'status': 'idle',
              'dayKey': '',
              'totalSegments': 0,
              'processedSegments': 0,
              'currentRangeLabel': '',
              'currentStageLabel': '',
              'currentStageDetail': '',
              'currentSegmentId': 0,
              'retryCount': 0,
              'retryLimit': 3,
              'recentStreamChunks': <String>[],
            },
          ],
        };

        await tester.pumpWidget(_buildHarness());
        await _pumpUntilFound(
          tester,
          find.text(_summaryText(DateTime(2024, 4, 10))),
        );

        await tester.tap(find.byTooltip('重建动态'));
        await tester.pumpAndSettle();

        expect(find.text('并发天数'), findsOneWidget);
        expect(find.text('线程 1'), findsOneWidget);
        expect(find.text('线程 2'), findsOneWidget);
        expect(find.text('线程 3'), findsOneWidget);
        expect(find.text('重试 1/3'), findsOneWidget);
        expect(find.textContaining('并发 3'), findsOneWidget);
        expect(find.textContaining('待续失败天数 1'), findsOneWidget);
        expect(find.text('最近 3 条流式数据'), findsOneWidget);
        expect(find.textContaining('1. 第一条流式预览'), findsOneWidget);
        expect(find.textContaining('2. 第二条流式预览'), findsOneWidget);
        expect(find.textContaining('3. 第三条流式预览'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );
}
