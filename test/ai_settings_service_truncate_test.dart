import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareChatDb(Directory root, {required String cid}) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  final db = await ScreenshotDatabase.instance.database;
  final int now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('ai_conversations', <String, Object?>{
    'cid': cid,
    'title': 'retry-test',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('ai_messages', <String, Object?>{
    'conversation_id': cid,
    'role': 'user',
    'content': 'before',
    'created_at': 1000,
  });
  await db.insert('ai_messages', <String, Object?>{
    'conversation_id': cid,
    'role': 'assistant',
    'content': 'old answer',
    'created_at': 2000,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('silent truncate does not broadcast chat history reload', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_silent_truncate_',
    );
    final List<String> events = <String>[];
    StreamSubscription<String>? sub;
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareChatDb(root, cid: 'retry-cid');

      sub = AISettingsService.instance.onContextChanged.listen(events.add);
      await AISettingsService.instance.truncateConversationAfterCreatedAt(
        'retry-cid',
        2000,
        notify: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, isEmpty);
      final rows = await ScreenshotDatabase.instance.getAiMessagesTail(
        'retry-cid',
        limit: 10,
      );
      expect(rows.map((e) => e['content']).toList(), <String>['before']);
    } finally {
      await sub?.cancel();
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('truncate broadcasts chat history reload by default', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_notify_truncate_',
    );
    final List<String> events = <String>[];
    StreamSubscription<String>? sub;
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareChatDb(root, cid: 'notify-cid');

      sub = AISettingsService.instance.onContextChanged.listen(events.add);
      await AISettingsService.instance.truncateConversationAfterCreatedAt(
        'notify-cid',
        2000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, contains('chat:history'));
    } finally {
      await sub?.cancel();
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });
}
