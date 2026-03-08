import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/user_memory_index_service.dart';
import 'package:screen_memo/services/user_memory_service.dart';

void main() {
  ExtractedUserMemoryItem item(String content) => ExtractedUserMemoryItem(
    kind: 'fact',
    key: null,
    content: content,
    keywords: <String>['k'],
    confidence: 0.5,
    evidenceFilenames: const <String>[],
  );

  test(
    'resolveWritesFromMergeDecisions parses append/merge/upsert/discard',
    () {
      final List<ExtractedUserMemoryItem> extracted = <ExtractedUserMemoryItem>[
        item('A'),
        item('B'),
        item('C'),
        item('D'),
      ];

      final List<dynamic> decisionsRaw = <dynamic>[
        <String, Object?>{
          'index': 0,
          'action': 'append',
          'target_id': 42,
          'canonical': <String, Object?>{
            'kind': 'habit',
            'content': 'A2',
            'keywords': <String>['x'],
            'confidence': 0.9,
          },
        },
        <String, Object?>{
          'index': 1,
          'action': 'merge',
          'target_id': 42,
          'canonical': <String, Object?>{
            'content': 'B2',
            'keywords': <String>['y'],
            'confidence': 0.8,
          },
        },
        <String, Object?>{'index': 2, 'action': 'discard'},
        <String, Object?>{
          'index': 3,
          'action': 'upsert',
          'canonical': <String, Object?>{
            'content': 'D2',
            'keywords': <String>['z'],
            'confidence': 0.7,
          },
        },
      ];

      final List<UserMemoryResolvedWrite> out =
          UserMemoryIndexService.resolveWritesFromMergeDecisions(
            extracted: extracted,
            decisionsRaw: decisionsRaw,
            allowedCandidateIds: <int>{42},
          );

      expect(out, hasLength(4));

      expect(out[0].action, UserMemoryResolvedAction.append);
      expect(out[0].targetId, 42);
      expect(out[0].item.kind, 'habit');
      expect(out[0].item.content, 'A2');

      expect(out[1].action, UserMemoryResolvedAction.merge);
      expect(out[1].targetId, 42);
      expect(out[1].item.content, 'B2');

      expect(out[2].action, UserMemoryResolvedAction.discard);
      expect(out[2].targetId, isNull);
      expect(out[2].item.content, 'C');

      expect(out[3].action, UserMemoryResolvedAction.upsert);
      expect(out[3].targetId, isNull);
      expect(out[3].item.content, 'D2');
    },
  );

  test(
    'resolveWritesFromMergeDecisions falls back to upsert on invalid target',
    () {
      final List<ExtractedUserMemoryItem> extracted = <ExtractedUserMemoryItem>[
        item('A'),
      ];

      final List<dynamic> decisionsRaw = <dynamic>[
        <String, Object?>{
          'index': 0,
          'action': 'append',
          'target_id': 999,
          'canonical': <String, Object?>{
            'content': 'A2',
            'keywords': <String>['x'],
            'confidence': 0.9,
          },
        },
      ];

      final List<UserMemoryResolvedWrite> out =
          UserMemoryIndexService.resolveWritesFromMergeDecisions(
            extracted: extracted,
            decisionsRaw: decisionsRaw,
            allowedCandidateIds: <int>{42},
          );

      expect(out, hasLength(1));
      expect(out[0].action, UserMemoryResolvedAction.upsert);
      expect(out[0].targetId, isNull);
      expect(out[0].item.content, 'A2');
    },
  );
}
