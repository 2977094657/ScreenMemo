import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/ai_settings_service.dart';
import 'package:screen_memo/services/prompt_budget.dart';

void main() {
  test('keepTailUnderTokenBudget returns empty when maxTokens <= 0', () {
    final List<AIMessage> input = <AIMessage>[
      AIMessage(role: 'user', content: 'hello'),
      AIMessage(role: 'assistant', content: 'world'),
    ];

    final List<AIMessage> out0 = PromptBudget.keepTailUnderTokenBudget(
      input,
      maxTokens: 0,
    );
    final List<AIMessage> outNeg = PromptBudget.keepTailUnderTokenBudget(
      input,
      maxTokens: -10,
    );

    expect(out0, isEmpty);
    expect(outNeg, isEmpty);
  });

  test('keepTailUnderTokenBudget trims tail and can truncate oldest kept', () {
    final List<AIMessage> input = <AIMessage>[
      AIMessage(role: 'user', content: 'a' * 200),
      AIMessage(role: 'assistant', content: 'b' * 220),
      AIMessage(role: 'user', content: 'c' * 240),
    ];

    final int cap = PromptBudget.approxTokensForMessageJson(input.last) + 8;
    final List<AIMessage> out = PromptBudget.keepTailUnderTokenBudget(
      input,
      maxTokens: cap,
    );

    expect(out, isNotEmpty);
    expect(out.length <= 2, isTrue);
    expect(out.last.role, 'user');

    final int outTokens = PromptBudget.approxTokensForMessagesJson(out);
    expect(outTokens <= cap, isTrue);

    if (out.length == 2) {
      final AIMessage srcOldestKept = input[input.length - out.length];
      final AIMessage actualOldestKept = out.first;
      expect(actualOldestKept.role, srcOldestKept.role);
      expect(actualOldestKept.content.length <= srcOldestKept.content.length, isTrue);
    }
  });
}

