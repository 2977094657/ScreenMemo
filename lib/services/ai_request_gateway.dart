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
    this.reasoning,
    this.reasoningDuration,
  });

  final String content;
  final String modelUsed;
  final String? reasoning;
  final Duration? reasoningDuration;
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

  Future<AIGatewayResult> complete({
    required List<AIEndpoint> endpoints,
    required List<AIMessage> messages,
    required String responseStartMarker,
    Duration? timeout,
    bool preferStreaming = true,
    String? logContext,
  }) async {
    if (endpoints.isEmpty) {
      throw Exception('No AI endpoints configured');
    }
    Exception? lastError;
    for (final AIEndpoint endpoint in endpoints) {
      try {
        final _PreparedRequest prepared = _prepareRequest(
          endpoint: endpoint,
          messages: messages,
          stream: preferStreaming,
        );
        if (preferStreaming && _supportsStreaming(prepared)) {
          try {
            final _GatewayAggregate aggregate = await _performStreaming(
              prepared: prepared,
              responseStartMarker: responseStartMarker,
              timeout: timeout,
              logContext: logContext,
            );
            return AIGatewayResult(
              content: aggregate.content,
              reasoning: aggregate.reasoning,
              reasoningDuration: aggregate.reasoningDuration,
              modelUsed: endpoint.model,
            );
          } catch (e) {
            lastError = e is Exception ? e : Exception(e.toString());
            try {
              await FlutterLogger.nativeWarn(
                'AI',
                '[Gateway] stream fallback (${endpoint.baseUrl}): $e',
              );
            } catch (_) {}
          }
        }

        final _PreparedRequest fallback = _prepareRequest(
          endpoint: endpoint,
          messages: messages,
          stream: false,
        );
        final _GatewayAggregate aggregate = await _performNonStreaming(
          prepared: fallback,
          responseStartMarker: responseStartMarker,
          timeout: timeout,
          logContext: logContext,
        );
        return AIGatewayResult(
          content: aggregate.content,
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
        try {
          final _PreparedRequest prepared = _prepareRequest(
            endpoint: endpoint,
            messages: messages,
            stream: true,
          );
          if (!_supportsStreaming(prepared)) {
            final _PreparedRequest fallback = _prepareRequest(
              endpoint: endpoint,
              messages: messages,
              stream: false,
            );
            final _GatewayAggregate aggregate = await _performNonStreaming(
              prepared: fallback,
              responseStartMarker: responseStartMarker,
              timeout: timeout,
              logContext: logContext,
              controller: controller,
            );
            if (!completer.isCompleted) {
              completer.complete(
                AIGatewayResult(
                  content: aggregate.content,
                  reasoning: aggregate.reasoning,
                  reasoningDuration: aggregate.reasoningDuration,
                  modelUsed: endpoint.model,
                ),
              );
            }
            await controller.close();
            return;
          }

          final _GatewayAggregate aggregate = await _performStreaming(
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
              '[Gateway] stream error (${endpoint.baseUrl}): $e',
            );
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
    return !prepared.isGoogle;
  }

  _PreparedRequest _prepareRequest({
    required AIEndpoint endpoint,
    required List<AIMessage> messages,
    required bool stream,
  }) {
    final String trimmedBase = endpoint.baseUrl.trim();
    final Uri baseUri = _resolveBaseUri(trimmedBase);
    final bool isGoogle = _isGoogleBase(baseUri);
    final String? apiKey = endpoint.apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key is empty');
    }

    if (isGoogle) {
      final Uri uri = baseUri.resolve(
        '/v1beta/models/${Uri.encodeComponent(endpoint.model)}:generateContent',
      );
      final Map<String, dynamic> payload = _buildGooglePayload(messages);
      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      };
      return _PreparedRequest(
        uri: uri,
        headers: headers,
        body: jsonEncode(payload),
        isGoogle: true,
      );
    }

    final Uri uri = _buildEndpointUriFromBase(baseUri, endpoint.chatPath);
    final Map<String, dynamic> payload = <String, dynamic>{
      'model': endpoint.model,
      'messages': messages.map((AIMessage m) => m.toJson()).toList(),
      'temperature': _defaultTemperature,
      'stream': stream,
    };
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    return _PreparedRequest(
      uri: uri,
      headers: headers,
      body: jsonEncode(payload),
      isGoogle: false,
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
        '[Gateway] HTTP POST ${prepared.uri} (log=$logContext) bodyLen=${prepared.body.length}',
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
        '[Gateway] HTTP RESP ${response.statusCode} (log=$logContext) bodyLen=${response.body.length}',
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
    final StringBuffer contentBuffer = StringBuffer();
    final StringBuffer reasoningBuffer = StringBuffer();
    final DateTime reasoningStart = DateTime.now();

    try {
      final http.Request request = http.Request('POST', prepared.uri)
        ..headers.addAll(prepared.headers)
        ..body = prepared.body;
      try {
        await FlutterLogger.nativeDebug(
          'AI',
          '[Gateway] HTTP STREAM POST ${prepared.uri} (log=$logContext) bodyLen=${prepared.body.length}',
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
      await for (final String chunk in streamed.stream.transform(utf8.decoder)) {
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
            buffer = '';
            break;
          }
          Map<String, dynamic> json;
          try {
            json = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final dynamic type = json['type'];
          if (type is String) {
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
              final dynamic delta = first['delta'];
              if (delta is Map<String, dynamic>) {
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
        }
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
      final String reasoningText = reasoningBuffer.toString();
      final Duration? reasoningDuration =
          reasoningText.isEmpty ? null : DateTime.now().difference(reasoningStart);
      return _GatewayAggregate(
        content: cleanedContent,
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
    final String? reasoning = ((message['reasoning_content'] as String?) ??
            (message['reasoning'] as String?) ??
            (message['thinking'] as String?))
        ?.trim();
    return _OpenAIResponse(
      content: content,
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
    if (!sanitized.startsWith(marker)) {
      throw InvalidResponseStartException(marker, sanitized);
    }
    String remainder = sanitized.substring(marker.length);
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
    this.reasoning,
    this.reasoningDuration,
  });

  final String content;
  final String? reasoning;
  final Duration? reasoningDuration;
}

class _OpenAIResponse {
  const _OpenAIResponse({
    required this.content,
    this.reasoning,
  });

  final String content;
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
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final bool isGoogle;
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
        final String invalid = _buffer + chunk.substring(index + 1);
        throw InvalidResponseStartException(marker, invalid);
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
    if (_awaiting) {
      throw InvalidResponseStartException(marker, _buffer);
    }
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

