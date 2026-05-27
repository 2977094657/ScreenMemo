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

Future<void> _writeSseData(HttpResponse response, Object data) async {
  final String encoded = data is String ? data : jsonEncode(data);
  response.write('data: $encoded\n\n');
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
            'response': <String, dynamic>{
              'id': 'resp_test',
              'usage': <String, dynamic>{
                'input_tokens': 100,
                'output_tokens': 25,
                'total_tokens': 125,
                'input_tokens_details': <String, dynamic>{'cached_tokens': 40},
              },
            },
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
    expect(result.usagePromptTokens, 100);
    expect(result.usageCompletionTokens, 25);
    expect(result.usageTotalTokens, 125);
    expect(result.usageCacheHitTokens, 40);
    final String streamedText = contentChunks.join();
    expect(_countOccurrences(streamedText, finalText), 1);

    await serverDone;
    await server.close(force: true);
  });

  test(
    'chat completions stream reads usage chunk after finish_reason',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      Map<String, dynamic>? capturedBody;
      final Future<void> serverDone = () async {
        await for (final HttpRequest req in server) {
          if (req.method != 'POST' || req.uri.path != '/v1/chat/completions') {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
            continue;
          }

          final String body = await utf8.decoder.bind(req).join();
          capturedBody = jsonDecode(body) as Map<String, dynamic>;

          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/event-stream; charset=utf-8',
          );
          req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

          await _writeSseData(req.response, <String, dynamic>{
            'id': 'chatcmpl_test',
            'model': 'gpt-test',
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'index': 0,
                'delta': <String, dynamic>{'content': 'Hello'},
                'finish_reason': null,
              },
            ],
          });
          await _writeSseData(req.response, <String, dynamic>{
            'id': 'chatcmpl_test',
            'model': 'gpt-test',
            'choices': <Map<String, dynamic>>[
              <String, dynamic>{
                'index': 0,
                'delta': <String, dynamic>{},
                'finish_reason': 'stop',
              },
            ],
          });
          await _writeSseData(req.response, <String, dynamic>{
            'id': 'chatcmpl_test',
            'model': 'gpt-test',
            'choices': <Object>[],
            'usage': <String, dynamic>{
              'prompt_tokens': 11,
              'completion_tokens': 3,
              'total_tokens': 14,
              'prompt_tokens_details': <String, dynamic>{'cached_tokens': 5},
            },
          });
          await _writeSseData(req.response, '[DONE]');
          await req.response.close();
          break;
        }
      }();

      final AIEndpoint endpoint = AIEndpoint(
        groupId: null,
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'test-key',
        model: 'gpt-test',
        chatPath: '/v1/chat/completions',
        useResponseApi: false,
      );

      final AIGatewayStreamingSession session = AIRequestGateway.instance
          .startStreaming(
            endpoints: <AIEndpoint>[endpoint],
            messages: <AIMessage>[AIMessage(role: 'user', content: 'hello')],
            responseStartMarker: '',
            timeout: const Duration(seconds: 5),
          );

      final Future<List<String>> contentChunksFuture = session.stream
          .where((AIGatewayEvent e) => e.kind == AIGatewayEventKind.content)
          .map((AIGatewayEvent e) => e.data)
          .toList();

      final AIGatewayResult result = await session.completed;
      final List<String> contentChunks = await contentChunksFuture;

      expect(contentChunks.join(), 'Hello');
      expect(result.content, 'Hello');
      expect(result.usagePromptTokens, 11);
      expect(result.usageCompletionTokens, 3);
      expect(result.usageTotalTokens, 14);
      expect(result.usageCacheHitTokens, 5);
      expect(
        (capturedBody?['stream_options'] as Map?)?['include_usage'],
        isTrue,
      );

      await serverDone;
      await server.close(force: true);
    },
  );

  test('OpenAI Responses GPT models auto inject web_search tool', () async {
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
            'output': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'message',
                'role': 'assistant',
                'content': <Map<String, dynamic>>[
                  <String, dynamic>{'type': 'output_text', 'text': 'ok'},
                ],
              },
            ],
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
          baseUrl: 'http://127.0.0.1:${server.port}',
          apiKey: 'test-key',
          model: 'openai/gpt-5.2',
          chatPath: '/v1/responses',
          useResponseApi: true,
        ),
      ],
      messages: <AIMessage>[AIMessage(role: 'user', content: 'latest news')],
      responseStartMarker: '',
      preferStreaming: false,
      trackKeyStats: false,
    );

    await serverDone;
    await server.close(force: true);

    expect(result.content, 'ok');
    final List<dynamic> tools = captured?['tools'] as List<dynamic>;
    expect(
      tools.where(
        (dynamic tool) =>
            tool is Map &&
            ((tool['type'] as String?) ?? '').trim() == 'web_search',
      ),
      hasLength(1),
    );
  });

  test(
    'Chat Completions GPT models do not auto inject web_search tool',
    () async {
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
                  'message': <String, dynamic>{'content': 'ok'},
                },
              ],
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
            baseUrl: 'http://127.0.0.1:${server.port}',
            apiKey: 'test-key',
            model: 'gpt-5.2',
            chatPath: '/v1/chat/completions',
            useResponseApi: false,
          ),
        ],
        messages: <AIMessage>[AIMessage(role: 'user', content: 'latest news')],
        responseStartMarker: '',
        preferStreaming: false,
        trackKeyStats: false,
      );

      await serverDone;
      await server.close(force: true);

      expect(result.content, 'ok');
      expect(captured?.containsKey('tools'), isFalse);
    },
  );

  test(
    'explicit web_search tool is not duplicated for Responses GPT models',
    () async {
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
              'output': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'message',
                  'role': 'assistant',
                  'content': <Map<String, dynamic>>[
                    <String, dynamic>{'type': 'output_text', 'text': 'ok'},
                  ],
                },
              ],
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
            baseUrl: 'http://127.0.0.1:${server.port}',
            apiKey: 'test-key',
            model: 'gpt-5.2',
            chatPath: '/v1/responses',
            useResponseApi: true,
          ),
        ],
        messages: <AIMessage>[AIMessage(role: 'user', content: 'latest news')],
        responseStartMarker: '',
        preferStreaming: false,
        tools: const <Map<String, dynamic>>[
          <String, dynamic>{'type': 'web_search', 'search_context_size': 'low'},
        ],
        trackKeyStats: false,
      );

      await serverDone;
      await server.close(force: true);

      expect(result.content, 'ok');
      final List<dynamic> tools = captured?['tools'] as List<dynamic>;
      expect(
        tools.where(
          (dynamic tool) =>
              tool is Map &&
              ((tool['type'] as String?) ?? '').trim() == 'web_search',
        ),
        hasLength(1),
      );
    },
  );

  test('parses Responses web_search_call and url_citation metadata', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    final Future<void> serverDone = () async {
      await for (final HttpRequest req in server) {
        await utf8.decoder.bind(req).join();
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode(<String, dynamic>{
            'output': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'web_search_call',
                'id': 'ws_123',
                'status': 'completed',
                'action': <String, dynamic>{
                  'type': 'search',
                  'query': 'weather seattle',
                  'queries': <String>['weather seattle', 'seattle weather now'],
                },
              },
              <String, dynamic>{
                'type': 'message',
                'role': 'assistant',
                'content': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'output_text',
                    'text': 'Seattle weather is mild today.',
                    'annotations': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'type': 'url_citation',
                        'start_index': 0,
                        'end_index': 15,
                        'url': 'https://example.com/weather',
                        'title': 'Example Weather',
                      },
                    ],
                  },
                ],
              },
            ],
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
          baseUrl: 'http://127.0.0.1:${server.port}',
          apiKey: 'test-key',
          model: 'gpt-5.2',
          chatPath: '/v1/responses',
          useResponseApi: true,
        ),
      ],
      messages: <AIMessage>[AIMessage(role: 'user', content: 'weather?')],
      responseStartMarker: '',
      preferStreaming: false,
      trackKeyStats: false,
    );

    await serverDone;
    await server.close(force: true);

    expect(result.content, 'Seattle weather is mild today.');
    expect(result.webSearchCalls, hasLength(1));
    expect(result.webSearchCalls.single.id, 'ws_123');
    expect(result.webSearchCalls.single.status, 'completed');
    expect(result.webSearchCalls.single.actionType, 'search');
    expect(result.webSearchCalls.single.query, 'weather seattle');
    expect(
      result.webSearchCalls.single.queries,
      contains('seattle weather now'),
    );
    expect(result.citations, hasLength(1));
    expect(result.citations.single.title, 'Example Weather');
    expect(result.citations.single.url, 'https://example.com/weather');
    expect(result.citations.single.startIndex, 0);
    expect(result.citations.single.endIndex, 15);
  });

  test('streams Responses web_search_call ui metadata', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

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

        await _writeSseEvent(
          req.response,
          'response.output_item.added',
          <String, dynamic>{
            'type': 'response.output_item.added',
            'output_index': 1,
            'item': <String, dynamic>{
              'id': 'ws_live',
              'type': 'web_search_call',
              'status': 'in_progress',
            },
          },
        );
        await _writeSseEvent(
          req.response,
          'response.web_search_call.searching',
          <String, dynamic>{
            'type': 'response.web_search_call.searching',
            'output_index': 1,
            'item_id': 'ws_live',
          },
        );
        await _writeSseEvent(req.response, 'response.output_item.done', <
          String,
          dynamic
        >{
          'type': 'response.output_item.done',
          'output_index': 1,
          'item': <String, dynamic>{
            'id': 'ws_live',
            'type': 'web_search_call',
            'status': 'completed',
            'action': <String, dynamic>{
              'type': 'search',
              'queries': <String>[
                'Responses API web_search_call url_citation fields',
              ],
              'sources': <Map<String, dynamic>>[
                <String, dynamic>{
                  'title': 'Web search',
                  'url':
                      'https://platform.openai.com/docs/guides/tools-web-search',
                },
              ],
            },
          },
        });
        await _writeSseEvent(req.response, 'response.output_item.done', <
          String,
          dynamic
        >{
          'type': 'response.output_item.done',
          'output_index': 2,
          'item': <String, dynamic>{
            'id': 'msg_live',
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            'content': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'output_text',
                'text': 'OpenAI documents the web search tool.',
                'annotations': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'url_citation',
                    'start_index': 0,
                    'end_index': 6,
                    'title': 'Web search',
                    'url':
                        'https://platform.openai.com/docs/guides/tools-web-search',
                  },
                ],
              },
            ],
          },
        });
        await _writeSseEvent(
          req.response,
          'response.completed',
          <String, dynamic>{
            'type': 'response.completed',
            'response': <String, dynamic>{
              'output': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'ws_live',
                  'type': 'web_search_call',
                  'status': 'completed',
                  'action': <String, dynamic>{
                    'type': 'search',
                    'queries': <String>[
                      'Responses API web_search_call url_citation fields',
                    ],
                  },
                },
              ],
            },
          },
        );
        await req.response.close();
        break;
      }
    }();

    final AIGatewayStreamingSession session = AIRequestGateway.instance
        .startStreaming(
          endpoints: <AIEndpoint>[
            AIEndpoint(
              groupId: null,
              baseUrl: 'http://127.0.0.1:${server.port}',
              apiKey: 'test-key',
              model: 'gpt-5.4-mini',
              chatPath: '/v1/responses',
              useResponseApi: true,
            ),
          ],
          messages: <AIMessage>[
            AIMessage(role: 'user', content: 'search docs'),
          ],
          responseStartMarker: '',
          trackKeyStats: false,
        );

    final List<Map<String, dynamic>> webSearchEvents = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> citationEvents = <Map<String, dynamic>>[];
    await for (final AIGatewayEvent event in session.stream) {
      if (event.kind != AIGatewayEventKind.ui) continue;
      final Map<String, dynamic> payload =
          jsonDecode(event.data) as Map<String, dynamic>;
      final String type = (payload['type'] ?? '').toString();
      if (type == 'web_search_call') webSearchEvents.add(payload);
      if (type == 'url_citation') citationEvents.add(payload);
    }
    final AIGatewayResult result = await session.completed;

    await serverDone;
    await server.close(force: true);

    expect(result.content, 'OpenAI documents the web search tool.');
    expect(result.webSearchCalls, hasLength(1));
    expect(result.webSearchCalls.single.id, 'ws_live');
    expect(result.webSearchCalls.single.status, 'completed');
    expect(result.webSearchCalls.single.actionType, 'search');
    expect(result.webSearchCalls.single.startedAtMs, isNotNull);
    expect(result.webSearchCalls.single.completedAtMs, isNotNull);
    expect(result.webSearchCalls.single.durationMs, greaterThanOrEqualTo(0));
    expect(
      result.webSearchCalls.single.queries.single,
      'Responses API web_search_call url_citation fields',
    );
    expect(result.webSearchCalls.single.sources, hasLength(1));
    expect(result.citations, hasLength(1));
    expect(webSearchEvents.length, greaterThanOrEqualTo(3));
    expect(
      webSearchEvents
          .map((Map<String, dynamic> e) => e['call'])
          .whereType<Map>()
          .map((Map e) => e['status'])
          .toList(),
      containsAllInOrder(<String>['in_progress', 'searching', 'completed']),
    );
    expect(citationEvents, hasLength(1));
  });
}
