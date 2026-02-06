import 'dart:convert';

int _asInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

List<String> _parseStringList(Object? raw) {
  if (raw is List) {
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
  if (raw is String) {
    final String s = raw.trim();
    return s.isEmpty ? const <String>[] : <String>[s];
  }
  return const <String>[];
}

Map<String, dynamic>? _tryDecodeJsonMap(String raw) {
  final String t = raw.trim();
  if (t.isEmpty) return null;
  try {
    final Object? decoded = jsonDecode(t);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

Map<String, dynamic> _ensureV2Base({
  required Map<String, dynamic>? decoded,
  required int assistantCreatedAtMs,
}) {
  if (decoded != null && _asInt(decoded['v']) == 2) {
    return decoded;
  }
  return <String, dynamic>{
    'v': 2,
    'blocks': <Map<String, dynamic>>[
      <String, dynamic>{
        'created_at': assistantCreatedAtMs,
        'events': <Map<String, dynamic>>[],
      },
    ],
  };
}

Map<String, dynamic> _ensureWritableBlock(Map<String, dynamic> obj) {
  final Object? blocks0 = obj['blocks'];
  List<dynamic> blocks = <dynamic>[];
  if (blocks0 is List) blocks = List<dynamic>.from(blocks0);
  if (blocks.isEmpty) {
    blocks.add(<String, dynamic>{
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'events': <Map<String, dynamic>>[],
    });
  }

  // Prefer the last unfinished block, otherwise use the last block.
  Map<String, dynamic>? selected;
  for (int i = blocks.length - 1; i >= 0; i--) {
    final Object? b0 = blocks[i];
    if (b0 is! Map) continue;
    final Map<String, dynamic> b = Map<String, dynamic>.from(b0);
    final Object? finished = b['finished_at'];
    if (finished == null || _asInt(finished) <= 0) {
      selected = b;
      blocks[i] = b;
      break;
    }
  }
  if (selected == null) {
    final Object? b0 = blocks.last;
    selected = (b0 is Map) ? Map<String, dynamic>.from(b0) : <String, dynamic>{};
    blocks[blocks.length - 1] = selected;
  }

  // Ensure events list exists.
  final Object? events0 = selected['events'];
  if (events0 is List) {
    selected['events'] = List<dynamic>.from(events0);
  } else {
    selected['events'] = <dynamic>[];
  }

  obj['blocks'] = blocks;
  return selected;
}

Map<String, dynamic> _ensureToolsEvent(
  Map<String, dynamic> block, {
  required String toolsTitle,
  String toolsIconKey = 'auto_awesome_outlined',
}) {
  final List<dynamic> events =
      (block['events'] is List) ? List<dynamic>.from(block['events'] as List) : <dynamic>[];

  Map<String, dynamic>? found;
  for (int i = events.length - 1; i >= 0; i--) {
    final Object? e0 = events[i];
    if (e0 is! Map) continue;
    final Map<String, dynamic> e = Map<String, dynamic>.from(e0);
    final String type = (e['type'] ?? '').toString().trim();
    if (type == 'tools') {
      found = e;
      events[i] = e;
      break;
    }
  }
  if (found == null) {
    found = <String, dynamic>{
      'type': 'tools',
      'title': toolsTitle,
      'icon': toolsIconKey,
      'tools': <Map<String, dynamic>>[],
    };
    events.add(found);
  } else {
    if (((found['title'] ?? '').toString().trim()).isEmpty) {
      found['title'] = toolsTitle;
    }
    if (((found['icon'] ?? '').toString().trim()).isEmpty) {
      found['icon'] = toolsIconKey;
    }
  }

  // Ensure tools list exists.
  final Object? tools0 = found['tools'];
  if (tools0 is List) {
    found['tools'] = List<dynamic>.from(tools0);
  } else {
    found['tools'] = <dynamic>[];
  }

  block['events'] = events;
  return found;
}

/// Patch/extend v2 `ui_thinking_json` with tool UI events emitted by the service.
///
/// Supported payload types:
/// - `tool_batch_begin`: upserts tool chips and marks them active.
/// - `tool_call_end`: marks the matching chip inactive and attaches `result_summary`.
///
/// If `uiThinkingJson` is empty, we create a minimal v2 structure so the chat
/// bubble can still render the tool timeline even if the UI detached.
String? patchUiThinkingJsonWithToolUiEvent(
  String? uiThinkingJson,
  Map<String, dynamic> payload, {
  required int assistantCreatedAtMs,
  required String toolsTitle,
}) {
  final String type = (payload['type'] ?? '').toString().trim();
  if (type != 'tool_batch_begin' && type != 'tool_call_end') return uiThinkingJson;

  final int createdAtMs = assistantCreatedAtMs > 0
      ? assistantCreatedAtMs
      : DateTime.now().millisecondsSinceEpoch;

  final String raw = (uiThinkingJson ?? '').trim();
  final Map<String, dynamic>? decoded =
      raw.isEmpty ? null : _tryDecodeJsonMap(raw);
  if (raw.isNotEmpty && decoded == null) return uiThinkingJson;

  final Map<String, dynamic> obj = _ensureV2Base(
    decoded: decoded,
    assistantCreatedAtMs: createdAtMs,
  );
  if (_asInt(obj['v']) != 2) return uiThinkingJson;

  // Ensure the target block/event exists.
  final Map<String, dynamic> block = _ensureWritableBlock(obj);
  final Map<String, dynamic> toolsEvent = _ensureToolsEvent(
    block,
    toolsTitle: toolsTitle,
  );

  if (type == 'tool_batch_begin') {
    final Object? tools0 = payload['tools'];
    if (tools0 is! List) return jsonEncode(obj);

    final List<dynamic> chips =
        (toolsEvent['tools'] is List) ? List<dynamic>.from(toolsEvent['tools'] as List) : <dynamic>[];
    final Set<String> seen = <String>{};

    for (final t0 in tools0) {
      if (t0 is! Map) continue;
      final Map<String, dynamic> t = Map<String, dynamic>.from(t0);
      final String callId = (t['call_id'] ?? '').toString().trim();
      final String toolName = (t['tool_name'] ?? '').toString().trim();
      if (callId.isEmpty || toolName.isEmpty) continue;
      final String labelRaw = (t['label'] ?? '').toString().trim();
      final String label = labelRaw.isEmpty ? toolName : labelRaw;
      final List<String> appNames = _parseStringList(t['app_names']);
      final List<String> appPkgs = _parseStringList(t['app_package_names']);

      seen.add(callId);

      int existingIdx = -1;
      Map<String, dynamic>? existing;
      for (int i = 0; i < chips.length; i++) {
        final Object? c0 = chips[i];
        if (c0 is! Map) continue;
        final Map<String, dynamic> c = Map<String, dynamic>.from(c0);
        final String id = (c['call_id'] ?? '').toString().trim();
        if (id == callId) {
          existingIdx = i;
          existing = c;
          break;
        }
      }

      final Map<String, dynamic> chip = existing ?? <String, dynamic>{
        'call_id': callId,
        'tool_name': toolName,
      };
      chip['tool_name'] = toolName;
      chip['label'] = label;
      chip['active'] = true;
      chip.remove('result_summary');
      if (appNames.isNotEmpty) chip['app_names'] = appNames;
      if (appPkgs.isNotEmpty) chip['app_package_names'] = appPkgs;

      if (existingIdx >= 0) {
        chips[existingIdx] = chip;
      } else {
        chips.add(chip);
      }
    }

    // Only shimmer tools that are currently in flight.
    for (int i = 0; i < chips.length; i++) {
      final Object? c0 = chips[i];
      if (c0 is! Map) continue;
      final Map<String, dynamic> c = Map<String, dynamic>.from(c0);
      final String callId = (c['call_id'] ?? '').toString().trim();
      if (callId.isEmpty) continue;
      if (!seen.contains(callId)) {
        c['active'] = false;
        chips[i] = c;
      }
    }

    toolsEvent['tools'] = chips;
  } else if (type == 'tool_call_end') {
    final String callId = (payload['call_id'] ?? '').toString().trim();
    final String toolName = (payload['tool_name'] ?? '').toString().trim();
    final String summary = (payload['result_summary'] ?? '').toString().trim();
    if (callId.isEmpty || toolName.isEmpty) return jsonEncode(obj);

    bool updated = false;

    // Find the chip across blocks (new tool calls may start in a different block).
    final Object? blocks0 = obj['blocks'];
    final List<dynamic> blocks =
        (blocks0 is List) ? List<dynamic>.from(blocks0) : <dynamic>[];
    for (int bi = blocks.length - 1; bi >= 0 && !updated; bi--) {
      final Object? b0 = blocks[bi];
      if (b0 is! Map) continue;
      final Map<String, dynamic> b = Map<String, dynamic>.from(b0);
      final Object? events0 = b['events'];
      final List<dynamic> events =
          (events0 is List) ? List<dynamic>.from(events0) : <dynamic>[];
      for (int ei = events.length - 1; ei >= 0 && !updated; ei--) {
        final Object? e0 = events[ei];
        if (e0 is! Map) continue;
        final Map<String, dynamic> e = Map<String, dynamic>.from(e0);
        final String et = (e['type'] ?? '').toString().trim();
        if (et != 'tools') continue;
        final Object? chips0 = e['tools'];
        final List<dynamic> chips =
            (chips0 is List) ? List<dynamic>.from(chips0) : <dynamic>[];
        for (int ci = 0; ci < chips.length; ci++) {
          final Object? c0 = chips[ci];
          if (c0 is! Map) continue;
          final Map<String, dynamic> c = Map<String, dynamic>.from(c0);
          final String id = (c['call_id'] ?? '').toString().trim();
          if (id != callId) continue;
          c['active'] = false;
          if (summary.isNotEmpty) c['result_summary'] = summary;
          chips[ci] = c;
          e['tools'] = chips;
          events[ei] = e;
          b['events'] = events;
          blocks[bi] = b;
          updated = true;
          break;
        }
      }
    }

    if (!updated) {
      // Fallback: ensure a tools event exists and append a minimal chip.
      final List<dynamic> chips =
          (toolsEvent['tools'] is List) ? List<dynamic>.from(toolsEvent['tools'] as List) : <dynamic>[];
      chips.add(<String, dynamic>{
        'call_id': callId,
        'tool_name': toolName,
        'label': toolName,
        'active': false,
        if (summary.isNotEmpty) 'result_summary': summary,
      });
      toolsEvent['tools'] = chips;
    }

    obj['blocks'] = blocks;
  }

  try {
    return jsonEncode(obj);
  } catch (_) {
    return uiThinkingJson;
  }
}

