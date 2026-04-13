import 'dart:convert';

import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';

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
    final Map<String, dynamic> tool = <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': toolName,
        'description': toolDescription,
        'parameters': parametersSchema,
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
    return MemoryStructuredToolResult(
      payload: payload,
      modelUsed: result.modelUsed,
      rawText: result.content,
      viaToolCall: false,
    );
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
