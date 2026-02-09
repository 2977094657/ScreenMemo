import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/ai_chat_service.dart';

void main() {
  test('chat context forces includeHistory when persistHistory is true', () {
    final bool effective = AIChatService.includeHistoryEffective(
      context: 'chat',
      includeHistory: false,
      persistHistory: true,
    );
    expect(effective, isTrue);
  });

  test('non-chat context does not force includeHistory', () {
    final bool effective = AIChatService.includeHistoryEffective(
      context: 'extract',
      includeHistory: false,
      persistHistory: true,
    );
    expect(effective, isFalse);
  });

  test('explicit includeHistory true remains true', () {
    final bool effective = AIChatService.includeHistoryEffective(
      context: 'chat',
      includeHistory: true,
      persistHistory: false,
    );
    expect(effective, isTrue);
  });
}

