import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _deleteTempDir(Directory dir) async {
  for (int attempt = 0; attempt < 5; attempt++) {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    } on PathAccessException {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
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

  test('对话列表查询不会返回上下文大字段', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_ai_conversation_list_',
    );
    try {
      await ScreenshotDatabase.instance.initializeForDesktop(tmp.path);
      final db = await ScreenshotDatabase.instance.database;
      final String largeText = List<String>.filled(64 * 1024, 'x').join();
      final int now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < 4; i++) {
        await db.insert('ai_conversations', <String, Object?>{
          'cid': 'cid-$i',
          'title': 'conversation-$i',
          'provider_id': i + 1,
          'model': 'model-$i',
          'summary': largeText,
          'tool_memory_json': '{"memory":"$largeText"}',
          'last_prompt_breakdown_json': '{"tokens":"$largeText"}',
          'created_at': now + i,
          'updated_at': now + i,
        });
      }

      final rows = (await ScreenshotDatabase.instance.listAiConversations())
          .where((row) => (row['cid'] as String? ?? '').startsWith('cid-'))
          .toList();

      expect(rows, hasLength(4));
      for (final row in rows) {
        expect(
          row.keys,
          containsAll(<String>[
            'id',
            'cid',
            'title',
            'provider_id',
            'model',
            'pinned',
            'archived',
            'created_at',
            'updated_at',
          ]),
        );
        expect(row, isNot(contains('summary')));
        expect(row, isNot(contains('tool_memory_json')));
        expect(row, isNot(contains('last_prompt_breakdown_json')));
      }

      final detail = await ScreenshotDatabase.instance.getAiConversationByCid(
        'cid-0',
      );
      expect(detail?['summary'], largeText);
      expect(detail?['tool_memory_json'], contains(largeText));
      expect(detail?['last_prompt_breakdown_json'], contains(largeText));
    } finally {
      await ScreenshotDatabase.instance.disposeDesktop();
      await _deleteTempDir(tmp);
    }
  });
}
