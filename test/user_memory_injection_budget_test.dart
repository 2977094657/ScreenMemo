import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/prompt_budget.dart';
import 'package:screen_memo/services/user_memory_service.dart';

void main() {
  test(
    'buildUserMemoryContextFromData respects budget and pinned priority',
    () {
      final List<UserMemoryItem> pinned = <UserMemoryItem>[
        const UserMemoryItem(
          id: 1,
          kind: 'rule',
          memoryKey: 'tone',
          content: 'Prefer concise answers.',
          pinned: true,
          userEdited: false,
          updatedAtMs: 1,
          confidence: 0.9,
        ),
        const UserMemoryItem(
          id: 2,
          kind: 'habit',
          memoryKey: null,
          content: 'Usually uses English variable names in code.',
          pinned: true,
          userEdited: false,
          updatedAtMs: 1,
          confidence: 0.8,
        ),
        const UserMemoryItem(
          id: 3,
          kind: 'fact',
          memoryKey: null,
          content: 'Uses Windows.',
          pinned: true,
          userEdited: false,
          updatedAtMs: 1,
          confidence: 0.7,
        ),
      ];

      final List<UserMemoryItem> relevant = List<UserMemoryItem>.generate(
        10,
        (i) => UserMemoryItem(
          id: 100 + i,
          kind: 'fact',
          memoryKey: null,
          content: 'Relevant $i',
          pinned: false,
          userEdited: false,
          updatedAtMs: 1,
          confidence: null,
        ),
        growable: false,
      );

      final String msg = UserMemoryService.buildUserMemoryContextFromData(
        profileMarkdown: '# Profile\n${'x' * 5000}',
        pinned: pinned,
        relevant: relevant,
        maxTokens: 180,
        maxRelevantItems: 2,
      );

      expect(msg.contains('<user_memory>'), isTrue);
      expect(msg.contains('</user_memory>'), isTrue);

      // Budget is enforced by bytes (tokens * bytesPerToken).
      expect(
        PromptBudget.utf8Bytes(msg) <= 180 * PromptBudget.approxBytesPerToken,
        isTrue,
      );

      // Pinned items should be present even if maxRelevantItems is small.
      expect(msg.contains('Prefer concise answers.'), isTrue);
      expect(
        msg.contains('Usually uses English variable names in code.'),
        isTrue,
      );
      expect(msg.contains('Uses Windows.'), isTrue);

      // Only up to 2 relevant items should be included (pinned does not count).
      expect(msg.contains('Relevant 0'), isTrue);
      expect(msg.contains('Relevant 1'), isTrue);
      expect(msg.contains('Relevant 2'), isFalse);
    },
  );
}
