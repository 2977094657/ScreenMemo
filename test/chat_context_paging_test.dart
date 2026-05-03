import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/ai/application/chat_context_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(
  Directory root, {
  required String cid,
}) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  final db = await ScreenshotDatabase.instance.database;
  await db.insert('ai_conversations', <String, Object?>{
    'cid': cid,
    'title': 'paging-test',
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}

Future<void> _insertFullMessages(String cid, int count) async {
  final db = await ScreenshotDatabase.instance.database;
  final batch = db.batch();
  final int now = DateTime.now().millisecondsSinceEpoch;
  for (int i = 0; i < count; i++) {
    batch.insert('ai_messages_full', <String, Object?>{
      'conversation_id': cid,
      'role': (i % 2 == 0) ? 'user' : 'assistant',
      'content': 'm$i',
      'created_at': now + i,
    });
  }
  await batch.commit(noResult: true);
}

Future<void> _insertRawMessages(String cid, int count) async {
  final db = await ScreenshotDatabase.instance.database;
  final batch = db.batch();
  final int now = DateTime.now().millisecondsSinceEpoch;
  for (int i = 0; i < count; i++) {
    batch.insert('ai_messages_raw', <String, Object?>{
      'conversation_id': cid,
      'role': (i % 2 == 0) ? 'user' : 'assistant',
      'content': 'r$i',
      'created_at': now + i,
    });
  }
  await batch.commit(noResult: true);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('full prompt history not capped at 240 rows', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_full_paging_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root, cid: 'full-cid');
      await _insertFullMessages('full-cid', 350);

      final List<AIMessage> history = await ChatContextService.instance
          .loadRecentMessagesForPrompt(cid: 'full-cid', maxTokens: 1 << 30);

      expect(history.length, greaterThan(240));
      expect(history.first.content, 'm0');
      expect(history.last.content, 'm349');
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('raw transcript not capped at 1200 rows', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_raw_paging_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root, cid: 'raw-cid');
      await _insertRawMessages('raw-cid', 1305);

      final List<AIMessage> strict = await ChatContextService.instance
          .loadRawTranscriptForPrompt(cid: 'raw-cid', maxTokens: 0);

      expect(strict.length, greaterThan(1200));
      expect(strict.first.content, 'r0');
      expect(strict.last.content, 'r1304');
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('loadFullMessagesPage keyset pagination works', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_full_page_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root, cid: 'page-cid');
      await _insertFullMessages('page-cid', 500);

      final FullMessagesPage p1 = await ChatContextService.instance
          .loadFullMessagesPage(cid: 'page-cid', limit: 200);
      expect(p1.messages.length, 200);
      expect(p1.hasMore, isTrue);
      expect(p1.nextBeforeId, isNotNull);
      expect(p1.messages.first.content, 'm300');
      expect(p1.messages.last.content, 'm499');

      final FullMessagesPage p2 = await ChatContextService.instance
          .loadFullMessagesPage(
            cid: 'page-cid',
            beforeId: p1.nextBeforeId,
            limit: 200,
          );
      expect(p2.messages.length, 200);
      expect(p2.messages.first.content, 'm100');
      expect(p2.messages.last.content, 'm299');
      expect(p2.messages.last.content != p1.messages.first.content, isTrue);
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
