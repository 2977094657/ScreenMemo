import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/services/ai_settings_service.dart';
import 'package:screen_memo/services/chat_context_service.dart';
import 'package:screen_memo/services/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(
  Directory root, {
  required String cid,
}) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  final db = await ScreenshotDatabase.instance.database;
  await db.insert('ai_conversations', <String, Object?>{
    'cid': cid,
    'title': 'dedupe-test',
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('appendCompletedTurn respects provided created_at for dedupe', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_completed_turn_dedupe_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      const String cid = 'dedupe-cid';
      await _prepareDesktopDbRoot(root, cid: cid);

      final int t0 = DateTime.now().millisecondsSinceEpoch;
      await ChatContextService.instance.seedFromChatHistoryIfEmpty(
        cid: cid,
        history: <AIMessage>[
          AIMessage(
            role: 'user',
            content: 'hello',
            createdAt: DateTime.fromMillisecondsSinceEpoch(t0),
          ),
        ],
      );

      await ChatContextService.instance.appendCompletedTurn(
        cid: cid,
        userMessage: 'hello',
        assistantMessage: 'world',
        userCreatedAtMs: t0,
        assistantCreatedAtMs: t0 + 1,
      );

      final FullMessagesPage page = await ChatContextService.instance
          .loadFullMessagesPage(cid: cid, limit: 10);
      expect(page.messages.length, 2);
      expect(page.messages[0].role, 'user');
      expect(page.messages[0].content, 'hello');
      expect(page.messages[1].role, 'assistant');
      expect(page.messages[1].content, 'world');

      final int userCount = page.messages
          .where((m) => m.role == 'user' && m.content.trim() == 'hello')
          .length;
      expect(userCount, 1);
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });
}

