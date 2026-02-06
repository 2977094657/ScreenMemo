import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'ai_context_budgets.dart';
import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'locale_service.dart';
import 'prompt_budget.dart';
import 'screenshot_database.dart';

class ChatContextSnapshot {
  const ChatContextSnapshot({
    required this.cid,
    required this.summary,
    required this.summaryUpdatedAtMs,
    required this.summaryTokens,
    required this.compactionCount,
    required this.lastCompactionReason,
    required this.toolMemoryJson,
    required this.toolMemoryUpdatedAtMs,
    required this.lastPromptTokens,
    required this.lastPromptAtMs,
    required this.lastPromptBreakdownJson,
    required this.fullMessageCount,
  });

  final String cid;
  final String summary;
  final int? summaryUpdatedAtMs;
  final int summaryTokens;
  final int compactionCount;
  final String? lastCompactionReason;
  final String toolMemoryJson;
  final int? toolMemoryUpdatedAtMs;
  final int? lastPromptTokens;
  final int? lastPromptAtMs;
  final String lastPromptBreakdownJson;
  final int fullMessageCount;
}

/// Aggregate prompt-token stats across all conversations.
///
/// Note: this is based on the last recorded prompt snapshot per conversation
/// (`ai_conversations.last_prompt_*`), so it's an approximate "global usage"
/// view, not a billing-accurate counter.
class GlobalPromptTokenStats {
  const GlobalPromptTokenStats({
    required this.totalTokens,
    required this.parts,
  });

  final int totalTokens;
  final Map<String, int> parts;
}

/// Conversation context system inspired by Codex:
/// - Stores a rolling summary + compact tool-memory per conversation (cid)
/// - Maintains an append-only transcript for safe compaction
/// - Auto-compacts when the transcript grows past a token budget
class ChatContextService {
  ChatContextService._internal();
  static final ChatContextService instance = ChatContextService._internal();

  static const int maxSummaryTokens = 1200;
  static const int autoCompactTriggerTokens = 9000;
  static const int autoCompactTriggerMessages = 400;
  static const int keepRecentUncompactedTokens = 6000;
  static const int keepRecentUncompactedMinMessages = 20;
  static const int maxCompactionInputTokens = 16000;

  static const int toolMemoryMaxItems = 30;
  static const int toolMemoryMaxBytes = 40 * 1024; // keep it small

  final AISettingsService _settings = AISettingsService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  final Map<String, Future<void>> _serialized = <String, Future<void>>{};

  Future<void> recordPromptTokens({
    required String cid,
    required int tokensApprox,
    String? breakdownJson,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final storage = await _db.database;
      if (breakdownJson != null) {
        await storage.execute(
          'UPDATE ai_conversations SET last_prompt_tokens = ?, last_prompt_at = ?, last_prompt_breakdown_json = ? WHERE cid = ?',
          <Object?>[tokensApprox, now, breakdownJson, cid],
        );
      } else {
        await storage.execute(
          'UPDATE ai_conversations SET last_prompt_tokens = ?, last_prompt_at = ? WHERE cid = ?',
          <Object?>[tokensApprox, now, cid],
        );
      }
    } catch (_) {}
  }

  Future<void> logContextEvent({
    required String cid,
    required String type,
    Map<String, dynamic>? payload,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final storage = await _db.database;
      await storage.insert('ai_context_events', <String, Object?>{
        'conversation_id': cid,
        'type': type.trim().isEmpty ? 'event' : type.trim(),
        'payload_json': payload == null ? null : jsonEncode(payload),
        'created_at': now,
      });
    } catch (_) {}
  }

  Future<int> getGlobalPromptTokensTotal() async {
    try {
      final storage = await _db.database;
      final rows = await storage.rawQuery(
        'SELECT SUM(COALESCE(last_prompt_tokens, 0)) AS c FROM ai_conversations',
      );
      if (rows.isEmpty) return 0;
      return _toInt(rows.first['c']);
    } catch (_) {
      return 0;
    }
  }

  Future<GlobalPromptTokenStats> getGlobalPromptTokensStats() async {
    int totalTokens = 0;
    final Map<String, int> parts = <String, int>{};

    try {
      final storage = await _db.database;
      final rows = await storage.query(
        'ai_conversations',
        columns: <String>['last_prompt_tokens', 'last_prompt_breakdown_json'],
      );

      for (final Map<String, Object?> row in rows) {
        int rowTotal = _toInt(row['last_prompt_tokens']);

        final String raw =
            (row['last_prompt_breakdown_json'] as String?)?.trim() ?? '';

        Map? decodedMap;
        if (raw.isNotEmpty) {
          try {
            final dynamic decoded = jsonDecode(raw);
            if (decoded is Map) decodedMap = decoded;
          } catch (_) {}
        }

        // Prefer the breakdown's `total_tokens` so the total matches parts.
        if (decodedMap != null) {
          final dynamic t = decodedMap['total_tokens'];
          if (t is num) rowTotal = t.toInt();
        }

        if (rowTotal <= 0) continue;
        totalTokens += rowTotal;

        if (decodedMap == null) {
          // No breakdown: keep totals consistent under a generic bucket.
          parts['extra_system'] = (parts['extra_system'] ?? 0) + rowTotal;
          continue;
        }

        int rowPartsSum = 0;
        final dynamic p = decodedMap['parts'];
        if (p is Map) {
          for (final entry in p.entries) {
            final String k = entry.key.toString();
            final dynamic v = entry.value;
            if (v is! num) continue;
            final int t = v.toInt();
            if (t <= 0) continue;
            parts[k] = (parts[k] ?? 0) + t;
            rowPartsSum += t;
          }
        }

        // Partial breakdown: put the remainder into a generic bucket.
        final int diff = rowTotal - rowPartsSum;
        if (diff > 0) {
          parts['extra_system'] = (parts['extra_system'] ?? 0) + diff;
        }
      }
    } catch (_) {}

    return GlobalPromptTokenStats(totalTokens: totalTokens, parts: parts);
  }

  Future<ChatContextSnapshot> getSnapshot({String? cid}) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    final Map<String, dynamic>? row = await _db.getAiConversationByCid(
      resolvedCid,
    );

    String summary = '';
    int? summaryUpdatedAtMs;
    int summaryTokens0 = 0;
    int compactionCount = 0;
    String? lastCompactionReason;
    String toolMemoryJson = '';
    int? toolMemoryUpdatedAtMs;
    int? lastPromptTokens;
    int? lastPromptAtMs;
    String lastPromptBreakdownJson = '';

    if (row != null) {
      summary = (row['summary'] as String?)?.trim() ?? '';
      summaryUpdatedAtMs = row['summary_updated_at'] as int?;
      summaryTokens0 = _toInt(row['summary_tokens']);
      compactionCount = _toInt(row['compaction_count']);
      lastCompactionReason = (row['last_compaction_reason'] as String?)?.trim();
      toolMemoryJson = (row['tool_memory_json'] as String?)?.trim() ?? '';
      toolMemoryUpdatedAtMs = row['tool_memory_updated_at'] as int?;
      lastPromptTokens = _toInt(row['last_prompt_tokens']);
      lastPromptAtMs = row['last_prompt_at'] as int?;
      lastPromptBreakdownJson =
          (row['last_prompt_breakdown_json'] as String?)?.trim() ?? '';
    }

    final int fullMessageCount = await _countFullMessages(resolvedCid);
    final int summaryTokens = summaryTokens0 > 0
        ? summaryTokens0
        : PromptBudget.approxTokensForText(summary);

    return ChatContextSnapshot(
      cid: resolvedCid,
      summary: summary,
      summaryUpdatedAtMs: summaryUpdatedAtMs,
      summaryTokens: summaryTokens,
      compactionCount: compactionCount,
      lastCompactionReason: lastCompactionReason,
      toolMemoryJson: toolMemoryJson,
      toolMemoryUpdatedAtMs: toolMemoryUpdatedAtMs,
      lastPromptTokens: lastPromptTokens,
      lastPromptAtMs: lastPromptAtMs,
      lastPromptBreakdownJson: lastPromptBreakdownJson,
      fullMessageCount: fullMessageCount,
    );
  }

  /// Build a single system message that injects compacted conversation memory.
  /// Return empty string if there is nothing to inject.
  Future<String> buildSystemContextMessage({String? cid}) async {
    final ChatContextSnapshot snap = await getSnapshot(cid: cid);
    final String summary = snap.summary.trim();
    final String toolMem = snap.toolMemoryJson.trim();

    final List<String> blocks = <String>[];
    if (summary.isNotEmpty) {
      blocks.add(_formatSummaryBlock(summary));
    }
    final String toolBlock = _formatToolMemoryBlock(toolMem);
    if (toolBlock.isNotEmpty) {
      blocks.add(toolBlock);
    }
    if (blocks.isEmpty) return '';

    return [
      '<conversation_context>',
      ...blocks,
      '</conversation_context>',
    ].join('\n').trim();
  }

  /// Seed the append-only transcript using the current chat history (tail table)
  /// if the transcript is still empty. This is a best-effort bootstrap for
  /// existing installs that already have `ai_messages` but not `ai_messages_full`.
  Future<void> seedFromChatHistoryIfEmpty({
    String? cid,
    required List<AIMessage> history,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    if (history.isEmpty) return;
    final int fullCount = await _countFullMessages(resolvedCid);
    if (fullCount > 0) return;
    for (final AIMessage m in history) {
      final String role = m.role;
      if (role != 'user' && role != 'assistant') continue;
      final String text = m.content.trim();
      if (text.isEmpty) continue;
      await _appendFullMessageDedup(
        resolvedCid,
        role: role,
        content: text,
        createdAtMs: m.createdAt.millisecondsSinceEpoch,
      );
    }
  }

  /// Load recent conversation turns from the append-only transcript and keep a
  /// tail that fits within [maxTokens] (approx).
  ///
  /// This is intentionally decoupled from the UI history tail so the model can
  /// retain more context than what the UI renders.
  Future<List<AIMessage>> loadRecentMessagesForPrompt({
    String? cid,
    required int maxTokens,
    int maxRows = 240,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    if (maxTokens <= 0) return const <AIMessage>[];
    final int lim = maxRows.clamp(20, 1000);
    try {
      final storage = await _db.database;
      final rowsDesc = await storage.query(
        'ai_messages_full',
        columns: <String>['role', 'content', 'created_at'],
        where: 'conversation_id = ?',
        whereArgs: <Object?>[resolvedCid],
        orderBy: 'id DESC',
        limit: lim,
      );
      final List<AIMessage> msgs = rowsDesc.reversed
          .map((r) {
            final String role = (r['role'] as String?) ?? 'user';
            if (role != 'user' && role != 'assistant') return null;
            final String content = (r['content'] as String?) ?? '';
            if (content.trim().isEmpty) return null;
            final int createdAt = _toInt(r['created_at']);
            return AIMessage(
              role: role,
              content: content,
              createdAt: createdAt > 0
                  ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                  : null,
            );
          })
          .whereType<AIMessage>()
          .toList();

      if (msgs.isEmpty) return const <AIMessage>[];
      return PromptBudget.keepTailUnderTokenBudget(msgs, maxTokens: maxTokens);
    } catch (_) {
      return const <AIMessage>[];
    }
  }

  Future<void> appendCompletedTurn({
    required String cid,
    required String userMessage,
    required String assistantMessage,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _appendFullMessageDedup(
      cid,
      role: 'user',
      content: userMessage,
      createdAtMs: now,
    );
    await _appendFullMessageDedup(
      cid,
      role: 'assistant',
      content: assistantMessage,
      createdAtMs: now,
    );
  }

  Future<void> mergeToolDigests({
    required String cid,
    required Map<String, Map<String, dynamic>> signatureDigests,
  }) async {
    if (signatureDigests.isEmpty) return;
    final int now = DateTime.now().millisecondsSinceEpoch;

    Map<String, dynamic> parsed = <String, dynamic>{
      'v': 1,
      'items': <dynamic>[],
    };
    try {
      final Map<String, dynamic>? row = await _db.getAiConversationByCid(cid);
      final String? raw = row?['tool_memory_json'] as String?;
      if (raw != null && raw.trim().isNotEmpty) {
        final dynamic v = jsonDecode(raw);
        if (v is Map) {
          parsed = Map<String, dynamic>.from(v);
        }
      }
    } catch (_) {}

    final List<dynamic> items0 = (parsed['items'] is List)
        ? List<dynamic>.from(parsed['items'] as List)
        : <dynamic>[];

    final Map<String, dynamic> bySig = <String, dynamic>{};
    for (final dynamic it in items0) {
      if (it is! Map) continue;
      final String sig = (it['sig'] ?? '').toString();
      if (sig.isEmpty) continue;
      bySig[sig] = Map<String, dynamic>.from(it);
    }

    for (final MapEntry<String, Map<String, dynamic>> e
        in signatureDigests.entries) {
      final String sig = e.key.trim();
      if (sig.isEmpty) continue;
      final Map<String, dynamic> digest = Map<String, dynamic>.from(e.value);
      final String tool = (digest['tool'] as String?)?.trim() ?? '';
      bySig[sig] = <String, dynamic>{
        'ts': now,
        'tool': tool,
        'sig': sig,
        'digest': digest,
      };
    }

    final List<Map<String, dynamic>> merged =
        bySig.values
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
          ..sort((a, b) => _toInt(a['ts']).compareTo(_toInt(b['ts'])));

    final List<Map<String, dynamic>> tail = merged.length <= toolMemoryMaxItems
        ? merged
        : merged.sublist(merged.length - toolMemoryMaxItems);

    String encoded = jsonEncode(<String, dynamic>{
      'v': 1,
      'updated_at': now,
      'items': tail,
    });

    // Final guard: avoid unbounded memory JSON.
    if (PromptBudget.utf8Bytes(encoded) > toolMemoryMaxBytes) {
      // Drop oldest until it fits.
      final List<Map<String, dynamic>> shrink = List<Map<String, dynamic>>.from(
        tail,
      );
      while (shrink.isNotEmpty &&
          PromptBudget.utf8Bytes(encoded) > toolMemoryMaxBytes) {
        shrink.removeAt(0);
        encoded = jsonEncode(<String, dynamic>{
          'v': 1,
          'updated_at': now,
          'items': shrink,
        });
      }
    }

    try {
      final storage = await _db.database;
      await storage.execute(
        'UPDATE ai_conversations SET tool_memory_json = ?, tool_memory_updated_at = ? WHERE cid = ?',
        <Object?>[encoded, now, cid],
      );
    } catch (_) {}
  }

  /// Enqueue auto-compaction for a conversation. Safe to call frequently; it
  /// serializes by cid and exits early when under budget.
  void scheduleAutoCompact({required String cid, String reason = 'auto'}) {
    _serialized[cid] = (_serialized[cid] ?? Future<void>.value())
        .then((_) async {
          await _maybeAutoCompact(cid, reason: reason);
        })
        .catchError((_) {});
  }

  Future<void> compactNow({String? cid, String reason = 'manual'}) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    await (_serialized[resolvedCid] ?? Future<void>.value());
    final Future<void> task = _maybeAutoCompact(
      resolvedCid,
      force: true,
      reason: reason,
    );
    _serialized[resolvedCid] = task;
    await task;
  }

  Future<void> clearContext({String? cid}) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    try {
      final storage = await _db.database;
      await storage.transaction((txn) async {
        try {
          await txn.execute(
            'UPDATE ai_conversations SET summary = NULL, summary_updated_at = NULL, summary_tokens = NULL, compaction_count = 0, last_compaction_reason = NULL, tool_memory_json = NULL, tool_memory_updated_at = NULL, last_prompt_tokens = NULL, last_prompt_at = NULL, last_prompt_breakdown_json = NULL WHERE cid = ?',
            <Object?>[resolvedCid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_messages_full',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[resolvedCid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_atomic_memories',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[resolvedCid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_context_events',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[resolvedCid],
          );
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _maybeAutoCompact(
    String cid, {
    bool force = false,
    String reason = 'auto',
  }) async {
    final Stopwatch sw = Stopwatch()..start();

    final List<_FullMsg> msgs = await _loadFullMessages(cid);
    if (msgs.isEmpty) return;

    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: 'chat',
    );
    if (endpoints.isEmpty) return;
    final String modelForBudget = endpoints.first.model.trim().isNotEmpty
        ? endpoints.first.model
        : (await _settings.getModel());
    final AIContextBudgets budgets =
        await AIContextBudgets.forModelWithOverrides(modelForBudget);

    final int totalTokens = _approxTokensForFullMessages(msgs);
    // Codex-style: compact only when we are close to the model context window.
    if (!force && totalTokens < budgets.autoCompactTriggerTokens) return;

    final int keepStart = _selectKeepStartIndex(
      msgs,
      keepRecentTokens: budgets.keepRecentUncompactedTokens,
    );
    if (keepStart <= 0) return;
    final List<_FullMsg> toCompact = msgs.sublist(0, keepStart);
    final List<_FullMsg> toKeep = msgs.sublist(keepStart);

    final Map<String, dynamic>? row = await _db.getAiConversationByCid(cid);
    final String oldSummary = (row?['summary'] as String?)?.trim() ?? '';

    final int beforeSummaryTokens = PromptBudget.approxTokensForText(
      oldSummary,
    );
    final int beforeMessages = msgs.length;

    String summary = oldSummary;
    String modelUsed = '';
    final List<List<_FullMsg>> chunks = _chunkForCompaction(
      toCompact,
      maxChunkTokens: budgets.maxCompactionInputTokens,
    );
    for (final chunk in chunks) {
      final _CompactionRun out = await _runCompactionOnce(
        endpoints: endpoints,
        previousSummary: summary,
        messages: chunk,
        maxSummaryTokens: budgets.maxSummaryTokens,
        maxCompactionInputTokens: budgets.maxCompactionInputTokens,
      );
      summary = out.summary;
      modelUsed = out.modelUsed;
    }
    summary = _enforceSummaryBudget(
      summary,
      maxSummaryTokens: budgets.maxSummaryTokens,
    );

    final int afterSummaryTokens = PromptBudget.approxTokensForText(summary);
    final int compactedUpToId = toCompact.last.id;
    final int now = DateTime.now().millisecondsSinceEpoch;
    sw.stop();

    final Map<String, dynamic> eventPayload = <String, dynamic>{
      'reason': reason,
      'before_uncompacted_tokens': totalTokens,
      'after_uncompacted_tokens': _approxTokensForFullMessages(toKeep),
      'before_summary_tokens': beforeSummaryTokens,
      'after_summary_tokens': afterSummaryTokens,
      'compacted_messages': toCompact.length,
      'kept_messages': toKeep.length,
      'before_messages': beforeMessages,
      'duration_ms': sw.elapsedMilliseconds,
      'chunk_count': chunks.length,
    };
    eventPayload['model_used'] = modelUsed.isEmpty ? null : modelUsed;

    try {
      final storage = await _db.database;
      await storage.transaction((txn) async {
        try {
          await txn.execute(
            'UPDATE ai_conversations SET summary = ?, summary_updated_at = ?, summary_tokens = ?, compaction_count = COALESCE(compaction_count, 0) + 1, last_compaction_reason = ? WHERE cid = ?',
            <Object?>[summary, now, afterSummaryTokens, reason, cid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_messages_full',
            where: 'conversation_id = ? AND id <= ?',
            whereArgs: <Object?>[cid, compactedUpToId],
          );
        } catch (_) {}
        try {
          await txn.insert('ai_context_events', <String, Object?>{
            'conversation_id': cid,
            'type': 'compaction',
            'payload_json': jsonEncode(eventPayload),
            'created_at': now,
          });
        } catch (_) {}
      });
    } catch (_) {}

    try {
      await FlutterLogger.nativeInfo(
        'Context',
        'compacted cid=$cid reason=$reason compacted=${toCompact.length} kept=${toKeep.length} tokens≈$totalTokens summaryTokens≈$afterSummaryTokens',
      );
    } catch (_) {}
  }

  Future<int> _countFullMessages(String cid) async {
    try {
      final storage = await _db.database;
      final rows = await storage.rawQuery(
        'SELECT COUNT(*) AS c FROM ai_messages_full WHERE conversation_id = ?',
        <Object?>[cid],
      );
      if (rows.isEmpty) return 0;
      return _toInt(rows.first['c']);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _appendFullMessageDedup(
    String cid, {
    required String role,
    required String content,
    required int createdAtMs,
  }) async {
    final String text = content.trim();
    if (text.isEmpty) return;
    try {
      final storage = await _db.database;
      final List<Map<String, Object?>> last = await storage.query(
        'ai_messages_full',
        columns: <String>['role', 'content', 'created_at'],
        where: 'conversation_id = ?',
        whereArgs: <Object?>[cid],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (last.isNotEmpty) {
        final String lr = (last.first['role'] as String?) ?? '';
        final String lc = (last.first['content'] as String?) ?? '';
        final int lt = _toInt(last.first['created_at']);
        if (lr == role && lc == text && (createdAtMs - lt).abs() <= 8000) {
          return;
        }
      }

      await storage.insert('ai_messages_full', <String, Object?>{
        'conversation_id': cid,
        'role': role,
        'content': text,
        'created_at': createdAtMs,
      });
    } catch (_) {}
  }

  Future<List<_FullMsg>> _loadFullMessages(String cid) async {
    try {
      final storage = await _db.database;
      final rows = await storage.query(
        'ai_messages_full',
        columns: <String>['id', 'role', 'content', 'created_at'],
        where: 'conversation_id = ?',
        whereArgs: <Object?>[cid],
        orderBy: 'id ASC',
      );
      return rows
          .map(
            (r) => _FullMsg(
              id: _toInt(r['id']),
              role: (r['role'] as String?) ?? 'user',
              content: (r['content'] as String?) ?? '',
              createdAtMs: _toInt(r['created_at']),
            ),
          )
          .where((m) => m.id > 0 && m.content.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return <_FullMsg>[];
    }
  }

  int _selectKeepStartIndex(
    List<_FullMsg> msgs, {
    required int keepRecentTokens,
  }) {
    // Keep at least N last messages, and keep tail tokens <= keepRecentTokens.
    int tokens = 0;
    int kept = 0;
    int i = msgs.length - 1;
    for (; i >= 0; i--) {
      tokens += PromptBudget.approxTokensForText(
        '${msgs[i].role}\n${msgs[i].content}',
      );
      kept += 1;
      if (kept >= keepRecentUncompactedMinMessages &&
          tokens >= keepRecentTokens) {
        break;
      }
    }
    final int start = (i <= 0) ? 0 : i;
    return start;
  }

  int _approxTokensForFullMessages(List<_FullMsg> msgs) {
    int total = 0;
    for (final m in msgs) {
      total += PromptBudget.approxTokensForText('${m.role}\n${m.content}');
    }
    return total;
  }

  List<List<_FullMsg>> _chunkForCompaction(
    List<_FullMsg> msgs, {
    required int maxChunkTokens,
  }) {
    if (msgs.isEmpty) return const <List<_FullMsg>>[];
    final List<List<_FullMsg>> out = <List<_FullMsg>>[];
    int i = 0;
    while (i < msgs.length) {
      int tokens = 0;
      int j = i;
      for (; j < msgs.length; j++) {
        final _FullMsg m = msgs[j];
        final int t = PromptBudget.approxTokensForText(
          '${m.role}\n${m.content}',
        );
        if (j > i && tokens + t > maxChunkTokens) break;
        tokens += t;
      }
      out.add(msgs.sublist(i, j));
      i = j;
    }
    return out;
  }

  Future<_CompactionRun> _runCompactionOnce({
    required List<AIEndpoint> endpoints,
    required String previousSummary,
    required List<_FullMsg> messages,
    required int maxSummaryTokens,
    required int maxCompactionInputTokens,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final String system = _compactionSystemPrompt(
      maxSummaryTokens: maxSummaryTokens,
    );
    final String user = _compactionUserPrompt(
      previousSummary: previousSummary,
      messages: messages,
      maxCompactionInputTokens: maxCompactionInputTokens,
    );

    final AIGatewayResult result = await _gateway.complete(
      endpoints: endpoints,
      messages: <AIMessage>[
        AIMessage(role: 'system', content: system),
        AIMessage(role: 'user', content: user),
      ],
      responseStartMarker: '',
      timeout: const Duration(seconds: 60),
      preferStreaming: false,
      logContext: 'chat_compact',
    );
    sw.stop();

    final String summary = _sanitizeModelText(result.content);
    return _CompactionRun(
      summary: summary,
      modelUsed: result.modelUsed,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  String _compactionSystemPrompt({required int maxSummaryTokens}) {
    final bool zh = _isZhLocale();
    if (zh) {
      return [
        '你是一个“对话上下文压缩器”。你要把对话历史压缩为可复用的记忆摘要，用于后续模型继续对话。',
        '',
        '硬性规则：',
        '- 只基于输入内容，不要编造、不确定就标注不确定。',
        '- 保留用户偏好、约束、已做决定、进行中的任务、关键结论。',
        '- 若出现证据引用，请保留原样，例如 [evidence: filename]。',
        '- 输出为简洁的 Markdown 文本，不要代码块。',
        '',
        '长度要求：尽量短，目标不超过约 $maxSummaryTokens tokens（粗估 bytes/4）。',
      ].join('\n');
    }
    return [
      'You are a conversation CONTEXT COMPACTOR. Produce a reusable memory summary for future turns.',
      '',
      'Hard rules:',
      '- Use ONLY the provided input. Do not invent facts; mark uncertainty explicitly.',
      '- Preserve user preferences/constraints, decisions, ongoing tasks, and key conclusions.',
      '- Preserve evidence markers verbatim, e.g. [evidence: filename].',
      '- Output concise Markdown text only (no code fences).',
      '',
      'Length: keep it short; target <= ~$maxSummaryTokens tokens (rough bytes/4).',
    ].join('\n');
  }

  String _compactionUserPrompt({
    required String previousSummary,
    required List<_FullMsg> messages,
    required int maxCompactionInputTokens,
  }) {
    final String prev = previousSummary.trim().isEmpty
        ? '(empty)'
        : previousSummary.trim();
    final StringBuffer sb = StringBuffer();
    sb.writeln('Existing summary:');
    sb.writeln('<<<');
    sb.writeln(prev);
    sb.writeln('>>>');
    sb.writeln('');
    sb.writeln('New messages to incorporate:');
    for (final _FullMsg m in messages) {
      final String role = m.role == 'assistant' ? 'Assistant' : 'User';
      final String content = _trimForCompaction(
        m.content,
        maxCompactionInputTokens: maxCompactionInputTokens,
      );
      sb.writeln('- $role: $content');
    }
    sb.writeln('');
    sb.writeln('Return the UPDATED summary only.');
    return sb.toString().trim();
  }

  String _trimForCompaction(
    String text, {
    required int maxCompactionInputTokens,
  }) {
    final String t = text.trim();
    if (t.isEmpty) return '';
    final int maxBytes =
        (maxCompactionInputTokens * PromptBudget.approxBytesPerToken * 0.9)
            .floor();
    return PromptBudget.truncateTextByBytes(
      text: t,
      maxBytes: maxBytes,
      marker: '…truncated…',
    );
  }

  String _sanitizeModelText(String text) {
    String t = text.trim();
    if (!t.startsWith('```')) return t;
    t = t.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*```$'), '');
    return t.trim();
  }

  String _enforceSummaryBudget(
    String summary, {
    required int maxSummaryTokens,
  }) {
    final String t = summary.trim();
    if (t.isEmpty) return t;
    final int tokens = PromptBudget.approxTokensForText(t);
    if (tokens <= maxSummaryTokens) return t;
    final int maxBytes = maxSummaryTokens * PromptBudget.approxBytesPerToken;
    return PromptBudget.truncateTextByBytes(
      text: t,
      maxBytes: maxBytes,
      marker: '…summary truncated…',
    ).trim();
  }

  String _formatSummaryBlock(String summary) {
    final bool zh = _isZhLocale();
    final String label = zh ? '对话摘要（压缩）' : 'Conversation summary (compacted)';
    return ['$label:', summary.trim()].join('\n');
  }

  String _formatToolMemoryBlock(String rawJson) {
    if (rawJson.trim().isEmpty) return '';
    dynamic parsed;
    try {
      parsed = jsonDecode(rawJson);
    } catch (_) {
      return '';
    }
    if (parsed is! Map) return '';
    final List<dynamic> items = (parsed['items'] is List)
        ? List<dynamic>.from(parsed['items'] as List)
        : const <dynamic>[];
    if (items.isEmpty) return '';

    final bool zh = _isZhLocale();
    final String label = zh ? '最近工具记忆（摘要）' : 'Recent tool memory (digest)';
    final List<String> lines = <String>[label + ':'];
    int shown = 0;
    for (final dynamic it in items.reversed) {
      if (it is! Map) continue;
      final String tool = (it['tool'] ?? '').toString();
      final Map<String, dynamic>? digest = (it['digest'] is Map)
          ? Map<String, dynamic>.from(it['digest'] as Map)
          : null;
      if (tool.trim().isEmpty || digest == null) continue;
      final String short = _oneLine(jsonEncode(_toolDigestForPrompt(digest)));
      lines.add('- $tool: ${_clip(short, 240)}');
      shown += 1;
      if (shown >= 10) break;
    }
    return lines.join('\n').trim();
  }

  Map<String, dynamic> _toolDigestForPrompt(Map<String, dynamic> digest) {
    final Map<String, dynamic> out = <String, dynamic>{};
    const List<String> keep = <String>[
      'tool',
      'query',
      'mode',
      'app_package_name',
      'start_local',
      'end_local',
      'limit',
      'offset',
      'count',
      'warnings',
      'paging',
      'results',
    ];
    for (final k in keep) {
      if (!digest.containsKey(k)) continue;
      out[k] = digest[k];
    }
    // Results can still be big; trim here.
    final dynamic results = out['results'];
    if (results is List && results.length > 8) {
      out['results'] = <dynamic>[
        ...results.take(6),
        '…omitted ${results.length - 6}…',
      ];
    }
    return out;
  }

  bool _isZhLocale() {
    final Locale? configured = LocaleService.instance.locale;
    final Locale device = WidgetsBinding.instance.platformDispatcher.locale;
    final Locale base = configured ?? device;
    return base.languageCode.toLowerCase().startsWith('zh');
  }

  String _oneLine(String text) =>
      text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();

  String _clip(String text, int maxLen) {
    final String t = _oneLine(text);
    if (t.length <= maxLen) return t;
    return t.substring(0, maxLen) + '…';
  }

  int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

class _FullMsg {
  _FullMsg({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAtMs,
  });

  final int id;
  final String role;
  final String content;
  final int createdAtMs;
}

class _CompactionRun {
  _CompactionRun({
    required this.summary,
    required this.modelUsed,
    required this.durationMs,
  });

  final String summary;
  final String modelUsed;
  final int durationMs;
}
