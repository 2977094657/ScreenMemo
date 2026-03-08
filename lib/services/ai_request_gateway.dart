import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'openai_responses_extract.dart';

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
    this.usagePromptTokens,
    this.usageCompletionTokens,
    this.usageTotalTokens,
  });

  final String content;
  final String modelUsed;
  final List<AIToolCall> toolCalls;
  final String? reasoning;
  final Duration? reasoningDuration;
  final int? usagePromptTokens;
  final int? usageCompletionTokens;
  final int? usageTotalTokens;
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
    'function': <String, dynamic>{'name': name, 'arguments': argumentsJson},
  };
}

/// 网关流式会话，包含事件流与最终结果
class AIGatewayStreamingSession {
  AIGatewayStreamingSession({
    required Stream<AIGatewayEvent> stream,
    required Future<AIGatewayResult> completed,
  }) : stream = stream,
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
  int _traceSeq = 0;
  String _newTraceId() =>
      'trace_${DateTime.now().millisecondsSinceEpoch}_${++_traceSeq}';

  int _countInputImages(List<AIMessage> messages) {
    int count = 0;
    for (final AIMessage m in messages) {
      final Object? api = m.apiContent;
      if (api is! List) continue;
      for (final dynamic raw in api) {
        if (raw is! Map) continue;
        final Map<String, dynamic> map = Map<String, dynamic>.from(raw as Map);
        final String type = (map['type'] as String? ?? '').trim().toLowerCase();
        if (type == 'image_url' || type == 'input_image') {
          count += 1;
        }
      }
    }
    return count;
  }

  Future<AIGatewayResult> complete({
    required List<AIEndpoint> endpoints,
    required List<AIMessage> messages,
    required String responseStartMarker,
    Duration? timeout,
    bool preferStreaming = true,
    String? logContext,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
    bool forceChatCompletions = false,
  }) async {
    if (endpoints.isEmpty) {
      throw Exception('No AI endpoints configured');
    }
    final int imagesCount = _countInputImages(messages);
    final int toolsCount = tools.length;
    Exception? lastError;
    for (final AIEndpoint endpoint in endpoints) {
      final AIEndpoint effectiveEndpoint = forceChatCompletions
          ? _forceChatCompletionsEndpoint(endpoint)
          : endpoint;
      // Try streaming first (when allowed), then fall back to non-streaming for
      // providers/endpoints that don't support SSE.
      if (preferStreaming) {
        try {
          final _PreparedRequest prepared = _prepareRequest(
            endpoint: effectiveEndpoint,
            messages: messages,
            stream: true,
            tools: tools,
            toolChoice: toolChoice,
            useResponsesApiOverride: forceChatCompletions ? false : null,
          );
          final _GatewayAggregate aggregate = await _performStreaming(
            endpoint: effectiveEndpoint,
            prepared: prepared,
            responseStartMarker: responseStartMarker,
            timeout: timeout,
            logContext: logContext,
            imagesCount: imagesCount,
            toolsCount: toolsCount,
          );
          return AIGatewayResult(
            content: aggregate.content,
            toolCalls: aggregate.toolCalls,
            reasoning: aggregate.reasoning,
            reasoningDuration: aggregate.reasoningDuration,
            modelUsed: endpoint.model,
            usagePromptTokens: aggregate.usage?.promptTokens,
            usageCompletionTokens: aggregate.usage?.completionTokens,
            usageTotalTokens: aggregate.usage?.totalTokens,
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

      _PreparedRequest? prepared;
      try {
        prepared = _prepareRequest(
          endpoint: effectiveEndpoint,
          messages: messages,
          stream: false,
          tools: tools,
          toolChoice: toolChoice,
          useResponsesApiOverride: forceChatCompletions ? false : null,
        );
        final _GatewayAggregate aggregate = await _performNonStreaming(
          endpoint: effectiveEndpoint,
          prepared: prepared,
          responseStartMarker: responseStartMarker,
          timeout: timeout,
          logContext: logContext,
          imagesCount: imagesCount,
          toolsCount: toolsCount,
        );
        return AIGatewayResult(
          content: aggregate.content,
          toolCalls: aggregate.toolCalls,
          reasoning: aggregate.reasoning,
          reasoningDuration: aggregate.reasoningDuration,
          modelUsed: endpoint.model,
          usagePromptTokens: aggregate.usage?.promptTokens,
          usageCompletionTokens: aggregate.usage?.completionTokens,
          usageTotalTokens: aggregate.usage?.totalTokens,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());

        // Some OpenAI-compatible relays incorrectly type `tool_choice` as a string
        // in the Responses API response DTOs, and crash when OpenAI returns an object
        // tool_choice (e.g. forced function calling). In that case, retry once using
        // Chat Completions to avoid the relay's Responses parsing path.
        if (prepared != null &&
            prepared.useResponsesApi &&
            _looksLikeGoToolChoiceUnmarshalError(lastError)) {
          try {
            await FlutterLogger.nativeWarn(
              'AI',
              '[网关] 检测到 tool_choice 兼容性错误，改用 Chat Completions 重试（${endpoint.baseUrl}）',
            );
          } catch (_) {}
          try {
            final AIEndpoint chatEndpoint = _forceChatCompletionsEndpoint(
              effectiveEndpoint,
            );
            final _PreparedRequest retryPrepared = _prepareRequest(
              endpoint: chatEndpoint,
              messages: messages,
              stream: false,
              tools: tools,
              toolChoice: toolChoice,
              useResponsesApiOverride: false,
            );
            final _GatewayAggregate aggregate = await _performNonStreaming(
              endpoint: chatEndpoint,
              prepared: retryPrepared,
              responseStartMarker: responseStartMarker,
              timeout: timeout,
              logContext: logContext,
              imagesCount: imagesCount,
              toolsCount: toolsCount,
            );
            return AIGatewayResult(
              content: aggregate.content,
              toolCalls: aggregate.toolCalls,
              reasoning: aggregate.reasoning,
              reasoningDuration: aggregate.reasoningDuration,
              modelUsed: chatEndpoint.model,
              usagePromptTokens: aggregate.usage?.promptTokens,
              usageCompletionTokens: aggregate.usage?.completionTokens,
              usageTotalTokens: aggregate.usage?.totalTokens,
            );
          } catch (retryErr) {
            lastError = retryErr is Exception
                ? retryErr
                : Exception(retryErr.toString());
          }
        }

        // Some "OpenAI-compatible" providers implement Chat Completions with a
        // non-standard tool_choice schema:
        // - OpenAI Chat Completions spec: {"type":"function","function":{"name":"..."}} (nested)
        // - some relays expect: {"type":"function","name":"..."} (flat)
        // When we detect that variant, retry once with the flat form.
        if (toolsCount > 0 &&
            toolChoice != null &&
            _looksLikeUnknownToolChoiceFunctionParam(lastError)) {
          final Object? flattenedToolChoice = _normalizeResponsesToolChoice(
            toolChoice,
          );
          if (flattenedToolChoice != null) {
            try {
              await FlutterLogger.nativeWarn(
                'AI',
                '[网关] tool_choice.function 不被支持，改用扁平 tool_choice{name} 重试（${endpoint.baseUrl}）',
              );
            } catch (_) {}
            try {
              final AIEndpoint chatEndpoint = _forceChatCompletionsEndpoint(
                effectiveEndpoint,
              );
              final _PreparedRequest retryPrepared = _prepareRequest(
                endpoint: chatEndpoint,
                messages: messages,
                stream: false,
                tools: tools,
                toolChoice: flattenedToolChoice,
                useResponsesApiOverride: false,
              );
              final _GatewayAggregate aggregate = await _performNonStreaming(
                endpoint: chatEndpoint,
                prepared: retryPrepared,
                responseStartMarker: responseStartMarker,
                timeout: timeout,
                logContext: logContext,
                imagesCount: imagesCount,
                toolsCount: toolsCount,
              );
              return AIGatewayResult(
                content: aggregate.content,
                toolCalls: aggregate.toolCalls,
                reasoning: aggregate.reasoning,
                reasoningDuration: aggregate.reasoningDuration,
                modelUsed: chatEndpoint.model,
                usagePromptTokens: aggregate.usage?.promptTokens,
                usageCompletionTokens: aggregate.usage?.completionTokens,
                usageTotalTokens: aggregate.usage?.totalTokens,
              );
            } catch (retryErr) {
              lastError = retryErr is Exception
                  ? retryErr
                  : Exception(retryErr.toString());
            }
          }
        }
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
    bool forceChatCompletions = false,
  }) {
    if (endpoints.isEmpty) {
      final StreamController<AIGatewayEvent> empty =
          StreamController<AIGatewayEvent>();
      empty.close();
      return AIGatewayStreamingSession(
        stream: empty.stream,
        completed: Future<AIGatewayResult>.error(
          Exception('No AI endpoints configured'),
        ),
      );
    }

    final int imagesCount = _countInputImages(messages);
    final int toolsCount = tools.length;

    final StreamController<AIGatewayEvent> controller =
        StreamController<AIGatewayEvent>();
    final Completer<AIGatewayResult> completer = Completer<AIGatewayResult>();

    () async {
      Exception? lastError;
      for (final AIEndpoint endpoint in endpoints) {
        final AIEndpoint effectiveEndpoint = forceChatCompletions
            ? _forceChatCompletionsEndpoint(endpoint)
            : endpoint;
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
            endpoint: effectiveEndpoint,
            messages: messages,
            stream: true,
            tools: tools,
            toolChoice: toolChoice,
            useResponsesApiOverride: forceChatCompletions ? false : null,
          );

          final _GatewayAggregate aggregate = await _performStreaming(
            endpoint: effectiveEndpoint,
            prepared: prepared,
            responseStartMarker: responseStartMarker,
            timeout: timeout,
            logContext: logContext,
            controller: proxy,
            imagesCount: imagesCount,
            toolsCount: toolsCount,
          );
          if (!completer.isCompleted) {
            completer.complete(
              AIGatewayResult(
                content: aggregate.content,
                toolCalls: aggregate.toolCalls,
                reasoning: aggregate.reasoning,
                reasoningDuration: aggregate.reasoningDuration,
                modelUsed: endpoint.model,
                usagePromptTokens: aggregate.usage?.promptTokens,
                usageCompletionTokens: aggregate.usage?.completionTokens,
                usageTotalTokens: aggregate.usage?.totalTokens,
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
              endpoint: endpoint,
              prepared: prepared,
              responseStartMarker: responseStartMarker,
              timeout: timeout,
              logContext: logContext,
              controller: controller,
              imagesCount: imagesCount,
              toolsCount: toolsCount,
            );
            if (!completer.isCompleted) {
              completer.complete(
                AIGatewayResult(
                  content: aggregate.content,
                  toolCalls: aggregate.toolCalls,
                  reasoning: aggregate.reasoning,
                  reasoningDuration: aggregate.reasoningDuration,
                  modelUsed: endpoint.model,
                  usagePromptTokens: aggregate.usage?.promptTokens,
                  usageCompletionTokens: aggregate.usage?.completionTokens,
                  usageTotalTokens: aggregate.usage?.totalTokens,
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
        completer.completeError(
          lastError ?? Exception('No valid AI endpoint available'),
        );
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
    bool? useResponsesApiOverride,
  }) {
    final String trimmedBase = endpoint.baseUrl.trim();
    final Uri baseUri = _resolveBaseUri(trimmedBase);
    final bool isGoogle = _isGoogleBase(baseUri);
    final String? apiKey = endpoint.apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key is empty');
    }

    if (isGoogle) {
      final String method = stream
          ? 'streamGenerateContent'
          : 'generateContent';
      Uri uri = baseUri.resolve(
        '/v1beta/models/${Uri.encodeComponent(endpoint.model)}:$method',
      );
      if (stream) {
        uri = uri.replace(
          queryParameters: const <String, String>{'alt': 'sse'},
        );
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
        useResponsesApi: false,
      );
    }

    final bool useResponsesApi =
        useResponsesApiOverride ??
        _shouldUseResponsesApi(
          endpoint: endpoint,
          baseUri: baseUri,
          tools: tools,
        );
    final Uri uri = useResponsesApi
        ? _buildResponsesUriFromBase(baseUri, endpoint.chatPath)
        : _buildEndpointUriFromBase(baseUri, endpoint.chatPath);
    final Map<String, dynamic> payload = useResponsesApi
        ? _buildResponsesPayload(
            endpoint: endpoint,
            messages: messages,
            stream: stream,
            tools: tools,
            toolChoice: toolChoice,
          )
        : _buildChatCompletionsPayload(
            endpoint: endpoint,
            messages: messages,
            stream: stream,
            tools: tools,
            toolChoice: toolChoice,
          );
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
      useResponsesApi: useResponsesApi,
    );
  }

  bool _looksLikeGoToolChoiceUnmarshalError(Object? error) {
    if (error == null) return false;
    final String t = error.toString().toLowerCase();
    if (!t.contains('cannot unmarshal object')) return false;
    if (!t.contains('go struct field')) return false;
    if (!t.contains('tool_choice')) return false;
    return true;
  }

  bool _looksLikeUnknownToolChoiceFunctionParam(Object? error) {
    if (error == null) return false;
    final String t = error.toString().toLowerCase();
    if (!t.contains('unknown parameter')) return false;
    if (!t.contains('tool_choice.function')) return false;
    return true;
  }

  AIEndpoint _forceChatCompletionsEndpoint(AIEndpoint endpoint) {
    final String path = endpoint.chatPath.trim();
    if (!_isResponsesPath(path)) return endpoint;
    return AIEndpoint(
      groupId: endpoint.groupId,
      providerId: endpoint.providerId,
      providerName: endpoint.providerName,
      providerType: endpoint.providerType,
      baseUrl: endpoint.baseUrl,
      apiKey: endpoint.apiKey,
      model: endpoint.model,
      chatPath: '/v1/chat/completions',
      useResponseApi: endpoint.useResponseApi,
    );
  }

  Map<String, dynamic> _buildGooglePayload(List<AIMessage> messages) {
    final List<Map<String, dynamic>> contents = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> systemParts = <Map<String, dynamic>>[];
    for (final AIMessage m in messages) {
      if (m.role == 'system') {
        final String text = m.content.trim();
        if (text.isNotEmpty) {
          systemParts.add(<String, dynamic>{'text': text});
        }
        continue;
      }
      final String role = m.role == 'assistant' ? 'model' : 'user';
      final List<Map<String, dynamic>> parts = <Map<String, dynamic>>[];

      final Object? api = m.apiContent;
      if (api is List) {
        for (final dynamic raw in api) {
          if (raw is! Map) continue;
          final Map<String, dynamic> map = Map<String, dynamic>.from(
            raw as Map,
          );
          final String type = (map['type'] as String? ?? '')
              .trim()
              .toLowerCase();

          if (type == 'text' || type == 'input_text' || type == 'output_text') {
            final String txt = (map['text'] as String?)?.toString() ?? '';
            final String t = txt.trim();
            if (t.isNotEmpty) {
              parts.add(<String, dynamic>{'text': t});
            }
            continue;
          }

          if (type == 'image_url' || type == 'input_image') {
            String url = '';
            final dynamic imageObj = map['image_url'] ?? map['imageUrl'];
            if (imageObj is String) {
              url = imageObj;
            } else if (imageObj is Map) {
              final Map<String, dynamic> imageMap = Map<String, dynamic>.from(
                imageObj as Map,
              );
              url =
                  (imageMap['url'] as String?) ??
                  (imageMap['image_url'] as String?) ??
                  (imageMap['imageUrl'] as String?) ??
                  '';
            } else {
              url = (map['url'] as String?) ?? '';
            }
            url = url.trim();
            if (url.isEmpty) continue;

            // data:<mime>;base64,<payload>
            if (url.startsWith('data:')) {
              final int semi = url.indexOf(';');
              final int comma = url.indexOf(',');
              if (semi > 5 && comma > semi) {
                final String mime = url.substring(5, semi).trim();
                final String meta = url
                    .substring(semi + 1, comma)
                    .trim()
                    .toLowerCase();
                final String payload = url.substring(comma + 1).trim();
                if (meta.contains('base64') && payload.isNotEmpty) {
                  parts.add(<String, dynamic>{
                    'inline_data': <String, dynamic>{
                      'mime_type': mime.isEmpty
                          ? 'application/octet-stream'
                          : mime,
                      'data': payload,
                    },
                  });
                }
              }
              continue;
            }

            // Best-effort: treat as file uri (may not work for all providers).
            parts.add(<String, dynamic>{
              'file_data': <String, dynamic>{
                'mime_type': 'application/octet-stream',
                'file_uri': url,
              },
            });
            continue;
          }
        }
      }

      final String text = m.content.trim();
      if (parts.isEmpty && text.isNotEmpty) {
        parts.add(<String, dynamic>{'text': text});
      }
      if (parts.isEmpty) continue;
      contents.add(<String, dynamic>{'role': role, 'parts': parts});
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      'contents': contents,
      'generationConfig': <String, dynamic>{'temperature': _defaultTemperature},
    };
    if (systemParts.isNotEmpty) {
      payload['system_instruction'] = <String, dynamic>{'parts': systemParts};
    }
    return payload;
  }

  Map<String, dynamic> _buildChatCompletionsPayload({
    required AIEndpoint endpoint,
    required List<AIMessage> messages,
    required bool stream,
    required List<Map<String, dynamic>> tools,
    required Object? toolChoice,
  }) {
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
    return payload;
  }

  Map<String, dynamic> _buildResponsesPayload({
    required AIEndpoint endpoint,
    required List<AIMessage> messages,
    required bool stream,
    required List<Map<String, dynamic>> tools,
    required Object? toolChoice,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'model': endpoint.model,
      'input': _buildResponsesInputItems(messages),
      'temperature': _defaultTemperature,
      'stream': stream,
    };
    if (tools.isNotEmpty) {
      payload['tools'] = _normalizeResponsesTools(tools);
      final Object? normalizedToolChoice = _normalizeResponsesToolChoice(
        toolChoice,
      );
      if (normalizedToolChoice != null) {
        payload['tool_choice'] = normalizedToolChoice;
      }
    }
    return payload;
  }

  List<Map<String, dynamic>> _buildResponsesInputItems(
    List<AIMessage> messages,
  ) {
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    int syntheticCallSeq = 0;

    for (final AIMessage message in messages) {
      final String role = message.role.trim().toLowerCase();

      if (role == 'tool') {
        final String callId = (message.toolCallId ?? '').trim();
        if (callId.isNotEmpty) {
          items.add(<String, dynamic>{
            'type': 'function_call_output',
            'call_id': callId,
            'output': message.content,
          });
        } else {
          final List<Map<String, dynamic>> fallbackParts =
              _buildResponsesContentParts(
                role: 'user',
                content: message.content,
                apiContent: message.apiContent,
              );
          if (fallbackParts.isNotEmpty) {
            items.add(<String, dynamic>{
              'role': 'user',
              'content': fallbackParts,
            });
          }
        }
        continue;
      }

      if (role == 'assistant' &&
          message.toolCalls != null &&
          message.toolCalls!.isNotEmpty) {
        final List<Map<String, dynamic>> assistantParts =
            _buildResponsesContentParts(
              role: 'assistant',
              content: message.content,
              apiContent: message.apiContent,
            );
        if (assistantParts.isNotEmpty) {
          items.add(<String, dynamic>{
            'role': 'assistant',
            'content': assistantParts,
          });
        }

        for (final Map<String, dynamic> tc in message.toolCalls!) {
          final Map<String, dynamic> map = Map<String, dynamic>.from(tc);
          final String id = ((map['id'] as String?) ?? '').trim().isNotEmpty
              ? (map['id'] as String).trim()
              : 'call_fallback_${++syntheticCallSeq}';

          String name = '';
          Object? argumentsRaw;
          final dynamic fnRaw = map['function'];
          if (fnRaw is Map) {
            final Map<String, dynamic> fn = Map<String, dynamic>.from(
              fnRaw as Map,
            );
            name = ((fn['name'] as String?) ?? '').trim();
            argumentsRaw = fn['arguments'];
          }
          name = name.isNotEmpty
              ? name
              : ((map['name'] as String?) ?? '').trim();
          argumentsRaw ??= map['arguments'];
          if (name.isEmpty) continue;

          final String arguments = _stringifyJsonLike(argumentsRaw);
          items.add(<String, dynamic>{
            'type': 'function_call',
            'call_id': id,
            'name': name,
            'arguments': arguments.isEmpty ? '{}' : arguments,
          });
        }
        continue;
      }

      final String normalizedRole =
          role == 'assistant' || role == 'system' || role == 'developer'
          ? role
          : 'user';
      final List<Map<String, dynamic>> parts = _buildResponsesContentParts(
        role: normalizedRole,
        content: message.content,
        apiContent: message.apiContent,
      );
      if (parts.isEmpty) continue;
      items.add(<String, dynamic>{'role': normalizedRole, 'content': parts});
    }

    return items;
  }

  List<Map<String, dynamic>> _buildResponsesContentParts({
    required String role,
    required String content,
    required Object? apiContent,
  }) {
    final List<Map<String, dynamic>> parts = <Map<String, dynamic>>[];
    final bool assistant = role == 'assistant';

    if (apiContent is List) {
      for (final dynamic raw in apiContent) {
        if (raw is! Map) continue;
        final Map<String, dynamic> map = Map<String, dynamic>.from(raw as Map);
        final String type = (map['type'] as String? ?? '').trim().toLowerCase();

        if (type == 'text') {
          final String text = (map['text'] as String?) ?? '';
          if (text.isNotEmpty) {
            parts.add(<String, dynamic>{
              'type': assistant ? 'output_text' : 'input_text',
              'text': text,
            });
          }
          continue;
        }

        if (type == 'input_text' ||
            type == 'output_text' ||
            type == 'refusal') {
          if (assistant && (type == 'output_text' || type == 'refusal')) {
            parts.add(map);
          } else if (!assistant && type == 'input_text') {
            parts.add(map);
          }
          continue;
        }

        if (!assistant && (type == 'image_url' || type == 'input_image')) {
          String url = '';
          final dynamic imageObj = map['image_url'];
          if (imageObj is String) {
            url = imageObj;
          } else if (imageObj is Map) {
            final Map<String, dynamic> imageMap = Map<String, dynamic>.from(
              imageObj as Map,
            );
            url =
                (imageMap['url'] as String?) ??
                (imageMap['image_url'] as String?) ??
                '';
          } else {
            url = (map['url'] as String?) ?? '';
          }
          if (url.isNotEmpty) {
            parts.add(<String, dynamic>{
              'type': 'input_image',
              'image_url': url,
            });
          }
        }
      }
    }

    if (parts.isEmpty && content.isNotEmpty) {
      parts.add(<String, dynamic>{
        'type': assistant ? 'output_text' : 'input_text',
        'text': content,
      });
    }

    return parts;
  }

  List<Map<String, dynamic>> _normalizeResponsesTools(
    List<Map<String, dynamic>> tools,
  ) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> raw in tools) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
      final String type = (map['type'] as String? ?? '').trim().toLowerCase();
      if (type != 'function') {
        out.add(map);
        continue;
      }

      final dynamic fnRaw = map['function'];
      if (fnRaw is Map) {
        final Map<String, dynamic> fn = Map<String, dynamic>.from(fnRaw as Map);
        final String name = (fn['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        out.add(<String, dynamic>{
          'type': 'function',
          'name': name,
          if ((fn['description'] as String?)?.trim().isNotEmpty == true)
            'description': (fn['description'] as String).trim(),
          if (fn['parameters'] != null) 'parameters': fn['parameters'],
          if (fn['strict'] != null) 'strict': fn['strict'],
        });
        continue;
      }

      final String name = (map['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      out.add(<String, dynamic>{
        'type': 'function',
        'name': name,
        if ((map['description'] as String?)?.trim().isNotEmpty == true)
          'description': (map['description'] as String).trim(),
        if (map['parameters'] != null) 'parameters': map['parameters'],
        if (map['strict'] != null) 'strict': map['strict'],
      });
    }
    return out;
  }

  Object? _normalizeResponsesToolChoice(Object? toolChoice) {
    if (toolChoice == null) return null;
    if (toolChoice is! Map) return toolChoice;

    final Map<String, dynamic> map = Map<String, dynamic>.from(
      toolChoice as Map,
    );
    final String type = (map['type'] as String? ?? '').trim().toLowerCase();
    if (type != 'function') {
      return map;
    }

    String name = (map['name'] as String? ?? '').trim();
    final dynamic fnRaw = map['function'];
    if (name.isEmpty && fnRaw is Map) {
      final Map<String, dynamic> fn = Map<String, dynamic>.from(fnRaw as Map);
      name = (fn['name'] as String? ?? '').trim();
    }
    if (name.isEmpty) return map;
    return <String, dynamic>{'type': 'function', 'name': name};
  }

  bool _isLikelyOpenAIHost(Uri baseUri) {
    final String host = baseUri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'api.openai.com') return true;
    if (host.endsWith('.openai.com')) return true;
    // Azure OpenAI endpoints often look like: {resource}.openai.azure.com
    if (host.contains('openai.azure.com')) return true;
    return false;
  }

  bool _shouldUseResponsesApi({
    required AIEndpoint endpoint,
    required Uri baseUri,
    required List<Map<String, dynamic>> tools,
  }) {
    if (endpoint.useResponseApi) return true;
    if (_isResponsesPath(endpoint.chatPath)) return true;

    final String host = baseUri.host.toLowerCase();
    if (host.contains('codex-api') || host.contains('packycode')) {
      return true;
    }

    final String model = endpoint.model.trim().toLowerCase();
    if (model.startsWith('gpt-5')) {
      // Keep gpt-5 on Responses for official hosts by default, but do NOT force
      // Responses for arbitrary proxies unless explicitly enabled.
      return _isLikelyOpenAIHost(baseUri);
    }

    if (tools.isEmpty) return false;
    return false;
  }

  String _stringifyJsonLike(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  Future<_GatewayAggregate> _performNonStreaming({
    required AIEndpoint endpoint,
    required _PreparedRequest prepared,
    required String responseStartMarker,
    Duration? timeout,
    String? logContext,
    StreamController<AIGatewayEvent>? controller,
    int imagesCount = 0,
    int toolsCount = 0,
  }) async {
    String clip(String s, int maxLen) {
      if (s.length <= maxLen) return s;
      if (maxLen <= 32) {
        return s.substring(0, maxLen) + '…(len=${s.length})';
      }
      final int head = maxLen ~/ 2;
      final int tail = maxLen - head;
      return s.substring(0, head) +
          '…(truncated,len=${s.length})…' +
          s.substring(s.length - tail);
    }

    Map<String, String> maskHeaders(Map<String, String> headers) {
      final Map<String, String> out = <String, String>{};
      headers.forEach((String k, String v) {
        final String key = k.toLowerCase();
        if (key == 'authorization') {
          out[k] = v.startsWith('Bearer ') ? 'Bearer ***' : '***';
          return;
        }
        if (key == 'x-goog-api-key' || key == 'api-key' || key == 'x-api-key') {
          out[k] = '***';
          return;
        }
        out[k] = v;
      });
      return out;
    }

    String redactDataUrls(String s) {
      // Keep the data url prefix but remove the actual base64 payload to avoid
      // exploding logs and leaking user screenshots into text logs.
      const String needle = 'base64,';
      int i = 0;
      final StringBuffer out = StringBuffer();
      while (true) {
        final int idx = s.indexOf(needle, i);
        if (idx < 0) {
          out.write(s.substring(i));
          break;
        }
        final int payloadStart = idx + needle.length;
        int end = s.indexOf('"', payloadStart);
        if (end < 0) end = s.length;
        final int payloadLen = (end - payloadStart).clamp(0, 1 << 30);
        out.write(s.substring(i, payloadStart));
        out.write('<base64 len=$payloadLen>');
        i = end;
      }
      return out.toString();
    }

    void emitUiLog(String line, {Object? extra}) {
      if (controller == null) return;
      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 'gateway_log',
        'at': DateTime.now().millisecondsSinceEpoch,
        'line': line,
      };
      if (extra != null) payload['extra'] = extra;
      try {
        controller.add(AIGatewayEvent('ui', jsonEncode(payload)));
      } catch (_) {}
    }

    final String traceId = _newTraceId();
    final Stopwatch sw = Stopwatch()..start();

    final String apiType = prepared.isGoogle
        ? 'google.generateContent'
        : (prepared.useResponsesApi
              ? 'openai.responses'
              : 'openai.chat.completions');
    final String providerName = (endpoint.providerName ?? '').trim();
    final String providerType = (endpoint.providerType ?? '').trim();
    final String providerIdText = endpoint.providerId == null
        ? ''
        : endpoint.providerId.toString();

    String usageFields(_UsageSnapshot? usage) {
      if (usage == null) return '';
      final List<String> parts = <String>[];
      if (usage.promptTokens != null) {
        parts.add('promptTokens=${usage.promptTokens}');
      }
      if (usage.completionTokens != null) {
        parts.add('completionTokens=${usage.completionTokens}');
      }
      if (usage.totalTokens != null) {
        parts.add('totalTokens=${usage.totalTokens}');
      }
      return parts.join(' ');
    }

    emitUiLog(
      'REQ POST ${prepared.uri} stream=0 google=${prepared.isGoogle ? 1 : 0} bodyLen=${prepared.body.length}',
    );
    emitUiLog('REQ headers', extra: maskHeaders(prepared.headers));
    emitUiLog('REQ body', extra: clip(prepared.body, 12000));

    try {
      final String body = clip(redactDataUrls(prepared.body), 12000);
      final String reqText = [
        'REQ $traceId',
        'POST ${prepared.uri}',
        'ctx=${(logContext ?? '').trim()} api=$apiType stream=0',
        if (providerName.isNotEmpty || providerType.isNotEmpty)
          'provider=${providerName.isEmpty ? '-' : providerName}'
              '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
              ' type=${providerType.isEmpty ? '-' : providerType}',
        'model=${endpoint.model} tools=$toolsCount images=$imagesCount toolChoice=${prepared.body.contains('"tool_choice"') ? 1 : 0}',
        'chatPath=${endpoint.chatPath} endpoint.useResponseApi=${endpoint.useResponseApi ? 1 : 0} resolved.responses=${prepared.useResponsesApi ? 1 : 0}',
        'headers=${jsonEncode(maskHeaders(prepared.headers))}',
        'body=$body',
      ].join('\n');
      await FlutterLogger.nativeDebug('AITrace', reqText);
    } catch (_) {}

    try {
      await FlutterLogger.nativeDebug(
        'AI',
        '[网关] HTTP POST ${prepared.uri} (log=$logContext) 请求体长度=${prepared.body.length}',
      );
    } catch (_) {}

    final Future<http.Response> future = http.post(
      prepared.uri,
      headers: prepared.headers,
      body: prepared.body,
    );
    final http.Response response = timeout == null
        ? await future
        : await future.timeout(timeout);
    sw.stop();

    emitUiLog(
      'RESP status=${response.statusCode} contentType=${response.headers['content-type'] ?? ''} bodyLen=${response.body.length}',
      extra: <String, dynamic>{'headers': response.headers},
    );

    try {
      final String body = clip(redactDataUrls(response.body), 12000);
      final String respText = [
        'RESP $traceId',
        '${response.statusCode} ${prepared.uri}',
        'ctx=${(logContext ?? '').trim()} api=$apiType stream=0 tookMs=${sw.elapsedMilliseconds}',
        if (providerName.isNotEmpty || providerType.isNotEmpty)
          'provider=${providerName.isEmpty ? '-' : providerName}'
              '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
              ' type=${providerType.isEmpty ? '-' : providerType}',
        'model=${endpoint.model} bodyLen=${response.body.length}',
        'headers=${jsonEncode(response.headers)}',
        'body=$body',
      ].join('\n');
      await FlutterLogger.nativeDebug('AITrace', respText);
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      emitUiLog('RESP error body', extra: clip(response.body, 12000));
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
      final String usage = usageFields(parsed.usage);
      emitUiLog(
        'PARSED google contentLen=${sanitized.length} reasoningLen=${(parsed.reasoning ?? '').length}${usage.isEmpty ? '' : ' $usage'}',
      );
      if (usage.isNotEmpty) {
        try {
          final String respUsageText = [
            'RESP $traceId',
            '${response.statusCode} ${prepared.uri}',
            'ctx=${(logContext ?? '').trim()} api=$apiType stream=0 tookMs=${sw.elapsedMilliseconds}',
            if (providerName.isNotEmpty || providerType.isNotEmpty)
              'provider=${providerName.isEmpty ? '-' : providerName}'
                  '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
                  ' type=${providerType.isEmpty ? '-' : providerType}',
            'model=${endpoint.model} bodyLen=${response.body.length} $usage',
          ].join('\n');
          await FlutterLogger.nativeDebug('AITrace', respUsageText);
        } catch (_) {}
      }
      if (parsed.reasoning != null && parsed.reasoning!.isNotEmpty) {
        controller?.add(
          AIGatewayEvent(AIGatewayEventKind.reasoning, parsed.reasoning!),
        );
      }
      controller?.add(AIGatewayEvent(AIGatewayEventKind.content, sanitized));
      return _GatewayAggregate(
        content: sanitized,
        reasoning: parsed.reasoning,
        reasoningDuration: null,
        usage: parsed.usage,
      );
    }

    final _OpenAIResponse parsed = _parseOpenAIResponse(response.body);
    final bool hasToolCalls = parsed.toolCalls.isNotEmpty;
    final String sanitized = hasToolCalls
        ? _trimLeadingIgnorable(parsed.content)
        : _stripResponseStart(responseStartMarker, parsed.content);
    final String usage = usageFields(parsed.usage);
    emitUiLog(
      'PARSED openai contentLen=${sanitized.length} toolCalls=${parsed.toolCalls.length} reasoningLen=${(parsed.reasoning ?? '').length}${usage.isEmpty ? '' : ' $usage'}',
    );
    if (usage.isNotEmpty) {
      try {
        final String respUsageText = [
          'RESP $traceId',
          '${response.statusCode} ${prepared.uri}',
          'ctx=${(logContext ?? '').trim()} api=$apiType stream=0 tookMs=${sw.elapsedMilliseconds}',
          if (providerName.isNotEmpty || providerType.isNotEmpty)
            'provider=${providerName.isEmpty ? '-' : providerName}'
                '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
                ' type=${providerType.isEmpty ? '-' : providerType}',
          'model=${endpoint.model} bodyLen=${response.body.length} $usage',
        ].join('\n');
        await FlutterLogger.nativeDebug('AITrace', respUsageText);
      } catch (_) {}
    }
    if (parsed.reasoning != null && parsed.reasoning!.isNotEmpty) {
      controller?.add(
        AIGatewayEvent(AIGatewayEventKind.reasoning, parsed.reasoning!),
      );
    }
    controller?.add(AIGatewayEvent(AIGatewayEventKind.content, sanitized));
    return _GatewayAggregate(
      content: sanitized,
      toolCalls: parsed.toolCalls,
      reasoning: parsed.reasoning,
      reasoningDuration: null,
      usage: parsed.usage,
    );
  }

  Future<_GatewayAggregate> _performStreaming({
    required AIEndpoint endpoint,
    required _PreparedRequest prepared,
    required String responseStartMarker,
    Duration? timeout,
    String? logContext,
    StreamController<AIGatewayEvent>? controller,
    int imagesCount = 0,
    int toolsCount = 0,
  }) async {
    final http.Client client = http.Client();
    final _ResponseStartFilter startFilter = _ResponseStartFilter(
      responseStartMarker,
    );
    final _ThinkStreamFilter thinkFilter = _ThinkStreamFilter();
    final _ToolCallAccumulator toolAccumulator = _ToolCallAccumulator(
      _newFallbackToolCallId,
    );
    final StringBuffer contentBuffer = StringBuffer();
    final StringBuffer reasoningBuffer = StringBuffer();
    final DateTime reasoningStart = DateTime.now();
    String googleLastContent = '';
    String googleLastThought = '';
    // Responses API streaming sometimes sends cumulative text in *.done events.
    // Track per output/content index so we can emit only the missing delta.
    final Map<String, String> responsesLastOutputText = <String, String>{};
    final Map<String, String> responsesLastReasoningText = <String, String>{};
    final Map<String, String> responsesLastReasoningSummaryText =
        <String, String>{};
    // Some providers only emit output items (e.g. response.output_item.done) instead of
    // output_text deltas. Also track tool-call args so we can feed toolAccumulator with deltas.
    final Map<String, String> responsesLastToolArgs = <String, String>{};
    final Map<String, String> responsesToolCallCanonicalIdByItemId =
        <String, String>{};
    final Map<String, String> responsesToolCallNameById = <String, String>{};
    int responsesToolCallSeq = 0;
    final Map<String, int> responsesToolCallIndexById = <String, int>{};
    final Set<String> responsesTerminalOutputTextSeen = <String>{};
    String responsesFinalOutputText = '';
    final RegExp responsesThinkTagRe = RegExp(r'</?think>');
    _UsageSnapshot? usageSnapshot;
    int? ttftMs;
    final Stopwatch sw = Stopwatch()..start();

    String usageFields(_UsageSnapshot? usage) {
      if (usage == null) return '';
      final List<String> parts = <String>[];
      if (usage.promptTokens != null) {
        parts.add('promptTokens=${usage.promptTokens}');
      }
      if (usage.completionTokens != null) {
        parts.add('completionTokens=${usage.completionTokens}');
      }
      if (usage.totalTokens != null) {
        parts.add('totalTokens=${usage.totalTokens}');
      }
      return parts.join(' ');
    }

    void markFirstTokenSeen() {
      ttftMs ??= sw.elapsedMilliseconds;
    }

    String responsesKey(
      Map<String, dynamic> json, {
      String primaryIndex = 'output_index',
      String secondaryIndex = 'content_index',
    }) {
      final dynamic a = json[primaryIndex];
      final dynamic b = json[secondaryIndex];
      if (a is int && b is int) return '$a:$b';
      if (a is int) return '$a';
      if (b is int) return '$b';
      return '0';
    }

    int toolIndexForCallId(String callId) {
      return responsesToolCallIndexById.putIfAbsent(
        callId,
        () => responsesToolCallSeq++,
      );
    }

    void rememberResponsesFinalOutputText(String text) {
      if (text.isEmpty) return;
      String normalized = text.replaceAll(responsesThinkTagRe, '');
      normalized = _stripResponseStart(
        responseStartMarker,
        normalized,
      ).trimRight();
      if (normalized.isEmpty) return;
      if (normalized.length >= responsesFinalOutputText.length) {
        responsesFinalOutputText = normalized;
      }
    }

    void emitContentDelta(String delta) {
      if (delta.isEmpty) return;
      final _ThinkStreamFilterResult r = thinkFilter.process(delta);
      if (r.visibleDelta.isNotEmpty) {
        final String? sanitized = startFilter.process(r.visibleDelta);
        if (sanitized != null && sanitized.isNotEmpty) {
          markFirstTokenSeen();
          contentBuffer.write(sanitized);
          controller?.add(
            AIGatewayEvent(AIGatewayEventKind.content, sanitized),
          );
        }
      }
      if (r.reasoningDelta.isNotEmpty) {
        markFirstTokenSeen();
        reasoningBuffer.write(r.reasoningDelta);
        controller?.add(
          AIGatewayEvent(AIGatewayEventKind.reasoning, r.reasoningDelta),
        );
      }
    }

    void emitReasoningDelta(String delta) {
      if (delta.isEmpty) return;
      markFirstTokenSeen();
      reasoningBuffer.write(delta);
      controller?.add(AIGatewayEvent(AIGatewayEventKind.reasoning, delta));
    }

    String clip(String s, int maxLen) {
      if (s.length <= maxLen) return s;
      if (maxLen <= 32) {
        return s.substring(0, maxLen) + '…(len=${s.length})';
      }
      final int head = maxLen ~/ 2;
      final int tail = maxLen - head;
      return s.substring(0, head) +
          '…(truncated,len=${s.length})…' +
          s.substring(s.length - tail);
    }

    Map<String, String> maskHeaders(Map<String, String> headers) {
      final Map<String, String> out = <String, String>{};
      headers.forEach((String k, String v) {
        final String key = k.toLowerCase();
        if (key == 'authorization') {
          out[k] = v.startsWith('Bearer ') ? 'Bearer ***' : '***';
          return;
        }
        if (key == 'x-goog-api-key' || key == 'api-key' || key == 'x-api-key') {
          out[k] = '***';
          return;
        }
        out[k] = v;
      });
      return out;
    }

    String redactDataUrls(String s) {
      // Keep the data url prefix but remove the actual base64 payload to avoid
      // exploding logs and leaking user screenshots into text logs.
      const String needle = 'base64,';
      int i = 0;
      final StringBuffer out = StringBuffer();
      while (true) {
        final int idx = s.indexOf(needle, i);
        if (idx < 0) {
          out.write(s.substring(i));
          break;
        }
        final int payloadStart = idx + needle.length;
        int end = s.indexOf('"', payloadStart);
        if (end < 0) end = s.length;
        final int payloadLen = (end - payloadStart).clamp(0, 1 << 30);
        out.write(s.substring(i, payloadStart));
        out.write('<base64 len=$payloadLen>');
        i = end;
      }
      return out.toString();
    }

    void emitUiLog(String line, {Object? extra}) {
      if (controller == null) return;
      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 'gateway_log',
        'at': DateTime.now().millisecondsSinceEpoch,
        'line': line,
      };
      if (extra != null) {
        payload['extra'] = extra;
      }
      try {
        controller.add(AIGatewayEvent('ui', jsonEncode(payload)));
      } catch (_) {}
    }

    final String traceId = _newTraceId();

    final String apiType = prepared.isGoogle
        ? 'google.streamGenerateContent'
        : (prepared.useResponsesApi
              ? 'openai.responses'
              : 'openai.chat.completions');
    final String providerName = (endpoint.providerName ?? '').trim();
    final String providerType = (endpoint.providerType ?? '').trim();
    final String providerIdText = endpoint.providerId == null
        ? ''
        : endpoint.providerId.toString();

    try {
      final http.Request request = http.Request('POST', prepared.uri)
        ..headers.addAll(prepared.headers)
        ..body = prepared.body;
      emitUiLog(
        'REQ POST ${prepared.uri} stream=1 google=${prepared.isGoogle ? 1 : 0} bodyLen=${prepared.body.length}',
      );
      emitUiLog('REQ headers', extra: maskHeaders(prepared.headers));
      emitUiLog('REQ body', extra: clip(prepared.body, 12000));

      try {
        final String body = clip(redactDataUrls(prepared.body), 12000);
        final String reqText = [
          'REQ $traceId',
          'POST ${prepared.uri}',
          'ctx=${(logContext ?? '').trim()} api=$apiType stream=1',
          if (providerName.isNotEmpty || providerType.isNotEmpty)
            'provider=${providerName.isEmpty ? '-' : providerName}'
                '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
                ' type=${providerType.isEmpty ? '-' : providerType}',
          'model=${endpoint.model} tools=$toolsCount images=$imagesCount toolChoice=${prepared.body.contains('"tool_choice"') ? 1 : 0}',
          'chatPath=${endpoint.chatPath} endpoint.useResponseApi=${endpoint.useResponseApi ? 1 : 0} resolved.responses=${prepared.useResponsesApi ? 1 : 0}',
          'headers=${jsonEncode(maskHeaders(prepared.headers))}',
          'body=$body',
        ].join('\n');
        await FlutterLogger.nativeDebug('AITrace', reqText);
      } catch (_) {}

      try {
        await FlutterLogger.nativeDebug(
          'AI',
          '[网关] HTTP 流式 POST ${prepared.uri} (log=$logContext) 请求体长度=${prepared.body.length}',
        );
      } catch (_) {}
      final Future<http.StreamedResponse> sendFuture = client.send(request);
      final http.StreamedResponse streamed = timeout == null
          ? await sendFuture
          : await sendFuture.timeout(timeout);

      try {
        final String respText = [
          'RESP $traceId',
          '${streamed.statusCode} ${prepared.uri}',
          'ctx=${(logContext ?? '').trim()} api=$apiType stream=1',
          if (providerName.isNotEmpty || providerType.isNotEmpty)
            'provider=${providerName.isEmpty ? '-' : providerName}'
                '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
                ' type=${providerType.isEmpty ? '-' : providerType}',
          'model=${endpoint.model}',
          'headers=${jsonEncode(streamed.headers)}',
        ].join('\n');
        await FlutterLogger.nativeDebug('AITrace', respText);
      } catch (_) {}

      emitUiLog(
        'RESP status=${streamed.statusCode} contentType=${streamed.headers['content-type'] ?? ''}',
        extra: <String, dynamic>{'headers': streamed.headers},
      );

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final http.Response failure = await http.Response.fromStream(streamed);
        emitUiLog('RESP error body', extra: clip(failure.body, 12000));
        throw Exception(
          'Request failed: ${streamed.statusCode} ${failure.body}',
        );
      }

      String buffer = '';
      bool done = false;
      bool sawData = false;
      String lastSseEvent = '';
      String currentSseEvent = '';
      String pendingData = '';
      int pendingDataLines = 0;
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

          // SSE frame delimiter: a blank line terminates the current event.
          if (line.isEmpty) {
            if (pendingData.isNotEmpty) {
              emitUiLog(
                'SSE jsonDecode failed (lines=$pendingDataLines)',
                extra: clip(pendingData, 4000),
              );
              pendingData = '';
              pendingDataLines = 0;
            }
            currentSseEvent = '';
            continue;
          }
          if (line.startsWith('event:')) {
            final String ev = line.substring(6).trim();
            currentSseEvent = ev;
            lastSseEvent = ev;
            emitUiLog('SSE event', extra: ev);
            continue;
          }
          if (line.startsWith('id:') ||
              line.startsWith('retry:') ||
              line.startsWith(':')) {
            // Keep these for debugging proxy/relay behavior.
            emitUiLog('SSE meta', extra: line);
            continue;
          }
          if (!line.startsWith('data:')) continue;

          // Per SSE spec, strip a single leading space after ":" (if present).
          String dataLine = line.substring(5);
          if (dataLine.startsWith(' ')) {
            dataLine = dataLine.substring(1);
          }
          // `line` is already trimRight()'d; keep as-is otherwise.
          if (dataLine.isNotEmpty) {
            sawData = true;
          }
          emitUiLog('SSE data', extra: clip(dataLine, 4000));

          if (pendingData.isEmpty) {
            pendingData = dataLine;
          } else {
            pendingData += '\n' + dataLine;
          }
          pendingDataLines += 1;

          if (pendingData.trim() == '[DONE]') {
            done = true;
            buffer = '';
            pendingData = '';
            pendingDataLines = 0;
            break;
          }

          // Some relays pretty-print JSON over multiple data lines. Try decode
          // incrementally; if it fails, wait for more data lines and only log
          // on frame end.
          Map<String, dynamic> json;
          try {
            final dynamic decoded = jsonDecode(pendingData);
            if (decoded is! Map) {
              emitUiLog(
                'SSE decoded non-map',
                extra: decoded.runtimeType.toString(),
              );
              pendingData = '';
              pendingDataLines = 0;
              continue;
            }
            json = Map<String, dynamic>.from(decoded as Map);
          } catch (_) {
            continue;
          }

          // Decoded one full JSON payload; clear pending to allow the next one
          // (even within the same SSE frame).
          pendingData = '';
          pendingDataLines = 0;

          // Some relays may put the event type in the SSE "event:" line instead of JSON.
          final String fallbackEvent = currentSseEvent.isNotEmpty
              ? currentSseEvent
              : lastSseEvent;
          if (fallbackEvent.isNotEmpty) {
            final dynamic t = json['type'];
            if (t is! String || t.trim().isEmpty) {
              json['type'] = fallbackEvent;
            }
          }

          if (prepared.isGoogle) {
            final _GoogleStreamParts chunk = _extractGoogleStreamParts(json);
            usageSnapshot = _extractUsageSnapshotFromAny(json) ?? usageSnapshot;

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
                emitContentDelta(delta);
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
                emitReasoningDelta(delta);
              }
            }
            continue;
          }

          final dynamic type = json['type'];
          if (type is String) {
            emitUiLog('EVENT type=$type');
            usageSnapshot = _extractUsageSnapshotFromAny(json) ?? usageSnapshot;
            if (type == 'response.completed') {
              final dynamic resp0 = json['response'];
              if (resp0 is Map) {
                usageSnapshot =
                    _extractUsageSnapshotFromAny(
                      Map<String, dynamic>.from(resp0),
                    ) ??
                    usageSnapshot;
              }
            }
            if (type == 'response.completed') {
              emitUiLog(
                'EVENT completed',
                extra: json['response'] ?? json['usage'] ?? '',
              );
              done = true;
              continue;
            }
            if (type == 'response.reasoning_summary_text.delta' ||
                type == 'response.reasoning_summary_text.done') {
              final dynamic chunk = json['delta'] ?? json['text'];
              if (chunk is String && chunk.isNotEmpty) {
                final String key = responsesKey(
                  json,
                  secondaryIndex: 'summary_index',
                );
                final String prev =
                    responsesLastReasoningSummaryText[key] ?? '';
                final String delta = _deltaFromPossiblyCumulative(
                  previous: prev,
                  incoming: chunk,
                );
                responsesLastReasoningSummaryText[key] = _updateCumulativeProbe(
                  previous: prev,
                  incoming: chunk,
                );
                emitUiLog(
                  'EVENT reasoning_summary deltaLen=${delta.length} key=$key',
                );
                emitReasoningDelta(delta);
              }
              continue;
            }
            if (type == 'response.reasoning_text.delta' ||
                type == 'response.reasoning_text.done') {
              final dynamic chunk = json['delta'] ?? json['text'];
              if (chunk is String && chunk.isNotEmpty) {
                final String key = responsesKey(
                  json,
                  secondaryIndex: 'content_index',
                );
                final String prev = responsesLastReasoningText[key] ?? '';
                final String delta = _deltaFromPossiblyCumulative(
                  previous: prev,
                  incoming: chunk,
                );
                responsesLastReasoningText[key] = _updateCumulativeProbe(
                  previous: prev,
                  incoming: chunk,
                );
                emitUiLog('EVENT reasoning deltaLen=${delta.length} key=$key');
                emitReasoningDelta(delta);
              }
              continue;
            }
            if (type == 'response.output_text.delta') {
              final dynamic chunk = json['delta'];
              if (chunk is String && chunk.isNotEmpty) {
                final String key = responsesKey(
                  json,
                  secondaryIndex: 'content_index',
                );
                final String prev = responsesLastOutputText[key] ?? '';
                final String delta = _deltaFromPossiblyCumulative(
                  previous: prev,
                  incoming: chunk,
                );
                responsesLastOutputText[key] = _updateCumulativeProbe(
                  previous: prev,
                  incoming: chunk,
                );
                emitUiLog(
                  'EVENT output_text deltaLen=${delta.length} key=$key',
                );
                emitContentDelta(delta);
              }
              continue;
            }
            if (type == 'response.output_text.done') {
              final dynamic chunk = json['text'] ?? json['delta'];
              if (chunk is String && chunk.isNotEmpty) {
                final String key = responsesKey(
                  json,
                  secondaryIndex: 'content_index',
                );
                final String prev = responsesLastOutputText[key] ?? '';
                final String delta = _deltaFromTerminalFull(
                  previous: prev,
                  fullText: chunk,
                );
                responsesLastOutputText[key] = chunk;
                responsesTerminalOutputTextSeen.add(key);
                emitUiLog(
                  'EVENT output_text.done fullLen=${chunk.length} prevLen=${prev.length} deltaLen=${delta.length} key=$key',
                );
                emitContentDelta(delta);
                rememberResponsesFinalOutputText(chunk);
              }
              continue;
            }
            if (type == 'response.output_item.added' ||
                type == 'response.output_item.done') {
              final dynamic itemRaw = json['item'];
              if (itemRaw is Map) {
                final Map<String, dynamic> item = Map<String, dynamic>.from(
                  itemRaw as Map,
                );
                final String itemType = (item['type'] as String?) ?? '';

                if (itemType == 'message') {
                  String fullText = extractResponsesMessageOutputText(item);
                  if (fullText.isNotEmpty) {
                    // Best-effort normalization to improve dedupe when the stream also emits
                    // output_text deltas or when the model includes <think> tags.
                    fullText = fullText.replaceAll(responsesThinkTagRe, '');
                    fullText = _stripResponseStart(
                      responseStartMarker,
                      fullText,
                    );
                    rememberResponsesFinalOutputText(fullText);

                    final String already = contentBuffer.toString();
                    if (already.isNotEmpty) {
                      if (fullText.startsWith(already)) {
                        final String delta = fullText.substring(already.length);
                        emitUiLog(
                          'EVENT output_item.message fullLen=${fullText.length} alreadyLen=${already.length} deltaLen=${delta.length} (dedupe=buffer)',
                        );
                        emitContentDelta(delta);
                      } else {
                        emitUiLog(
                          'EVENT output_item.message fullLen=${fullText.length} alreadyLen=${already.length} (dedupe-miss)',
                          extra: clip(fullText, 4000),
                        );
                      }
                    } else {
                      final String itemId =
                          ((item['id'] as String?) ??
                                  (json['item_id'] as String?) ??
                                  (json['itemId'] as String?) ??
                                  '')
                              .trim();
                      final String key = itemId.isNotEmpty
                          ? 'msg:$itemId'
                          : 'msg:${responsesKey(json, secondaryIndex: 'content_index')}';
                      final String prev = responsesLastOutputText[key] ?? '';
                      final String delta = _deltaFromPossiblyCumulative(
                        previous: prev,
                        incoming: fullText,
                      );
                      responsesLastOutputText[key] = _updateCumulativeProbe(
                        previous: prev,
                        incoming: fullText,
                      );
                      emitUiLog(
                        'EVENT output_item.message fullLen=${fullText.length} prevLen=${prev.length} deltaLen=${delta.length} key=$key',
                      );
                      emitContentDelta(delta);
                    }
                  }
                  continue;
                }

                if (itemType == 'reasoning') {
                  final String fullReasoning = extractResponsesReasoningText(
                    item,
                  );
                  if (fullReasoning.isNotEmpty) {
                    final String itemId =
                        ((item['id'] as String?) ??
                                (json['item_id'] as String?) ??
                                (json['itemId'] as String?) ??
                                '')
                            .trim();
                    final String key = itemId.isNotEmpty
                        ? 'reason:$itemId'
                        : 'reason:${responsesKey(json, secondaryIndex: 'summary_index')}';
                    final String prev = responsesLastReasoningText[key] ?? '';
                    final String delta = _deltaFromPossiblyCumulative(
                      previous: prev,
                      incoming: fullReasoning,
                    );
                    responsesLastReasoningText[key] = _updateCumulativeProbe(
                      previous: prev,
                      incoming: fullReasoning,
                    );
                    emitUiLog(
                      'EVENT output_item.reasoning fullLen=${fullReasoning.length} prevLen=${prev.length} deltaLen=${delta.length} key=$key',
                    );
                    emitReasoningDelta(delta);
                  }
                  continue;
                }

                final ResponsesFunctionCallItem? fc =
                    extractResponsesFunctionCallItem(item);
                if (fc != null) {
                  final String itemId =
                      ((item['id'] as String?) ??
                              (json['item_id'] as String?) ??
                              (json['itemId'] as String?) ??
                              '')
                          .trim();
                  if (itemId.isNotEmpty) {
                    responsesToolCallCanonicalIdByItemId[itemId] = fc.callId;
                  }
                  responsesToolCallNameById[fc.callId] = fc.name;

                  final String prev = responsesLastToolArgs[fc.callId] ?? '';
                  final String argsDelta = _deltaFromPossiblyCumulative(
                    previous: prev,
                    incoming: fc.arguments,
                  );
                  responsesLastToolArgs[fc.callId] = _updateCumulativeProbe(
                    previous: prev,
                    incoming: fc.arguments,
                  );
                  emitUiLog(
                    'EVENT output_item.function_call id=${fc.callId} name=${fc.name} argsDeltaLen=${argsDelta.length}',
                  );

                  final int idx = toolIndexForCallId(fc.callId);
                  toolAccumulator.ingestChatDelta(<String, dynamic>{
                    'tool_calls': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'index': idx,
                        'id': fc.callId,
                        'function': <String, dynamic>{
                          'name': fc.name,
                          if (argsDelta.isNotEmpty) 'arguments': argsDelta,
                        },
                      },
                    ],
                  });
                }
              }
              continue;
            }
            if (type == 'response.function_call_arguments.delta') {
              final String argsDelta = (json['delta'] as String?) ?? '';
              if (argsDelta.isNotEmpty) {
                final String itemId =
                    ((json['item_id'] as String?) ??
                            (json['itemId'] as String?) ??
                            '')
                        .trim();
                String callId =
                    ((json['call_id'] as String?) ??
                            (json['callId'] as String?) ??
                            '')
                        .trim();
                if (callId.isEmpty && itemId.isNotEmpty) {
                  callId =
                      responsesToolCallCanonicalIdByItemId[itemId] ?? itemId;
                }
                if (callId.isNotEmpty) {
                  emitUiLog(
                    'EVENT function_call_arguments.delta callId=$callId deltaLen=${argsDelta.length}',
                  );
                  responsesLastToolArgs[callId] =
                      (responsesLastToolArgs[callId] ?? '') + argsDelta;
                  final int idx = toolIndexForCallId(callId);
                  final String name = responsesToolCallNameById[callId] ?? '';
                  toolAccumulator.ingestChatDelta(<String, dynamic>{
                    'tool_calls': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'index': idx,
                        'id': callId,
                        'function': <String, dynamic>{
                          if (name.isNotEmpty) 'name': name,
                          'arguments': argsDelta,
                        },
                      },
                    ],
                  });
                }
              }
              continue;
            }
            if (type == 'response.function_call_arguments.done') {
              continue;
            }
            if (type == 'response.content_part.done') {
              // Some relays may only emit content parts. Treat output_text parts as content.
              final dynamic part = json['part'];
              if (part is Map) {
                final Map<String, dynamic> p = Map<String, dynamic>.from(
                  part as Map,
                );
                final String partType = (p['type'] as String?) ?? '';
                final String txt = (p['text'] as String?) ?? '';
                if (partType == 'output_text' && txt.isNotEmpty) {
                  final String key = responsesKey(
                    json,
                    secondaryIndex: 'content_index',
                  );
                  rememberResponsesFinalOutputText(txt);
                  if (responsesTerminalOutputTextSeen.contains(key)) {
                    emitUiLog(
                      'EVENT content_part.done skipped key=$key reason=seen_terminal',
                    );
                  } else {
                    final String prev = responsesLastOutputText[key] ?? '';
                    final String delta = _deltaFromTerminalFull(
                      previous: prev,
                      fullText: txt,
                    );
                    responsesLastOutputText[key] = txt;
                    responsesTerminalOutputTextSeen.add(key);
                    emitUiLog(
                      'EVENT content_part.done fullLen=${txt.length} prevLen=${prev.length} deltaLen=${delta.length} key=$key',
                    );
                    emitContentDelta(delta);
                  }
                }
              }
              continue;
            }
          }

          final dynamic choices = json['choices'];
          usageSnapshot = _extractUsageSnapshotFromAny(json) ?? usageSnapshot;
          if (choices is List && choices.isNotEmpty) {
            final dynamic first = choices.first;
            if (first is Map<String, dynamic>) {
              final dynamic finishReason = first['finish_reason'];
              if (finishReason is String &&
                  finishReason.isNotEmpty &&
                  finishReason != 'null') {
                done = true;
              }
              final dynamic delta = first['delta'];
              if (delta is Map<String, dynamic>) {
                toolAccumulator.ingestChatDelta(delta);
                final dynamic reasoningField = delta['reasoning'];
                final dynamic reasoningPart =
                    delta['reasoning_content'] ??
                    delta['reasoningContent'] ??
                    (reasoningField is Map
                        ? (reasoningField['content'] ?? reasoningField['text'])
                        : (reasoningField is String ? reasoningField : null)) ??
                    delta['thinking'];
                if (reasoningPart is String && reasoningPart.isNotEmpty) {
                  emitReasoningDelta(reasoningPart);
                }
                final String part = _extractOpenAIChatText(delta['content']);
                if (part.isNotEmpty) {
                  emitContentDelta(part);
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
        emitReasoningDelta(trailing);
      }
      startFilter.ensureCompleted();

      String cleanedContent = contentBuffer.toString().replaceAll(
        RegExp(r'</?think>'),
        '',
      );
      if (responsesFinalOutputText.isNotEmpty) {
        emitUiLog(
          'EVENT content reconcile streamLen=${cleanedContent.length} finalLen=${responsesFinalOutputText.length}',
        );
        cleanedContent = responsesFinalOutputText;
      }
      final List<AIToolCall> toolCalls = toolAccumulator.finalize();
      final String reasoningText = reasoningBuffer.toString();
      final Duration? reasoningDuration = reasoningText.isEmpty
          ? null
          : DateTime.now().difference(reasoningStart);
      sw.stop();
      final String usage = usageFields(usageSnapshot);

      emitUiLog(
        'PARSED stream contentLen=${cleanedContent.length} reasoningLen=${reasoningText.length} toolCalls=${toolCalls.length}${ttftMs == null ? '' : ' ttftMs=$ttftMs'}${usage.isEmpty ? '' : ' $usage'}',
      );

      try {
        final String summary = [
          'STREAM_DONE $traceId',
          'ctx=${(logContext ?? '').trim()} api=$apiType tookMs=${sw.elapsedMilliseconds}',
          if (providerName.isNotEmpty || providerType.isNotEmpty)
            'provider=${providerName.isEmpty ? '-' : providerName}'
                '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
                ' type=${providerType.isEmpty ? '-' : providerType}',
          'model=${endpoint.model} contentLen=${cleanedContent.length} reasoningLen=${reasoningText.length} toolCalls=${toolCalls.length}${ttftMs == null ? '' : ' ttftMs=$ttftMs'}${usage.isEmpty ? '' : ' $usage'}',
        ].join('\n');
        await FlutterLogger.nativeDebug('AITrace', summary);
      } catch (_) {}

      return _GatewayAggregate(
        content: cleanedContent,
        toolCalls: toolCalls,
        reasoning: reasoningText.isEmpty ? null : reasoningText,
        reasoningDuration: reasoningDuration,
        usage: usageSnapshot,
      );
    } catch (e) {
      sw.stop();
      try {
        final String err = [
          'STREAM_ERR $traceId',
          'ctx=${(logContext ?? '').trim()} api=$apiType tookMs=${sw.elapsedMilliseconds}',
          if (providerName.isNotEmpty || providerType.isNotEmpty)
            'provider=${providerName.isEmpty ? '-' : providerName}'
                '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
                ' type=${providerType.isEmpty ? '-' : providerType}',
          'model=${endpoint.model}',
          'error=$e',
        ].join('\n');
        await FlutterLogger.nativeWarn('AITrace', err);
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  _OpenAIResponse _parseOpenAIResponse(String body) {
    final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;
    final _UsageSnapshot? usage = _extractUsageSnapshotFromAny(data);
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
          final String name =
              fn?['name']?.toString() ?? (it['name']?.toString() ?? '');
          final Object? argsRaw =
              (fn != null ? fn['arguments'] : null) ?? it['arguments'];
          final String args = _stringifyJsonLike(argsRaw);
          if (name.trim().isNotEmpty) {
            toolCalls.add(
              AIToolCall(
                id: id.trim().isEmpty ? _newFallbackToolCallId() : id.trim(),
                name: name.trim(),
                argumentsJson: args,
              ),
            );
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
        usage: usage,
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
    final String content = _extractOpenAIChatText(message['content']);
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
        final String args = _stringifyJsonLike(fn?['arguments']);
        if (name.trim().isEmpty) continue;
        toolCalls.add(
          AIToolCall(
            id: id.trim().isEmpty ? _newFallbackToolCallId() : id.trim(),
            name: name.trim(),
            argumentsJson: args,
          ),
        );
      }
    } else {
      final dynamic fc = message['function_call'];
      if (fc is Map) {
        final Map<String, dynamic> fn = Map<String, dynamic>.from(fc as Map);
        final String name = (fn['name'] as String?) ?? '';
        final String args = _stringifyJsonLike(fn['arguments']);
        if (name.trim().isNotEmpty) {
          toolCalls.add(
            AIToolCall(
              id: 'function_call',
              name: name.trim(),
              argumentsJson: args,
            ),
          );
        }
      }
    }
    final String? reasoning =
        ((message['reasoning_content'] as String?) ??
                (message['reasoning'] as String?) ??
                (message['thinking'] as String?))
            ?.trim();

    return _OpenAIResponse(
      content: content,
      toolCalls: toolCalls,
      reasoning: reasoning?.isEmpty == true ? null : reasoning,
      usage: usage,
    );
  }

  _GoogleResponse _parseGoogleResponse(String body) {
    final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;
    final _UsageSnapshot? usage = _extractUsageSnapshotFromAny(data);
    final List<dynamic>? candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Empty candidates');
    }
    final Map<String, dynamic>? first =
        candidates.first as Map<String, dynamic>?;
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
      usage: usage,
    );
  }

  bool _isGoogleBase(Uri baseUri) {
    final String host = baseUri.host.toLowerCase();
    return host.contains('googleapis.com') ||
        host.contains('generativelanguage');
  }

  bool _isResponsesPath(String path) {
    final String p = path.trim().toLowerCase();
    if (p.isEmpty) return false;
    return p.endsWith('/responses') ||
        p.contains('/responses?') ||
        p == 'responses';
  }

  Uri _buildResponsesUriFromBase(Uri baseUri, String path) {
    String trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      return baseUri.resolve('/v1/responses');
    }

    if (_isResponsesPath(trimmedPath)) {
      final String effectivePath = trimmedPath.startsWith('/')
          ? trimmedPath
          : '/$trimmedPath';
      return baseUri.resolve(effectivePath);
    }

    final String normalized = trimmedPath.startsWith('/')
        ? trimmedPath
        : '/$trimmedPath';
    final RegExp chatCompletions = RegExp(
      r'/chat/completions(?:$|\?)',
      caseSensitive: false,
    );
    if (chatCompletions.hasMatch(normalized)) {
      final String replaced = normalized.replaceFirst(
        chatCompletions,
        '/responses',
      );
      return baseUri.resolve(replaced);
    }

    final int lastSlash = normalized.lastIndexOf('/');
    final String prefix = lastSlash >= 0
        ? normalized.substring(0, lastSlash)
        : '';
    final String versionPrefix = prefix.toLowerCase().endsWith('/v1')
        ? prefix
        : '/v1';
    return baseUri.resolve('$versionPrefix/responses');
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
    this.usage,
  });

  final String content;
  final List<AIToolCall> toolCalls;
  final String? reasoning;
  final Duration? reasoningDuration;
  final _UsageSnapshot? usage;
}

class _OpenAIResponse {
  const _OpenAIResponse({
    required this.content,
    this.toolCalls = const <AIToolCall>[],
    this.reasoning,
    this.usage,
  });

  final String content;
  final List<AIToolCall> toolCalls;
  final String? reasoning;
  final _UsageSnapshot? usage;
}

class _GoogleResponse {
  const _GoogleResponse({required this.content, this.reasoning, this.usage});

  final String content;
  final String? reasoning;
  final _UsageSnapshot? usage;
}

class _UsageSnapshot {
  const _UsageSnapshot({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  bool get isEmpty =>
      promptTokens == null && completionTokens == null && totalTokens == null;
}

class _PreparedRequest {
  const _PreparedRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.isGoogle,
    required this.hasTools,
    required this.useResponsesApi,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final bool isGoogle;
  final bool hasTools;
  final bool useResponsesApi;
}

class _GoogleStreamParts {
  const _GoogleStreamParts({required this.content, required this.thought});

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
  final Map<String, dynamic> candidate = Map<String, dynamic>.from(
    first as Map,
  );
  final dynamic content = candidate['content'];
  if (content is! Map) {
    return const _GoogleStreamParts(content: '', thought: '');
  }
  final Map<String, dynamic> contentMap = Map<String, dynamic>.from(
    content as Map,
  );
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

_UsageSnapshot? _extractUsageSnapshotFromAny(Map<String, dynamic> json) {
  final _UsageSnapshot? direct = _usageFromObject(json['usage']);
  if (direct != null && !direct.isEmpty) return direct;

  final _UsageSnapshot? usageMetadata = _usageFromObject(json['usageMetadata']);
  if (usageMetadata != null && !usageMetadata.isEmpty) return usageMetadata;

  final dynamic resp0 = json['response'];
  if (resp0 is Map) {
    final Map<String, dynamic> resp = Map<String, dynamic>.from(resp0);
    final _UsageSnapshot? fromRespUsage = _usageFromObject(resp['usage']);
    if (fromRespUsage != null && !fromRespUsage.isEmpty) return fromRespUsage;
    final _UsageSnapshot? fromRespUsageMeta = _usageFromObject(
      resp['usageMetadata'],
    );
    if (fromRespUsageMeta != null && !fromRespUsageMeta.isEmpty) {
      return fromRespUsageMeta;
    }
  }

  return null;
}

_UsageSnapshot? _usageFromObject(Object? raw) {
  if (raw is! Map) return null;
  final Map<String, dynamic> map = Map<String, dynamic>.from(raw);

  int? intFromKey(String key) {
    final dynamic v = map[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  int? firstOf(List<String> keys) {
    for (final String key in keys) {
      final int? v = intFromKey(key);
      if (v != null) return v;
    }
    return null;
  }

  int? fromNested(String parentKey, List<String> keys) {
    final dynamic parent0 = map[parentKey];
    if (parent0 is! Map) return null;
    final Map<String, dynamic> parent = Map<String, dynamic>.from(parent0);
    for (final String key in keys) {
      final dynamic v = parent[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final int? parsed = int.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  final int? prompt =
      firstOf(<String>[
        'prompt_tokens',
        'input_tokens',
        'inputTokens',
        'promptTokenCount',
      ]) ??
      fromNested('input_tokens_details', <String>['total']) ??
      fromNested('inputTokensDetails', <String>['total']);

  final int? completion =
      firstOf(<String>[
        'completion_tokens',
        'output_tokens',
        'outputTokens',
        'candidatesTokenCount',
        'completionTokenCount',
      ]) ??
      fromNested('output_tokens_details', <String>['total']) ??
      fromNested('outputTokensDetails', <String>['total']);

  int? total = firstOf(<String>[
    'total_tokens',
    'totalTokens',
    'totalTokenCount',
  ]);
  total ??= (prompt != null && completion != null)
      ? (prompt + completion)
      : null;

  final _UsageSnapshot snapshot = _UsageSnapshot(
    promptTokens: prompt,
    completionTokens: completion,
    totalTokens: total,
  );
  return snapshot.isEmpty ? null : snapshot;
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

String _deltaFromTerminalFull({
  required String previous,
  required String fullText,
}) {
  if (fullText.isEmpty) return '';
  if (previous.isEmpty) return fullText;
  if (fullText.startsWith(previous)) {
    return fullText.substring(previous.length);
  }
  return fullText;
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
    final String namePart =
        (fn?['name'] as String?) ?? (chunk['name'] as String?) ?? '';
    if (namePart.trim().isNotEmpty) {
      name = namePart.trim();
    }
    final String argsPart =
        (fn?['arguments'] as String?) ?? (chunk['arguments'] as String?) ?? '';
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
        final Map<String, dynamic> chunk = Map<String, dynamic>.from(
          raw as Map,
        );
        final dynamic idxRaw = chunk['index'];
        final int idx = idxRaw is int ? idxRaw : i;
        final _ToolCallDraft draft = _drafts.putIfAbsent(
          idx,
          () => _ToolCallDraft(idx),
        );
        draft.mergeFromChunk(chunk);
      }
    }

    final dynamic functionCall =
        delta['function_call'] ?? delta['functionCall'];
    if (functionCall is Map) {
      final Map<String, dynamic> chunk = Map<String, dynamic>.from(
        functionCall as Map,
      );
      final _ToolCallDraft draft = _drafts.putIfAbsent(
        0,
        () => _ToolCallDraft(0),
      );
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

String _extractOpenAIChatText(dynamic node) {
  if (node == null) return '';
  if (node is String) return node;
  if (node is Map) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(node as Map);
    final String type = (map['type'] as String?) ?? '';
    final String text = (map['text'] as String?) ?? '';
    if (text.isNotEmpty) {
      if (type.isEmpty ||
          type == 'text' ||
          type == 'output_text' ||
          type == 'input_text') {
        return text;
      }
    }
    final String fromContent = _extractOpenAIChatText(map['content']);
    if (fromContent.isNotEmpty) return fromContent;
    final String fromParts = _extractOpenAIChatText(map['parts']);
    if (fromParts.isNotEmpty) return fromParts;
    return '';
  }
  if (node is List) {
    final StringBuffer out = StringBuffer();
    for (final dynamic item in node) {
      final String piece = _extractOpenAIChatText(item);
      if (piece.isNotEmpty) out.write(piece);
    }
    return out.toString();
  }
  return '';
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
