import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/features/ai/application/chat_context_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(Directory root) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  final db = await ScreenshotDatabase.instance.database;
  await db.insert('ai_conversations', <String, Object?>{
    'cid': 'test-cid',
    'title': 'test',
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('logPromptTrimEvent writes standardized prompt_trim payload', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_trim_event_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root);

      await ChatContextService.instance.logPromptTrimEvent(
        cid: 'test-cid',
        stage: 'chat_setup',
        kind: 'extras_drop',
        beforeTokens: 1500,
        afterTokens: 1200,
        droppedMessages: 2,
        droppedChunks: 0,
        truncatedOldest: false,
        reason: 'reserve_history',
        model: 'gpt-test',
      );

      final List<ChatContextEvent> events = await ChatContextService.instance
          .listRecentContextEvents(
            cid: 'test-cid',
            type: 'prompt_trim',
            limit: 50,
          );

      expect(events, isNotEmpty);
      final ChatContextEvent e = events.first;
      expect(e.type, 'prompt_trim');
      expect(e.stage, 'chat_setup');
      expect(e.kind, 'extras_drop');
      expect(e.beforeTokens, 1500);
      expect(e.afterTokens, 1200);
      expect(e.droppedTokens, 300);
      expect(e.droppedMessages, 2);
      expect(e.droppedChunks, 0);
      expect(e.truncatedOldest, isFalse);
      expect(e.reason, 'reserve_history');
      expect(e.model, 'gpt-test');
      expect(e.payload.containsKey('created_at_ms'), isTrue);
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test(
    'listRecentContextEvents respects type filter and limit clamp',
    () async {
      final Directory tmp = await Directory.systemTemp.createTemp(
        'screen_memo_trim_event_list_',
      );
      try {
        final Directory root = Directory(p.join(tmp.path, 'root'));
        await root.create(recursive: true);
        await _prepareDesktopDbRoot(root);
        final db = await ScreenshotDatabase.instance.database;
        final int now = DateTime.now().millisecondsSinceEpoch;

        await db.insert('ai_context_events', <String, Object?>{
          'conversation_id': 'test-cid',
          'type': 'prompt_trim',
          'payload_json': jsonEncode(<String, Object?>{
            'stage': 'a',
            'kind': 'history_tail',
            'before_tokens': 100,
            'after_tokens': 90,
          }),
          'created_at': now,
        });
        await db.insert('ai_context_events', <String, Object?>{
          'conversation_id': 'test-cid',
          'type': 'atomic_memory',
          'payload_json': jsonEncode(<String, Object?>{'enabled': true}),
          'created_at': now + 1,
        });

        final List<ChatContextEvent> onlyTrim = await ChatContextService
            .instance
            .listRecentContextEvents(
              cid: 'test-cid',
              type: 'prompt_trim',
              limit: 999,
            );

        expect(onlyTrim, isNotEmpty);
        expect(onlyTrim.every((e) => e.type == 'prompt_trim'), isTrue);

        final List<ChatContextEvent> allEvents = await ChatContextService
            .instance
            .listRecentContextEvents(cid: 'test-cid', limit: 0);
        expect(allEvents, isNotEmpty);
        expect(allEvents.length >= 2, isTrue);
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
