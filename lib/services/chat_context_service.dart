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

class FullMessagesPage {
  const FullMessagesPage({
    required this.messages,
    required this.nextBeforeId,
    required this.hasMore,
  });

  final List<AIMessage> messages;
  final int? nextBeforeId;
  final bool hasMore;
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

class ChatContextEvent {
  const ChatContextEvent({
    required this.id,
    required this.conversationId,
    required this.type,
    required this.createdAtMs,
    required this.payload,
  });

  final int id;
  final String conversationId;
  final String type;
  final int createdAtMs;
  final Map<String, dynamic> payload;

  String get stage => (payload['stage'] ?? '').toString().trim();
  String get kind => (payload['kind'] ?? '').toString().trim();
  int get beforeTokens => _toInt(payload['before_tokens']);
  int get afterTokens => _toInt(payload['after_tokens']);
  int get droppedTokens => _toInt(payload['dropped_tokens']);
  int get droppedMessages => _toInt(payload['dropped_messages']);
  int get droppedChunks => _toInt(payload['dropped_chunks']);
  bool get truncatedOldest => _toBool(payload['truncated_oldest']);
  String get reason => (payload['reason'] ?? '').toString().trim();
  String get model => (payload['model'] ?? '').toString().trim();

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static bool _toBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final String s = (v ?? '').toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'y';
  }
}

class PromptUsageEvent {
  const PromptUsageEvent({
    required this.id,
    required this.conversationId,
    required this.model,
    required this.promptEstBefore,
    required this.promptEstSent,
    required this.usagePromptTokens,
    required this.usageCompletionTokens,
    required this.usageTotalTokens,
    required this.usageSource,
    required this.isToolLoop,
    required this.includeHistory,
    required this.toolsCount,
    required this.strictFullAttempted,
    required this.fallbackTriggered,
    required this.breakdown,
    required this.createdAtMs,
  });

  final int id;
  final String conversationId;
  final String model;
  final int? promptEstBefore;
  final int? promptEstSent;
  final int? usagePromptTokens;
  final int? usageCompletionTokens;
  final int? usageTotalTokens;
  final String usageSource;
  final bool isToolLoop;
  final bool includeHistory;
  final int toolsCount;
  final bool strictFullAttempted;
  final bool fallbackTriggered;
  final Map<String, dynamic> breakdown;
  final int createdAtMs;

  bool get hasUsage =>
      usagePromptTokens != null ||
      usageCompletionTokens != null ||
      usageTotalTokens != null;

  int get resolvedPromptTokens =>
      usagePromptTokens ?? promptEstSent ?? promptEstBefore ?? 0;

  int get resolvedCompletionTokens {
    if (usageCompletionTokens != null) return usageCompletionTokens!;
    final dynamic v = breakdown['completion_estimate'];
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  int get resolvedTotalTokens {
    if (usageTotalTokens != null) return usageTotalTokens!;
    final dynamic v = breakdown['total_estimate'];
    if (v is num) return v.toInt();
    final int maybe = int.tryParse((v ?? '').toString()) ?? 0;
    if (maybe > 0) return maybe;
    return resolvedPromptTokens + resolvedCompletionTokens;
  }
}

class PromptUsageTotals {
  const PromptUsageTotals({
    required this.eventsCount,
    required this.usageBackedCount,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  final int eventsCount;
  final int usageBackedCount;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  double get usageCoverage =>
      eventsCount <= 0 ? 0 : (usageBackedCount / eventsCount);
}

/// Conversation context system inspired by Codex:
/// - Stores a rolling summary + compact tool-memory per conversation (cid)
/// - Maintains an append-only transcript for safe compaction
/// - Auto-compacts when the transcript grows past a token budget
class ChatContextService {
  ChatContextService._internal();
  static final ChatContextService instance = ChatContextService._internal();

  static const int fullMessagesPageSize = 200;
  static const int rawTranscriptPageSize = 200;

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

  Future<void> appendRawTranscriptMessages({
    required String cid,
    required List<AIMessage> messages,
  }) async {
    final String resolvedCid = cid.trim();
    if (resolvedCid.isEmpty || messages.isEmpty) return;
    try {
      final storage = await _db.database;
      await storage.transaction((txn) async {
        for (final AIMessage message in messages) {
          final String role = message.role.trim();
          if (role.isEmpty) continue;
          final String content = message.content;
          String? apiContentJson;
          String? toolCallsJson;
          if (message.apiContent != null) {
            try {
              apiContentJson = jsonEncode(message.apiContent);
            } catch (_) {}
          }
          if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
            try {
              toolCallsJson = jsonEncode(message.toolCalls);
            } catch (_) {}
          }
          final int createdAtMs = message.createdAt.millisecondsSinceEpoch;
          await txn.insert('ai_messages_raw', <String, Object?>{
            'conversation_id': resolvedCid,
            'role': role,
            'content': content,
            'api_content_json': apiContentJson,
            'tool_calls_json': toolCallsJson,
            'tool_call_id': (message.toolCallId ?? '').trim().isEmpty
                ? null
                : message.toolCallId!.trim(),
            'created_at': createdAtMs > 0
                ? createdAtMs
                : DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    } catch (_) {}
  }

  Future<List<AIMessage>> loadRawTranscriptForPrompt({
    String? cid,
    int maxTokens = 0,
    int maxRows = 8000,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    final int hardLimit = maxRows.clamp(40, 20000);
    try {
      final storage = await _db.database;

      int tokens = 0;
      int totalRows = 0;
      int? beforeId;
      final List<AIMessage> desc = <AIMessage>[];

      while (totalRows < hardLimit && (maxTokens <= 0 || tokens < maxTokens)) {
        final int chunk = (hardLimit - totalRows)
            .clamp(1, ChatContextService.rawTranscriptPageSize)
            .toInt();
        final String where = beforeId == null
            ? 'conversation_id = ?'
            : 'conversation_id = ? AND id < ?';
        final List<Object?> args = beforeId == null
            ? <Object?>[resolvedCid]
            : <Object?>[resolvedCid, beforeId];
        final List<Map<String, Object?>> rowsDesc = await storage.query(
          'ai_messages_raw',
          columns: const <String>[
            'id',
            'role',
            'content',
            'api_content_json',
            'tool_calls_json',
            'tool_call_id',
            'created_at',
          ],
          where: where,
          whereArgs: args,
          orderBy: 'id DESC',
          limit: chunk,
        );
        if (rowsDesc.isEmpty) break;

        totalRows += rowsDesc.length;
        beforeId = _toInt(rowsDesc.last['id']);

        for (final Map<String, Object?> row in rowsDesc) {
          final String role = (row['role'] as String?)?.trim() ?? '';
          if (role.isEmpty) continue;
          final String content = (row['content'] as String?) ?? '';

          Object? apiContent;
          final String apiRaw = (row['api_content_json'] as String?) ?? '';
          if (apiRaw.trim().isNotEmpty) {
            try {
              apiContent = jsonDecode(apiRaw);
            } catch (_) {
              apiContent = null;
            }
          }

          List<Map<String, dynamic>>? toolCalls;
          final String toolCallsRaw = (row['tool_calls_json'] as String?) ?? '';
          if (toolCallsRaw.trim().isNotEmpty) {
            try {
              final dynamic decoded = jsonDecode(toolCallsRaw);
              if (decoded is List) {
                toolCalls = decoded
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList(growable: false);
              }
            } catch (_) {
              toolCalls = null;
            }
          }

          final String? toolCallId =
              (row['tool_call_id'] as String?)?.trim().isNotEmpty == true
              ? (row['tool_call_id'] as String?)!.trim()
              : null;
          final int createdAt = _toInt(row['created_at']);
          final AIMessage msg = AIMessage(
            role: role,
            content: content,
            apiContent: apiContent,
            toolCalls: toolCalls,
            toolCallId: toolCallId,
            createdAt: createdAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                : null,
          );
          desc.add(msg);
          if (maxTokens > 0) {
            tokens += PromptBudget.approxTokensForMessageJson(msg);
          }
        }

        if (rowsDesc.length < chunk) break;
      }

      if (desc.isEmpty) return const <AIMessage>[];
      final List<AIMessage> msgs = desc.reversed.toList(growable: false);
      if (maxTokens <= 0) return msgs;
      return PromptBudget.keepTailUnderTokenBudget(msgs, maxTokens: maxTokens);
    } catch (_) {
      return const <AIMessage>[];
    }
  }

  /// Page the append-only transcript table (`ai_messages_full`) by row ID.
  ///
  /// - Returns messages in chronological order (oldest -> newest) within the page.
  /// - Uses keyset pagination (`beforeId`) to fetch older rows without offset scans.
  Future<FullMessagesPage> loadFullMessagesPage({
    String? cid,
    int? beforeId,
    int limit = ChatContextService.fullMessagesPageSize,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    final int lim = limit.clamp(1, 1000);
    final int? before = (beforeId ?? 0) > 0 ? beforeId : null;
    try {
      final storage = await _db.database;
      final String where = before == null
          ? 'conversation_id = ?'
          : 'conversation_id = ? AND id < ?';
      final List<Object?> args = before == null
          ? <Object?>[resolvedCid]
          : <Object?>[resolvedCid, before];
      final List<Map<String, Object?>> rowsDesc = await storage.query(
        'ai_messages_full',
        columns: const <String>['id', 'role', 'content', 'created_at'],
        where: where,
        whereArgs: args,
        orderBy: 'id DESC',
        limit: lim + 1,
      );
      if (rowsDesc.isEmpty) {
        return const FullMessagesPage(
          messages: <AIMessage>[],
          nextBeforeId: null,
          hasMore: false,
        );
      }

      final bool hasMore = rowsDesc.length > lim;
      final List<Map<String, Object?>> kept = hasMore
          ? rowsDesc.sublist(0, lim)
          : rowsDesc;
      final int? nextBeforeId = hasMore ? _toInt(kept.last['id']) : null;

      final List<AIMessage> msgs = kept.reversed
          .map((Map<String, Object?> row) {
            final String role = (row['role'] as String?)?.trim() ?? '';
            if (role != 'user' && role != 'assistant') return null;
            final String content = (row['content'] as String?) ?? '';
            if (content.trim().isEmpty) return null;
            final int createdAt = _toInt(row['created_at']);
            return AIMessage(
              role: role,
              content: content,
              createdAt: createdAt > 0
                  ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                  : null,
            );
          })
          .whereType<AIMessage>()
          .toList(growable: false);

      return FullMessagesPage(
        messages: msgs,
        nextBeforeId: nextBeforeId,
        hasMore: hasMore,
      );
    } catch (_) {
      return const FullMessagesPage(
        messages: <AIMessage>[],
        nextBeforeId: null,
        hasMore: false,
      );
    }
  }

  Future<void> recordPromptUsageEvent({
    required String cid,
    String? model,
    int? promptEstBefore,
    int? promptEstSent,
    int? usagePromptTokens,
    int? usageCompletionTokens,
    int? usageTotalTokens,
    required bool isToolLoop,
    required bool includeHistory,
    required int toolsCount,
    required bool strictFullAttempted,
    required bool fallbackTriggered,
    String? breakdownJson,
    int? createdAtMs,
  }) async {
    final String resolvedCid = cid.trim();
    if (resolvedCid.isEmpty) return;
    try {
      final storage = await _db.database;
      final bool hasUsage =
          usagePromptTokens != null ||
          usageCompletionTokens != null ||
          usageTotalTokens != null;
      await storage.insert('ai_prompt_usage_events', <String, Object?>{
        'conversation_id': resolvedCid,
        'model': (model ?? '').trim().isEmpty ? null : model!.trim(),
        'prompt_est_before': promptEstBefore,
        'prompt_est_sent': promptEstSent,
        'usage_prompt_tokens': usagePromptTokens,
        'usage_completion_tokens': usageCompletionTokens,
        'usage_total_tokens': usageTotalTokens,
        'usage_source': hasUsage ? 'usage' : 'estimate',
        'is_tool_loop': isToolLoop ? 1 : 0,
        'include_history': includeHistory ? 1 : 0,
        'tools_count': toolsCount < 0 ? 0 : toolsCount,
        'strict_full_attempted': strictFullAttempted ? 1 : 0,
        'fallback_triggered': fallbackTriggered ? 1 : 0,
        'breakdown_json': (breakdownJson ?? '').trim().isEmpty
            ? null
            : breakdownJson!.trim(),
        'created_at': createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  Future<List<PromptUsageEvent>> listPromptUsageEvents({
    String? cid,
    int limit = 100,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    final int lim = limit.clamp(1, 500);
    try {
      final storage = await _db.database;
      final List<Map<String, Object?>> rows = await storage.query(
        'ai_prompt_usage_events',
        columns: <String>[
          'id',
          'conversation_id',
          'model',
          'prompt_est_before',
          'prompt_est_sent',
          'usage_prompt_tokens',
          'usage_completion_tokens',
          'usage_total_tokens',
          'usage_source',
          'is_tool_loop',
          'include_history',
          'tools_count',
          'strict_full_attempted',
          'fallback_triggered',
          'breakdown_json',
          'created_at',
        ],
        where: 'conversation_id = ?',
        whereArgs: <Object?>[resolvedCid],
        orderBy: 'id DESC',
        limit: lim,
      );
      return rows
          .map((Map<String, Object?> row) {
            final String raw = (row['breakdown_json'] as String?)?.trim() ?? '';
            Map<String, dynamic> breakdown = <String, dynamic>{};
            if (raw.isNotEmpty) {
              try {
                final dynamic decoded = jsonDecode(raw);
                if (decoded is Map) {
                  breakdown = Map<String, dynamic>.from(decoded);
                }
              } catch (_) {}
            }
            return PromptUsageEvent(
              id: _toInt(row['id']),
              conversationId:
                  (row['conversation_id'] as String?) ?? resolvedCid,
              model: (row['model'] as String?)?.trim() ?? '',
              promptEstBefore: row['prompt_est_before'] == null
                  ? null
                  : _toInt(row['prompt_est_before']),
              promptEstSent: row['prompt_est_sent'] == null
                  ? null
                  : _toInt(row['prompt_est_sent']),
              usagePromptTokens: row['usage_prompt_tokens'] == null
                  ? null
                  : _toInt(row['usage_prompt_tokens']),
              usageCompletionTokens: row['usage_completion_tokens'] == null
                  ? null
                  : _toInt(row['usage_completion_tokens']),
              usageTotalTokens: row['usage_total_tokens'] == null
                  ? null
                  : _toInt(row['usage_total_tokens']),
              usageSource: (row['usage_source'] as String?)?.trim() ?? '',
              isToolLoop: _toInt(row['is_tool_loop']) != 0,
              includeHistory: _toInt(row['include_history']) != 0,
              toolsCount: _toInt(row['tools_count']),
              strictFullAttempted: _toInt(row['strict_full_attempted']) != 0,
              fallbackTriggered: _toInt(row['fallback_triggered']) != 0,
              breakdown: breakdown,
              createdAtMs: _toInt(row['created_at']),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <PromptUsageEvent>[];
    }
  }

  Future<PromptUsageTotals> getConversationPromptUsageTotals({
    String? cid,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    try {
      final storage = await _db.database;
      final List<Map<String, Object?>> rows = await storage.query(
        'ai_prompt_usage_events',
        columns: <String>[
          'prompt_est_before',
          'prompt_est_sent',
          'usage_prompt_tokens',
          'usage_completion_tokens',
          'usage_total_tokens',
          'breakdown_json',
        ],
        where: 'conversation_id = ?',
        whereArgs: <Object?>[resolvedCid],
      );
      if (rows.isEmpty) {
        return const PromptUsageTotals(
          eventsCount: 0,
          usageBackedCount: 0,
          promptTokens: 0,
          completionTokens: 0,
          totalTokens: 0,
        );
      }
      int usageBacked = 0;
      int prompt = 0;
      int completion = 0;
      int total = 0;
      for (final Map<String, Object?> row in rows) {
        final int? usagePrompt = row['usage_prompt_tokens'] == null
            ? null
            : _toInt(row['usage_prompt_tokens']);
        final int? usageCompletion = row['usage_completion_tokens'] == null
            ? null
            : _toInt(row['usage_completion_tokens']);
        final int? usageTotal = row['usage_total_tokens'] == null
            ? null
            : _toInt(row['usage_total_tokens']);
        if (usagePrompt != null ||
            usageCompletion != null ||
            usageTotal != null) {
          usageBacked += 1;
        }

        final int promptResolved =
            usagePrompt ??
            (row['prompt_est_sent'] == null
                ? (row['prompt_est_before'] == null
                      ? 0
                      : _toInt(row['prompt_est_before']))
                : _toInt(row['prompt_est_sent']));

        int completionResolved = usageCompletion ?? 0;
        int totalResolved = usageTotal ?? 0;

        if (usageCompletion == null || usageTotal == null) {
          final String breakdownRaw =
              (row['breakdown_json'] as String?)?.trim() ?? '';
          if (breakdownRaw.isNotEmpty) {
            try {
              final dynamic decoded = jsonDecode(breakdownRaw);
              if (decoded is Map) {
                final dynamic c = decoded['completion_estimate'];
                if (completionResolved <= 0 && c is num) {
                  completionResolved = c.toInt();
                }
                final dynamic t = decoded['total_estimate'];
                if (totalResolved <= 0 && t is num) {
                  totalResolved = t.toInt();
                }
              }
            } catch (_) {}
          }
        }
        if (totalResolved <= 0) {
          totalResolved = promptResolved + completionResolved;
        }

        prompt += promptResolved;
        completion += completionResolved;
        total += totalResolved;
      }
      return PromptUsageTotals(
        eventsCount: rows.length,
        usageBackedCount: usageBacked,
        promptTokens: prompt,
        completionTokens: completion,
        totalTokens: total,
      );
    } catch (_) {
      return const PromptUsageTotals(
        eventsCount: 0,
        usageBackedCount: 0,
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
      );
    }
  }

  Future<void> logPromptTrimEvent({
    required String cid,
    required String stage,
    required String kind,
    required int beforeTokens,
    required int afterTokens,
    int droppedMessages = 0,
    int droppedChunks = 0,
    bool truncatedOldest = false,
    String reason = '',
    String model = '',
  }) async {
    final int before = beforeTokens.clamp(0, 1 << 62).toInt();
    final int after = afterTokens.clamp(0, 1 << 62).toInt();
    final int dropped = (before - after).clamp(0, 1 << 62).toInt();
    final int now = DateTime.now().millisecondsSinceEpoch;
    await logContextEvent(
      cid: cid,
      type: 'prompt_trim',
      payload: <String, dynamic>{
        'stage': stage.trim().isEmpty ? 'chat' : stage.trim(),
        'kind': kind.trim().isEmpty ? 'trim' : kind.trim(),
        'before_tokens': before,
        'after_tokens': after,
        'dropped_tokens': dropped,
        'dropped_messages': droppedMessages.clamp(0, 1 << 30),
        'dropped_chunks': droppedChunks.clamp(0, 1 << 30),
        'truncated_oldest': truncatedOldest,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (model.trim().isNotEmpty) 'model': model.trim(),
        'created_at_ms': now,
      },
    );
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

  Future<List<ChatContextEvent>> listRecentContextEvents({
    String? cid,
    int limit = 50,
    String? type,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    final int lim = (limit <= 0 ? 50 : limit).clamp(1, 200);
    try {
      final storage = await _db.database;
      final String where = type == null || type.trim().isEmpty
          ? 'conversation_id = ?'
          : 'conversation_id = ? AND type = ?';
      final List<Object?> args = type == null || type.trim().isEmpty
          ? <Object?>[resolvedCid]
          : <Object?>[resolvedCid, type.trim()];
      final List<Map<String, Object?>> rows = await storage.query(
        'ai_context_events',
        columns: <String>[
          'id',
          'conversation_id',
          'type',
          'payload_json',
          'created_at',
        ],
        where: where,
        whereArgs: args,
        orderBy: 'id DESC',
        limit: lim,
      );
      return rows
          .map((row) {
            final String payloadRaw =
                (row['payload_json'] as String?)?.trim() ?? '';
            Map<String, dynamic> payload = <String, dynamic>{};
            if (payloadRaw.isNotEmpty) {
              try {
                final dynamic decoded = jsonDecode(payloadRaw);
                if (decoded is Map) {
                  payload = Map<String, dynamic>.from(decoded);
                }
              } catch (_) {}
            }
            return ChatContextEvent(
              id: _toInt(row['id']),
              conversationId: (row['conversation_id'] as String?) ?? '',
              type: (row['type'] as String?)?.trim() ?? 'event',
              createdAtMs: _toInt(row['created_at']),
              payload: payload,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <ChatContextEvent>[];
    }
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
    int maxRows = 4000,
  }) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();
    if (maxTokens <= 0) return const <AIMessage>[];
    final int hardLimit = maxRows.clamp(20, 20000);
    try {
      final storage = await _db.database;

      int tokens = 0;
      int totalRows = 0;
      int? beforeId;
      final List<AIMessage> desc = <AIMessage>[];

      while (totalRows < hardLimit && tokens < maxTokens) {
        final int chunk = (hardLimit - totalRows)
            .clamp(1, ChatContextService.fullMessagesPageSize)
            .toInt();
        final String where = beforeId == null
            ? 'conversation_id = ?'
            : 'conversation_id = ? AND id < ?';
        final List<Object?> args = beforeId == null
            ? <Object?>[resolvedCid]
            : <Object?>[resolvedCid, beforeId];
        final List<Map<String, Object?>> rowsDesc = await storage.query(
          'ai_messages_full',
          columns: const <String>['id', 'role', 'content', 'created_at'],
          where: where,
          whereArgs: args,
          orderBy: 'id DESC',
          limit: chunk,
        );
        if (rowsDesc.isEmpty) break;

        totalRows += rowsDesc.length;
        beforeId = _toInt(rowsDesc.last['id']);

        for (final Map<String, Object?> row in rowsDesc) {
          final String role = (row['role'] as String?)?.trim() ?? '';
          if (role != 'user' && role != 'assistant') continue;
          final String content = (row['content'] as String?) ?? '';
          if (content.trim().isEmpty) continue;
          final int createdAt = _toInt(row['created_at']);
          final AIMessage msg = AIMessage(
            role: role,
            content: content,
            createdAt: createdAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                : null,
          );
          desc.add(msg);
          tokens += PromptBudget.approxTokensForMessageJson(msg);
          if (tokens >= maxTokens) break;
        }

        if (rowsDesc.length < chunk) break;
      }

      if (desc.isEmpty) return const <AIMessage>[];
      final List<AIMessage> msgs = desc.reversed.toList(growable: false);
      return PromptBudget.keepTailUnderTokenBudget(msgs, maxTokens: maxTokens);
    } catch (_) {
      return const <AIMessage>[];
    }
  }

  /// Load restorable conversation messages for export/debug.
  ///
  /// - Prefer append-only transcript (`ai_messages_full`) in chronological order.
  /// - Fall back to UI tail history for older installs where the full transcript
  ///   may still be empty.
  Future<List<AIMessage>> loadMessagesForExport({String? cid}) async {
    final String resolvedCid = (cid == null || cid.trim().isEmpty)
        ? await _settings.getActiveConversationCid()
        : cid.trim();

    try {
      final List<_FullMsg> full = await _loadFullMessages(resolvedCid);
      if (full.isNotEmpty) {
        return full
            .where((m) {
              final String role = m.role.trim();
              return (role == 'user' || role == 'assistant') &&
                  m.content.trim().isNotEmpty;
            })
            .map(
              (m) => AIMessage(
                role: m.role,
                content: m.content,
                createdAt: m.createdAtMs > 0
                    ? DateTime.fromMillisecondsSinceEpoch(m.createdAtMs)
                    : null,
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {}

    try {
      final List<AIMessage> tail = await _settings.getChatHistoryByCid(
        resolvedCid,
      );
      return tail
          .where((m) {
            final String role = m.role.trim();
            return (role == 'user' || role == 'assistant') &&
                m.content.trim().isNotEmpty;
          })
          .toList(growable: false);
    } catch (_) {
      return const <AIMessage>[];
    }
  }

  Future<void> appendCompletedTurn({
    required String cid,
    required String userMessage,
    required String assistantMessage,
    int? userCreatedAtMs,
    int? assistantCreatedAtMs,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int userAt = (userCreatedAtMs ?? 0) > 0 ? userCreatedAtMs! : now;
    final int assistantAt = (assistantCreatedAtMs ?? 0) > 0
        ? assistantCreatedAtMs!
        : now;
    await _appendFullMessageDedup(
      cid,
      role: 'user',
      content: userMessage,
      createdAtMs: userAt,
    );
    await _appendFullMessageDedup(
      cid,
      role: 'assistant',
      content: assistantMessage,
      createdAtMs: assistantAt,
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
        try {
          await txn.delete(
            'ai_messages_raw',
            where: 'conversation_id = ?',
            whereArgs: <Object?>[resolvedCid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'ai_prompt_usage_events',
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
    final String note = zh
        ? '说明：以下是历史工具记录摘要，不是当前这轮对话的硬约束。'
        : 'Note: the following are digests of historical tool calls, not hard constraints for the current turn.';
    final List<String> lines = <String>[label + ':', note];
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
      'limit',
      'offset',
      'count',
    ];
    for (final k in keep) {
      if (!digest.containsKey(k)) continue;
      out[k] = digest[k];
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
