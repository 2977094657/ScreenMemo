import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/ai_settings_service.dart';
import 'package:screen_memo/services/chat_history_merge.dart';

String _uiThinkingV2({
  required int createdAtMs,
  bool finished = false,
}) {
  return jsonEncode(<String, dynamic>{
    'v': 2,
    'blocks': <Map<String, dynamic>>[
      <String, dynamic>{
        'created_at': createdAtMs,
        if (finished) 'finished_at': createdAtMs + 123,
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'intent',
            'title': 'Analyze intent',
            'active': !finished,
          },
        ],
      },
    ],
  });
}

void main() {
  test('mergeCompletedTurnIntoHistory replaces unfinished placeholder and patches finished_at', () {
    final DateTime userAt = DateTime.fromMillisecondsSinceEpoch(1000);
    final DateTime assistantAt = DateTime.fromMillisecondsSinceEpoch(2000);

    final existing = <AIMessage>[
      AIMessage(role: 'user', content: 'Hi', createdAt: userAt),
      AIMessage(
        role: 'assistant',
        content: '1/4 ...',
        createdAt: assistantAt,
        uiThinkingJson: _uiThinkingV2(createdAtMs: assistantAt.millisecondsSinceEpoch),
      ),
    ];

    final assistantFinal = AIMessage(
      role: 'assistant',
      content: 'Final answer',
      reasoningContent: 'model reasoning',
      reasoningDuration: const Duration(milliseconds: 3000),
    );

    final merged = mergeCompletedTurnIntoHistory(
      existingHistory: existing,
      userMessage: 'Hi',
      assistantFinal: assistantFinal,
      nowMs: 999999,
    );

    expect(merged.length, 2);
    expect(merged[0].role, 'user');
    expect(merged[0].createdAt, userAt);
    expect(merged[1].role, 'assistant');
    expect(merged[1].content, 'Final answer');
    // Keep assistant createdAt from placeholder so bubble timestamp remains stable.
    expect(merged[1].createdAt, assistantAt);
    expect((merged[1].uiThinkingJson ?? '').isNotEmpty, true);

    final decoded = jsonDecode(merged[1].uiThinkingJson!) as Map<String, dynamic>;
    final blocks = decoded['blocks'] as List<dynamic>;
    final b0 = blocks.first as Map<String, dynamic>;
    expect(b0.containsKey('finished_at'), true);
    // finished_at should align with created_at + reasoningDuration when possible.
    expect(
      b0['finished_at'] as int,
      assistantAt.millisecondsSinceEpoch + 3000,
    );
  });

  test('mergeCompletedTurnIntoHistory prefers the more complete uiThinkingJson', () {
    final DateTime assistantAt = DateTime.fromMillisecondsSinceEpoch(2000);
    final String minimal = _uiThinkingV2(
      createdAtMs: assistantAt.millisecondsSinceEpoch,
      finished: false,
    );
    final String richer = jsonEncode(<String, dynamic>{
      'v': 2,
      'blocks': <Map<String, dynamic>>[
        <String, dynamic>{
          'created_at': assistantAt.millisecondsSinceEpoch,
          'events': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'intent',
              'title': 'Analyze intent',
              'active': false,
            },
            <String, dynamic>{
              'type': 'tools',
              'title': 'Tools',
              'icon': 'auto_awesome_outlined',
              'tools': <Map<String, dynamic>>[
                <String, dynamic>{
                  'call_id': 'c1',
                  'tool_name': 'search_segments',
                  'label': 'search_segments',
                  'active': false,
                  'result_summary': 'count=1',
                },
              ],
            },
          ],
        },
      ],
    });

    final existing = <AIMessage>[
      AIMessage(role: 'user', content: 'Hi'),
      AIMessage(
        role: 'assistant',
        content: 'partial',
        createdAt: assistantAt,
        uiThinkingJson: minimal,
      ),
    ];

    final assistantFinal = AIMessage(
      role: 'assistant',
      content: 'Final answer',
      uiThinkingJson: richer,
    );

    final merged = mergeCompletedTurnIntoHistory(
      existingHistory: existing,
      userMessage: 'Hi',
      assistantFinal: assistantFinal,
      nowMs: 999999,
    );

    final decoded = jsonDecode(merged[1].uiThinkingJson!) as Map<String, dynamic>;
    final blocks = decoded['blocks'] as List<dynamic>;
    final b0 = blocks.first as Map<String, dynamic>;
    final events = b0['events'] as List<dynamic>;
    expect(events.where((e) => (e as Map)['type'] == 'tools').isNotEmpty, true);
  });

  test('mergeCompletedTurnIntoHistory inserts assistant after existing user when no placeholder exists', () {
    final existing = <AIMessage>[
      AIMessage(
        role: 'user',
        content: 'Q',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    ];
    final assistantFinal = AIMessage(role: 'assistant', content: 'A');

    final merged = mergeCompletedTurnIntoHistory(
      existingHistory: existing,
      userMessage: 'Q',
      assistantFinal: assistantFinal,
    );

    expect(merged.map((m) => m.role).toList(), <String>['user', 'assistant']);
    expect(merged.last.content, 'A');
  });

  test('mergeCompletedTurnIntoHistory cleans up duplicate user+assistant pair after placeholder', () {
    final DateTime assistantAt = DateTime.fromMillisecondsSinceEpoch(2000);
    final existing = <AIMessage>[
      AIMessage(role: 'user', content: 'Same'),
      AIMessage(
        role: 'assistant',
        content: 'partial',
        createdAt: assistantAt,
        uiThinkingJson: _uiThinkingV2(createdAtMs: assistantAt.millisecondsSinceEpoch),
      ),
      AIMessage(role: 'user', content: 'Same'),
      AIMessage(role: 'assistant', content: 'old final'),
    ];

    final merged = mergeCompletedTurnIntoHistory(
      existingHistory: existing,
      userMessage: 'Same',
      assistantFinal: AIMessage(role: 'assistant', content: 'new final'),
      nowMs: 999999,
    );

    expect(merged.length, 2);
    expect(merged[0].role, 'user');
    expect(merged[1].role, 'assistant');
    expect(merged[1].content, 'new final');
  });

  test('mergeCompletedTurnIntoHistory keeps later turns when merging an earlier placeholder', () {
    final DateTime a1At = DateTime.fromMillisecondsSinceEpoch(1000);
    final DateTime a2At = DateTime.fromMillisecondsSinceEpoch(3000);
    final existing = <AIMessage>[
      AIMessage(role: 'user', content: 'U1'),
      AIMessage(
        role: 'assistant',
        content: 'partial1',
        createdAt: a1At,
        uiThinkingJson: _uiThinkingV2(createdAtMs: a1At.millisecondsSinceEpoch),
      ),
      AIMessage(role: 'user', content: 'U2'),
      AIMessage(
        role: 'assistant',
        content: 'partial2',
        createdAt: a2At,
        uiThinkingJson: _uiThinkingV2(createdAtMs: a2At.millisecondsSinceEpoch),
      ),
    ];

    final merged = mergeCompletedTurnIntoHistory(
      existingHistory: existing,
      userMessage: 'U1',
      assistantFinal: AIMessage(role: 'assistant', content: 'final1'),
      nowMs: 999999,
    );

    expect(merged.length, 4);
    expect(merged[1].content, 'final1');
    expect(merged[2].content, 'U2');
    expect(merged[3].content, 'partial2');
  });

  test('patchUiThinkingJsonFinish returns original on invalid json', () {
    expect(
      patchUiThinkingJsonFinish('{not json'),
      '{not json',
    );
  });
}
