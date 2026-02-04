import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_settings_service.dart';
import 'flutter_logger.dart';

/// 统一的网关事件类型
class AIGatewayEventKind {
  static const String content = 'content';
  static const String reasoning = 'reasoning';
}

/// 流式事件（内容或思考增量）
class AIGatewayEvent {
  const AIGatewayEvent(this.kind, this.data);

  final String kind;
  final String data;
}

/// 网关的最终响应结果
class AIGatewayResult {
  const AIGatewayResult({
    required this.content,
    required this.modelUsed,
    this.toolCalls = const <AIToolCall>[],
    this.reasoning,
    this.reasoningDuration,
  });

  final String content;
  final String modelUsed;
  final List<AIToolCall> toolCalls;
  final String? reasoning;
  final Duration? reasoningDuration;
}

/// OpenAI function-calling tool call (Chat Completions compatible)
class AIToolCall {
  const AIToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;

  Map<String, dynamic> toOpenAIToolCallJson() => <String, dynamic>{
        'id': id,
        'type': 'function',
        'function': <String, dynamic>{
          'name': name,
          'arguments': argumentsJson,
        },
      };
}

/// 网关流式会话，包含事件流与最终结果
class AIGatewayStreamingSession {
  AIGatewayStreamingSession({
    required Stream<AIGatewayEvent> stream,
    required Future<AIGatewayResult> completed,
  })  : stream = stream,
        completed = completed;

  final Stream<AIGatewayEvent> stream;
  final Future<AIGatewayResult> completed;
}

/// AI 请求网关：负责统一处理流式/非流式请求，并根据端点自动适配协议
class AIRequestGateway {
  AIRequestGateway._();

  static final AIRequestGateway instance = AIRequestGateway._();

  static const double _defaultTemperature = 0.2;
  int _fallbackToolCallSeq = 0;
  String _newFallbackToolCallId() => 'toolu_fallback_${++_fallbackToolCallSeq}';

  Future<AIGatewayResult> complete({
    required List<AIEndpoint> endpoints,
    required List<AIMessage> messages,
    required String responseStartMarker,
    Duration? timeout,
    bool preferStreaming = true,
    String? logContext,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
  }) async {
    if (endpoints.isEmpty) {
      throw Exception('No AI endpoints configured');
    }
    Exception? lastError;
    for (final AIEndpoint endpoint in endpoints) {
      // Try streaming first (when allowed), then fall back to non-streaming for
      // providers/endpoints that don't support SSE.
      if (preferStreaming) {
        try {
          final _PreparedRequest prepared = _prepareRequest(
            endpoint: endpoint,
            messages: messages,
            stream: true,
            tools: tools,
            toolChoice: toolChoice,
          );
          final _GatewayAggregate aggregate = await _performStreaming(
            prepared: prepared,
            responseStartMarker: responseStartMarker,
            timeout: timeout,
            logContext: logContext,
          );
          return AIGatewayResult(
            content: aggregate.content,
            toolCalls: aggregate.toolCalls,
            reasoning: aggregate.reasoning,
            reasoningDuration: aggregate.reasoningDuration,
            modelUsed: endpoint.model,
          );
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          try {
            await FlutterLogger.nativeWarn(
              'AI',
              '[网关] 流式失败，回退非流式（${endpoint.baseUrl}）：$e',
            );
          } catch (_) {}
        }
      }

      try {
        final _PreparedRequest prepared = _prepareRequest(
          endpoint: endpoint,
          messages: messages,
          stream: false,
          tools: tools,
          toolChoice: toolChoice,
        );
        final _GatewayAggregate aggregate = await _performNonStreaming(
          prepared: prepared,
          responseStartMarker: responseStartMarker,
          timeout: timeout,
          logContext: logContext,
        );
        return AIGatewayResult(
          content: aggregate.content,
          toolCalls: aggregate.toolCalls,
          reasoning: aggregate.reasoning,
          reasoningDuration: aggregate.reasoningDuration,
          modelUsed: endpoint.model,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        continue;
      }
    }
    throw lastError ?? Exception('No valid AI endpoint available');
  }

  AIGatewayStreamingSession startStreaming({
    required List<AIEndpoint> endpoints,
    required List<AIMessage> messages,
    required String responseStartMarker,
    Duration? timeout,
    String? logContext,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
  }) {
    if (endpoints.isEmpty) {
      final StreamController<AIGatewayEvent> empty = StreamController<AIGatewayEvent>();
      empty.close();
      return AIGatewayStreamingSession(
        stream: empty.stream,
        completed: Future<AIGatewayResult>.error(
          Exception('No AI endpoints configured'),
        ),
      );
    }

    final StreamController<AIGatewayEvent> controller = StreamController<AIGatewayEvent>();
    final Completer<AIGatewayResult> completer = Completer<AIGatewayResult>();

    () async {
      Exception? lastError;
      for (final AIEndpoint endpoint in endpoints) {
        StreamController<AIGatewayEvent>? proxy;
        StreamSubscription<AIGatewayEvent>? sub;
        int emittedCount = 0;
        try {
          proxy = StreamController<AIGatewayEvent>(sync: true);
          sub = proxy.stream.listen((AIGatewayEvent event) {
            emittedCount += 1;
            if (!controller.isClosed) {
              controller.add(event);
            }
          });
          final _PreparedRequest prepared = _prepareRequest(
            endpoint: endpoint,
            messages: messages,
            stream: true,
            tools: tools,
            toolChoice: toolChoice,
          );

          final _GatewayAggregate aggregate = await _performStreaming(
            prepared: prepared,
            responseStartMarker: responseStartMarker,
            timeout: timeout,
            logContext: logContext,
            controller: proxy,
          );
          if (!completer.isCompleted) {
            completer.complete(
              AIGatewayResult(
                content: aggregate.content,
                toolCalls: aggregate.toolCalls,
                reasoning: aggregate.reasoning,
                reasoningDuration: aggregate.reasoningDuration,
                modelUsed: endpoint.model,
              ),
            );
          }
          await controller.close();
          return;
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          try {
            await FlutterLogger.nativeWarn(
              'AI',
              '[网关] 流式错误（${endpoint.baseUrl}）：$e',
            );
          } catch (_) {}

          // If we already emitted partial tokens, do not mix outputs from a
          // different attempt (fallback or another endpoint).
          if (emittedCount > 0) {
            break;
          }

          // Otherwise, try a best-effort non-streaming fallback for endpoints
          // that don't support SSE and still surface the result via the stream
          // as a single "content" event.
          try {
            await FlutterLogger.nativeWarn(
              'AI',
              '[网关] 尝试非流式回退（${endpoint.baseUrl}）',
            );
          } catch (_) {}
          try {
            final _PreparedRequest prepared = _prepareRequest(
              endpoint: endpoint,
              messages: messages,
              stream: false,
              tools: tools,
              toolChoice: toolChoice,
            );
            final _GatewayAggregate aggregate = await _performNonStreaming(
              prepared: prepared,
              responseStartMarker: responseStartMarker,
              timeout: timeout,
              logContext: logContext,
              controller: controller,
            );
            if (!completer.isCompleted) {
              completer.complete(
                AIGatewayResult(
                  content: aggregate.content,
                  toolCalls: aggregate.toolCalls,
                  reasoning: aggregate.reasoning,
                  reasoningDuration: aggregate.reasoningDuration,
                  modelUsed: endpoint.model,
                ),
              );
            }
            await controller.close();
            return;
          } catch (fallbackErr) {
            lastError = fallbackErr is Exception
                ? fallbackErr
                : Exception(fallbackErr.toString());
            continue;
          }
        } finally {
          try {
            await sub?.cancel();
          } catch (_) {}
          try {
            await proxy?.close();
          } catch (_) {}
        }
      }
      if (!completer.isCompleted) {
        completer.completeError(lastError ?? Exception('No valid AI endpoint available'));
      }
      if (!controller.isClosed) {
        if (lastError != null) {
          controller.addError(lastError);
        }
        await controller.close();
      }
    }();

    return AIGatewayStreamingSession(
      stream: controller.stream,
      completed: completer.future,
    );
  }

  bool _supportsStreaming(_PreparedRequest prepared) {
    return true;
  }

  _PreparedRequest _prepareRequest({
    required AIEndpoint endpoint,
    required List<AIMessage> messages,
    required bool stream,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
  }) {
    final String trimmedBase = endpoint.baseUrl.trim();
    final Uri baseUri = _resolveBaseUri(trimmedBase);
    final bool isGoogle = _isGoogleBase(baseUri);
    final String? apiKey = endpoint.apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key is empty');
    }

    if (isGoogle) {
      final String method = stream ? 'streamGenerateContent' : 'generateContent';
      Uri uri = baseUri.resolve(
        '/v1beta/models/${Uri.encodeComponent(endpoint.model)}:$method',
      );
      if (stream) {
        uri = uri.replace(queryParameters: const <String, String>{'alt': 'sse'});
      }
      final Map<String, dynamic> payload = _buildGooglePayload(messages);
      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
        if (stream) 'Accept': 'text/event-stream',
      };
      return _PreparedRequest(
        uri: uri,
        headers: headers,
        body: jsonEncode(payload),
        isGoogle: true,
        hasTools: false,
      );
    }

    final Uri uri = _buildEndpointUriFromBase(baseUri, endpoint.chatPath);
    final Map<String, dynamic> payload = <String, dynamic>{
      'model': endpoint.model,
      'messages': messages.map((AIMessage m) => m.toJson()).toList(),
      'temperature': _defaultTemperature,
      'stream': stream,
    };
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      if (toolChoice != null) {
        payload['tool_choice'] = toolChoice;
      }
    }
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      if (stream) 'Accept': 'text/event-stream',
    };
    return _PreparedRequest(
      uri: uri,
      headers: headers,
      body: jsonEncode(payload),
      isGoogle: false,
      hasTools: tools.isNotEmpty,
    );
  }

  Map<String, dynamic> _buildGooglePayload(List<AIMessage> messages) {
    final List<Map<String, dynamic>> contents = <Map<String, dynamic>>[];
    final List<Map<String, String>> systemParts = <Map<String, String>>[];
    for (final AIMessage m in messages) {
      final String text = m.content.trim();
      if (text.isEmpty) continue;
      if (m.role == 'system') {
        systemParts.add(<String, String>{'text': text});
        continue;
      }
      final String role = m.role == 'assistant' ? 'model' : 'user';
      contents.add(<String, dynamic>{
        'role': role,
        'parts': <Map<String, String>>[
          <String, String>{'text': text},
        ],
      });
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      'contents': contents,
      'generationConfig': <String, dynamic>{
        'temperature': _defaultTemperature,
      },
    };
    if (systemParts.isNotEmpty) {
      payload['system_instruction'] = <String, dynamic>{
        'parts': systemParts,
      };
    }
    return payload;
  }

  Future<_GatewayAggregate> _performNonStreaming({
    required _PreparedRequest prepared,
    required String responseStartMarker,
    Duration? timeout,
    String? logContext,
    StreamController<AIGatewayEvent>? controller,
  }) async {
    try {
      await FlutterLogger.nativeDebug(
        'AI',
        '[网关] HTTP POST ${prepared.uri} (log=$logContext) 请求体长度=${prepared.body.length}',
      );
    } catch (_) {}

    final Future<http.Response> future =
        http.post(prepared.uri, headers: prepared.headers, body: prepared.body);
    final http.Response response = timeout == null
        ? await future
        : await future.timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Request failed: ${response.statusCode} ${response.body}',
      );
    }

    try {
      await FlutterLogger.nativeDebug(
        'AI',
        '[网关] HTTP 响应 ${response.statusCode} (log=$logContext) 响应体长度=${response.body.length}',
      );
    } catch (_) {}

    if (prepared.isGoogle) {
      final _GoogleResponse parsed = _parseGoogleResponse(response.body);
      final String sanitized = _stripResponseStart(
        responseStartMarker,
        parsed.content,
      );
      if (parsed.reasoning != null && parsed.reasoning!.isNotEmpty) {
        controller?.add(AIGatewayEvent(
          AIGatewayEventKind.reasoning,
          parsed.reasoning!,
        ));
      }
      controller?.add(AIGatewayEvent(
        AIGatewayEventKind.content,
        sanitized,
      ));
      return _GatewayAggregate(
        content: sanitized,
        reasoning: parsed.reasoning,
        reasoningDuration: null,
      );
    }

    final _OpenAIResponse parsed = _parseOpenAIResponse(response.body);
    final bool hasToolCalls = parsed.toolCalls.isNotEmpty;
    final String sanitized = hasToolCalls
        ? _trimLeadingIgnorable(parsed.content)
        : _stripResponseStart(
            responseStartMarker,
            parsed.content,
          );
    if (parsed.reasoning != null && parsed.reasoning!.isNotEmpty) {
      controller?.add(AIGatewayEvent(
        AIGatewayEventKind.reasoning,
        parsed.reasoning!,
      ));
    }
    controller?.add(AIGatewayEvent(
      AIGatewayEventKind.content,
      sanitized,
    ));
    return _GatewayAggregate(
      content: sanitized,
      toolCalls: parsed.toolCalls,
      reasoning: parsed.reasoning,
      reasoningDuration: null,
    );
  }

  Future<_GatewayAggregate> _performStreaming({
    required _PreparedRequest prepared,
    required String responseStartMarker,
    Duration? timeout,
    String? logContext,
    StreamController<AIGatewayEvent>? controller,
  }) async {
    final http.Client client = http.Client();
    final _ResponseStartFilter startFilter = _ResponseStartFilter(responseStartMarker);
    final _ThinkStreamFilter thinkFilter = _ThinkStreamFilter();
    final _ToolCallAccumulator toolAccumulator = _ToolCallAccumulator(_newFallbackToolCallId);
    final StringBuffer contentBuffer = StringBuffer();
    final StringBuffer reasoningBuffer = StringBuffer();
    final DateTime reasoningStart = DateTime.now();
    String googleLastContent = '';
    String googleLastThought = '';

    try {
      final http.Request request = http.Request('POST', prepared.uri)
        ..headers.addAll(prepared.headers)
        ..body = prepared.body;
      try {
        await FlutterLogger.nativeDebug(
          'AI',
          '[网关] HTTP 流式 POST ${prepared.uri} (log=$logContext) 请求体长度=${prepared.body.length}',
        );
      } catch (_) {}
      final Future<http.StreamedResponse> sendFuture = client.send(request);
      final http.StreamedResponse streamed =
          timeout == null ? await sendFuture : await sendFuture.timeout(timeout);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final http.Response failure = await http.Response.fromStream(streamed);
        throw Exception(
          'Request failed: ${streamed.statusCode} ${failure.body}',
        );
      }

      String buffer = '';
      bool done = false;
      bool sawData = false;
      final Stream<String> decoded = timeout == null
          ? streamed.stream.transform(utf8.decoder)
          : streamed.stream.transform(utf8.decoder).timeout(timeout);
      await for (final String chunk in decoded) {
        buffer += chunk;
        while (true) {
          final int idx = buffer.indexOf('\n');
          if (idx == -1) break;
          final String line = buffer.substring(0, idx).trimRight();
          buffer = buffer.substring(idx + 1);
          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;
          final String data = line.substring(5).trim();
          if (data == '[DONE]') {
            done = true;
            buffer = '';
            break;
          }
          if (data.isNotEmpty) {
            sawData = true;
          }
          Map<String, dynamic> json;
          try {
            json = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }

          if (prepared.isGoogle) {
            final _GoogleStreamParts chunk = _extractGoogleStreamParts(json);

            // Visible content parts (thought=false). Still run through the <think> filter for
            // OpenAI-compatible relays that embed tags in plain text.
            if (chunk.content.isNotEmpty) {
              final String delta = _deltaFromPossiblyCumulative(
                previous: googleLastContent,
                incoming: chunk.content,
              );
              if (delta.isNotEmpty) {
                googleLastContent = _updateCumulativeProbe(
                  previous: googleLastContent,
                  incoming: chunk.content,
                );
                final _ThinkStreamFilterResult r = thinkFilter.process(delta);
                if (r.visibleDelta.isNotEmpty) {
                  final String? sanitized = startFilter.process(r.visibleDelta);
                  if (sanitized != null && sanitized.isNotEmpty) {
                    contentBuffer.write(sanitized);
                    controller?.add(AIGatewayEvent(
                      AIGatewayEventKind.content,
                      sanitized,
                    ));
                  }
                }
                if (r.reasoningDelta.isNotEmpty) {
                  reasoningBuffer.write(r.reasoningDelta);
                  controller?.add(AIGatewayEvent(
                    AIGatewayEventKind.reasoning,
                    r.reasoningDelta,
                  ));
                }
              }
            }

            // Gemini thinking mode may stream chain-of-thought as parts with `thought=true`.
            // Treat them as reasoning (never as content).
            if (chunk.thought.isNotEmpty) {
              final String delta = _deltaFromPossiblyCumulative(
                previous: googleLastThought,
                incoming: chunk.thought,
              );
              if (delta.isNotEmpty) {
                googleLastThought = _updateCumulativeProbe(
                  previous: googleLastThought,
                  incoming: chunk.thought,
                );
                reasoningBuffer.write(delta);
                controller?.add(AIGatewayEvent(
                  AIGatewayEventKind.reasoning,
                  delta,
                ));
              }
            }
            continue;
          }

          final dynamic type = json['type'];
          if (type is String) {
            if (type == 'response.completed') {
              done = true;
              continue;
            }
            if (type == 'response.reasoning_summary_text.delta') {
              final dynamic delta = json['delta'];
              if (delta is String && delta.isNotEmpty) {
                reasoningBuffer.write(delta);
                controller?.add(AIGatewayEvent(
                  AIGatewayEventKind.reasoning,
                  delta,
                ));
              }
              continue;
            }
            if (type == 'response.output_text.delta') {
              final dynamic delta = json['delta'];
              if (delta is String && delta.isNotEmpty) {
                final _ThinkStreamFilterResult r = thinkFilter.process(delta);
                if (r.visibleDelta.isNotEmpty) {
                  final String? sanitized = startFilter.process(r.visibleDelta);
                  if (sanitized != null && sanitized.isNotEmpty) {
                    contentBuffer.write(sanitized);
                    controller?.add(AIGatewayEvent(
                      AIGatewayEventKind.content,
                      sanitized,
                    ));
                  }
                }
                if (r.reasoningDelta.isNotEmpty) {
                  reasoningBuffer.write(r.reasoningDelta);
                  controller?.add(AIGatewayEvent(
                    AIGatewayEventKind.reasoning,
                    r.reasoningDelta,
                  ));
                }
              }
              continue;
            }
          }

          final dynamic choices = json['choices'];
          if (choices is List && choices.isNotEmpty) {
            final dynamic first = choices.first;
            if (first is Map<String, dynamic>) {
              final dynamic finishReason = first['finish_reason'];
              if (finishReason is String && finishReason.isNotEmpty && finishReason != 'null') {
                done = true;
              }
              final dynamic delta = first['delta'];
              if (delta is Map<String, dynamic>) {
                toolAccumulator.ingestChatDelta(delta);
                final dynamic reasoningPart = delta['reasoning_content'] ??
                    (delta['reasoning'] is Map
                        ? (delta['reasoning']['content'])
                        : null) ??
                    delta['thinking'];
                if (reasoningPart is String && reasoningPart.isNotEmpty) {
                  reasoningBuffer.write(reasoningPart);
                  controller?.add(AIGatewayEvent(
                    AIGatewayEventKind.reasoning,
                    reasoningPart,
                  ));
                }
                final dynamic part = delta['content'];
                if (part is String && part.isNotEmpty) {
                  final _ThinkStreamFilterResult r = thinkFilter.process(part);
                  if (r.visibleDelta.isNotEmpty) {
                    final String? sanitized = startFilter.process(r.visibleDelta);
                    if (sanitized != null && sanitized.isNotEmpty) {
                      contentBuffer.write(sanitized);
                      controller?.add(AIGatewayEvent(
                        AIGatewayEventKind.content,
                        sanitized,
                      ));
                    }
                  }
                  if (r.reasoningDelta.isNotEmpty) {
                    reasoningBuffer.write(r.reasoningDelta);
                    controller?.add(AIGatewayEvent(
                      AIGatewayEventKind.reasoning,
                      r.reasoningDelta,
                    ));
                  }
                }
              }
            }
          }
          if (done) {
            buffer = '';
            break;
          }
        }
        if (done) break;
      }
      if (!sawData) {
        throw Exception('Streaming not supported: no SSE data received');
      }

      final String trailing = thinkFilter.finalize();
      if (trailing.isNotEmpty) {
        reasoningBuffer.write(trailing);
        controller?.add(AIGatewayEvent(
          AIGatewayEventKind.reasoning,
          trailing,
        ));
      }
      startFilter.ensureCompleted();

      final String cleanedContent = contentBuffer
          .toString()
          .replaceAll(RegExp(r'</?think>'), '');
      final List<AIToolCall> toolCalls = toolAccumulator.finalize();
      final String reasoningText = reasoningBuffer.toString();
      final Duration? reasoningDuration =
          reasoningText.isEmpty ? null : DateTime.now().difference(reasoningStart);
      return _GatewayAggregate(
        content: cleanedContent,
        toolCalls: toolCalls,
        reasoning: reasoningText.isEmpty ? null : reasoningText,
        reasoningDuration: reasoningDuration,
      );
    } finally {
      client.close();
    }
  }

  _OpenAIResponse _parseOpenAIResponse(String body) {
    final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;
    if (data['output'] is List) {
      final List<dynamic> outs = (data['output'] as List).cast<dynamic>();
      final StringBuffer cbuf = StringBuffer();
      final StringBuffer rbuf = StringBuffer();
      final List<AIToolCall> toolCalls = <AIToolCall>[];
      for (final dynamic it in outs) {
        if (it is! Map<String, dynamic>) continue;
        final dynamic type = it['type'];
        if (type == 'reasoning') {
          final dynamic summary = it['summary'];
          if (summary is List) {
            for (final dynamic p in summary) {
              if (p is Map<String, dynamic> && p['type'] == 'summary_text') {
                final String txt = (p['text'] as String?) ?? '';
                if (txt.isNotEmpty) {
                  if (rbuf.isNotEmpty) rbuf.write('\n');
                  rbuf.write(txt);
                }
              }
            }
          }
        } else if (type == 'tool_call' || type == 'function_call') {
          final String id = (it['id'] as String?) ?? '';
          final Map<String, dynamic>? fn = it['function'] is Map
              ? (it['function'] as Map).cast<String, dynamic>()
              : null;
          final String name = fn?['name']?.toString() ?? (it['name']?.toString() ?? '');
          final String args = fn?['arguments']?.toString() ?? (it['arguments']?.toString() ?? '');
          if (name.trim().isNotEmpty) {
            toolCalls.add(AIToolCall(
              id: id.trim().isEmpty ? _newFallbackToolCallId() : id.trim(),
              name: name.trim(),
              argumentsJson: args,
            ));
          }
        } else if (type == 'message') {
          final dynamic cont = it['content'];
          if (cont is List) {
            for (final dynamic p in cont) {
              if (p is Map<String, dynamic> && p['type'] == 'output_text') {
                final String txt = (p['text'] as String?) ?? '';
                if (txt.isNotEmpty) cbuf.write(txt);
              }
            }
          }
        }
      }
      final String content = cbuf.toString();
      final String reasoning = rbuf.toString();
      return _OpenAIResponse(
        content: content,
        toolCalls: toolCalls,
        reasoning: reasoning.isEmpty ? null : reasoning,
      );
    }

    final List<dynamic>? choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Empty choices');
    }
    final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
    final Map<String, dynamic>? message =
        first['message'] as Map<String, dynamic>?;
    if (message == null) {
      throw Exception('Invalid response');
    }
    final String content = (message['content'] as String?) ?? '';
    final List<AIToolCall> toolCalls = <AIToolCall>[];
    final dynamic toolCallsRaw = message['tool_calls'];
    if (toolCallsRaw is List) {
      for (final dynamic tc in toolCallsRaw) {
        if (tc is! Map) continue;
        final map = Map<String, dynamic>.from(tc as Map);
        final String id = (map['id'] as String?) ?? '';
        final Map<String, dynamic>? fn = map['function'] is Map
            ? Map<String, dynamic>.from(map['function'] as Map)
            : null;
        final String name = (fn?['name'] as String?) ?? '';
        final String args = (fn?['arguments'] as String?) ?? '';
        if (name.trim().isEmpty) continue;
        toolCalls.add(AIToolCall(
          id: id.trim().isEmpty ? _newFallbackToolCallId() : id.trim(),
          name: name.trim(),
          argumentsJson: args,
        ));
      }
    } else {
      final dynamic fc = message['function_call'];
      if (fc is Map) {
        final Map<String, dynamic> fn = Map<String, dynamic>.from(fc as Map);
        final String name = (fn['name'] as String?) ?? '';
        final String args = (fn['arguments'] as String?) ?? '';
        if (name.trim().isNotEmpty) {
          toolCalls.add(AIToolCall(
            id: 'function_call',
            name: name.trim(),
            argumentsJson: args,
          ));
        }
      }
    }
    final String? reasoning = ((message['reasoning_content'] as String?) ??
            (message['reasoning'] as String?) ??
            (message['thinking'] as String?))
        ?.trim();
    return _OpenAIResponse(
      content: content,
      toolCalls: toolCalls,
      reasoning: reasoning?.isEmpty == true ? null : reasoning,
    );
  }

  _GoogleResponse _parseGoogleResponse(String body) {
    final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;
    final List<dynamic>? candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Empty candidates');
    }
    final Map<String, dynamic>? first = candidates.first as Map<String, dynamic>?;
    if (first == null) {
      throw Exception('Invalid candidate');
    }
    final Map<String, dynamic>? contentObj =
        first['content'] as Map<String, dynamic>?;
    if (contentObj == null) {
      throw Exception('Missing content');
    }
    final List<dynamic>? parts = contentObj['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Empty parts');
    }

    final StringBuffer content = StringBuffer();
    final StringBuffer reasoning = StringBuffer();
    for (final dynamic part in parts) {
      if (part is! Map<String, dynamic>) continue;
      final String text = (part['text'] as String?) ?? '';
      if (text.isEmpty) continue;
      final bool thought = (part['thought'] as bool?) ?? false;
      if (thought) {
        if (reasoning.isNotEmpty) reasoning.write('\n');
        reasoning.write(text);
      } else {
        content.write(text);
      }
    }
    return _GoogleResponse(
      content: content.toString(),
      reasoning: reasoning.isEmpty ? null : reasoning.toString(),
    );
  }

  bool _isGoogleBase(Uri baseUri) {
    final String host = baseUri.host.toLowerCase();
    return host.contains('googleapis.com') || host.contains('generativelanguage');
  }

  Uri _buildEndpointUriFromBase(Uri baseUri, String path) {
    final String trimmedPath = path.trim();
    final String effectivePath = trimmedPath.isEmpty
        ? '/v1/chat/completions'
        : (trimmedPath.startsWith('/') ? trimmedPath : '/$trimmedPath');
    return baseUri.resolve(effectivePath);
  }

  Uri _resolveBaseUri(String base) {
    final String trimmed = base.trim();
    if (trimmed.isEmpty) {
      throw InvalidEndpointConfigurationException('Base URL is empty');
    }
    Uri? parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed;
    }
    parsed = Uri.tryParse('https://$trimmed');
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed;
    }
    throw InvalidEndpointConfigurationException('Invalid base URL: $trimmed');
  }

  String _stripResponseStart(String marker, String text) {
    final String sanitized = _trimLeadingIgnorable(text);

    // Marker is a best-effort protocol hint. Some models/endpoints may ignore it
    // (e.g. returning fenced JSON). In those cases, fall back to returning the
    // raw sanitized content instead of hard-failing the whole chat flow.
    if (marker.trim().isEmpty) return sanitized;

    int idx = sanitized.indexOf(marker);
    if (idx < 0) return sanitized;

    String remainder = sanitized.substring(idx + marker.length);
    if (remainder.startsWith('\r\n')) {
      remainder = remainder.substring(2);
    } else if (remainder.startsWith('\n')) {
      remainder = remainder.substring(1);
    }
    return remainder;
  }
}

class InvalidResponseStartException implements Exception {
  InvalidResponseStartException(this.marker, this.receivedPreview);

  final String marker;
  final String receivedPreview;

  @override
  String toString() {
    final String preview = receivedPreview.length > 160
        ? '${receivedPreview.substring(0, 160)}…'
        : receivedPreview;
    return 'Invalid response start: expected marker "$marker" but received "$preview"';
  }
}

class InvalidEndpointConfigurationException implements Exception {
  InvalidEndpointConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'InvalidEndpointConfigurationException: $message';
}

class _GatewayAggregate {
  const _GatewayAggregate({
    required this.content,
    this.toolCalls = const <AIToolCall>[],
    this.reasoning,
    this.reasoningDuration,
  });

  final String content;
  final List<AIToolCall> toolCalls;
  final String? reasoning;
  final Duration? reasoningDuration;
}

class _OpenAIResponse {
  const _OpenAIResponse({
    required this.content,
    this.toolCalls = const <AIToolCall>[],
    this.reasoning,
  });

  final String content;
  final List<AIToolCall> toolCalls;
  final String? reasoning;
}

class _GoogleResponse {
  const _GoogleResponse({
    required this.content,
    this.reasoning,
  });

  final String content;
  final String? reasoning;
}

class _PreparedRequest {
  const _PreparedRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.isGoogle,
    required this.hasTools,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final bool isGoogle;
  final bool hasTools;
}

class _GoogleStreamParts {
  const _GoogleStreamParts({
    required this.content,
    required this.thought,
  });

  final String content;
  final String thought;
}

_GoogleStreamParts _extractGoogleStreamParts(Map<String, dynamic> json) {
  final dynamic candidates = json['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    return const _GoogleStreamParts(content: '', thought: '');
  }
  final dynamic first = candidates.first;
  if (first is! Map) return const _GoogleStreamParts(content: '', thought: '');
  final Map<String, dynamic> candidate = Map<String, dynamic>.from(first as Map);
  final dynamic content = candidate['content'];
  if (content is! Map) return const _GoogleStreamParts(content: '', thought: '');
  final Map<String, dynamic> contentMap = Map<String, dynamic>.from(content as Map);
  final dynamic parts = contentMap['parts'];
  if (parts is! List || parts.isEmpty) {
    return const _GoogleStreamParts(content: '', thought: '');
  }
  final StringBuffer contentOut = StringBuffer();
  final StringBuffer thoughtOut = StringBuffer();
  for (final dynamic p in parts) {
    if (p is! Map) continue;
    final Map<String, dynamic> part = Map<String, dynamic>.from(p as Map);
    final dynamic text = part['text'];
    if (text is String && text.isNotEmpty) {
      final bool thought = (part['thought'] as bool?) ?? false;
      if (thought) {
        thoughtOut.write(text);
      } else {
        contentOut.write(text);
      }
    }
  }
  return _GoogleStreamParts(
    content: contentOut.toString(),
    thought: thoughtOut.toString(),
  );
}

String _deltaFromPossiblyCumulative({
  required String previous,
  required String incoming,
}) {
  if (incoming.isEmpty) return '';
  if (previous.isEmpty) return incoming;
  if (incoming.startsWith(previous)) {
    return incoming.substring(previous.length);
  }
  if (previous.startsWith(incoming)) {
    return '';
  }
  return incoming;
}

String _updateCumulativeProbe({
  required String previous,
  required String incoming,
}) {
  if (incoming.isEmpty) return previous;
  if (previous.isEmpty) return incoming;
  if (incoming.startsWith(previous)) {
    return incoming;
  }
  if (previous.startsWith(incoming)) {
    return previous;
  }
  return previous + incoming;
}

class _ToolCallDraft {
  _ToolCallDraft(this.index);

  final int index;
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  void mergeFromChunk(Map<String, dynamic> chunk) {
    final String idPart = (chunk['id'] as String?) ?? '';
    if (idPart.trim().isNotEmpty) {
      id = idPart.trim();
    }
    final Map<String, dynamic>? fn = chunk['function'] is Map
        ? Map<String, dynamic>.from(chunk['function'] as Map)
        : null;
    final String namePart = (fn?['name'] as String?) ??
        (chunk['name'] as String?) ??
        '';
    if (namePart.trim().isNotEmpty) {
      name = namePart.trim();
    }
    final String argsPart = (fn?['arguments'] as String?) ??
        (chunk['arguments'] as String?) ??
        '';
    if (argsPart.isNotEmpty) {
      arguments.write(argsPart);
    }
  }

  AIToolCall? toToolCall(String Function() newId) {
    if (name.trim().isEmpty) return null;
    final String resolvedId = id.trim().isEmpty ? newId() : id.trim();
    return AIToolCall(
      id: resolvedId,
      name: name.trim(),
      argumentsJson: arguments.toString(),
    );
  }
}

class _ToolCallAccumulator {
  _ToolCallAccumulator(this._newId);

  final String Function() _newId;
  final Map<int, _ToolCallDraft> _drafts = <int, _ToolCallDraft>{};

  void ingestChatDelta(Map<String, dynamic> delta) {
    final dynamic toolCalls = delta['tool_calls'] ?? delta['toolCalls'];
    if (toolCalls is List) {
      for (int i = 0; i < toolCalls.length; i += 1) {
        final dynamic raw = toolCalls[i];
        if (raw is! Map) continue;
        final Map<String, dynamic> chunk = Map<String, dynamic>.from(raw as Map);
        final dynamic idxRaw = chunk['index'];
        final int idx = idxRaw is int ? idxRaw : i;
        final _ToolCallDraft draft =
            _drafts.putIfAbsent(idx, () => _ToolCallDraft(idx));
        draft.mergeFromChunk(chunk);
      }
    }

    final dynamic functionCall = delta['function_call'] ?? delta['functionCall'];
    if (functionCall is Map) {
      final Map<String, dynamic> chunk = Map<String, dynamic>.from(functionCall as Map);
      final _ToolCallDraft draft =
          _drafts.putIfAbsent(0, () => _ToolCallDraft(0));
      draft.mergeFromChunk(chunk);
    }
  }

  List<AIToolCall> finalize() {
    if (_drafts.isEmpty) return const <AIToolCall>[];
    final List<int> indices = _drafts.keys.toList()..sort();
    final List<AIToolCall> out = <AIToolCall>[];
    for (final int idx in indices) {
      final _ToolCallDraft? draft = _drafts[idx];
      if (draft == null) continue;
      final AIToolCall? call = draft.toToolCall(_newId);
      if (call != null) {
        out.add(call);
      }
    }
    return out;
  }
}

class _ThinkStreamFilterResult {
  const _ThinkStreamFilterResult(this.visibleDelta, this.reasoningDelta);

  final String visibleDelta;
  final String reasoningDelta;
}

class _ThinkStreamFilter {
  bool _insideThink = false;

  _ThinkStreamFilterResult process(String chunk) {
    if (chunk.isEmpty) return const _ThinkStreamFilterResult('', '');
    final StringBuffer visible = StringBuffer();
    final StringBuffer reasoning = StringBuffer();
    int index = 0;
    while (index < chunk.length) {
      if (_insideThink) {
        final int closeIdx = chunk.indexOf('</think>', index);
        if (closeIdx == -1) {
          reasoning.write(chunk.substring(index));
          index = chunk.length;
          break;
        } else {
          reasoning.write(chunk.substring(index, closeIdx));
          index = closeIdx + 8;
          _insideThink = false;
        }
      } else {
        final int openIdx = chunk.indexOf('<think>', index);
        final int closeIdx = chunk.indexOf('</think>', index);
        if (openIdx == -1 && closeIdx == -1) {
          visible.write(chunk.substring(index));
          index = chunk.length;
          break;
        }
        if (closeIdx != -1 && (openIdx == -1 || closeIdx < openIdx)) {
          visible.write(chunk.substring(index, closeIdx));
          index = closeIdx + 8;
          continue;
        }
        if (openIdx != -1) {
          visible.write(chunk.substring(index, openIdx));
          index = openIdx + 7;
          _insideThink = true;
          continue;
        }
        index = chunk.length;
      }
    }
    return _ThinkStreamFilterResult(visible.toString(), reasoning.toString());
  }

  String finalize() {
    _insideThink = false;
    return '';
  }
}

class _ResponseStartFilter {
  _ResponseStartFilter(this.marker);

  final String marker;
  String _buffer = '';
  bool _awaiting = true;

  String? process(String chunk) {
    if (marker.trim().isEmpty) return chunk;
    if (!_awaiting) return chunk;
    if (chunk.isEmpty) return '';
    int index = 0;
    while (index < chunk.length) {
      final String char = chunk[index];
      if (_awaiting && _buffer.isEmpty && _isIgnorableLeadingChar(char)) {
        index++;
        continue;
      }
      _buffer += char;
      if (!marker.startsWith(_buffer)) {
        _awaiting = false;
        final String passthrough = _buffer + chunk.substring(index + 1);
        _buffer = '';
        return passthrough;
      }
      index++;
      if (_buffer.length == marker.length) {
        _awaiting = false;
        _buffer = '';
        String remainder = chunk.substring(index);
        if (remainder.startsWith('\r\n')) {
          remainder = remainder.substring(2);
        } else if (remainder.startsWith('\n')) {
          remainder = remainder.substring(1);
        }
        return remainder;
      }
    }
    return null;
  }

  void ensureCompleted() {
    // Best-effort: if the marker never appears, do not fail the entire stream.
    _awaiting = false;
  }
}

bool _isIgnorableLeadingChar(String char) {
  if (char.isEmpty) return false;
  if (char == '\ufeff') return true; // BOM
  return char.trim().isEmpty;
}

String _trimLeadingIgnorable(String text) {
  int index = 0;
  while (index < text.length) {
    final String char = text[index];
    if (!_isIgnorableLeadingChar(char)) break;
    index++;
  }
  if (index == 0) return text;
  return text.substring(index);
}

