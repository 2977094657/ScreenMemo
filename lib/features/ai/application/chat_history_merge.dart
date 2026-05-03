import 'dart:convert';

import 'package:screen_memo/features/ai/application/ai_settings_service.dart';

String _norm(String s) => s.trim();

int _asInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

bool _uiThinkingHasUnfinishedBlocks(String raw) {
  final String t = raw.trim();
  if (t.isEmpty) return false;
  try {
    final Object? decoded = jsonDecode(t);
    if (decoded is! Map) return false;
    final Map<String, dynamic> obj = Map<String, dynamic>.from(decoded);
    if (_asInt(obj['v']) != 2) return false;
    final Object? blocks0 = obj['blocks'];
    if (blocks0 is! List) return false;
    for (final b0 in blocks0) {
      if (b0 is! Map) continue;
      final Map<String, dynamic> b = Map<String, dynamic>.from(b0);
      final Object? finished = b['finished_at'];
      if (finished == null) return true;
      if (_asInt(finished) <= 0) return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// Best-effort: patch v2 `ui_thinking_json` to mark loading blocks finished.
///
/// This is used when the UI detached mid-stream (so the persisted timeline has
/// no `finished_at`), and the background request later completes at service
/// level.
String? patchUiThinkingJsonFinish(
  String? uiThinkingJson, {
  Duration? reasoningDuration,
  int? nowMs,
}) {
  final String t = (uiThinkingJson ?? '').trim();
  if (t.isEmpty) return uiThinkingJson;
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  try {
    final Object? decoded = jsonDecode(t);
    if (decoded is! Map) return uiThinkingJson;
    final Map<String, dynamic> obj = Map<String, dynamic>.from(decoded);
    if (_asInt(obj['v']) != 2) return uiThinkingJson;
    final Object? blocks0 = obj['blocks'];
    if (blocks0 is! List) return uiThinkingJson;

    final List<dynamic> blocks = List<dynamic>.from(blocks0);
    if (blocks.isEmpty) return uiThinkingJson;

    // Prefer aligning the finished timestamp with the recorded reasoning duration.
    int finishAt = now;
    if (reasoningDuration != null && reasoningDuration.inMilliseconds > 0) {
      final Object? first0 = blocks.first;
      if (first0 is Map) {
        final Map<String, dynamic> first = Map<String, dynamic>.from(first0);
        final int createdAt = _asInt(first['created_at']);
        if (createdAt > 0) {
          finishAt = createdAt + reasoningDuration.inMilliseconds;
        }
      }
    }

    bool changed = false;
    for (int i = 0; i < blocks.length; i++) {
      final Object? b0 = blocks[i];
      if (b0 is! Map) continue;
      final Map<String, dynamic> b = Map<String, dynamic>.from(b0);
      final Object? finished0 = b['finished_at'];
      if (finished0 != null && _asInt(finished0) > 0) continue;
      final int createdAt = _asInt(b['created_at']);
      if (createdAt <= 0) continue;
      b['finished_at'] = finishAt < createdAt ? createdAt : finishAt;
      blocks[i] = b;
      changed = true;
    }

    // Also clear any lingering "active" shimmer flags. The UI only expects
    // `active` on loading blocks; after background completion we may patch
    // `finished_at`, but stale `active: true` would keep shimmering forever.
    for (int i = 0; i < blocks.length; i++) {
      final Object? b0 = blocks[i];
      if (b0 is! Map) continue;
      final Map<String, dynamic> b = Map<String, dynamic>.from(b0);
      final Object? events0 = b['events'];
      if (events0 is! List) continue;
      final List<dynamic> events = List<dynamic>.from(events0);
      bool eventsChanged = false;
      for (int ei = 0; ei < events.length; ei++) {
        final Object? e0 = events[ei];
        if (e0 is! Map) continue;
        final Map<String, dynamic> e = Map<String, dynamic>.from(e0);
        if (e.containsKey('active')) {
          e.remove('active');
          eventsChanged = true;
        }
        final Object? tools0 = e['tools'];
        if (tools0 is List) {
          final List<dynamic> tools = List<dynamic>.from(tools0);
          bool toolsChanged = false;
          for (int ci = 0; ci < tools.length; ci++) {
            final Object? c0 = tools[ci];
            if (c0 is! Map) continue;
            final Map<String, dynamic> c = Map<String, dynamic>.from(c0);
            if (c.containsKey('active')) {
              c.remove('active');
              tools[ci] = c;
              toolsChanged = true;
            }
          }
          if (toolsChanged) {
            e['tools'] = tools;
            eventsChanged = true;
          }
        }
        if (eventsChanged) events[ei] = e;
      }
      if (eventsChanged) {
        b['events'] = events;
        blocks[i] = b;
        changed = true;
      }
    }

    if (!changed) return uiThinkingJson;
    obj['blocks'] = blocks;
    return jsonEncode(obj);
  } catch (_) {
    return uiThinkingJson;
  }
}

bool _isUserMatch(AIMessage m, String userTrim) =>
    m.role == 'user' && _norm(m.content) == userTrim;

/// Merge a completed assistant turn into the current persisted chat history.
///
/// Rationale: the UI may have already persisted the in-flight user message and a
/// placeholder assistant bubble (including `uiThinkingJson`) before the model
/// finishes. If the service overwrites history using a stale snapshot, it can:
/// - duplicate the user message
/// - drop the UI thinking timeline (`uiThinkingJson`)
List<AIMessage> mergeCompletedTurnIntoHistory({
  required List<AIMessage> existingHistory,
  required String userMessage,
  required AIMessage assistantFinal,
  int? nowMs,
}) {
  final String userTrim = userMessage.trim();
  final List<AIMessage> out = List<AIMessage>.from(existingHistory);
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  int uiThinkingScore(String? raw) {
    final String t = (raw ?? '').trim();
    if (t.isEmpty) return 0;
    try {
      final Object? decoded = jsonDecode(t);
      if (decoded is! Map) return 1;
      final Map<String, dynamic> obj = Map<String, dynamic>.from(decoded);
      final int ver = _asInt(obj['v']);
      if (ver != 2) return 1;
      final Object? blocks0 = obj['blocks'];
      if (blocks0 is! List) return 1;

      int blocks = 0;
      int events = 0;
      int chips = 0;
      int summaries = 0;
      for (final b0 in blocks0) {
        if (b0 is! Map) continue;
        blocks += 1;
        final Map<String, dynamic> b = Map<String, dynamic>.from(b0);
        final Object? events0 = b['events'];
        if (events0 is! List) continue;
        for (final e0 in events0) {
          if (e0 is! Map) continue;
          events += 1;
          final Map<String, dynamic> e = Map<String, dynamic>.from(e0);
          final Object? tools0 = e['tools'];
          if (tools0 is! List) continue;
          for (final c0 in tools0) {
            if (c0 is! Map) continue;
            chips += 1;
            final Map<String, dynamic> c = Map<String, dynamic>.from(c0);
            final String rs = (c['result_summary'] ?? '').toString().trim();
            if (rs.isNotEmpty) summaries += 1;
          }
        }
      }

      int segBonus = 0;
      final Object? seg0 = obj['seg_lens'];
      if (seg0 is List && seg0.length > 1) segBonus = 1;

      return blocks * 100000 +
          events * 1000 +
          chips * 10 +
          summaries +
          segBonus;
    } catch (_) {
      return 1;
    }
  }

  String? pickBetterUiThinkingJson(String? a, String? b) {
    final int sa = uiThinkingScore(a);
    final int sb = uiThinkingScore(b);
    if (sb > sa) return b;
    if (sa > sb) return a;
    final String ta = (a ?? '').trim();
    final String tb = (b ?? '').trim();
    if (ta.isEmpty) return tb.isEmpty ? a : b;
    if (tb.isEmpty) return a;
    return a;
  }

  AIMessage mergedAssistantFrom(AIMessage? existingAssistant) {
    final AIMessage base = existingAssistant ?? assistantFinal;

    final String content = assistantFinal.content.trim().isNotEmpty
        ? assistantFinal.content
        : base.content;
    final String? reasoning =
        (assistantFinal.reasoningContent ?? '').trim().isNotEmpty
        ? assistantFinal.reasoningContent
        : base.reasoningContent;
    final Duration? dur =
        assistantFinal.reasoningDuration ?? base.reasoningDuration;

    String? ui = pickBetterUiThinkingJson(
      base.uiThinkingJson,
      assistantFinal.uiThinkingJson,
    );
    ui = patchUiThinkingJsonFinish(ui, reasoningDuration: dur, nowMs: now);

    return AIMessage(
      role: 'assistant',
      content: content,
      createdAt: base.createdAt,
      reasoningContent: reasoning,
      reasoningDuration: dur,
      uiThinkingJson: ui,
    );
  }

  if (userTrim.isEmpty) {
    out.add(mergedAssistantFrom(null));
    return out;
  }

  int userIdx = -1;
  int assistantIdx = -1;
  bool anchoredOnUnfinishedUi = false;

  // 1) Prefer replacing an unfinished UI placeholder (uiThinkingJson without finished_at).
  for (int i = out.length - 1; i >= 1; i--) {
    final AIMessage a = out[i];
    if (a.role != 'assistant') continue;
    final String ui = (a.uiThinkingJson ?? '').trim();
    if (ui.isEmpty) continue;
    if (!_uiThinkingHasUnfinishedBlocks(ui)) continue;
    final AIMessage u = out[i - 1];
    if (_isUserMatch(u, userTrim)) {
      userIdx = i - 1;
      assistantIdx = i;
      anchoredOnUnfinishedUi = true;
      break;
    }
  }

  // 2) Fallback: match the last user message and replace/insert after it.
  if (userIdx < 0) {
    for (int i = out.length - 1; i >= 0; i--) {
      if (_isUserMatch(out[i], userTrim)) {
        userIdx = i;
        break;
      }
    }
    if (userIdx >= 0) {
      for (int j = userIdx + 1; j < out.length; j++) {
        final String r = out[j].role;
        if (r == 'assistant') {
          assistantIdx = j;
          break;
        }
        if (r == 'user') break;
      }
    }
  }

  if (assistantIdx >= 0) {
    final AIMessage existingAssistant = out[assistantIdx];
    out[assistantIdx] = mergedAssistantFrom(existingAssistant);

    // Clean up corrupted history from older buggy runs:
    // [user X, assistant placeholder, user X, assistant ...] -> collapse the dup pair.
    if (anchoredOnUnfinishedUi &&
        assistantIdx + 1 < out.length &&
        _isUserMatch(out[assistantIdx + 1], userTrim)) {
      out.removeAt(assistantIdx + 1);
      if (assistantIdx + 1 < out.length &&
          out[assistantIdx + 1].role == 'assistant') {
        out.removeAt(assistantIdx + 1);
      }
    }
    return out;
  }

  if (userIdx >= 0) {
    // Insert the assistant right after the matched user message (even if later turns exist).
    out.insert(userIdx + 1, mergedAssistantFrom(null));
    return out;
  }

  // No matching user found: append a new completed turn.
  out.add(AIMessage(role: 'user', content: userTrim));
  out.add(mergedAssistantFrom(null));
  return out;
}
