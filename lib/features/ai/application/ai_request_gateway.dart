import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai/application/provider_request_headers.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/features/ai/application/openai_responses_extract.dart';

part 'ai_request_gateway_payloads.dart';
part 'ai_request_gateway_streaming_helpers.dart';

/// 统一的网关事件类型
class AIGatewayEventKind {
  static const String content = 'content';
  static const String reasoning = 'reasoning';
  static const String ui = 'ui';
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
    this.webSearchCalls = const <AIWebSearchCall>[],
    this.citations = const <AIUrlCitation>[],
    this.reasoning,
    this.reasoningDuration,
    this.usagePromptTokens,
    this.usageCompletionTokens,
    this.usageTotalTokens,
    this.usageCacheHitTokens,
    this.usageCacheMissTokens,
  });

  final String content;
  final String modelUsed;
  final List<AIToolCall> toolCalls;
  final List<AIWebSearchCall> webSearchCalls;
  final List<AIUrlCitation> citations;
  final String? reasoning;
  final Duration? reasoningDuration;
  final int? usagePromptTokens;
  final int? usageCompletionTokens;
  final int? usageTotalTokens;
  final int? usageCacheHitTokens;
  final int? usageCacheMissTokens;

  bool get hasUsage =>
      usagePromptTokens != null ||
      usageCompletionTokens != null ||
      usageTotalTokens != null ||
      usageCacheHitTokens != null ||
      usageCacheMissTokens != null;
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

  static const int _keyRetryLimit = 3;
  static const int _keyCooldownMs = 10 * 60 * 1000;

  String _classifyFailure(Object error) {
    final text = error.toString().toLowerCase();
    final codeMatch = RegExp(r'request failed:\s*(\d{3})').firstMatch(text);
    final int? code = codeMatch == null
        ? null
        : int.tryParse(codeMatch.group(1)!);
    if (code == 401 || code == 403) return 'auth_failed';
    if (text.contains('model_not_found') ||
        text.contains('unsupported_model') ||
        text.contains('does not exist') ||
        text.contains('not found') && text.contains('model')) {
      return 'model_not_found';
    }
    if (code == 408 || code == 429 || (code != null && code >= 500)) {
      return 'retryable';
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return 'retryable';
    }
    if (code != null && code >= 400 && code < 500) return 'fatal';
    return 'retryable';
  }

  bool _shouldStopEndpointFallback(String errorType) => errorType == 'fatal';

  bool _shouldCooldown(String errorType) => errorType == 'retryable';

  bool _looksLikeUnsupportedReasoningParam(Object? error) {
    if (error == null) return false;
    final String t = error.toString().toLowerCase();
    if (!(t.contains('reasoning') ||
        t.contains('reasoning_effort') ||
        t.contains('thinking') ||
        t.contains('thinking_budget') ||
        t.contains('enable_thinking'))) {
      return false;
    }
    return t.contains('unknown parameter') ||
        t.contains('unsupported parameter') ||
        t.contains('unrecognized') ||
        t.contains('invalid_request_error') ||
        t.contains('extra inputs are not permitted') ||
        t.contains('not support');
  }

  Future<void> _markEndpointSuccess(AIEndpoint endpoint) async {
    final int? keyId = endpoint.providerKeyId;
    if (keyId == null) return;
    await AIProvidersService.instance.markProviderKeySuccess(keyId);
  }

  Future<void> _markEndpointFailure({
    required AIEndpoint endpoint,
    required String errorType,
    required Object error,
    required int attemptCountForKey,
  }) async {
    final int? keyId = endpoint.providerKeyId;
    if (keyId == null) return;
    final bool auth = errorType == 'auth_failed';
    final bool model = errorType == 'model_not_found';
    final bool retryable = _shouldCooldown(errorType);
    final int? cooldownUntil = retryable && attemptCountForKey >= _keyRetryLimit
        ? DateTime.now().millisecondsSinceEpoch + _keyCooldownMs
        : null;
    await AIProvidersService.instance.markProviderKeyFailure(
      keyId: keyId,
      errorType: errorType,
      errorMessage: error.toString(),
      incrementFailure: retryable,
      cooldownUntilMs: auth ? null : cooldownUntil,
      resetFailureCount: auth || model,
    );
  }

  String _summarizeEndpointFailures(
    List<AIGatewayEndpointFailure> failures,
    Exception? lastError,
  ) {
    if (failures.isEmpty)
      return lastError?.toString() ?? 'No valid AI endpoint available';
    final String model = failures.first.endpoint.model;
    final Map<String, List<AIGatewayEndpointFailure>> byKey =
        <String, List<AIGatewayEndpointFailure>>{};
    for (final f in failures) {
      final e = f.endpoint;
      final String label =
          (e.providerKeyName == null || e.providerKeyName!.trim().isEmpty)
          ? 'key#${e.providerKeyId ?? '-'}'
          : '${e.providerKeyName}#${e.providerKeyId ?? '-'}';
      byKey.putIfAbsent(label, () => <AIGatewayEndpointFailure>[]).add(f);
    }
    final parts = <String>['AI request failed for model $model.'];
    parts.add('Candidate keys: ${byKey.keys.join(', ')}.');
    byKey.forEach((key, items) {
      final last = items.last;
      parts.add(
        '$key: ${items.length} attempt(s), ${last.errorType}, ${last.message}',
      );
    });
    return parts.join(' ');
  }

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
    AIReasoningLevel reasoningLevel = AIReasoningLevel.auto,
    bool forceChatCompletions = false,
    bool trackKeyStats = true,
    String? promptCacheKey,
  }) async {
    if (endpoints.isEmpty) {
      throw Exception('No AI endpoints configured');
    }
    final int imagesCount = _countInputImages(messages);
    final int toolsCount = tools.length;
    Exception? lastError;
    final failures = <AIGatewayEndpointFailure>[];
    final attemptsByKey = <int, int>{};
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
            reasoningLevel: reasoningLevel,
            useResponsesApiOverride: forceChatCompletions ? false : null,
            promptCacheKey: promptCacheKey,
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
          if (trackKeyStats) await _markEndpointSuccess(endpoint);
          return AIGatewayResult(
            content: aggregate.content,
            toolCalls: aggregate.toolCalls,
            webSearchCalls: aggregate.webSearchCalls,
            citations: aggregate.citations,
            reasoning: aggregate.reasoning,
            reasoningDuration: aggregate.reasoningDuration,
            modelUsed: endpoint.model,
            usagePromptTokens: aggregate.usage?.promptTokens,
            usageCompletionTokens: aggregate.usage?.completionTokens,
            usageTotalTokens: aggregate.usage?.totalTokens,
            usageCacheHitTokens: aggregate.usage?.cacheHitTokens,
            usageCacheMissTokens: aggregate.usage?.cacheMissTokens,
          );
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          final String errorType = _classifyFailure(e);
          if (endpoint.providerKeyId != null) {
            final int attemptCount =
                (attemptsByKey[endpoint.providerKeyId!] ?? 0) + 1;
            attemptsByKey[endpoint.providerKeyId!] = attemptCount;
            failures.add(
              AIGatewayEndpointFailure(
                endpoint: endpoint,
                errorType: errorType,
                message: e.toString(),
              ),
            );
            if (trackKeyStats) {
              await _markEndpointFailure(
                endpoint: endpoint,
                errorType: errorType,
                error: e,
                attemptCountForKey: attemptCount,
              );
            }
          }
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
        Future<_GatewayAggregate> performWithLevel(
          AIReasoningLevel level,
        ) async {
          prepared = _prepareRequest(
            endpoint: effectiveEndpoint,
            messages: messages,
            stream: false,
            tools: tools,
            toolChoice: toolChoice,
            reasoningLevel: level,
            useResponsesApiOverride: forceChatCompletions ? false : null,
            promptCacheKey: promptCacheKey,
          );
          return _performNonStreaming(
            endpoint: effectiveEndpoint,
            prepared: prepared!,
            responseStartMarker: responseStartMarker,
            timeout: timeout,
            logContext: logContext,
            imagesCount: imagesCount,
            toolsCount: toolsCount,
          );
        }

        _GatewayAggregate aggregate;
        try {
          aggregate = await performWithLevel(reasoningLevel);
        } catch (err) {
          if (reasoningLevel == AIReasoningLevel.auto ||
              !_looksLikeUnsupportedReasoningParam(err)) {
            rethrow;
          }
          try {
            await FlutterLogger.nativeWarn(
              'AI',
              '[网关] reasoning 参数不兼容，移除后重试（${endpoint.baseUrl}）：$err',
            );
          } catch (_) {}
          aggregate = await performWithLevel(AIReasoningLevel.auto);
        }
        if (trackKeyStats) await _markEndpointSuccess(endpoint);
        return AIGatewayResult(
          content: aggregate.content,
          toolCalls: aggregate.toolCalls,
          webSearchCalls: aggregate.webSearchCalls,
          citations: aggregate.citations,
          reasoning: aggregate.reasoning,
          reasoningDuration: aggregate.reasoningDuration,
          modelUsed: endpoint.model,
          usagePromptTokens: aggregate.usage?.promptTokens,
          usageCompletionTokens: aggregate.usage?.completionTokens,
          usageTotalTokens: aggregate.usage?.totalTokens,
          usageCacheHitTokens: aggregate.usage?.cacheHitTokens,
          usageCacheMissTokens: aggregate.usage?.cacheMissTokens,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        final String errorType = _classifyFailure(e);
        if (endpoint.providerKeyId != null) {
          final int attemptCount =
              (attemptsByKey[endpoint.providerKeyId!] ?? 0) + 1;
          attemptsByKey[endpoint.providerKeyId!] = attemptCount;
          failures.add(
            AIGatewayEndpointFailure(
              endpoint: endpoint,
              errorType: errorType,
              message: e.toString(),
            ),
          );
          if (trackKeyStats) {
            await _markEndpointFailure(
              endpoint: endpoint,
              errorType: errorType,
              error: e,
              attemptCountForKey: attemptCount,
            );
          }
        }
        if (_shouldStopEndpointFallback(errorType)) {
          throw Exception(_summarizeEndpointFailures(failures, lastError));
        }

        // Some OpenAI-compatible relays incorrectly type `tool_choice` as a string
        // in the Responses API response DTOs, and crash when OpenAI returns an object
        // tool_choice (e.g. forced function calling). In that case, retry once using
        // Chat Completions to avoid the relay's Responses parsing path.
        final _PreparedRequest? failedPrepared = prepared;
        if (failedPrepared != null &&
            failedPrepared.useResponsesApi &&
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
              reasoningLevel: reasoningLevel,
              useResponsesApiOverride: false,
              promptCacheKey: promptCacheKey,
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
            if (trackKeyStats) await _markEndpointSuccess(endpoint);
            return AIGatewayResult(
              content: aggregate.content,
              toolCalls: aggregate.toolCalls,
              webSearchCalls: aggregate.webSearchCalls,
              citations: aggregate.citations,
              reasoning: aggregate.reasoning,
              reasoningDuration: aggregate.reasoningDuration,
              modelUsed: chatEndpoint.model,
              usagePromptTokens: aggregate.usage?.promptTokens,
              usageCompletionTokens: aggregate.usage?.completionTokens,
              usageTotalTokens: aggregate.usage?.totalTokens,
              usageCacheHitTokens: aggregate.usage?.cacheHitTokens,
              usageCacheMissTokens: aggregate.usage?.cacheMissTokens,
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
                reasoningLevel: reasoningLevel,
                useResponsesApiOverride: false,
                promptCacheKey: promptCacheKey,
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
              if (trackKeyStats) await _markEndpointSuccess(endpoint);
              return AIGatewayResult(
                content: aggregate.content,
                toolCalls: aggregate.toolCalls,
                webSearchCalls: aggregate.webSearchCalls,
                citations: aggregate.citations,
                reasoning: aggregate.reasoning,
                reasoningDuration: aggregate.reasoningDuration,
                modelUsed: chatEndpoint.model,
                usagePromptTokens: aggregate.usage?.promptTokens,
                usageCompletionTokens: aggregate.usage?.completionTokens,
                usageTotalTokens: aggregate.usage?.totalTokens,
                usageCacheHitTokens: aggregate.usage?.cacheHitTokens,
                usageCacheMissTokens: aggregate.usage?.cacheMissTokens,
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
    throw Exception(_summarizeEndpointFailures(failures, lastError));
  }

  AIGatewayStreamingSession startStreaming({
    required List<AIEndpoint> endpoints,
    required List<AIMessage> messages,
    required String responseStartMarker,
    Duration? timeout,
    String? logContext,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
    AIReasoningLevel reasoningLevel = AIReasoningLevel.auto,
    bool forceChatCompletions = false,
    bool trackKeyStats = true,
    String? promptCacheKey,
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
      final failures = <AIGatewayEndpointFailure>[];
      final attemptsByKey = <int, int>{};
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
            reasoningLevel: reasoningLevel,
            useResponsesApiOverride: forceChatCompletions ? false : null,
            promptCacheKey: promptCacheKey,
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
          if (trackKeyStats) await _markEndpointSuccess(endpoint);
          if (!completer.isCompleted) {
            completer.complete(
              AIGatewayResult(
                content: aggregate.content,
                toolCalls: aggregate.toolCalls,
                webSearchCalls: aggregate.webSearchCalls,
                citations: aggregate.citations,
                reasoning: aggregate.reasoning,
                reasoningDuration: aggregate.reasoningDuration,
                modelUsed: endpoint.model,
                usagePromptTokens: aggregate.usage?.promptTokens,
                usageCompletionTokens: aggregate.usage?.completionTokens,
                usageTotalTokens: aggregate.usage?.totalTokens,
                usageCacheHitTokens: aggregate.usage?.cacheHitTokens,
                usageCacheMissTokens: aggregate.usage?.cacheMissTokens,
              ),
            );
          }
          await controller.close();
          return;
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          final String errorType = _classifyFailure(e);
          if (endpoint.providerKeyId != null) {
            final int attemptCount =
                (attemptsByKey[endpoint.providerKeyId!] ?? 0) + 1;
            attemptsByKey[endpoint.providerKeyId!] = attemptCount;
            failures.add(
              AIGatewayEndpointFailure(
                endpoint: endpoint,
                errorType: errorType,
                message: e.toString(),
              ),
            );
            if (trackKeyStats) {
              await _markEndpointFailure(
                endpoint: endpoint,
                errorType: errorType,
                error: e,
                attemptCountForKey: attemptCount,
              );
            }
          }
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
              reasoningLevel: reasoningLevel,
              promptCacheKey: promptCacheKey,
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
            if (trackKeyStats) await _markEndpointSuccess(endpoint);
            if (!completer.isCompleted) {
              completer.complete(
                AIGatewayResult(
                  content: aggregate.content,
                  toolCalls: aggregate.toolCalls,
                  webSearchCalls: aggregate.webSearchCalls,
                  citations: aggregate.citations,
                  reasoning: aggregate.reasoning,
                  reasoningDuration: aggregate.reasoningDuration,
                  modelUsed: endpoint.model,
                  usagePromptTokens: aggregate.usage?.promptTokens,
                  usageCompletionTokens: aggregate.usage?.completionTokens,
                  usageTotalTokens: aggregate.usage?.totalTokens,
                  usageCacheHitTokens: aggregate.usage?.cacheHitTokens,
                  usageCacheMissTokens: aggregate.usage?.cacheMissTokens,
                ),
              );
            }
            await controller.close();
            return;
          } catch (fallbackErr) {
            lastError = fallbackErr is Exception
                ? fallbackErr
                : Exception(fallbackErr.toString());
            final String fallbackType = _classifyFailure(fallbackErr);
            if (endpoint.providerKeyId != null) {
              final int attemptCount =
                  (attemptsByKey[endpoint.providerKeyId!] ?? 0) + 1;
              attemptsByKey[endpoint.providerKeyId!] = attemptCount;
              failures.add(
                AIGatewayEndpointFailure(
                  endpoint: endpoint,
                  errorType: fallbackType,
                  message: fallbackErr.toString(),
                ),
              );
              if (trackKeyStats) {
                await _markEndpointFailure(
                  endpoint: endpoint,
                  errorType: fallbackType,
                  error: fallbackErr,
                  attemptCountForKey: attemptCount,
                );
              }
            }
            if (_shouldStopEndpointFallback(fallbackType)) break;
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
          Exception(_summarizeEndpointFailures(failures, lastError)),
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
    AIReasoningLevel reasoningLevel = AIReasoningLevel.auto,
    bool? useResponsesApiOverride,
    String? promptCacheKey,
  }) {
    final String trimmedBase = endpoint.baseUrl.trim();
    final Uri baseUri = _resolveBaseUri(trimmedBase);
    final bool isGoogle = _isGoogleBase(baseUri);
    final String? apiKey = endpoint.apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key is empty');
    }
    final String requestBodyStyle = ProviderRequestBodyStyles.normalize(
      endpoint.requestBodyStyle,
    );
    final bool useClaudeCodeMessages =
        requestBodyStyle == ProviderRequestBodyStyles.claudeCodeMessages;
    final bool useAnthropicMessages =
        requestBodyStyle == ProviderRequestBodyStyles.anthropicMessages ||
        useClaudeCodeMessages;
    final bool useCodexResponses =
        requestBodyStyle == ProviderRequestBodyStyles.codexResponses;
    final ProviderRequestIdentity requestIdentity =
        endpoint.requestIdentity ?? ProviderRequestIdentity.create();

    if (isGoogle && !useAnthropicMessages && !useCodexResponses) {
      final String method = stream
          ? 'streamGenerateContent'
          : 'generateContent';
      Uri uri = _buildGoogleGenerateContentUriFromBase(
        baseUri,
        endpoint.chatPath,
        endpoint.model,
        method,
      );
      if (stream) {
        uri = uri.replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            'alt': 'sse',
          },
        );
      }
      final Map<String, dynamic> payload = _buildGooglePayload(
        endpoint: endpoint,
        messages: messages,
        reasoningLevel: reasoningLevel,
      );
      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
        if (stream) 'Accept': 'text/event-stream',
      };
      final Map<String, String> mergedHeaders =
          ProviderRequestHeaders.mergeHeaders(headers, endpoint.requestHeaders);
      return _PreparedRequest(
        uri: uri,
        headers: mergedHeaders,
        body: jsonEncode(payload),
        isGoogle: true,
        hasTools: false,
        useResponsesApi: false,
        requestBodyStyle: ProviderRequestBodyStyles.defaultStyle,
        promptCacheKey: null,
      );
    }

    final bool useResponsesApi =
        useCodexResponses ||
        (useResponsesApiOverride ??
            _shouldUseResponsesApi(
              endpoint: endpoint,
              baseUri: baseUri,
              tools: tools,
            ));
    final Uri uri = useAnthropicMessages
        ? _buildClaudeMessagesUriFromBase(
            baseUri,
            endpoint.chatPath,
            betaQuery: useClaudeCodeMessages,
          )
        : (useResponsesApi
              ? _buildResponsesUriFromBase(baseUri, endpoint.chatPath)
              : _buildEndpointUriFromBase(baseUri, endpoint.chatPath));
    final List<Map<String, dynamic>> effectiveTools =
        useResponsesApi && !useCodexResponses && !useAnthropicMessages
        ? _withAutoResponsesWebSearchTool(endpoint, tools)
        : tools;
    final Map<String, dynamic> payload = useClaudeCodeMessages
        ? _buildClaudeCodeMessagesPayload(
            endpoint: endpoint,
            messages: messages,
            stream: stream,
            tools: tools,
            reasoningLevel: reasoningLevel,
            identity: requestIdentity,
          )
        : (useAnthropicMessages
              ? _buildAnthropicMessagesPayload(
                  endpoint: endpoint,
                  messages: messages,
                  stream: stream,
                  tools: tools,
                  reasoningLevel: reasoningLevel,
                  identity: requestIdentity,
                )
              : (useResponsesApi
                    ? _buildResponsesPayload(
                        endpoint: endpoint,
                        messages: messages,
                        stream: stream,
                        tools: effectiveTools,
                        toolChoice: toolChoice,
                        reasoningLevel: reasoningLevel,
                        codexStyle: useCodexResponses,
                        identity: requestIdentity,
                      )
                    : _buildChatCompletionsPayload(
                        endpoint: endpoint,
                        messages: messages,
                        stream: stream,
                        tools: effectiveTools,
                        toolChoice: toolChoice,
                        reasoningLevel: reasoningLevel,
                      )));
    final String? effectivePromptCacheKey = _effectivePromptCacheKey(
      endpoint: endpoint,
      baseUri: baseUri,
      promptCacheKey: promptCacheKey,
    );
    if (effectivePromptCacheKey != null && !useCodexResponses) {
      payload['prompt_cache_key'] = effectivePromptCacheKey;
    }
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      if (stream) 'Accept': 'text/event-stream',
    };
    if (useClaudeCodeMessages) {
      headers.addAll(<String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $apiKey',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-beta':
            'prompt-caching-scope-2026-01-05,claude-code-20250219',
        'anthropic-dangerous-direct-browser-access': 'true',
        'x-app': 'cli',
        'User-Agent': 'claude-cli/2.1.121 (external, sdk-cli)',
        'X-Claude-Code-Session-Id': requestIdentity.sessionId,
        'x-stainless-arch': 'x64',
        'x-stainless-lang': 'js',
        'x-stainless-os': 'Windows',
        'x-stainless-package-version': '0.81.0',
        'x-stainless-retry-count': '0',
        'x-stainless-runtime': 'node',
        'x-stainless-runtime-version': 'v24.3.0',
        'x-stainless-timeout': '600',
      });
    } else if (useAnthropicMessages) {
      headers.addAll(<String, String>{
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      });
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    if (useCodexResponses) {
      headers.addAll(<String, String>{
        'originator': 'codex_cli_rs',
        'User-Agent': ProviderRequestHeaders.codexUserAgent,
        'session-id': requestIdentity.sessionId,
        'thread-id': requestIdentity.threadId,
        'x-client-request-id': requestIdentity.threadId,
        'x-codex-window-id': requestIdentity.windowId,
      });
    }
    final Map<String, String> mergedHeaders =
        ProviderRequestHeaders.mergeHeaders(headers, endpoint.requestHeaders);
    return _PreparedRequest(
      uri: uri,
      headers: mergedHeaders,
      body: jsonEncode(payload),
      isGoogle: false,
      hasTools: effectiveTools.isNotEmpty,
      useResponsesApi: useResponsesApi && !useAnthropicMessages,
      requestBodyStyle: requestBodyStyle,
      promptCacheKey: useCodexResponses
          ? requestIdentity.threadId
          : effectivePromptCacheKey,
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

  String? _effectivePromptCacheKey({
    required AIEndpoint endpoint,
    required Uri baseUri,
    required String? promptCacheKey,
  }) {
    final String key = (promptCacheKey ?? '').trim();
    if (key.isEmpty) return null;
    final String host = baseUri.host.toLowerCase();
    if (host == 'api.openai.com') return key;
    if (host.endsWith('.api.openai.com')) return key;
    return null;
  }

  AIEndpoint _forceChatCompletionsEndpoint(AIEndpoint endpoint) {
    final String path = endpoint.chatPath.trim();
    if (!_isResponsesPath(path)) return endpoint;
    return AIEndpoint(
      groupId: endpoint.groupId,
      providerId: endpoint.providerId,
      providerName: endpoint.providerName,
      providerType: endpoint.providerType,
      providerKeyId: endpoint.providerKeyId,
      providerKeyName: endpoint.providerKeyName,
      providerKeyPriority: endpoint.providerKeyPriority,
      baseUrl: endpoint.baseUrl,
      apiKey: endpoint.apiKey,
      model: endpoint.model,
      chatPath: '/v1/chat/completions',
      useResponseApi: endpoint.useResponseApi,
      requestHeaders: endpoint.requestHeaders,
      requestBodyStyle: ProviderRequestBodyStyles.defaultStyle,
      requestIdentity: endpoint.requestIdentity,
    );
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
      return ProviderRequestHeaders.redactForLog(headers);
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
        controller.add(
          AIGatewayEvent(AIGatewayEventKind.ui, jsonEncode(payload)),
        );
      } catch (_) {}
    }

    final String traceId = _newTraceId();
    final Stopwatch sw = Stopwatch()..start();

    final String apiType = prepared.apiTypeLabelForStream(false);
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
      if (usage.cacheHitTokens != null) {
        parts.add('cacheHitTokens=${usage.cacheHitTokens}');
      }
      if (usage.cacheMissTokens != null) {
        parts.add('cacheMissTokens=${usage.cacheMissTokens}');
      }
      return parts.join(' ');
    }

    await _logPreparedRequestSummary(
      traceId: traceId,
      endpoint: endpoint,
      prepared: prepared,
      logContext: (logContext ?? '').trim(),
      apiType: apiType,
      stream: false,
    );

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

    final _OpenAIResponse parsed = prepared.isClaudeMessages
        ? _parseClaudeMessagesResponse(response.body)
        : _parseOpenAIResponse(response.body);
    final bool hasToolCalls = parsed.toolCalls.isNotEmpty;
    final String sanitized = hasToolCalls
        ? _trimLeadingIgnorable(parsed.content)
        : _stripResponseStart(responseStartMarker, parsed.content);
    final String usage = usageFields(parsed.usage);
    emitUiLog(
      'PARSED ${prepared.isClaudeMessages ? 'anthropic' : 'openai'} contentLen=${sanitized.length} toolCalls=${parsed.toolCalls.length} reasoningLen=${(parsed.reasoning ?? '').length}${usage.isEmpty ? '' : ' $usage'}',
    );
    if (usage.isEmpty) {
      try {
        await FlutterLogger.nativeWarn(
          'AITrace',
          [
            'USAGE_MISSING $traceId',
            '${response.statusCode} ${prepared.uri}',
            'ctx=${(logContext ?? '').trim()} api=$apiType stream=0 tookMs=${sw.elapsedMilliseconds}',
            'model=${endpoint.model} contentLen=${sanitized.length} toolCalls=${parsed.toolCalls.length} reasoningLen=${(parsed.reasoning ?? '').length}',
          ].join('\n'),
        );
      } catch (_) {}
    }
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
      webSearchCalls: parsed.webSearchCalls,
      citations: parsed.citations,
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
    final Map<String, AIWebSearchCall> webSearchCallsByKey =
        <String, AIWebSearchCall>{};
    final Map<String, AIUrlCitation> citationsByKey = <String, AIUrlCitation>{};
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
      if (usage.cacheHitTokens != null) {
        parts.add('cacheHitTokens=${usage.cacheHitTokens}');
      }
      if (usage.cacheMissTokens != null) {
        parts.add('cacheMissTokens=${usage.cacheMissTokens}');
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

    AIWebSearchCall? rememberWebSearchCall(AIWebSearchCall call) {
      if (call.isEmpty) return null;
      final String id = (call.id ?? '').trim();
      final String key = id.isNotEmpty
          ? id
          : [
              (call.actionType ?? '').trim(),
              (call.query ?? '').trim(),
              call.queries.join('|'),
              (call.url ?? '').trim(),
              (call.pattern ?? '').trim(),
            ].join('\u0001');
      final AIWebSearchCall? previous = webSearchCallsByKey[key];
      final List<AIWebSearchCall> existing = previous == null
          ? const <AIWebSearchCall>[]
          : <AIWebSearchCall>[previous];
      final AIWebSearchCall merged = mergeAIWebSearchCalls(
        existing,
        <AIWebSearchCall>[call],
      ).first;
      webSearchCallsByKey[key] = merged;
      return merged;
    }

    void emitWebSearchCall(AIWebSearchCall call) {
      if (controller == null || call.isEmpty) return;
      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 'web_search_call',
        'call': call.toJson(),
      };
      try {
        controller.add(
          AIGatewayEvent(AIGatewayEventKind.ui, jsonEncode(payload)),
        );
      } catch (_) {}
    }

    AIWebSearchCall webSearchStatusCallFromEvent(
      Map<String, dynamic> eventJson,
      String eventType,
    ) {
      String status = eventType.split('.').last.trim();
      if (status == 'started') status = 'in_progress';
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final bool active = status == 'in_progress' || status == 'searching';
      final bool finished = status == 'completed' || status == 'failed';
      final String id =
          ((eventJson['item_id'] as String?) ??
                  (eventJson['itemId'] as String?) ??
                  (eventJson['id'] as String?) ??
                  '')
              .trim();
      return AIWebSearchCall(
        id: id.isEmpty ? null : id,
        status: status,
        startedAtMs: active ? nowMs : null,
        completedAtMs: finished ? nowMs : null,
      );
    }

    void rememberCitation(AIUrlCitation citation) {
      final String url = citation.url.trim();
      if (url.isEmpty) return;
      final String key = <Object?>[
        url,
        citation.title ?? '',
        citation.startIndex ?? '',
        citation.endIndex ?? '',
      ].join('\u0001');
      citationsByKey[key] = citation;
    }

    void emitCitation(AIUrlCitation citation) {
      if (controller == null || citation.url.trim().isEmpty) return;
      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 'url_citation',
        'citation': citation.toJson(),
      };
      try {
        controller.add(
          AIGatewayEvent(AIGatewayEventKind.ui, jsonEncode(payload)),
        );
      } catch (_) {}
    }

    void rememberAndEmitCitationsFromAnnotations(Object? raw) {
      for (final AIUrlCitation citation in _extractUrlCitations(raw)) {
        rememberCitation(citation);
        emitCitation(citation);
      }
    }

    void rememberCitationsFromResponsesMessage(Map<String, dynamic> item) {
      if (item['type'] != 'message') return;
      final dynamic content = item['content'];
      if (content is! List) return;
      for (final dynamic partRaw in content) {
        if (partRaw is! Map) continue;
        final Map<String, dynamic> part = Map<String, dynamic>.from(partRaw);
        rememberAndEmitCitationsFromAnnotations(part['annotations']);
      }
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
      return ProviderRequestHeaders.redactForLog(headers);
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
        controller.add(
          AIGatewayEvent(AIGatewayEventKind.ui, jsonEncode(payload)),
        );
      } catch (_) {}
    }

    final String traceId = _newTraceId();

    final String apiType = prepared.apiTypeLabelForStream(true);
    final String providerName = (endpoint.providerName ?? '').trim();
    final String providerType = (endpoint.providerType ?? '').trim();
    final String providerIdText = endpoint.providerId == null
        ? ''
        : endpoint.providerId.toString();

    void logUsageSnapshot(String stage, _UsageSnapshot? usage) {
      final String fields = usageFields(usage);
      unawaited(
        FlutterLogger.nativeDebug(
          'AIUsageTrace',
          [
            '$stage $traceId',
            'ctx=${(logContext ?? '').trim()} api=$apiType stream=1 tookMs=${sw.elapsedMilliseconds}',
            'model=${endpoint.model} usage=${fields.isEmpty ? '-' : fields}',
          ].join('\n'),
        ).catchError((_) {}),
      );
    }

    try {
      await _logPreparedRequestSummary(
        traceId: traceId,
        endpoint: endpoint,
        prepared: prepared,
        logContext: (logContext ?? '').trim(),
        apiType: apiType,
        stream: true,
      );
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
            json = Map<String, dynamic>.from(decoded);
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
            final _UsageSnapshot? incomingUsage = _extractUsageSnapshotFromAny(
              json,
            );
            if (incomingUsage != null && !incomingUsage.isEmpty) {
              usageSnapshot = incomingUsage;
              logUsageSnapshot('STREAM_USAGE_PARSED', usageSnapshot);
            }

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
            final _UsageSnapshot? incomingUsage = _extractUsageSnapshotFromAny(
              json,
            );
            if (incomingUsage != null && !incomingUsage.isEmpty) {
              usageSnapshot = incomingUsage;
              logUsageSnapshot('STREAM_USAGE_PARSED', usageSnapshot);
            }
            if (type == 'response.completed') {
              final dynamic resp0 = json['response'];
              if (resp0 is Map) {
                final _UsageSnapshot? completedUsage =
                    _extractUsageSnapshotFromAny(
                      Map<String, dynamic>.from(resp0),
                    );
                if (completedUsage != null && !completedUsage.isEmpty) {
                  usageSnapshot = completedUsage;
                  logUsageSnapshot('STREAM_USAGE_PARSED', usageSnapshot);
                }
              }
            }
            if (type == 'response.completed') {
              emitUiLog(
                'EVENT completed',
                extra: json['response'] ?? json['usage'] ?? '',
              );
              final dynamic resp = json['response'];
              if (resp is Map) {
                final dynamic output = resp['output'];
                if (output is List) {
                  for (final dynamic rawItem in output) {
                    if (rawItem is! Map) continue;
                    final Map<String, dynamic> item = Map<String, dynamic>.from(
                      rawItem,
                    );
                    final AIWebSearchCall? call = _parseWebSearchCall(item);
                    if (call != null) {
                      final AIWebSearchCall? merged = rememberWebSearchCall(
                        call,
                      );
                      if (merged != null) emitWebSearchCall(merged);
                    }
                    rememberCitationsFromResponsesMessage(item);
                  }
                }
              }
              done = true;
              continue;
            }
            if (type.startsWith('response.web_search_call.')) {
              final AIWebSearchCall? merged = rememberWebSearchCall(
                webSearchStatusCallFromEvent(json, type),
              );
              if (merged != null) {
                emitWebSearchCall(merged);
                emitUiLog(
                  'EVENT web_search_call status=${merged.status ?? '-'} id=${merged.id ?? '-'}',
                );
              }
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
                  itemRaw,
                );
                final String itemType = (item['type'] as String?) ?? '';

                if (itemType == 'web_search_call') {
                  final AIWebSearchCall? call = _parseWebSearchCall(item);
                  if (call != null) {
                    final AIWebSearchCall? merged = rememberWebSearchCall(call);
                    if (merged != null) emitWebSearchCall(merged);
                    emitUiLog(
                      'EVENT output_item.web_search status=${call.status ?? '-'} action=${call.actionType ?? '-'}',
                    );
                  }
                  continue;
                }

                if (itemType == 'message') {
                  rememberCitationsFromResponsesMessage(item);
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
                final Map<String, dynamic> p = Map<String, dynamic>.from(part);
                final String partType = (p['type'] as String?) ?? '';
                final String txt = (p['text'] as String?) ?? '';
                rememberAndEmitCitationsFromAnnotations(p['annotations']);
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
            if (prepared.isClaudeMessages) {
              if (type == 'message_stop') {
                done = true;
                continue;
              }
              if (type == 'message_delta') {
                final _UsageSnapshot? deltaUsage = _extractUsageSnapshotFromAny(
                  json,
                );
                if (deltaUsage != null && !deltaUsage.isEmpty) {
                  usageSnapshot = deltaUsage;
                  logUsageSnapshot('STREAM_USAGE_PARSED', usageSnapshot);
                }
                continue;
              }
              if (type == 'content_block_delta') {
                final dynamic deltaRaw = json['delta'];
                if (deltaRaw is Map) {
                  final Map<String, dynamic> delta = Map<String, dynamic>.from(
                    deltaRaw,
                  );
                  final String deltaType = (delta['type'] as String? ?? '')
                      .trim();
                  final String text =
                      (delta['text'] as String?) ??
                      (delta['thinking'] as String?) ??
                      '';
                  if (text.isNotEmpty) {
                    if (deltaType == 'thinking_delta' ||
                        delta.containsKey('thinking')) {
                      emitReasoningDelta(text);
                    } else {
                      emitContentDelta(text);
                    }
                  }
                }
                continue;
              }
              if (type == 'content_block_stop') {
                continue;
              }
            }
          }

          final dynamic choices = json['choices'];
          final _UsageSnapshot? incomingUsage = _extractUsageSnapshotFromAny(
            json,
          );
          if (incomingUsage != null && !incomingUsage.isEmpty) {
            usageSnapshot = incomingUsage;
            logUsageSnapshot('STREAM_USAGE_PARSED', usageSnapshot);
          }
          if (choices is List && choices.isNotEmpty) {
            final dynamic first = choices.first;
            if (first is Map<String, dynamic>) {
              final dynamic finishReason = first['finish_reason'];
              if (finishReason is String &&
                  finishReason.isNotEmpty &&
                  finishReason != 'null') {
                emitUiLog(
                  'EVENT chat.finish_reason=$finishReason keepReadingForUsage=1',
                );
                try {
                  await FlutterLogger.nativeDebug(
                    'AIUsageTrace',
                    [
                      'STREAM_FINISH_REASON $traceId',
                      'ctx=${(logContext ?? '').trim()} api=$apiType stream=1 tookMs=${sw.elapsedMilliseconds}',
                      'model=${endpoint.model} finishReason=$finishReason keepReadingForUsage=1 usage=${usageFields(usageSnapshot).isEmpty ? '-' : usageFields(usageSnapshot)}',
                    ].join('\n'),
                  );
                } catch (_) {}
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

      if (usage.isEmpty) {
        try {
          await FlutterLogger.nativeWarn(
            'AITrace',
            [
              'USAGE_MISSING $traceId',
              'ctx=${(logContext ?? '').trim()} api=$apiType stream=1 tookMs=${sw.elapsedMilliseconds}',
              if (providerName.isNotEmpty || providerType.isNotEmpty)
                'provider=${providerName.isEmpty ? '-' : providerName}'
                    '${providerIdText.isEmpty ? '' : '($providerIdText)'}'
                    ' type=${providerType.isEmpty ? '-' : providerType}',
              'model=${endpoint.model} contentLen=${cleanedContent.length} reasoningLen=${reasoningText.length} toolCalls=${toolCalls.length}${ttftMs == null ? '' : ' ttftMs=$ttftMs'}',
            ].join('\n'),
          );
        } catch (_) {}
      }

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
        webSearchCalls: webSearchCallsByKey.values.toList(growable: false),
        citations: citationsByKey.values.toList(growable: false),
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
      final List<dynamic> outs = data['output'] as List<dynamic>;
      final StringBuffer cbuf = StringBuffer();
      final StringBuffer rbuf = StringBuffer();
      final List<AIToolCall> toolCalls = <AIToolCall>[];
      final Map<String, AIWebSearchCall> webSearchCallsByKey =
          <String, AIWebSearchCall>{};
      final Map<String, AIUrlCitation> citationsByKey =
          <String, AIUrlCitation>{};
      void rememberWebSearchCall(AIWebSearchCall call) {
        if (call.isEmpty) return;
        final String id = (call.id ?? '').trim();
        final String key = id.isNotEmpty
            ? id
            : [
                (call.actionType ?? '').trim(),
                (call.query ?? '').trim(),
                call.queries.join('|'),
                (call.url ?? '').trim(),
                (call.pattern ?? '').trim(),
              ].join('\u0001');
        final AIWebSearchCall? previous = webSearchCallsByKey[key];
        final List<AIWebSearchCall> existing = previous == null
            ? const <AIWebSearchCall>[]
            : <AIWebSearchCall>[previous];
        webSearchCallsByKey[key] = mergeAIWebSearchCalls(
          existing,
          <AIWebSearchCall>[call],
        ).first;
      }

      void rememberCitation(AIUrlCitation citation) {
        final String url = citation.url.trim();
        if (url.isEmpty) return;
        final String key = <Object?>[
          url,
          citation.title ?? '',
          citation.startIndex ?? '',
          citation.endIndex ?? '',
        ].join('\u0001');
        citationsByKey[key] = citation;
      }

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
                for (final AIUrlCitation citation in _extractUrlCitations(
                  p['annotations'],
                )) {
                  rememberCitation(citation);
                }
                final String txt = (p['text'] as String?) ?? '';
                if (txt.isNotEmpty) cbuf.write(txt);
              }
            }
          }
        } else if (type == 'web_search_call') {
          final AIWebSearchCall? call = _parseWebSearchCall(it);
          if (call != null) rememberWebSearchCall(call);
        }
      }
      final String content = cbuf.toString();
      final String reasoning = rbuf.toString();
      return _OpenAIResponse(
        content: content,
        toolCalls: toolCalls,
        webSearchCalls: webSearchCallsByKey.values.toList(growable: false),
        citations: citationsByKey.values.toList(growable: false),
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
        final map = Map<String, dynamic>.from(tc);
        final String id = (map['id'] as String?) ?? '';
        final Map<String, dynamic>? fn = map['function'] is Map
            ? Map<String, dynamic>.from(
                map['function'] as Map<dynamic, dynamic>,
              )
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
        final Map<String, dynamic> fn = Map<String, dynamic>.from(fc);
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

  _OpenAIResponse _parseClaudeMessagesResponse(String body) {
    final Map<String, dynamic> data = jsonDecode(body) as Map<String, dynamic>;
    final StringBuffer content = StringBuffer();
    final StringBuffer reasoning = StringBuffer();
    final List<AIToolCall> toolCalls = <AIToolCall>[];
    final dynamic parts = data['content'];
    if (parts is List) {
      for (final dynamic raw in parts) {
        if (raw is! Map) continue;
        final Map<String, dynamic> part = Map<String, dynamic>.from(raw);
        final String type = (part['type'] as String? ?? '').trim();
        if (type == 'text') {
          final String text = (part['text'] as String? ?? '');
          if (text.isNotEmpty) content.write(text);
        } else if (type == 'thinking') {
          final String text = (part['thinking'] as String? ?? '');
          if (text.isNotEmpty) reasoning.write(text);
        } else if (type == 'tool_use') {
          final String name = (part['name'] as String? ?? '').trim();
          if (name.isEmpty) continue;
          final String id = ((part['id'] as String?) ?? '').trim();
          toolCalls.add(
            AIToolCall(
              id: id.isEmpty ? _newFallbackToolCallId() : id,
              name: name,
              argumentsJson: jsonEncode(part['input'] ?? <String, dynamic>{}),
            ),
          );
        }
      }
    }
    return _OpenAIResponse(
      content: content.toString(),
      toolCalls: toolCalls,
      reasoning: reasoning.isEmpty ? null : reasoning.toString(),
      usage: _extractUsageSnapshotFromAny(data),
    );
  }

  AIWebSearchCall? _parseWebSearchCall(Map<String, dynamic> item) {
    if (item['type'] != 'web_search_call') return null;
    String? readString(Object? value) {
      final String text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    int? readInt(Object? value) {
      final int n = value is num
          ? value.toInt()
          : int.tryParse(value?.toString().trim() ?? '') ?? 0;
      return n > 0 ? n : null;
    }

    List<String> readStrings(Object? value) {
      if (value is! List) return const <String>[];
      return value
          .map((Object? e) => e?.toString().trim() ?? '')
          .where((String e) => e.isNotEmpty)
          .toList(growable: false);
    }

    final Map<String, dynamic> action = item['action'] is Map
        ? Map<String, dynamic>.from(item['action'] as Map)
        : const <String, dynamic>{};
    List<AIWebSearchSource> readSources(Object? value) {
      if (value is! List) return const <AIWebSearchSource>[];
      return value
          .whereType<Map>()
          .map(
            (Map e) => AIWebSearchSource.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((AIWebSearchSource e) => !e.isEmpty)
          .toList(growable: false);
    }

    final String? status = readString(item['status']);
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final bool activeStatus = status == 'in_progress' || status == 'searching';
    final bool finishedStatus = status == 'completed' || status == 'failed';
    final AIWebSearchCall call = AIWebSearchCall(
      id: readString(item['id']),
      status: status,
      actionType: readString(action['type']),
      query: readString(action['query']) ?? readString(item['query']),
      queries: readStrings(action['queries'] ?? item['queries']),
      url: readString(action['url']) ?? readString(item['url']),
      pattern: readString(action['pattern']) ?? readString(item['pattern']),
      sources: readSources(action['sources'] ?? item['sources']),
      startedAtMs:
          readInt(item['started_at_ms']) ??
          readInt(item['startedAtMs']) ??
          readInt(action['started_at_ms']) ??
          readInt(action['startedAtMs']) ??
          (activeStatus ? nowMs : null),
      completedAtMs:
          readInt(item['completed_at_ms']) ??
          readInt(item['completedAtMs']) ??
          readInt(action['completed_at_ms']) ??
          readInt(action['completedAtMs']) ??
          (finishedStatus ? nowMs : null),
      durationMs:
          readInt(item['duration_ms']) ??
          readInt(item['durationMs']) ??
          readInt(action['duration_ms']) ??
          readInt(action['durationMs']),
    );
    return call.isEmpty ? null : call;
  }

  List<AIUrlCitation> _extractUrlCitations(Object? annotationsRaw) {
    if (annotationsRaw is! List) return const <AIUrlCitation>[];
    final List<AIUrlCitation> out = <AIUrlCitation>[];
    int? readInt(Map<String, dynamic> map, String snake, String camel) {
      final Object? value = map[snake] ?? map[camel];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    String readString(Object? value) => value?.toString().trim() ?? '';

    for (final Object? raw in annotationsRaw) {
      if (raw is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
      if (map['type'] != 'url_citation') continue;
      final Object? nestedRaw = map['url_citation'];
      final Map<String, dynamic> nested = nestedRaw is Map
          ? Map<String, dynamic>.from(nestedRaw)
          : const <String, dynamic>{};
      final String url = readString(map['url']).isNotEmpty
          ? readString(map['url'])
          : readString(nested['url']);
      if (url.isEmpty) continue;
      final String title = readString(map['title']).isNotEmpty
          ? readString(map['title'])
          : readString(nested['title']);
      out.add(
        AIUrlCitation(
          url: url,
          title: title.isEmpty ? null : title,
          startIndex: readInt(map, 'start_index', 'startIndex'),
          endIndex: readInt(map, 'end_index', 'endIndex'),
        ),
      );
    }
    return out;
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

  Uri _buildClaudeMessagesUriFromBase(
    Uri baseUri,
    String path, {
    bool betaQuery = false,
  }) {
    String trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      return baseUri.resolve(
        betaQuery ? '/v1/messages?beta=true' : '/v1/messages',
      );
    }
    if (trimmedPath.toLowerCase().contains('/messages') ||
        trimmedPath.toLowerCase() == 'messages') {
      final String effectivePath = trimmedPath.startsWith('/')
          ? trimmedPath
          : '/$trimmedPath';
      final Uri uri = baseUri.resolve(effectivePath);
      return betaQuery ? _withBetaQuery(uri) : uri;
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
        betaQuery ? '/messages?beta=true' : '/messages',
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
    return baseUri.resolve(
      betaQuery
          ? '$versionPrefix/messages?beta=true'
          : '$versionPrefix/messages',
    );
  }

  Uri _withBetaQuery(Uri uri) {
    if (uri.queryParameters['beta'] == 'true') return uri;
    final Map<String, String> query = <String, String>{
      ...uri.queryParameters,
      'beta': 'true',
    };
    return uri.replace(queryParameters: query);
  }

  Uri _buildGoogleGenerateContentUriFromBase(
    Uri baseUri,
    String path,
    String model,
    String method,
  ) {
    final String modelId = model.trim().startsWith('models/')
        ? model.trim().substring('models/'.length)
        : model.trim();
    final String encodedModel = Uri.encodeComponent(modelId);
    final String defaultPath = '/v1beta/models/$encodedModel:$method';
    final String trimmedPath = path.trim();
    if (trimmedPath.isEmpty) return baseUri.resolve(defaultPath);

    final String normalizedPath = trimmedPath.startsWith('/')
        ? trimmedPath
        : '/$trimmedPath';
    final String lowerPath = normalizedPath.toLowerCase();
    if (!normalizedPath.contains('{model}') &&
        !lowerPath.contains('/models/')) {
      return baseUri.resolve(defaultPath);
    }
    final String modelResource = 'models/$encodedModel';
    final String resolvedPath = normalizedPath
        .replaceAll('{model=models/*}', modelResource)
        .replaceAll('{model}', encodedModel)
        .replaceAll(':generateContent', ':$method')
        .replaceAll(':streamGenerateContent', ':$method');
    if (resolvedPath.contains('{model')) {
      return baseUri.resolve(defaultPath);
    }
    return baseUri.resolve(resolvedPath);
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
    this.webSearchCalls = const <AIWebSearchCall>[],
    this.citations = const <AIUrlCitation>[],
    this.reasoning,
    this.reasoningDuration,
    this.usage,
  });

  final String content;
  final List<AIToolCall> toolCalls;
  final List<AIWebSearchCall> webSearchCalls;
  final List<AIUrlCitation> citations;
  final String? reasoning;
  final Duration? reasoningDuration;
  final _UsageSnapshot? usage;
}

class _OpenAIResponse {
  const _OpenAIResponse({
    required this.content,
    this.toolCalls = const <AIToolCall>[],
    this.webSearchCalls = const <AIWebSearchCall>[],
    this.citations = const <AIUrlCitation>[],
    this.reasoning,
    this.usage,
  });

  final String content;
  final List<AIToolCall> toolCalls;
  final List<AIWebSearchCall> webSearchCalls;
  final List<AIUrlCitation> citations;
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
    this.cacheHitTokens,
    this.cacheMissTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? cacheHitTokens;
  final int? cacheMissTokens;

  bool get isEmpty =>
      promptTokens == null &&
      completionTokens == null &&
      totalTokens == null &&
      cacheHitTokens == null &&
      cacheMissTokens == null;
}

class _PreparedRequest {
  const _PreparedRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.isGoogle,
    required this.hasTools,
    required this.useResponsesApi,
    required this.requestBodyStyle,
    required this.promptCacheKey,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final bool isGoogle;
  final bool hasTools;
  final bool useResponsesApi;
  final String requestBodyStyle;
  final String? promptCacheKey;

  bool get isClaudeMessages =>
      requestBodyStyle == ProviderRequestBodyStyles.anthropicMessages ||
      requestBodyStyle == ProviderRequestBodyStyles.claudeCodeMessages;

  String get apiTypeLabel {
    if (isGoogle) return 'google.generateContent';
    if (isClaudeMessages) return 'anthropic.messages';
    return useResponsesApi ? 'openai.responses' : 'openai.chat.completions';
  }

  String apiTypeLabelForStream(bool stream) {
    if (!isGoogle) return apiTypeLabel;
    return stream ? 'google.streamGenerateContent' : 'google.generateContent';
  }
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
  final Map<String, dynamic> candidate = Map<String, dynamic>.from(first);
  final dynamic content = candidate['content'];
  if (content is! Map) {
    return const _GoogleStreamParts(content: '', thought: '');
  }
  final Map<String, dynamic> contentMap = Map<String, dynamic>.from(content);
  final dynamic parts = contentMap['parts'];
  if (parts is! List || parts.isEmpty) {
    return const _GoogleStreamParts(content: '', thought: '');
  }
  final StringBuffer contentOut = StringBuffer();
  final StringBuffer thoughtOut = StringBuffer();
  for (final dynamic p in parts) {
    if (p is! Map) continue;
    final Map<String, dynamic> part = Map<String, dynamic>.from(p);
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

  final int? anthropicInput = firstOf(<String>['input_tokens', 'inputTokens']);
  final int? anthropicCacheRead = firstOf(<String>[
    'cache_read_input_tokens',
    'cacheReadInputTokens',
  ]);
  final int? anthropicCacheCreation = firstOf(<String>[
    'cache_creation_input_tokens',
    'cacheCreationInputTokens',
  ]);
  final bool hasAnthropicCacheFields =
      anthropicCacheRead != null || anthropicCacheCreation != null;

  final int? cacheHit =
      firstOf(<String>[
        'prompt_cache_hit_tokens',
        'promptCacheHitTokens',
        'cache_hit_tokens',
        'cacheHitTokens',
        'cached_tokens',
        'cachedTokens',
        'cache_read_input_tokens',
        'cacheReadInputTokens',
        'cachedContentTokenCount',
      ]) ??
      fromNested('prompt_tokens_details', <String>[
        'cached_tokens',
        'cache_hit_tokens',
      ]) ??
      fromNested('promptTokensDetails', <String>[
        'cachedTokens',
        'cacheHitTokens',
      ]) ??
      fromNested('input_tokens_details', <String>[
        'cached_tokens',
        'cache_hit_tokens',
      ]) ??
      fromNested('inputTokensDetails', <String>[
        'cachedTokens',
        'cacheHitTokens',
      ]);

  final int? cacheMiss = firstOf(<String>[
    'prompt_cache_miss_tokens',
    'promptCacheMissTokens',
    'cache_miss_tokens',
    'cacheMissTokens',
    'cache_write_input_tokens',
    'cacheWriteInputTokens',
    'cache_creation_input_tokens',
    'cacheCreationInputTokens',
  ]);

  final int? prompt = hasAnthropicCacheFields && anthropicInput != null
      ? anthropicInput +
            (anthropicCacheRead ?? 0) +
            (anthropicCacheCreation ?? 0)
      : firstOf(<String>[
              'prompt_tokens',
              'input_tokens',
              'inputTokens',
              'promptTokenCount',
            ]) ??
            fromNested('input_tokens_details', <String>['total']) ??
            fromNested('inputTokensDetails', <String>['total']);

  final int? googleCandidates = firstOf(<String>[
    'candidatesTokenCount',
    'completionTokenCount',
  ]);
  final int? googleThoughts = intFromKey('thoughtsTokenCount');
  final int? completion = (googleCandidates != null || googleThoughts != null)
      ? (googleCandidates ?? 0) + (googleThoughts ?? 0)
      : firstOf(<String>[
              'completion_tokens',
              'output_tokens',
              'outputTokens',
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
    cacheHitTokens: cacheHit,
    cacheMissTokens: cacheMiss,
  );
  return snapshot.isEmpty ? null : snapshot;
}
