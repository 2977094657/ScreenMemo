import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/features/ai/application/ai_request_gateway.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';

void main() {
  test('assistant tool call message serializes reasoning_content', () {
    final AIMessage message = AIMessage(
      role: 'assistant',
      content: '',
      reasoningContent: 'model reasoning',
      toolCalls: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'call_1',
          'type': 'function',
          'function': <String, dynamic>{
            'name': 'search_segments',
            'arguments': '{}',
          },
        },
      ],
    );

    final Map<String, dynamic> json = message.toJson();

    expect(json['content'], isNull);
    expect(json['reasoning_content'], 'model reasoning');
    expect(json['tool_calls'], isA<List<dynamic>>());
  });

  test('DeepSeek chat completions payload preserves tool reasoning', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    Map<String, dynamic>? captured;

    final Future<void> serverDone = () async {
      await for (final HttpRequest req in server) {
        captured =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode(<String, dynamic>{
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'message': <String, dynamic>{
                  'role': 'assistant',
                  'content': 'ok',
                },
              },
            ],
            'usage': <String, dynamic>{
              'prompt_tokens': 10,
              'completion_tokens': 2,
              'total_tokens': 12,
            },
          }),
        );
        await req.response.close();
        break;
      }
    }();

    final AIGatewayResult result = await AIRequestGateway.instance.complete(
      endpoints: <AIEndpoint>[
        AIEndpoint(
          groupId: null,
          providerType: 'deepseek',
          baseUrl: 'http://127.0.0.1:${server.port}',
          apiKey: 'test-key',
          model: 'deepseek-v4-pro',
          chatPath: '/v1/chat/completions',
        ),
      ],
      messages: <AIMessage>[
        AIMessage(role: 'user', content: 'call a tool'),
        AIMessage(
          role: 'assistant',
          content: '',
          toolCalls: const <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'call_1',
              'type': 'function',
              'function': <String, dynamic>{
                'name': 'search_segments',
                'arguments': '{}',
              },
            },
          ],
        ),
        AIMessage(role: 'tool', content: '{}', toolCallId: 'call_1'),
      ],
      responseStartMarker: '',
      preferStreaming: false,
      reasoningLevel: AIReasoningLevel.high,
      trackKeyStats: false,
    );

    await serverDone;
    await server.close(force: true);

    expect(result.content, 'ok');

    final Map<String, dynamic> payload = captured!;
    expect(payload['thinking'], <String, dynamic>{'type': 'enabled'});
    expect(payload['reasoning_effort'], 'high');
    final List<dynamic> messages = payload['messages'] as List<dynamic>;
    final Map<String, dynamic> assistant = messages[1] as Map<String, dynamic>;
    expect(assistant['tool_calls'], isA<List<dynamic>>());
    expect(assistant.containsKey('reasoning_content'), isTrue);
    expect(assistant['reasoning_content'], '');
  });
}