// Structured AI request/response trace used for human-readable log viewing.
// This is intentionally UI-focused (not a full fidelity network dump).

enum AIRequestLogSource { aiTrace, gatewayLog, segmentTrace, nativeLog }

class AIRequestHttpRequest {
  const AIRequestHttpRequest({
    this.method,
    this.uri,
    this.headers,
    this.body,
    this.bodyLen,
  });

  final String? method;
  final Uri? uri;
  final Map<String, dynamic>? headers;
  final String? body;
  final int? bodyLen;
}

class AIRequestHttpResponse {
  const AIRequestHttpResponse({
    this.statusCode,
    this.contentType,
    this.headers,
    this.body,
    this.bodyLen,
    this.errorBody,
  });

  final int? statusCode;
  final String? contentType;
  final Map<String, dynamic>? headers;
  final String? body;
  final int? bodyLen;
  final String? errorBody;
}

class AIRequestStreamSummary {
  const AIRequestStreamSummary({
    this.contentLen,
    this.reasoningLen,
    this.toolCalls,
  });

  final int? contentLen;
  final int? reasoningLen;
  final int? toolCalls;
}

class AIRequestTrace {
  const AIRequestTrace({
    required this.source,
    this.traceId,
    this.startedAt,
    this.endedAt,
    this.durationMs,
    this.logContext,
    this.apiType,
    this.streaming,
    this.providerName,
    this.providerType,
    this.providerId,
    this.model,
    this.toolsCount,
    this.imagesCount,
    this.usagePromptTokens,
    this.usageCompletionTokens,
    this.usageTotalTokens,
    this.ttftMs,
    this.request,
    this.response,
    this.streamSummary,
    this.error,
    this.rawBlocks = const <String>[],
  });

  final AIRequestLogSource source;
  final String? traceId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationMs;
  final String? logContext;
  final String? apiType;
  final bool? streaming;
  final String? providerName;
  final String? providerType;
  final String? providerId;
  final String? model;
  final int? toolsCount;
  final int? imagesCount;
  final int? usagePromptTokens;
  final int? usageCompletionTokens;
  final int? usageTotalTokens;
  final int? ttftMs;
  final AIRequestHttpRequest? request;
  final AIRequestHttpResponse? response;
  final AIRequestStreamSummary? streamSummary;

  /// Non-HTTP errors (e.g. streaming runtime exceptions).
  final String? error;

  /// Raw log blocks/lines for debugging and copy/export.
  final List<String> rawBlocks;

  bool get hasHttpStatus => (response?.statusCode != null);
  bool get isHttpSuccess {
    final int? sc = response?.statusCode;
    if (sc == null) return false;
    return sc >= 200 && sc < 300;
  }

  bool get isError =>
      (error != null && error!.trim().isNotEmpty) ||
      (hasHttpStatus && !isHttpSuccess);
}
