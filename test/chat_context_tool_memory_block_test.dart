import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/services/chat_context_service.dart';
import 'package:screen_memo/services/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(Directory root) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  final db = await ScreenshotDatabase.instance.database;
  await db.insert('ai_conversations', <String, Object?>{
    'cid': 'ctx-cid',
    'title': 'ctx-test',
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'system context tool memory omits range/paging/result details',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_tool_memory_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);

        await ChatContextService.instance.mergeToolDigests(
          cid: 'ctx-cid',
          signatureDigests: <String, Map<String, dynamic>>{
            'sig-1': <String, dynamic>{
              'tool': 'search_segments',
              'query': '去年',
              'mode': 'list',
              'start_local': '2025-12-24 00:00',
              'end_local': '2025-12-31 23:59',
              'count': 0,
              'paging': <String, dynamic>{
                'prev': <String, dynamic>{
                  'start_local': '2025-12-17 00:00',
                  'end_local': '2025-12-23 23:59',
                },
              },
              'warnings': <String>['clamped to 7 days'],
              'results': <Map<String, dynamic>>[
                <String, dynamic>{'segment_id': 1},
              ],
            },
          },
        );

        final String ctx = await ChatContextService.instance
            .buildSystemContextMessage(cid: 'ctx-cid');

        expect(ctx, contains('历史工具记录'));
        expect(ctx, isNot(contains('start_local')));
        expect(ctx, isNot(contains('end_local')));
        expect(ctx, isNot(contains('paging')));
        expect(ctx, isNot(contains('warnings')));
        expect(ctx, isNot(contains('results')));
        expect(ctx, contains('"query":"去年"'));
        expect(ctx, contains('"count":0'));
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );
}
