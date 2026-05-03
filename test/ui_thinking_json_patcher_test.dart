import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/features/ai/application/ui_thinking_json_patcher.dart';

void main() {
  test(
    'patchUiThinkingJsonWithToolUiEvent creates v2 base and upserts tool chips',
    () {
      final String? out = patchUiThinkingJsonWithToolUiEvent(
        null,
        <String, dynamic>{
          'type': 'tool_batch_begin',
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{
              'call_id': 'c1',
              'tool_name': 'search_segments',
              'label': 'Search',
              'app_names': <String>['AppA'],
            },
          ],
        },
        assistantCreatedAtMs: 123,
        toolsTitle: 'Tools',
      );

      expect(out, isNotNull);
      final Map<String, dynamic> decoded =
          jsonDecode(out!) as Map<String, dynamic>;
      expect(decoded['v'], 2);
      final List<dynamic> blocks = decoded['blocks'] as List<dynamic>;
      expect(blocks.length, 1);
      final Map<String, dynamic> b0 = blocks.first as Map<String, dynamic>;
      final List<dynamic> events = b0['events'] as List<dynamic>;
      expect(events.isNotEmpty, true);
      final Map<String, dynamic> e0 = events.last as Map<String, dynamic>;
      expect(e0['type'], 'tools');
      expect(e0['title'], 'Tools');
      final List<dynamic> tools = e0['tools'] as List<dynamic>;
      expect(tools.length, 1);
      final Map<String, dynamic> chip = tools.first as Map<String, dynamic>;
      expect(chip['call_id'], 'c1');
      expect(chip['tool_name'], 'search_segments');
      expect(chip['label'], 'Search');
      expect(chip['active'], true);
    },
  );

  test(
    'patchUiThinkingJsonWithToolUiEvent marks tool_call_end inactive and stores summary',
    () {
      final String base = patchUiThinkingJsonWithToolUiEvent(
        null,
        <String, dynamic>{
          'type': 'tool_batch_begin',
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{
              'call_id': 'c1',
              'tool_name': 'search_segments',
              'label': 'Search',
            },
          ],
        },
        assistantCreatedAtMs: 123,
        toolsTitle: 'Tools',
      )!;

      final String out = patchUiThinkingJsonWithToolUiEvent(
        base,
        <String, dynamic>{
          'type': 'tool_call_end',
          'call_id': 'c1',
          'tool_name': 'search_segments',
          'result_summary': 'count=2',
        },
        assistantCreatedAtMs: 123,
        toolsTitle: 'Tools',
      )!;

      final Map<String, dynamic> decoded =
          jsonDecode(out) as Map<String, dynamic>;
      final List<dynamic> blocks = decoded['blocks'] as List<dynamic>;
      final Map<String, dynamic> b0 = blocks.first as Map<String, dynamic>;
      final List<dynamic> events = b0['events'] as List<dynamic>;
      final Map<String, dynamic> e0 = events.last as Map<String, dynamic>;
      final List<dynamic> tools = e0['tools'] as List<dynamic>;
      final Map<String, dynamic> chip = tools.first as Map<String, dynamic>;
      expect(chip['active'], false);
      expect(chip['result_summary'], 'count=2');
    },
  );

  test('patchUiThinkingJsonWithToolUiEvent preserves seg_lens', () {
    final String seeded = jsonEncode(<String, dynamic>{
      'v': 2,
      'blocks': <Map<String, dynamic>>[
        <String, dynamic>{'created_at': 10, 'events': <Map<String, dynamic>>[]},
      ],
      'seg_lens': <int>[3, 4],
    });

    final String out = patchUiThinkingJsonWithToolUiEvent(
      seeded,
      <String, dynamic>{
        'type': 'tool_batch_begin',
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{'call_id': 'c1', 'tool_name': 't'},
        ],
      },
      assistantCreatedAtMs: 10,
      toolsTitle: 'Tools',
    )!;

    final Map<String, dynamic> decoded =
        jsonDecode(out) as Map<String, dynamic>;
    expect(decoded['seg_lens'], <dynamic>[3, 4]);
  });

  test(
    'patchUiThinkingJsonWithToolUiEvent returns original on invalid json',
    () {
      final String raw = '{not json';
      expect(
        patchUiThinkingJsonWithToolUiEvent(
          raw,
          <String, dynamic>{
            'type': 'tool_call_end',
            'call_id': 'c1',
            'tool_name': 't',
          },
          assistantCreatedAtMs: 1,
          toolsTitle: 'Tools',
        ),
        raw,
      );
    },
  );
}
