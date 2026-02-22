import 'dart:convert';

import '../models/ai_request_log.dart';

class GatewayLogParseResult {
  const GatewayLogParseResult({
    required this.traces,
    this.leadingOrphans = const <String>[],
  });

  final List<AIRequestTrace> traces;
  final List<String> leadingOrphans;
}

List<AIRequestTrace> parseAiTraceMessages(
  Iterable<String> messages, {
  Iterable<DateTime>? times,
}) {
  final List<String> msgList = messages.toList(growable: false);
  final List<DateTime?> timeList = times == null
      ? List<DateTime?>.filled(msgList.length, null, growable: false)
      : times.map<DateTime?>((e) => e).toList(growable: false);

  final Map<String, _TraceBuilder> byId = <String, _TraceBuilder>{};
  final List<String> order = <String>[];

  for (int i = 0; i < msgList.length; i += 1) {
    final String original = msgList[i];
    final DateTime? at = (i < timeList.length) ? timeList[i] : null;
    final String text = _stripTalkerTagPrefix(original, tag: 'AITrace');
    final List<String> lines = _splitLines(text);
    if (lines.isEmpty) continue;

    final _AiTraceBlock? block = _parseAiTraceBlockKind(lines.first);
    if (block == null) continue;

    final String? traceId = _parseFirstTokenAfterKind(lines.first);
    if (traceId == null || traceId.trim().isEmpty) continue;
    final String tid = traceId.trim();

    _TraceBuilder b = byId[tid] ??= _TraceBuilder(
      source: AIRequestLogSource.aiTrace,
      traceId: tid,
    );
    if (!order.contains(tid)) order.add(tid);

    b.addRaw(original.trimRight());
    if (at != null) b.bumpTime(at);

    switch (block) {
      case _AiTraceBlock.req:
        _parseAiTraceReqBlock(lines, b);
        break;
      case _AiTraceBlock.resp:
        _parseAiTraceRespBlock(lines, b);
        break;
      case _AiTraceBlock.streamDone:
        _parseAiTraceStreamDoneBlock(lines, b);
        break;
      case _AiTraceBlock.streamErr:
        _parseAiTraceStreamErrBlock(lines, b);
        break;
    }
  }

  final List<AIRequestTrace> out = <AIRequestTrace>[];
  for (final String tid in order) {
    final _TraceBuilder? b = byId[tid];
    if (b == null) continue;
    out.add(b.build());
  }
  return out;
}

List<AIRequestTrace> parseGatewayLogText(String text) =>
    parseGatewayLogTextDetailed(text).traces;

GatewayLogParseResult parseGatewayLogTextDetailed(String text) {
  final List<String> lines = _splitLines(text);
  final List<String> leadingOrphans = <String>[];
  final List<_TraceBuilder> traces = <_TraceBuilder>[];

  _TraceBuilder? current;
  _GatewaySection lastSection = _GatewaySection.none;

  void pushCurrent() {
    if (current == null) return;
    traces.add(current!);
    current = null;
    lastSection = _GatewaySection.none;
  }

  for (final String rawLine0 in lines) {
    final String rawLine = rawLine0.trimRight();
    if (rawLine.isEmpty) continue;

    final _GatewayLine gl = _parseGatewayLine(rawLine);
    final String rest = gl.rest;
    final DateTime? at = gl.time;

    if (rest.startsWith('REQ POST ')) {
      pushCurrent();
      final _TraceBuilder b = _TraceBuilder(
        source: AIRequestLogSource.gatewayLog,
      );
      b.bumpTime(at);
      b.addRaw(rawLine);

      final String after = rest.substring('REQ POST '.length).trim();
      final List<String> tokens = after.split(RegExp(r'\s+'));
      if (tokens.isNotEmpty) {
        final Uri? uri = Uri.tryParse(tokens.first);
        if (uri != null) {
          b.reqMethod = 'POST';
          b.reqUri = uri;
        }
      }
      b.streaming = _parseBoolIntToken(after, key: 'stream');
      b.reqBodyLen = _parseIntToken(after, key: 'bodyLen');
      current = b;
      lastSection = _GatewaySection.none;
      continue;
    }

    if (current == null) {
      leadingOrphans.add(rawLine);
      continue;
    }

    current!.bumpTime(at);
    current!.addRaw(rawLine);

    if (rest == 'REQ headers') {
      lastSection = _GatewaySection.reqHeaders;
      continue;
    }
    if (rest == 'REQ body') {
      lastSection = _GatewaySection.reqBody;
      continue;
    }
    if (rest.startsWith('RESP status=')) {
      lastSection = _GatewaySection.respStatus;
      current!.respStatusCode = _parseIntToken(rest, key: 'status');
      current!.respContentType = _parseContentType(rest);
      current!.respBodyLen = _parseIntToken(rest, key: 'bodyLen');
      continue;
    }
    if (rest == 'RESP error body') {
      lastSection = _GatewaySection.respErrorBody;
      continue;
    }
    if (rest.startsWith('PARSED ')) {
      // e.g. "PARSED openai contentLen=.. toolCalls=.. reasoningLen=.."
      current!.streamContentLen = _parseIntToken(rest, key: 'contentLen');
      current!.streamReasoningLen = _parseIntToken(rest, key: 'reasoningLen');
      current!.streamToolCalls = _parseIntToken(rest, key: 'toolCalls');
      current!.usagePromptTokens = _parseIntToken(rest, key: 'promptTokens');
      current!.usageCompletionTokens = _parseIntToken(
        rest,
        key: 'completionTokens',
      );
      current!.usageTotalTokens = _parseIntToken(rest, key: 'totalTokens');
      current!.ttftMs = _parseIntToken(rest, key: 'ttftMs');
      lastSection = _GatewaySection.none;
      continue;
    }

    if (rest.startsWith('extra=')) {
      final String payload = rest.substring('extra='.length);
      final dynamic decoded = _tryJsonDecode(payload);
      switch (lastSection) {
        case _GatewaySection.reqHeaders:
          final Map<String, dynamic>? headers = _asStringKeyMap(decoded);
          if (headers != null) current!.reqHeaders = headers;
          break;
        case _GatewaySection.reqBody:
          current!.reqBody = _stringifyDecoded(decoded);
          break;
        case _GatewaySection.respStatus:
          // emitUiLog('RESP status...', extra: {'headers': response.headers})
          final Map<String, dynamic>? map = _asStringKeyMap(decoded);
          if (map != null) {
            final dynamic h = map['headers'];
            final Map<String, dynamic>? headers = _asStringKeyMap(h);
            if (headers != null) current!.respHeaders = headers;
          }
          break;
        case _GatewaySection.respErrorBody:
          current!.respErrorBody = _stringifyDecoded(decoded);
          break;
        case _GatewaySection.none:
          // Keep as raw only; already added.
          break;
      }
      continue;
    }

    // Everything else is treated as raw debug lines.
    lastSection = _GatewaySection.none;
  }

  pushCurrent();

  return GatewayLogParseResult(
    traces: traces.map((b) => b.build()).toList(growable: false),
    leadingOrphans: leadingOrphans,
  );
}

/// Parse a segment-level persisted request/response trace (stored in DB fields
/// `segment_results.raw_request/raw_response`) into a single [AIRequestTrace].
///
/// This is used by the "动态/segment" pages where logs are not emitted as
/// `[AITrace]` or `gateway_log` UI events.
List<AIRequestTrace> parseSegmentTrace({
  required String rawRequest,
  required String rawResponse,
  int? segmentId,
  String? provider,
  String? model,
  DateTime? createdAt,
}) {
  final String rq = rawRequest.trimRight();
  final String rs = rawResponse.trimRight();
  if (rq.trim().isEmpty && rs.trim().isEmpty) return const <AIRequestTrace>[];

  String? parsedProvider;
  String? parsedModel;
  Uri? parsedUri;
  int? parsedSegmentId;
  int? parsedImagesAttached;
  String? promptText;
  String? imagesText;
  String? baseUrlText;

  if (rq.trim().isNotEmpty) {
    final List<String> lines = _splitLines(rq);

    // 1) Header key-value lines.
    for (final String l0 in lines) {
      final String l = l0.trimRight();
      if (l.trim().isEmpty) break;
      if (l.startsWith('=== ')) continue;
      if (l == 'prompt:' || l == 'images:') break;

      final int idx = l.indexOf('=');
      if (idx <= 0) continue;
      final String k = l.substring(0, idx).trim();
      final String v = l.substring(idx + 1).trim();
      if (k == 'provider' && v.isNotEmpty) parsedProvider = v;
      if (k == 'url' && v.isNotEmpty) parsedUri = Uri.tryParse(v);
      if (k == 'base_url' && v.isNotEmpty) baseUrlText = v;
      if (k == 'model' && v.isNotEmpty) parsedModel = v;
      if (k == 'segment_id') {
        final int? id = int.tryParse(v);
        if (id != null && id > 0) parsedSegmentId = id;
      }
      if (k == 'images_attached') {
        final int? n = int.tryParse(v);
        if (n != null && n >= 0) parsedImagesAttached = n;
      }
    }

    // 2) Extract prompt/images sections if present.
    final int promptIdx = lines.indexWhere((e) => e.trimRight() == 'prompt:');
    if (promptIdx >= 0 && promptIdx + 1 < lines.length) {
      final int imagesIdx = lines.indexWhere(
        (e) => e.trimRight() == 'images:',
        promptIdx + 1,
      );
      final List<String> promptLines = (imagesIdx >= 0)
          ? lines.sublist(promptIdx + 1, imagesIdx)
          : lines.sublist(promptIdx + 1);
      final String p = promptLines.join('\n').trimRight();
      if (p.trim().isNotEmpty) promptText = p;

      if (imagesIdx >= 0 && imagesIdx + 1 < lines.length) {
        final String it = lines.sublist(imagesIdx + 1).join('\n').trimRight();
        if (it.trim().isNotEmpty) imagesText = it;
      }
    }
  }

  final int? tid = (segmentId != null && segmentId > 0)
      ? segmentId
      : parsedSegmentId;
  final _TraceBuilder b = _TraceBuilder(
    source: AIRequestLogSource.segmentTrace,
    traceId: tid?.toString(),
  );

  b.bumpTime(createdAt);
  final String providerText = (parsedProvider ?? provider ?? '').trim();
  if (providerText.isNotEmpty) b.providerName = providerText;
  final String modelText = (parsedModel ?? model ?? '').trim();
  if (modelText.isNotEmpty) b.model = modelText;
  b.imagesCount = parsedImagesAttached;

  // Request: use parsed url/base_url if available, but keep prompt/images for readability.
  final Uri? uri = parsedUri ?? Uri.tryParse(baseUrlText ?? '');
  if (uri != null) {
    b.reqMethod = 'POST';
    b.reqUri = uri;
  }
  final List<String> reqParts = <String>[];
  final String? trimmedPrompt = promptText?.trimRight();
  if (trimmedPrompt != null && trimmedPrompt.trim().isNotEmpty) {
    reqParts.add(trimmedPrompt);
  }
  final String? trimmedImages = imagesText?.trimRight();
  if (trimmedImages != null && trimmedImages.trim().isNotEmpty) {
    reqParts.add('images:\n$trimmedImages');
  }
  if (reqParts.isNotEmpty) {
    b.reqBody = reqParts.join('\n\n').trimRight();
  } else if (rq.trim().isNotEmpty) {
    b.reqBody = rq.trimRight();
  }

  // Response: exception traces are stored as a dedicated block.
  final String rsTrim = rs.trim();
  final bool isException = rsTrim.contains('=== AI Response (exception) ===');
  if (isException) {
    String? msg;
    for (final String l0 in _splitLines(rsTrim)) {
      final String l = l0.trimRight();
      if (l.startsWith('message=')) {
        final String v = l.substring('message='.length).trim();
        if (v.isNotEmpty) msg = v;
        break;
      }
    }
    b.error = msg ?? (rsTrim.isEmpty ? null : 'Exception');
    if (rsTrim.isNotEmpty) b.respErrorBody = rsTrim;
  } else if (rsTrim.isNotEmpty) {
    b.respBody = rsTrim;
  }

  if (rq.trim().isNotEmpty) b.addRaw(rq);
  if (rsTrim.isNotEmpty) b.addRaw(rsTrim);

  return <AIRequestTrace>[b.build()];
}

// ===== AITrace block parsing =====

enum _AiTraceBlock { req, resp, streamDone, streamErr }

_AiTraceBlock? _parseAiTraceBlockKind(String firstLine) {
  final String t = firstLine.trimLeft();
  if (t.startsWith('REQ ')) return _AiTraceBlock.req;
  if (t.startsWith('RESP ')) return _AiTraceBlock.resp;
  if (t.startsWith('STREAM_DONE ')) return _AiTraceBlock.streamDone;
  if (t.startsWith('STREAM_ERR ')) return _AiTraceBlock.streamErr;
  return null;
}

String? _parseFirstTokenAfterKind(String firstLine) {
  final List<String> parts = firstLine.trimLeft().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  return parts[1];
}

void _parseAiTraceReqBlock(List<String> lines, _TraceBuilder b) {
  // Lines:
  // REQ <traceId>
  // POST <uri>
  // ctx=... api=... stream=0|1
  // provider=... type=...
  // model=... tools=.. images=..
  // headers=...
  // body=...
  if (lines.length >= 2) {
    final String l2 = lines[1].trim();
    if (l2.startsWith('POST ')) {
      b.reqMethod = 'POST';
      b.reqUri = Uri.tryParse(l2.substring(5).trim());
    }
  }
  for (final String line in lines.skip(2)) {
    final String t = line.trimRight();
    _parseCommonAiTraceLine(t, b);
    if (t.startsWith('headers=')) {
      b.reqHeaders = _asStringKeyMap(_tryJsonDecode(t.substring(8)));
      continue;
    }
    if (t.startsWith('body=')) {
      b.reqBody = t.substring(5);
      continue;
    }
  }
}

void _parseAiTraceRespBlock(List<String> lines, _TraceBuilder b) {
  // Lines:
  // RESP <traceId>
  // <status> <uri>
  // ctx=... api=... stream=.. [tookMs=..]
  // provider=... type=...
  // model=... [bodyLen=..]
  // headers=...
  // body=... (non-stream only)
  if (lines.length >= 2) {
    final String l2 = lines[1].trim();
    final RegExpMatch? m = RegExp(r'^(\d{3})\s+(\S+)$').firstMatch(l2);
    if (m != null) {
      b.respStatusCode = int.tryParse(m.group(1)!);
      b.reqUri ??= Uri.tryParse(m.group(2)!);
    }
  }
  for (final String line in lines.skip(2)) {
    final String t = line.trimRight();
    _parseCommonAiTraceLine(t, b);
    if (t.startsWith('headers=')) {
      b.respHeaders = _asStringKeyMap(_tryJsonDecode(t.substring(8)));
      continue;
    }
    if (t.startsWith('body=')) {
      b.respBody = t.substring(5);
      continue;
    }
  }
}

void _parseAiTraceStreamDoneBlock(List<String> lines, _TraceBuilder b) {
  for (final String line in lines.skip(1)) {
    final String t = line.trimRight();
    _parseCommonAiTraceLine(t, b);
    // stream summary is encoded in the "model=..." line.
  }
}

void _parseAiTraceStreamErrBlock(List<String> lines, _TraceBuilder b) {
  for (final String line in lines.skip(1)) {
    final String t = line.trimRight();
    _parseCommonAiTraceLine(t, b);
    if (t.startsWith('error=')) {
      b.error = t.substring(6);
    }
  }
}

void _parseCommonAiTraceLine(String t, _TraceBuilder b) {
  if (t.startsWith('ctx=')) {
    b.logContext = _parseTokenValue(t, key: 'ctx');
    b.apiType = _parseTokenValue(t, key: 'api');
    final int? stream = _parseIntToken(t, key: 'stream');
    if (stream != null) b.streaming = stream == 1;
    final int? tookMs = _parseIntToken(t, key: 'tookMs');
    if (tookMs != null && tookMs > 0) b.durationMs = tookMs;
    return;
  }

  if (t.startsWith('provider=')) {
    final String? raw = _parseTokenValue(t, key: 'provider');
    if (raw != null && raw.isNotEmpty && raw != '-') {
      final RegExpMatch? m = RegExp(r'^(.+?)\((.+)\)$').firstMatch(raw);
      if (m != null) {
        b.providerName = m.group(1);
        b.providerId = m.group(2);
      } else {
        b.providerName = raw;
      }
    }
    final String? type = _parseTokenValue(t, key: 'type');
    if (type != null && type.isNotEmpty && type != '-') {
      b.providerType = type;
    }
    return;
  }

  if (t.startsWith('model=')) {
    final String? model = _parseTokenValue(t, key: 'model');
    if (model != null && model.isNotEmpty) b.model = model;
    b.toolsCount ??= _parseIntToken(t, key: 'tools');
    b.imagesCount ??= _parseIntToken(t, key: 'images');
    b.usagePromptTokens ??= _parseIntToken(t, key: 'promptTokens');
    b.usageCompletionTokens ??= _parseIntToken(t, key: 'completionTokens');
    b.usageTotalTokens ??= _parseIntToken(t, key: 'totalTokens');
    b.ttftMs ??= _parseIntToken(t, key: 'ttftMs');
    b.respBodyLen ??= _parseIntToken(t, key: 'bodyLen');
    b.streamContentLen ??= _parseIntToken(t, key: 'contentLen');
    b.streamReasoningLen ??= _parseIntToken(t, key: 'reasoningLen');
    b.streamToolCalls ??= _parseIntToken(t, key: 'toolCalls');
    return;
  }
}

// ===== Gateway parsing helpers =====

class _GatewayLine {
  const _GatewayLine({required this.time, required this.rest});

  final DateTime? time;
  final String rest;
}

_GatewayLine _parseGatewayLine(String rawLine) {
  final RegExpMatch? m = RegExp(
    r'^\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]\s*(.*)$',
  ).firstMatch(rawLine);
  if (m == null) return _GatewayLine(time: null, rest: rawLine.trimLeft());
  final int hh = int.tryParse(m.group(1)!) ?? 0;
  final int mm = int.tryParse(m.group(2)!) ?? 0;
  final int ss = int.tryParse(m.group(3)!) ?? 0;
  final int ms = int.tryParse(m.group(4)!) ?? 0;
  final String rest = (m.group(5) ?? '').trimLeft();
  return _GatewayLine(time: DateTime(2000, 1, 1, hh, mm, ss, ms), rest: rest);
}

enum _GatewaySection { none, reqHeaders, reqBody, respStatus, respErrorBody }

String? _parseContentType(String line) {
  // contentType may contain spaces (e.g. "application/json; charset=utf-8").
  final RegExpMatch? m = RegExp(
    r'\bcontentType=(.*?)(?:\s+bodyLen=|$)',
  ).firstMatch(line);
  if (m == null) return null;
  final String v = (m.group(1) ?? '').trim();
  return v.isEmpty ? null : v;
}

// ===== Generic helpers =====

List<String> _splitLines(String s) {
  final String normalized = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalized.split('\n');
}

String _stripTalkerTagPrefix(String message, {required String tag}) {
  final String t = message.trimLeft();
  final String prefix = '[$tag]';
  if (!t.startsWith(prefix)) return message;
  final String rest = t.substring(prefix.length);
  return rest.trimLeft();
}

String? _parseTokenValue(String line, {required String key}) {
  final RegExpMatch? m = RegExp('(?:^|\\s)$key=([^\\s]+)').firstMatch(line);
  if (m == null) return null;
  return m.group(1);
}

int? _parseIntToken(String line, {required String key}) {
  final String? v = _parseTokenValue(line, key: key);
  if (v == null) return null;
  return int.tryParse(v);
}

bool? _parseBoolIntToken(String line, {required String key}) {
  final int? v = _parseIntToken(line, key: key);
  if (v == null) return null;
  return v == 1;
}

dynamic _tryJsonDecode(String s) {
  final String t = s.trim();
  if (t.isEmpty) return null;
  try {
    return jsonDecode(t);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _asStringKeyMap(dynamic decoded) {
  if (decoded is Map) {
    final Map<String, dynamic> out = <String, dynamic>{};
    decoded.forEach((k, v) {
      if (k == null) return;
      out[k.toString()] = v;
    });
    return out;
  }
  return null;
}

String? _stringifyDecoded(dynamic decoded) {
  if (decoded == null) return null;
  if (decoded is String) return decoded;
  try {
    return jsonEncode(decoded);
  } catch (_) {
    return decoded.toString();
  }
}

class _TraceBuilder {
  _TraceBuilder({required this.source, this.traceId});

  final AIRequestLogSource source;
  final String? traceId;

  DateTime? startedAt;
  DateTime? endedAt;
  int? durationMs;
  String? logContext;
  String? apiType;
  bool? streaming;
  String? providerName;
  String? providerType;
  String? providerId;
  String? model;
  int? toolsCount;
  int? imagesCount;
  int? usagePromptTokens;
  int? usageCompletionTokens;
  int? usageTotalTokens;
  int? ttftMs;

  String? error;

  // Request
  String? reqMethod;
  Uri? reqUri;
  Map<String, dynamic>? reqHeaders;
  String? reqBody;
  int? reqBodyLen;

  // Response
  int? respStatusCode;
  String? respContentType;
  Map<String, dynamic>? respHeaders;
  String? respBody;
  int? respBodyLen;
  String? respErrorBody;

  // Stream summary
  int? streamContentLen;
  int? streamReasoningLen;
  int? streamToolCalls;

  final List<String> raw = <String>[];

  void addRaw(String blockOrLine) {
    final String t = blockOrLine.trimRight();
    if (t.isEmpty) return;
    raw.add(t);
  }

  void bumpTime(DateTime? at) {
    if (at == null) return;
    startedAt ??= at;
    endedAt = at;
  }

  AIRequestTrace build() {
    final AIRequestHttpRequest? req =
        (reqMethod != null ||
            reqUri != null ||
            reqHeaders != null ||
            (reqBody != null && reqBody!.trim().isNotEmpty) ||
            reqBodyLen != null)
        ? AIRequestHttpRequest(
            method: reqMethod,
            uri: reqUri,
            headers: reqHeaders,
            body: reqBody,
            bodyLen: reqBodyLen,
          )
        : null;

    final AIRequestHttpResponse? resp =
        (respStatusCode != null ||
            respContentType != null ||
            respHeaders != null ||
            (respBody != null && respBody!.trim().isNotEmpty) ||
            respBodyLen != null ||
            (respErrorBody != null && respErrorBody!.trim().isNotEmpty))
        ? AIRequestHttpResponse(
            statusCode: respStatusCode,
            contentType: respContentType,
            headers: respHeaders,
            body: respBody,
            bodyLen: respBodyLen,
            errorBody: respErrorBody,
          )
        : null;

    final AIRequestStreamSummary? summary =
        (streamContentLen != null ||
            streamReasoningLen != null ||
            streamToolCalls != null)
        ? AIRequestStreamSummary(
            contentLen: streamContentLen,
            reasoningLen: streamReasoningLen,
            toolCalls: streamToolCalls,
          )
        : null;

    int? dur = durationMs;
    if (dur == null && startedAt != null && endedAt != null) {
      final int diff = endedAt!.difference(startedAt!).inMilliseconds;
      if (diff > 0) dur = diff;
    }

    return AIRequestTrace(
      source: source,
      traceId: traceId,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: dur,
      logContext: (logContext ?? '').trim().isEmpty ? null : logContext,
      apiType: (apiType ?? '').trim().isEmpty ? null : apiType,
      streaming: streaming,
      providerName: (providerName ?? '').trim().isEmpty ? null : providerName,
      providerType: (providerType ?? '').trim().isEmpty ? null : providerType,
      providerId: (providerId ?? '').trim().isEmpty ? null : providerId,
      model: (model ?? '').trim().isEmpty ? null : model,
      toolsCount: toolsCount,
      imagesCount: imagesCount,
      usagePromptTokens: usagePromptTokens,
      usageCompletionTokens: usageCompletionTokens,
      usageTotalTokens: usageTotalTokens,
      ttftMs: ttftMs,
      request: req,
      response: resp,
      streamSummary: summary,
      error: (error ?? '').trim().isEmpty ? null : error,
      rawBlocks: raw.toList(growable: false),
    );
  }
}
