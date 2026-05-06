import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('截图入库不会在汇总更新时嵌套开启主库事务', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_insert_screenshot_',
    );
    try {
      await ScreenshotDatabase.instance.initializeForDesktop(tmp.path);

      final File imageFile = File(
        p.join(
          tmp.path,
          'output',
          'screen',
          'pkg.demo',
          '2026-05',
          '06',
          'demo.webp',
        ),
      );
      await imageFile.parent.create(recursive: true);
      await imageFile.writeAsBytes(<int>[1, 2, 3, 4]);

      final ScreenshotRecord record = ScreenshotRecord(
        appPackageName: 'pkg.demo',
        appName: 'Demo',
        filePath: imageFile.path,
        captureTime: DateTime(2026, 5, 6, 18, 38),
        fileSize: 0,
      );

      final int? gid = await ScreenshotDatabase.instance
          .insertScreenshotIfNotExists(record)
          .timeout(const Duration(seconds: 3));

      expect(gid, isNotNull);

      final List<ScreenshotRecord> screenshots = await ScreenshotDatabase
          .instance
          .getScreenshotsByApp('pkg.demo');
      expect(screenshots, hasLength(1));
      expect(screenshots.single.filePath, imageFile.path);
      expect(screenshots.single.fileSize, 4);

      final db = await ScreenshotDatabase.instance.database;
      final List<Map<String, Object?>> totals = await db.query(
        'totals',
        where: 'id = ?',
        whereArgs: <Object>[1],
        limit: 1,
      );
      expect(totals, hasLength(1));
      expect(totals.single['app_count'], 1);
      expect(totals.single['screenshot_count'], 1);
      expect(totals.single['total_size_bytes'], 4);

      final int? duplicated = await ScreenshotDatabase.instance
          .insertScreenshotIfNotExists(record)
          .timeout(const Duration(seconds: 3));
      expect(duplicated, isNull);

      final List<Map<String, Object?>> totalsAfterDuplicate = await db.query(
        'totals',
        where: 'id = ?',
        whereArgs: <Object>[1],
        limit: 1,
      );
      expect(totalsAfterDuplicate.single['screenshot_count'], 1);
    } finally {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });
}
