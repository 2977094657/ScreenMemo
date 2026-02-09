import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/services/ai_settings_service.dart';
import 'package:screen_memo/services/chat_context_service.dart';
import 'package:screen_memo/services/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(Directory root) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  final db = await ScreenshotDatabase.instance.database;
  await db.insert('ai_conversations', <String, Object?>{
    'cid': 'raw-cid',
    'title': 'raw-test',
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('raw transcript keeps assistant tool_calls and tool messages', () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_raw_transcript_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root);

      await ChatContextService.instance.appendRawTranscriptMessages(
        cid: 'raw-cid',
        messages: <AIMessage>[
          AIMessage(role: 'user', content: 'find last chat'),
          AIMessage(
            role: 'assistant',
            content: '',
            toolCalls: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'call_1',
                'type': 'function',
                'function': <String, dynamic>{
                  'name': 'search_segments',
                  'arguments': '{"query":"hello"}',
                },
              },
            ],
          ),
          AIMessage(
            role: 'tool',
            content: '{"tool":"search_segments","count":1}',
            toolCallId: 'call_1',
          ),
          AIMessage(role: 'assistant', content: 'done'),
        ],
      );

      final List<AIMessage> replay =
          await ChatContextService.instance.loadRawTranscriptForPrompt(
            cid: 'raw-cid',
            maxTokens: 0,
          );

      expect(replay.length, 4);
      expect(replay[1].role, 'assistant');
      expect(replay[1].toolCalls, isNotNull);
      expect(replay[1].toolCalls!.isNotEmpty, isTrue);
      expect(replay[2].role, 'tool');
      expect(replay[2].toolCallId, 'call_1');
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

