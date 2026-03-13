import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/pages/segment_status_page.dart';
import 'package:screen_memo/services/screenshot_database.dart';
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
  'totalSegments': 0,
  'processedSegments': 0,
  'failedSegments': 0,
  'currentDayKey': '',
  'currentSegmentId': 0,
  'currentRangeLabel': '',
  'lastError': null,
  'isActive': false,
  'progressPercent': '0%',
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
      'totalSegments': 0,
      'processedSegments': 0,
      'failedSegments': 0,
      'currentDayKey': '',
      'currentSegmentId': 0,
      'currentRangeLabel': '',
      'lastError': null,
      'isActive': false,
      'progressPercent': '0%',
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
        'totalSegments': 2,
        'processedSegments': 1,
        'failedSegments': 0,
        'currentDayKey': '2026-03-12',
        'currentSegmentId': 102,
        'currentRangeLabel': '09:05-09:35',
        'lastError': null,
        'isActive': true,
        'progressPercent': '50%',
      };

      await tester.pumpWidget(_buildHarness());
      await _pumpUntilFound(
        tester,
        find.text(_summaryText(DateTime(2024, 4, 10))),
      );

      await tester.tap(find.byTooltip('重建动态'));
      await tester.pumpAndSettle();

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
}
