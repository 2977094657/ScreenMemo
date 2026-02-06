/// Small helpers to parse OpenAI Responses-style "item" objects.
///
/// We keep these separate from the request gateway so they can be unit-tested
/// without having to mock HTTP streaming.

class ResponsesFunctionCallItem {
  const ResponsesFunctionCallItem({
    required this.callId,
    required this.name,
    required this.arguments,
  });

  final String callId;
  final String name;
  final String arguments;
}

/// Extracts reasoning text from a Responses `item` where:
/// - item.type == "reasoning"
/// - item.summary / item.content may contain parts with {type:"summary_text"|"reasoning_text"|"output_text", text:"..."}
String extractResponsesReasoningText(Map<String, dynamic> item) {
  final String type = (item['type'] as String?) ?? '';
  if (type != 'reasoning') return '';

  final StringBuffer out = StringBuffer();

  void readParts(dynamic raw) {
    if (raw is! List) return;
    for (final dynamic part in raw) {
      if (part is! Map) continue;
      final Map<String, dynamic> p = Map<String, dynamic>.from(part as Map);
      final String partType = (p['type'] as String?) ?? '';
      if (partType != 'summary_text' &&
          partType != 'reasoning_text' &&
          partType != 'output_text') {
        continue;
      }
      final String text = (p['text'] as String?) ?? '';
      if (text.isNotEmpty) out.write(text);
    }
  }

  readParts(item['summary']);
  readParts(item['content']);

  final dynamic textRaw = item['text'];
  if (textRaw is String && textRaw.isNotEmpty) {
    out.write(textRaw);
  }

  return out.toString();
}

/// Extracts user-visible text from a Responses `item` where:
/// - item.type == "message"
/// - item.content is a list of parts containing {type:"output_text", text:"..."}
String extractResponsesMessageOutputText(Map<String, dynamic> item) {
  final String type = (item['type'] as String?) ?? '';
  if (type != 'message') return '';

  // Only accept assistant messages (or unspecified role).
  final String role = (item['role'] as String?) ?? '';
  if (role.isNotEmpty && role != 'assistant') return '';

  final dynamic content = item['content'];
  if (content is! List) return '';

  final StringBuffer out = StringBuffer();
  for (final dynamic part in content) {
    if (part is! Map) continue;
    final Map<String, dynamic> p = Map<String, dynamic>.from(part as Map);
    final String partType = (p['type'] as String?) ?? '';
    if (partType != 'output_text') continue;
    final String text = (p['text'] as String?) ?? '';
    if (text.isNotEmpty) out.write(text);
  }
  return out.toString();
}

/// Extracts a function-call/tool-call from a Responses `item`.
///
/// Supports common shapes used by relays:
/// - {type:"function_call", call_id:"...", name:"...", arguments:"..."}
/// - {type:"tool_call", ...}
/// - {type:"function_call", id:"...", function:{name:"...", arguments:"..."}}
ResponsesFunctionCallItem? extractResponsesFunctionCallItem(
  Map<String, dynamic> item,
) {
  final String type = (item['type'] as String?) ?? '';
  if (type != 'function_call' && type != 'tool_call') return null;

  final String rawCallId = ((item['call_id'] as String?) ??
          (item['callId'] as String?) ??
          (item['id'] as String?) ??
          '')
      .trim();

  String name = ((item['name'] as String?) ?? '').trim();
  String arguments = (item['arguments'] as String?) ?? '';

  final dynamic fnRaw = item['function'];
  if (fnRaw is Map) {
    final Map<String, dynamic> fn = Map<String, dynamic>.from(fnRaw as Map);
    final String fnName = (fn['name'] as String?) ?? '';
    if (fnName.trim().isNotEmpty) {
      name = fnName.trim();
    }
    final String fnArgs = (fn['arguments'] as String?) ?? '';
    if (fnArgs.isNotEmpty) {
      arguments = fnArgs;
    }
  }

  if (rawCallId.isEmpty || name.isEmpty) return null;
  return ResponsesFunctionCallItem(
    callId: rawCallId,
    name: name,
    arguments: arguments,
  );
}
