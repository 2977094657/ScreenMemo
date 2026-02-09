import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/services/ai_settings_service.dart';
import 'package:screen_memo/services/chat_context_service.dart';
import 'package:screen_memo/services/prompt_budget.dart';
import 'package:screen_memo/services/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _prepareDesktopDbRoot(Directory root) async {
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  final db = await ScreenshotDatabase.instance.database;
  await db.insert('ai_conversations', <String, Object?>{
    'cid': 'strict-cid',
    'title': 'strict-test',
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('strict full transcript can exceed effective cap and fallback to trimmed',
      () async {
    final Directory tmp = await Directory.systemTemp.createTemp(
      'screen_memo_strict_fallback_',
    );
    try {
      final Directory root = Directory(p.join(tmp.path, 'root'));
      await root.create(recursive: true);
      await _prepareDesktopDbRoot(root);

      final String longChunk = '你' * 12000;
      await ChatContextService.instance.appendRawTranscriptMessages(
        cid: 'strict-cid',
        messages: <AIMessage>[
          AIMessage(role: 'user', content: longChunk),
          AIMessage(role: 'assistant', content: longChunk),
        ],
      );

      final List<AIMessage> strict =
          await ChatContextService.instance.loadRawTranscriptForPrompt(
            cid: 'strict-cid',
            maxTokens: 0,
          );
      expect(strict.length, 2);

      final int strictTokens = PromptBudget.approxTokensForMessagesJson(strict);
      final int cap = strictTokens > 10 ? (strictTokens ~/ 2) : strictTokens;
      final List<AIMessage> trimmed = PromptBudget.keepTailUnderTokenBudget(
        strict,
        maxTokens: cap,
      );
      final int trimmedTokens = PromptBudget.approxTokensForMessagesJson(trimmed);

      expect(strictTokens > cap, isTrue);
      expect(trimmedTokens <= cap, isTrue);
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
