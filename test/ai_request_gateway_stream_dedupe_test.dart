import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/features/ai/application/ai_request_gateway.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';

int _countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  int count = 0;
  int index = 0;
  while (true) {
    final int found = haystack.indexOf(needle, index);
    if (found < 0) break;
    count += 1;
    index = found + needle.length;
  }
  return count;
}

Future<void> _writeSseEvent(
  HttpResponse response,
  String type,
  Map<String, dynamic> data,
) async {
  response.write('event: $type\n');
  response.write('data: ${jsonEncode(data)}\n\n');
  await response.flush();
}

void main() {
  test('responses terminal events do not duplicate final content', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    final String finalText = '有，而且从你这段“去年”的记录里，我看到两类波动。';

    final Future<void> serverDone = () async {
      await for (final HttpRequest req in server) {
        if (req.method != 'POST' || req.uri.path != '/v1/responses') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          continue;
        }

        await utf8.decoder.bind(req).join();

        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/event-stream; charset=utf-8',
        );
        req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

        await Future<void>.delayed(const Duration(milliseconds: 20));

        await _writeSseEvent(
          req.response,
          'response.output_text.delta',
          <String, dynamic>{
            'type': 'response.output_text.delta',
            'output_index': 0,
            'content_index': 0,
            'delta': '有，',
          },
        );
        await _writeSseEvent(
          req.response,
          'response.output_text.delta',
          <String, dynamic>{
            'type': 'response.output_text.delta',
            'output_index': 0,
            'content_index': 0,
            'delta': '波动',
          },
        );
        await _writeSseEvent(
          req.response,
          'response.output_text.delta',
          <String, dynamic>{
            'type': 'response.output_text.delta',
            'output_index': 0,
            'content_index': 0,
            'delta': '开心',
          },
        );

        await _writeSseEvent(
          req.response,
          'response.output_text.done',
          <String, dynamic>{
            'type': 'response.output_text.done',
            'output_index': 0,
            'content_index': 0,
            'text': finalText,
          },
        );

        await _writeSseEvent(
          req.response,
          'response.content_part.done',
          <String, dynamic>{
            'type': 'response.content_part.done',
            'output_index': 0,
            'content_index': 0,
            'part': <String, dynamic>{
              'type': 'output_text',
              'text': finalText,
              'annotations': <Object>[],
            },
          },
        );

        await _writeSseEvent(
          req.response,
          'response.output_item.done',
          <String, dynamic>{
            'type': 'response.output_item.done',
            'output_index': 0,
            'item': <String, dynamic>{
              'id': 'msg_test',
              'type': 'message',
              'role': 'assistant',
              'status': 'completed',
              'content': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'output_text',
                  'text': finalText,
                  'annotations': <Object>[],
                },
              ],
            },
          },
        );

        await _writeSseEvent(
          req.response,
          'response.completed',
          <String, dynamic>{
            'type': 'response.completed',
            'response': <String, dynamic>{'id': 'resp_test'},
          },
        );

        await req.response.close();
        break;
      }
    }();

    final AIEndpoint endpoint = AIEndpoint(
      groupId: null,
      baseUrl: 'http://127.0.0.1:${server.port}',
      apiKey: 'test-key',
      model: 'gpt-5.2-xhigh',
      chatPath: '/v1/responses',
      useResponseApi: true,
    );

    final AIGatewayStreamingSession session = AIRequestGateway.instance
        .startStreaming(
          endpoints: <AIEndpoint>[endpoint],
          messages: <AIMessage>[
            AIMessage(role: 'user', content: '去年我有什么感情波动吗'),
          ],
          responseStartMarker: '',
          timeout: const Duration(seconds: 5),
        );

    final Future<List<String>> contentChunksFuture = session.stream
        .where((AIGatewayEvent e) => e.kind == AIGatewayEventKind.content)
        .map((AIGatewayEvent e) => e.data)
        .toList();

    final AIGatewayResult result = await session.completed;
    final List<String> contentChunks = await contentChunksFuture;

    expect(result.content, finalText);
    final String streamedText = contentChunks.join();
    expect(_countOccurrences(streamedText, finalText), 1);

    await serverDone;
    await server.close(force: true);
  });
}
