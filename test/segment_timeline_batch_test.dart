import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/services/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(Directory root) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
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
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
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
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
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
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );
}
