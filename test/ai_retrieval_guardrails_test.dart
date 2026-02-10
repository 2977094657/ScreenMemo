import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/ai_chat_service.dart';

void main() {
  group('retrieval guardrails', () {
    test('hard no-results stays hard even when asking a question', () {
      const String content = '没有找到相关记录。你能再确认一下关键词吗？';
      expect(
        AIChatService.instance.debugContentLooksLikeHardNoResultsConclusion(
          content,
        ),
        isTrue,
      );
    });

    test('clarification stop detected when only asking user to choose', () {
      const String content =
          '我可以继续，但需要你先确认两个信息：1) 去年是 2025 还是 2024？2) 你想按月还是按主题？';
      expect(
        AIChatService.instance.debugContentLooksLikeClarificationStop(content),
        isTrue,
      );
    });

    test('clarification stop not triggered when coverage is reported', () {
      const String content =
          '当前已覆盖 2025-12-01 到 2025-12-31，未覆盖 2025-01 到 2025-11。下一步我会继续按 paging.prev 翻页。';
      expect(
        AIChatService.instance.debugContentLooksLikeClarificationStop(content),
        isFalse,
      );
    });

    test('paging signal detected from paging object', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'tool': 'search_segments',
        'count': 0,
        'paging': <String, dynamic>{
          'prev': <String, dynamic>{
            'start_local': '2025-12-24 00:00',
            'end_local': '2025-12-31 23:59',
          },
        },
      };
      expect(
        AIChatService.instance.debugRetrievalPayloadHasPagingSignal(payload),
        isTrue,
      );
    });

    test('paging signal detected from clamped span', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'tool': 'search_segments',
        'count': 0,
        'time_span_limit': <String, dynamic>{'clamped': true},
      };
      expect(
        AIChatService.instance.debugRetrievalPayloadHasPagingSignal(payload),
        isTrue,
      );
    });
  });
}
