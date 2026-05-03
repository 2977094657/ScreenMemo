import 'package:screen_memo/models/ai_request_log.dart';

List<AIRequestTrace> parseNativeAiRequestLogText(
  String text, {
  DateTime? since,
  DateTime? until,
}) {
  final List<_NativeLogEntry> entries = _dedupeNativeLogEntries(
    _parseNativeLogEntries(text)
        .where((e) {
          if (e.tag != 'SegmentSummaryManager') return false;
          final DateTime? at = e.time;
          if (since != null && at != null && at.isBefore(since)) return false;
          if (until != null && at != null && at.isAfter(until)) return false;
          return true;
        })
        .toList(growable: false),
  );
  if (entries.isEmpty) return const <AIRequestTrace>[];

  final Map<String, _NativeTraceBuilder> byId = <String, _NativeTraceBuilder>{};
  final List<_NativeTraceBuilder> builders = <_NativeTraceBuilder>[];
  String? promptCaptureId;
  String? responseCaptureId;
  _NativeTraceBuilder? legacyCurrent;

  _NativeTraceBuilder ensureBuilder(String traceId) {
    return byId.putIfAbsent(traceId, () {
      final _NativeTraceBuilder b = _NativeTraceBuilder(traceId: traceId);
      builders.add(b);
      return b;
    });
  }

  _NativeTraceBuilder? pickBuilder({
    int? segmentId,
    DateTime? at,
    bool createIfMissing = false,
  }) {
    _NativeTraceBuilder? matched;
    for (final _NativeTraceBuilder candidate in builders.reversed) {
      if (segmentId != null &&
          candidate.segmentId != null &&
          candidate.segmentId == segmentId) {
        matched = candidate;
        break;
      }
      if (at != null && candidate.startedAt != null) {
        final int diff = at.difference(candidate.startedAt!).inSeconds.abs();
        if (diff <= 30) {
          matched ??= candidate;
        }
      }
    }
    if (matched != null || !createIfMissing) return matched;
    final String traceId =
        'legacy_${segmentId ?? 0}_${at?.millisecondsSinceEpoch ?? builders.length}';
    return ensureBuilder(traceId);
  }

  for (final _NativeLogEntry entry in entries) {
    final String message = entry.message.trimRight();
    if (message.isEmpty) continue;

    if (message.startsWith('AIREQ START ')) {
      final String? traceId = _parseStringToken(message, 'id');
      if (traceId != null && traceId.isNotEmpty) {
        final _NativeTraceBuilder builder = ensureBuilder(traceId);
        builder.addRaw(entry.raw);
        builder.bumpTime(entry.time);
        builder.apiType = 'native_direct';
        builder.streaming = true;
        builder.providerName ??= _parseStringToken(message, 'provider');
        builder.model ??= _parseStringToken(message, 'model');
        builder.imagesCount ??= _parseIntToken(message, 'images_attached');
        builder.segmentId ??= _parseIntToken(message, 'segment_id');
        builder.isMerge ??= _parseBoolToken(message, 'is_merge');
        final String? url = _parseStringToken(message, 'url');
        if (url != null && url.isNotEmpty) {
          builder.reqUri ??= Uri.tryParse(url);
        }
        builder.refreshLogContext();
        legacyCurrent = builder;
      }
      continue;
    }

    if (message.startsWith('AIREQ PROMPT_BEGIN ')) {
      promptCaptureId = _parseStringToken(message, 'id');
      final String? traceId = promptCaptureId;
      if (traceId != null) {
        ensureBuilder(traceId).addRaw(entry.raw);
      }
      continue;
    }

    if (message.startsWith('AIREQ PROMPT_END ')) {
      final String? traceId = _parseStringToken(message, 'id');
      if (traceId != null) {
        ensureBuilder(traceId).addRaw(entry.raw);
      }
      if (traceId == null || promptCaptureId == traceId) {
        promptCaptureId = null;
      }
      continue;
    }

    if (message.startsWith('AIREQ RESP_BODY_BEGIN ')) {
      responseCaptureId = _parseStringToken(message, 'id');
      final String? traceId = responseCaptureId;
      if (traceId != null) {
        ensureBuilder(traceId).addRaw(entry.raw);
      }
      continue;
    }

    if (message.startsWith('AIREQ RESP_BODY_END ')) {
      final String? traceId = _parseStringToken(message, 'id');
      if (traceId != null) {
        ensureBuilder(traceId).addRaw(entry.raw);
      }
      if (traceId == null || responseCaptureId == traceId) {
        responseCaptureId = null;
      }
      continue;
    }

    if (message.startsWith('AIREQ RESP ')) {
      final String? traceId = _parseStringToken(message, 'id');
      if (traceId != null && traceId.isNotEmpty) {
        final _NativeTraceBuilder builder = ensureBuilder(traceId);
        builder.addRaw(entry.raw);
        builder.bumpTime(entry.time);
        builder.respStatusCode ??= _parseIntToken(message, 'code');
        builder.durationMs ??= _parseIntToken(message, 'took_ms');
      }
      continue;
    }

    if (message.startsWith('AIREQ ERR ')) {
      final String? traceId = _parseStringToken(message, 'id');
      if (traceId != null && traceId.isNotEmpty) {
        final _NativeTraceBuilder builder = ensureBuilder(traceId);
        builder.addRaw(entry.raw);
        builder.bumpTime(entry.time);
        final String? kind = _parseStringToken(message, 'kind');
        final int? code = _parseIntToken(message, 'code');
        builder.respStatusCode ??= code;
        builder.appendError(
          [
            'kind=${kind ?? 'unknown'}',
            if (code != null) 'code=$code',
            message,
          ].join('\n'),
        );
      }
      continue;
    }

    if (message.startsWith('AIREQ DONE ')) {
      final String? traceId = _parseStringToken(message, 'id');
      if (traceId != null && traceId.isNotEmpty) {
        final _NativeTraceBuilder builder = ensureBuilder(traceId);
        builder.addRaw(entry.raw);
        builder.bumpTime(entry.time);
      }
      continue;
    }

    if (promptCaptureId != null) {
      final _NativeTraceBuilder builder = ensureBuilder(promptCaptureId);
      builder.addRaw(entry.raw);
      if (message != 'AI 提示词完整内容开始 >>>' && message != 'AI 提示词完整内容结束 <<<') {
        builder.appendRequestBody(message);
      }
      continue;
    }

    if (responseCaptureId != null) {
      final _NativeTraceBuilder builder = ensureBuilder(responseCaptureId);
      builder.addRaw(entry.raw);
      if (!message.startsWith('AI 响应完整内容') &&
          !message.startsWith('AI structured_json')) {
        builder.appendResponseBody(message);
      }
      continue;
    }

    if (message.startsWith('AI 准备：')) {
      final int? segmentId = _parseLegacySegmentId(message);
      final _NativeTraceBuilder builder =
          pickBuilder(
            segmentId: segmentId,
            at: entry.time,
            createIfMissing: true,
          ) ??
          ensureBuilder(
            'legacy_${segmentId ?? 0}_${entry.time?.millisecondsSinceEpoch ?? builders.length}',
          );
      builder.addRaw(entry.raw);
      builder.bumpTime(entry.time);
      builder.apiType = 'native_direct';
      builder.streaming = true;
      builder.providerName ??= _parseLegacyProvider(message);
      builder.model ??= _parseLegacyModel(message);
      builder.imagesCount ??= _parseLegacyImagesCount(message);
      builder.segmentId ??= segmentId;
      builder.isMerge ??= _parseLegacyMerge(message);
      builder.refreshLogContext();
      legacyCurrent = builder;
      continue;
    }

    if (message.startsWith('AI 请求')) {
      final _NativeTraceBuilder? builder =
          legacyCurrent ?? pickBuilder(at: entry.time, createIfMissing: true);
      if (builder == null) continue;
      builder.addRaw(entry.raw);
      builder.bumpTime(entry.time);
      builder.reqUri ??= _parseLegacyRequestUri(message);
      builder.model ??= _parseLegacyRequestModel(message);
      builder.imagesCount ??= _parseLegacyRequestImagesCount(message);
      builder.refreshLogContext();
      legacyCurrent = builder;
      continue;
    }

    if (message == 'AI 提示词完整内容开始 >>>') {
      final _NativeTraceBuilder? builder =
          legacyCurrent ?? pickBuilder(at: entry.time, createIfMissing: false);
      if (builder != null) {
        builder.addRaw(entry.raw);
        promptCaptureId = builder.traceId;
      }
      continue;
    }

    if (message == 'AI 提示词完整内容结束 <<<') {
      final String? traceId = promptCaptureId;
      if (traceId != null) {
        ensureBuilder(traceId).addRaw(entry.raw);
      }
      promptCaptureId = null;
      continue;
    }

    if (message.startsWith('AI 提示词预览：')) {
      final _NativeTraceBuilder? builder =
          legacyCurrent ?? pickBuilder(at: entry.time, createIfMissing: false);
      if (builder != null) {
        builder.addRaw(entry.raw);
        builder.promptPreview ??= _afterFirstColon(message);
      }
      continue;
    }

    if (message.startsWith('AI 响应元信息')) {
      final _NativeTraceBuilder? builder =
          legacyCurrent ?? pickBuilder(at: entry.time, createIfMissing: true);
      if (builder == null) continue;
      builder.addRaw(entry.raw);
      builder.bumpTime(entry.time);
      builder.respStatusCode ??= _parseLegacyStatusCode(message);
      builder.durationMs ??= _parseLegacyDurationMs(message);
      legacyCurrent = builder;
      continue;
    }

    if (message.startsWith('AI 响应完整内容')) {
      final _NativeTraceBuilder? builder =
          legacyCurrent ?? pickBuilder(at: entry.time, createIfMissing: false);
      if (builder == null) continue;
      builder.addRaw(entry.raw);
      responseCaptureId = builder.traceId;
      legacyCurrent = builder;
      continue;
    }

    if (message.startsWith('AI 响应预览')) {
      final _NativeTraceBuilder? builder =
          legacyCurrent ?? pickBuilder(at: entry.time, createIfMissing: false);
      if (builder != null) {
        builder.addRaw(entry.raw);
        builder.responsePreview ??= _afterFirstColon(message);
      }
      continue;
    }

    if (_isNativeRequestErrorLine(message)) {
      final _NativeTraceBuilder? builder =
          legacyCurrent ?? pickBuilder(at: entry.time, createIfMissing: false);
      if (builder != null) {
        builder.addRaw(entry.raw);
        builder.bumpTime(entry.time);
        builder.respStatusCode ??= _parseLegacyFailureStatusCode(message);
        builder.appendError(message);
      }
      continue;
    }
  }

  final List<AIRequestTrace> traces =
      builders
          .map((b) => b.build())
          .whereType<AIRequestTrace>()
          .toList(growable: false)
        ..sort((a, b) {
          final int ams = a.startedAt?.millisecondsSinceEpoch ?? 0;
          final int bms = b.startedAt?.millisecondsSinceEpoch ?? 0;
          return bms.compareTo(ams);
        });
  return traces;
}

class _NativeLogEntry {
  _NativeLogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    required this.raw,
  });

  final DateTime? time;
  final String level;
  final String tag;
  final String message;
  final String raw;
}

class _NativeTraceBuilder {
  _NativeTraceBuilder({required this.traceId});

  final String traceId;
  final List<String> rawBlocks = <String>[];
  final StringBuffer _requestBody = StringBuffer();
  final StringBuffer _responseBody = StringBuffer();

  DateTime? startedAt;
  DateTime? endedAt;
  int? durationMs;
  String? logContext;
  String? apiType;
  bool? streaming;
  String? providerName;
  String? model;
  int? imagesCount;
  int? segmentId;
  bool? isMerge;
  Uri? reqUri;
  int? respStatusCode;
  String? promptPreview;
  String? responsePreview;
  String? error;

  void addRaw(String raw) {
    if (rawBlocks.isEmpty || rawBlocks.last != raw) {
      rawBlocks.add(raw);
    }
  }

  void bumpTime(DateTime? at) {
    if (at == null) return;
    startedAt ??= at;
    endedAt = at;
  }

  void appendRequestBody(String text) {
    final String value = text.trimRight();
    if (value.isEmpty) return;
    if (_requestBody.isNotEmpty) _requestBody.writeln();
    _requestBody.write(value);
  }

  void appendResponseBody(String text) {
    final String value = text.trimRight();
    if (value.isEmpty) return;
    if (_responseBody.isNotEmpty) _responseBody.writeln();
    _responseBody.write(value);
  }

  void appendError(String text) {
    final String value = text.trim();
    if (value.isEmpty) return;
    if (error == null || error!.trim().isEmpty) {
      error = value;
      return;
    }
    if (!error!.contains(value)) {
      error = '${error!.trimRight()}\n$value';
    }
  }

  void refreshLogContext() {
    if (segmentId == null || segmentId! <= 0) {
      logContext ??= 'native-direct';
      return;
    }
    final String mergeText = isMerge == true ? ' merge' : '';
    logContext = 'segment=$segmentId$mergeText';
  }

  AIRequestTrace? build() {
    final String requestBody = _requestBody.toString().trimRight();
    final String responseBody = _responseBody.toString().trimRight();
    final String requestText = requestBody.isNotEmpty
        ? requestBody
        : (promptPreview ?? '').trimRight();
    final String responseText = responseBody.isNotEmpty
        ? responseBody
        : (responsePreview ?? '').trimRight();
    if (reqUri == null &&
        requestText.isEmpty &&
        responseText.isEmpty &&
        (error ?? '').trim().isEmpty &&
        respStatusCode == null &&
        segmentId == null) {
      return null;
    }
    refreshLogContext();
    return AIRequestTrace(
      source: AIRequestLogSource.nativeLog,
      traceId: traceId,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: durationMs,
      logContext: logContext,
      apiType: apiType ?? 'native_direct',
      streaming: streaming ?? true,
      providerName: providerName,
      model: model,
      imagesCount: imagesCount,
      request: AIRequestHttpRequest(
        method: 'POST',
        uri: reqUri,
        body: requestText.isEmpty ? null : requestText,
        bodyLen: requestText.isEmpty ? null : requestText.length,
      ),
      response: AIRequestHttpResponse(
        statusCode: respStatusCode,
        body: responseText.isEmpty ? null : responseText,
        bodyLen: responseText.isEmpty ? null : responseText.length,
      ),
      error: (error ?? '').trim().isEmpty ? null : error!.trimRight(),
      rawBlocks: rawBlocks,
    );
  }
}

List<_NativeLogEntry> _parseNativeLogEntries(String text) {
  final List<_NativeLogEntry> out = <_NativeLogEntry>[];
  final RegExp re = RegExp(
    r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \[([A-Z]+)\] ([^:]+): ?(.*)$',
  );
  DateTime? currentTime;
  String? currentLevel;
  String? currentTag;
  StringBuffer? currentMessage;
  StringBuffer? currentRaw;

  void flush() {
    if (currentTag == null || currentMessage == null || currentRaw == null) {
      return;
    }
    out.add(
      _NativeLogEntry(
        time: currentTime,
        level: currentLevel ?? 'INFO',
        tag: currentTag!,
        message: currentMessage!.toString(),
        raw: currentRaw!.toString(),
      ),
    );
    currentTime = null;
    currentLevel = null;
    currentTag = null;
    currentMessage = null;
    currentRaw = null;
  }

  for (final String rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
    final Match? match = re.firstMatch(rawLine);
    if (match != null) {
      flush();
      final String ts = match.group(1)!;
      currentTime = DateTime.tryParse(ts.replaceFirst(' ', 'T'));
      currentLevel = match.group(2);
      currentTag = match.group(3);
      currentMessage = StringBuffer(match.group(4) ?? '');
      currentRaw = StringBuffer(rawLine);
      continue;
    }
    if (currentMessage != null) {
      currentMessage!.write('\n');
      currentMessage!.write(rawLine);
      currentRaw!.write('\n');
      currentRaw!.write(rawLine);
    }
  }
  flush();
  out.sort((a, b) {
    final int ams = a.time?.millisecondsSinceEpoch ?? 0;
    final int bms = b.time?.millisecondsSinceEpoch ?? 0;
    return ams.compareTo(bms);
  });
  return out;
}

List<_NativeLogEntry> _dedupeNativeLogEntries(List<_NativeLogEntry> entries) {
  final List<_NativeLogEntry> out = <_NativeLogEntry>[];
  _NativeLogEntry? previous;
  for (final _NativeLogEntry entry in entries) {
    final bool sameMessage =
        previous != null &&
        previous.tag == entry.tag &&
        previous.level == entry.level &&
        previous.message == entry.message;
    final int deltaMs =
        (previous == null || previous.time == null || entry.time == null)
        ? 999999
        : entry.time!.difference(previous.time!).inMilliseconds.abs();
    if (sameMessage && deltaMs <= 1200) {
      continue;
    }
    out.add(entry);
    previous = entry;
  }
  return out;
}

String? _parseStringToken(String text, String key) {
  final RegExp re = RegExp('(?:^|\\s)$key=([^\\s]+)');
  return re.firstMatch(text)?.group(1);
}

int? _parseIntToken(String text, String key) {
  final String? value = _parseStringToken(text, key);
  if (value == null || value.isEmpty) return null;
  return int.tryParse(value);
}

bool? _parseBoolToken(String text, String key) {
  final String? value = _parseStringToken(text, key)?.toLowerCase();
  if (value == 'true') return true;
  if (value == 'false') return false;
  return null;
}

int? _parseLegacySegmentId(String text) {
  final Match? match = RegExp(r'段ID=(\d+)').firstMatch(text);
  return int.tryParse(match?.group(1) ?? '');
}

String? _parseLegacyProvider(String text) {
  return RegExp(r'提供方=([^,]+)').firstMatch(text)?.group(1)?.trim();
}

String? _parseLegacyModel(String text) {
  return RegExp(r'模型=([^,]+)').firstMatch(text)?.group(1)?.trim();
}

int? _parseLegacyImagesCount(String text) {
  final Match? match = RegExp(r'图片数=(\d+)').firstMatch(text);
  return int.tryParse(match?.group(1) ?? '');
}

bool? _parseLegacyMerge(String text) {
  final Match? match = RegExp(r'合并=(true|false)').firstMatch(text);
  final String? value = match?.group(1)?.toLowerCase();
  if (value == 'true') return true;
  if (value == 'false') return false;
  return null;
}

Uri? _parseLegacyRequestUri(String text) {
  final Match? match = RegExp(
    r'AI 请求(?:\(OpenAI兼容\))?：地址=([^\s]+)',
  ).firstMatch(text);
  return Uri.tryParse(match?.group(1) ?? '');
}

String? _parseLegacyRequestModel(String text) {
  return RegExp(r'模型=([^\s]+)').firstMatch(text)?.group(1)?.trim();
}

int? _parseLegacyRequestImagesCount(String text) {
  final Match? match = RegExp(r'图片数=(\d+)').firstMatch(text);
  return int.tryParse(match?.group(1) ?? '');
}

int? _parseLegacyStatusCode(String text) {
  final Match? match = RegExp(r'code=(\d+)').firstMatch(text);
  return int.tryParse(match?.group(1) ?? '');
}

int? _parseLegacyDurationMs(String text) {
  final Match? match = RegExp(r'耗时毫秒=(\d+)').firstMatch(text);
  return int.tryParse(match?.group(1) ?? '');
}

int? _parseLegacyFailureStatusCode(String text) {
  final Match? match = RegExp(r'code=?(\d+)').firstMatch(text);
  return int.tryParse(match?.group(1) ?? '');
}

bool _isNativeRequestErrorLine(String text) {
  return text.contains('AI 请求失败') ||
      text.contains('AI 请求超时') ||
      text.contains('AI 请求异常') ||
      text.contains('Gemini 请求因地区策略被阻止') ||
      text.contains('AI 成功(200)但响应体为错误');
}

String _afterFirstColon(String text) {
  final int idx = text.indexOf('：');
  if (idx >= 0 && idx + 1 < text.length) {
    return text.substring(idx + 1).trim();
  }
  final int idx2 = text.indexOf(':');
  if (idx2 >= 0 && idx2 + 1 < text.length) {
    return text.substring(idx2 + 1).trim();
  }
  return text.trim();
}
