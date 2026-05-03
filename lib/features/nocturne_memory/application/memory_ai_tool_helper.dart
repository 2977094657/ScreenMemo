import 'dart:convert';

import 'package:screen_memo/features/ai/application/ai_request_gateway.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';

class MemoryStructuredToolResult {
  const MemoryStructuredToolResult({
    required this.payload,
    required this.modelUsed,
    required this.rawText,
    required this.viaToolCall,
  });

  final Map<String, dynamic> payload;
  final String modelUsed;
  final String rawText;
  final bool viaToolCall;
}

class MemoryAIToolHelper {
  MemoryAIToolHelper._internal();

  static final MemoryAIToolHelper instance = MemoryAIToolHelper._internal();

  final AIRequestGateway _gateway = AIRequestGateway.instance;
  final AISettingsService _settings = AISettingsService.instance;

  Future<MemoryStructuredToolResult> callObjectTool({
    required String logContext,
    required List<AIMessage> messages,
    required String toolName,
    required String toolDescription,
    required Map<String, dynamic> parametersSchema,
    Duration timeout = const Duration(seconds: 90),
    String context = 'memory',
    bool allowTextFallback = false,
  }) async {
    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: context,
    );
    if (endpoints.isEmpty) {
      throw StateError('未配置可用的 AI Endpoint（$context 上下文）');
    }
    final Map<String, dynamic> strictSchema = _strictParametersSchema(
      parametersSchema,
    );
    if (context.trim().toLowerCase() == 'memory') {
      _assertMemoryPayloadHasNoForbiddenTextSources(messages);
    }
    final Map<String, dynamic> tool = <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': toolName,
        'description': toolDescription,
        'parameters': strictSchema,
        'strict': true,
      },
    };
    final Object nestedChoice = <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{'name': toolName},
    };

    final AIGatewayResult result = await _gateway.complete(
      endpoints: endpoints,
      messages: messages,
      responseStartMarker: '',
      timeout: timeout,
      preferStreaming: false,
      logContext: logContext,
      tools: <Map<String, dynamic>>[tool],
      toolChoice: nestedChoice,
      forceChatCompletions: true,
    );

    for (final AIToolCall call in result.toolCalls) {
      if (call.name.trim() != toolName) continue;
      final Map<String, dynamic> payload = _decodeObject(
        call.argumentsJson,
        toolName: toolName,
      );
      _validateValueAgainstSchema(payload, strictSchema, path: toolName);
      return MemoryStructuredToolResult(
        payload: payload,
        modelUsed: result.modelUsed,
        rawText: call.argumentsJson,
        viaToolCall: true,
      );
    }

    if (!allowTextFallback) {
      throw FormatException('$toolName 未返回结构化 tool call');
    }

    final Map<String, dynamic> payload = _decodeObject(
      _extractJsonPayload(result.content),
      toolName: toolName,
    );
    _validateValueAgainstSchema(payload, strictSchema, path: toolName);
    return MemoryStructuredToolResult(
      payload: payload,
      modelUsed: result.modelUsed,
      rawText: result.content,
      viaToolCall: false,
    );
  }

  Map<String, dynamic> _strictParametersSchema(Map<String, dynamic> schema) {
    final dynamic normalized = _strictifyJsonSchema(schema);
    if (normalized is Map<String, dynamic>) return normalized;
    throw ArgumentError('parametersSchema must be a JSON object schema');
  }

  dynamic _strictifyJsonSchema(dynamic raw) {
    if (raw is List) {
      return raw.map(_strictifyJsonSchema).toList(growable: false);
    }
    if (raw is! Map) return raw;

    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
    final dynamic typeRaw = map['type'];
    final bool isObject = typeRaw == 'object' || map['properties'] is Map;
    final bool isArray = typeRaw == 'array' || map['items'] != null;

    if (map['properties'] is Map) {
      final Map<String, dynamic> properties = <String, dynamic>{};
      final Map<Object?, Object?> rawProperties = Map<Object?, Object?>.from(
        map['properties'] as Map,
      );
      for (final MapEntry<Object?, Object?> entry in rawProperties.entries) {
        final String key = entry.key.toString();
        properties[key] = _strictifyJsonSchema(entry.value);
      }
      map['properties'] = properties;
      // OpenAI strict function schemas require every property to be listed in
      // `required`. Optional values are represented by empty strings/arrays in
      // these memory contracts, so the model still has a safe no-op value.
      map['required'] = properties.keys.toList(growable: false);
    }

    if (map['items'] != null) {
      map['items'] = _strictifyJsonSchema(map['items']);
    }
    if (map['anyOf'] is List) {
      map['anyOf'] = (map['anyOf'] as List)
          .map(_strictifyJsonSchema)
          .toList(growable: false);
    }
    if (map['oneOf'] is List) {
      map['oneOf'] = (map['oneOf'] as List)
          .map(_strictifyJsonSchema)
          .toList(growable: false);
    }
    if (map['allOf'] is List) {
      map['allOf'] = (map['allOf'] as List)
          .map(_strictifyJsonSchema)
          .toList(growable: false);
    }

    if (isObject) {
      map['type'] = 'object';
      map['additionalProperties'] = false;
    } else if (isArray) {
      map['type'] = 'array';
    }
    return map;
  }

  void _assertMemoryPayloadHasNoForbiddenTextSources(List<AIMessage> messages) {
    for (int index = 0; index < messages.length; index += 1) {
      final AIMessage message = messages[index];
      _assertNoForbiddenSourceKeys(
        message.apiContent,
        path: 'messages[$index].apiContent',
      );
      // Plain prompt text may mention OCR as a prohibition. Only JSON-like
      // payload strings are inspected for forbidden source keys.
      _assertJsonStringHasNoForbiddenSourceKeys(
        message.content,
        path: 'messages[$index].content',
      );
    }
  }

  void _assertNoForbiddenSourceKeys(Object? value, {required String path}) {
    if (value is Map) {
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final String key = entry.key.toString();
        final String normalizedKey = _normalizePayloadKey(key);
        if (_isForbiddenMemorySourceKey(normalizedKey)) {
          throw ArgumentError(
            'memory pipeline payload must not include OCR/text-source field: $path.$key',
          );
        }
        final Object? child = entry.value;
        _assertNoForbiddenSourceKeys(child, path: '$path.$key');
        if (child is String) {
          _assertJsonStringHasNoForbiddenSourceKeys(child, path: '$path.$key');
        }
      }
      return;
    }
    if (value is List) {
      for (int index = 0; index < value.length; index += 1) {
        final Object? child = value[index];
        _assertNoForbiddenSourceKeys(child, path: '$path[$index]');
        if (child is String) {
          _assertJsonStringHasNoForbiddenSourceKeys(
            child,
            path: '$path[$index]',
          );
        }
      }
    }
  }

  void _assertJsonStringHasNoForbiddenSourceKeys(
    String value, {
    required String path,
  }) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final bool looksJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    if (!looksJson) return;
    try {
      _assertNoForbiddenSourceKeys(jsonDecode(trimmed), path: path);
    } catch (error) {
      if (error is ArgumentError) rethrow;
    }
  }

  String _normalizePayloadKey(String key) {
    return key.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isForbiddenMemorySourceKey(String key) {
    const Set<String> exact = <String>{
      'ocr',
      'ocrtext',
      'ocrrawtext',
      'ocrindexhit',
      'ocrindexhits',
      'ocrmatch',
      'ocrmatches',
      'ocrsnippet',
      'ocrsnippets',
      'recognizedtext',
      'textblock',
      'textblocks',
      'pagetext',
      'pagebody',
      'bodytext',
      'rawtext',
      'extractedtext',
      'transcript',
      'transcription',
      'asr',
      'asrtext',
    };
    if (exact.contains(key)) return true;
    if (key.startsWith('ocr') || key.endsWith('ocr')) return true;
    if (key.contains('ocrindex') || key.contains('ocrsnippet')) return true;
    if (key.contains('recognizedtext')) return true;
    if (key.contains('textblock')) return true;
    if (key.contains('transcript') || key.contains('transcription')) {
      return true;
    }
    return false;
  }

  void _validateValueAgainstSchema(
    Object? value,
    Object? schema, {
    required String path,
  }) {
    if (schema is! Map) return;
    final Map<String, dynamic> map = Map<String, dynamic>.from(schema);
    final Object? typeRaw = map['type'];
    final String? type = typeRaw is String ? typeRaw : null;

    if (type == 'object' || map['properties'] is Map) {
      if (value is! Map) {
        throw FormatException('$path should be an object');
      }
      final Map<String, dynamic> object = Map<String, dynamic>.from(value);
      final Map<String, dynamic> properties = map['properties'] is Map
          ? Map<String, dynamic>.from(map['properties'] as Map)
          : <String, dynamic>{};
      final List<String> required = map['required'] is List
          ? (map['required'] as List).map((item) => item.toString()).toList()
          : properties.keys.toList(growable: false);
      for (final String key in required) {
        if (!object.containsKey(key)) {
          throw FormatException('$path missing required field: $key');
        }
      }
      for (final String key in object.keys) {
        if (!properties.containsKey(key)) {
          throw FormatException('$path contains unexpected field: $key');
        }
        _validateValueAgainstSchema(
          object[key],
          properties[key],
          path: '$path.$key',
        );
      }
      return;
    }

    if (type == 'array' || map['items'] != null) {
      if (value is! List) {
        throw FormatException('$path should be an array');
      }
      for (int index = 0; index < value.length; index += 1) {
        _validateValueAgainstSchema(
          value[index],
          map['items'],
          path: '$path[$index]',
        );
      }
      return;
    }

    if (type == 'string' && value is! String) {
      throw FormatException('$path should be a string');
    }
    if (type == 'number' && value is! num) {
      throw FormatException('$path should be a number');
    }
    if (type == 'integer' && value is! int) {
      throw FormatException('$path should be an integer');
    }
    if (type == 'boolean' && value is! bool) {
      throw FormatException('$path should be a boolean');
    }
  }

  Map<String, dynamic> _decodeObject(String raw, {required String toolName}) {
    final String text = raw.trim();
    if (text.isEmpty) {
      throw FormatException('$toolName 返回为空');
    }
    final dynamic decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('$toolName 返回的不是对象');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _extractJsonPayload(String raw) {
    String text = raw.trim();
    if (text.startsWith('```')) {
      final int firstLf = text.indexOf('\n');
      if (firstLf >= 0) {
        text = text.substring(firstLf + 1);
      }
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
      text = text.trim();
    }
    final int start = text.indexOf('{');
    final int end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }
}
