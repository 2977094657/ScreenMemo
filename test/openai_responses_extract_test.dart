import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/openai_responses_extract.dart';

void main() {
  test('extractResponsesMessageOutputText concatenates output_text parts', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'type': 'message',
      'role': 'assistant',
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'output_text', 'text': 'Hello'},
        <String, dynamic>{'type': 'output_text', 'text': ', world'},
      ],
    };

    expect(extractResponsesMessageOutputText(item), 'Hello, world');
  });

  test('extractResponsesMessageOutputText ignores non-assistant roles', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'type': 'message',
      'role': 'user',
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'output_text', 'text': 'should not appear'},
      ],
    };

    expect(extractResponsesMessageOutputText(item), '');
  });

  test('extractResponsesFunctionCallItem parses top-level call fields', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'type': 'function_call',
      'call_id': 'c1',
      'name': 'search_segments',
      'arguments': '{"q":"hi"}',
    };

    final ResponsesFunctionCallItem? out = extractResponsesFunctionCallItem(item);
    expect(out, isNotNull);
    expect(out!.callId, 'c1');
    expect(out.name, 'search_segments');
    expect(out.arguments, '{"q":"hi"}');
  });

  test('extractResponsesFunctionCallItem parses nested function object', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'type': 'tool_call',
      'id': 't1',
      'function': <String, dynamic>{
        'name': 'get_images',
        'arguments': '{"n":2}',
      },
    };

    final ResponsesFunctionCallItem? out = extractResponsesFunctionCallItem(item);
    expect(out, isNotNull);
    expect(out!.callId, 't1');
    expect(out.name, 'get_images');
    expect(out.arguments, '{"n":2}');
  });

  test('extractResponsesFunctionCallItem returns null when missing id/name', () {
    expect(
      extractResponsesFunctionCallItem(<String, dynamic>{
        'type': 'function_call',
        'name': 'x',
      }),
      isNull,
    );
    expect(
      extractResponsesFunctionCallItem(<String, dynamic>{
        'type': 'function_call',
        'call_id': 'c1',
      }),
      isNull,
    );
  });

  test('extractResponsesReasoningText reads summary_text parts', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'type': 'reasoning',
      'summary': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'summary_text', 'text': 'step A'},
        <String, dynamic>{'type': 'summary_text', 'text': ' + step B'},
      ],
    };

    expect(extractResponsesReasoningText(item), 'step A + step B');
  });

  test('extractResponsesReasoningText reads content/text fallback', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'type': 'reasoning',
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'reasoning_text', 'text': 'inner'},
      ],
      'text': ' tail',
    };

    expect(extractResponsesReasoningText(item), 'inner tail');
  });
}
