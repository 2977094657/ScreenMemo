import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(Directory root) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
}

Future<void> _disposeAndDeleteTemp(Directory tmp) async {
  try {
    await ScreenshotDatabase.instance.disposeDesktop();
  } catch (_) {}
  if (await tmp.exists()) {
    await tmp.delete(recursive: true);
  }
}

String _dateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

Future<void> _seedTimelineDays(List<DateTime> days) async {
  final db = await ScreenshotDatabase.instance.database;
  final batch = db.batch();
  int position = 0;
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
  final Database db2 = await ScreenshotDatabase.instance.database;
  final Batch detailBatch = db2.batch();
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
      'position_index': position++,
    });
    detailBatch.insert('segment_results', <String, Object?>{
      'segment_id': segmentId,
      'structured_json': jsonEncode(<String, Object?>{
        'overall_summary': 'summary ${_dateKey(days[i])}',
      }),
      'output_text': 'summary ${_dateKey(days[i])}',
    });
  }
  await detailBatch.commit(noResult: true);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    try {
      await ScreenshotDatabase.instance.disposeDesktop();
    } catch (_) {}
  });

  test(
    'timeline batch counts distinct populated days instead of natural 30-day range',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_timeline_sparse_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        final List<DateTime> days = <DateTime>[
          DateTime(2026, 3, 1),
          DateTime(2026, 2, 1),
          DateTime(2025, 1, 1),
        ];
        await _seedTimelineDays(days);

        final SegmentTimelineBatch batch = await ScreenshotDatabase.instance
            .listSegmentTimelineBatch(distinctDayCount: 30);

        expect(batch.dayKeys, <String>[
          '2026-03-01',
          '2026-02-01',
          '2025-01-01',
        ]);
        expect(batch.segments.length, 3);
        expect(batch.hasMoreOlder, isFalse);
      } finally {
        await _disposeAndDeleteTemp(tmp);
      }
    },
  );

  test(
    'timeline batch paginates by distinct day count and keeps ordering stable',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_timeline_paging_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        final DateTime latest = DateTime(2024, 4, 10);
        final List<DateTime> days = List<DateTime>.generate(
          45,
          (int index) => latest.subtract(Duration(days: index)),
        );
        await _seedTimelineDays(days);

        final SegmentTimelineBatch first = await ScreenshotDatabase.instance
            .listSegmentTimelineBatch(distinctDayCount: 30);
        final SegmentTimelineBatch second = await ScreenshotDatabase.instance
            .listSegmentTimelineBatch(
              distinctDayCount: 30,
              beforeDateKey: first.dayKeys.last,
            );

        expect(first.dayKeys.length, 30);
        expect(first.dayKeys.first, '2024-04-10');
        expect(first.dayKeys.last, '2024-03-12');
        expect(first.hasMoreOlder, isTrue);
        expect(second.dayKeys.length, 15);
        expect(second.dayKeys.first, '2024-03-11');
        expect(second.dayKeys.last, '2024-02-26');
        expect(second.hasMoreOlder, isFalse);
      } finally {
        await _disposeAndDeleteTemp(tmp);
      }
    },
  );

  test(
    'timeline batch expands refresh window to include pinned older day',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_timeline_pinned_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        final DateTime latest = DateTime(2024, 4, 10);
        final List<DateTime> days = List<DateTime>.generate(
          40,
          (int index) => latest.subtract(Duration(days: index)),
        );
        await _seedTimelineDays(days);

        final SegmentTimelineBatch batch = await ScreenshotDatabase.instance
            .listSegmentTimelineBatch(
              distinctDayCount: 30,
              pinnedDateKey: '2024-03-07',
            );

        expect(batch.dayKeys.length, 35);
        expect(batch.dayKeys.first, '2024-04-10');
        expect(batch.dayKeys.last, '2024-03-07');
        expect(batch.dayKeys.contains('2024-03-07'), isTrue);
        expect(batch.hasMoreOlder, isTrue);
      } finally {
        await _disposeAndDeleteTemp(tmp);
      }
    },
  );

  test(
    'timeline day batch centers pinned date with 14 newer and 15 older tabs',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_timeline_pinned_centered_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        final DateTime latest = DateTime(2024, 4, 30);
        final List<DateTime> days = List<DateTime>.generate(
          60,
          (int index) => latest.subtract(Duration(days: index)),
        );
        await _seedTimelineDays(days);

        final SegmentTimelineDayBatch batch = await ScreenshotDatabase.instance
            .listSegmentTimelineDayBatch(
              distinctDayCount: 30,
              pinnedDateKey: '2024-04-01',
            );

        expect(batch.dayKeys.length, 30);
        expect(batch.dayKeys.first, '2024-04-15');
        expect(batch.dayKeys[14], '2024-04-01');
        expect(batch.dayKeys.last, '2024-03-17');
        expect(batch.hasMoreOlder, isTrue);
      } finally {
        await _disposeAndDeleteTemp(tmp);
      }
    },
  );

  test('timeline month day counts only scan the requested month', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_timeline_month_counts_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root);
      await _seedTimelineDays(<DateTime>[
        DateTime(2024, 3, 10),
        DateTime(2024, 3, 10),
        DateTime(2024, 3, 1),
        DateTime(2024, 4, 1),
      ]);

      final List<SegmentTimelineDayInfo> days = await ScreenshotDatabase
          .instance
          .listSegmentTimelineMonthDayCounts(year: 2024, month: 3);
      final Map<String, int> counts = <String, int>{
        for (final SegmentTimelineDayInfo day in days) day.dayKey: day.count,
      };

      expect(counts['2024-03-10'], 2);
      expect(counts['2024-03-01'], 1);
      expect(counts.containsKey('2024-04-01'), isFalse);
    } finally {
      await _disposeAndDeleteTemp(tmp);
    }
  });

  test('timeline year list only returns years with dynamic entries', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_timeline_years_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root);
      await _seedTimelineDays(<DateTime>[
        DateTime(2022, 12, 31),
        DateTime(2024, 1, 1),
        DateTime(2024, 6, 8),
      ]);

      final List<int> years = await ScreenshotDatabase.instance
          .listSegmentTimelineYears();
      final List<int> cutoffYears = await ScreenshotDatabase.instance
          .listSegmentTimelineYears(maxDateKeyInclusive: '2023-12-31');

      expect(years, <int>[2024, 2022]);
      expect(cutoffYears, <int>[2022]);
    } finally {
      await _disposeAndDeleteTemp(tmp);
    }
  });

  test(
    'timeline day segments survive huge segment merge fields and expose summary preview',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_timeline_huge_segment_fields_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        final Database db = await ScreenshotDatabase.instance.database;
        final DateTime day = DateTime(2026, 6, 29, 12);
        final int startMs = day.millisecondsSinceEpoch;
        final int endMs = day
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch;
        final int segmentId = await db.insert('segments', <String, Object?>{
          'start_time': startMs,
          'end_time': endMs,
          'duration_sec': 300,
          'sample_interval_sec': 60,
          'status': 'completed',
          'segment_kind': 'global',
          'app_packages': 'pkg.test',
          'merge_attempted': 1,
          'merged_flag': 1,
          'merge_decision_json': 'x' * (1024 * 1024),
          'merge_decision_reason': 'reason' * 1000,
        });
        await db.insert('segment_samples', <String, Object?>{
          'segment_id': segmentId,
          'capture_time': startMs,
          'file_path': '/tmp/sample_$segmentId.png',
          'app_package_name': 'pkg.test',
          'app_name': 'Pkg Test',
          'position_index': 0,
        });
        await db.insert('segment_results', <String, Object?>{
          'segment_id': segmentId,
          'structured_json': jsonEncode(<String, Object?>{
            'apps': <String>['Pkg Test'],
            'overall_summary': 'short summary from overall_summary',
            'timeline': <Object?>[],
          }),
          'output_text': 'short summary from overall_summary',
        });

        final List<Map<String, dynamic>> rows = await ScreenshotDatabase
            .instance
            .listSegmentTimelineDaySegments(
              dateKey: '2026-06-29',
              truncateResultColumns: true,
            );

        expect(rows, hasLength(1));
        expect(rows.single['id'], segmentId);
        expect(
          rows.single['overall_summary_preview'] as String,
          contains('short summary from overall_summary'),
        );
        expect((rows.single['merge_decision_json'] as String).length, 4096);
      } finally {
        await _disposeAndDeleteTemp(tmp);
      }
    },
  );
}
