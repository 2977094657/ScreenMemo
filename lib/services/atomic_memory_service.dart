import 'dart:async';
import 'dart:convert';

import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'chat_context_service.dart';
import 'flutter_logger.dart';
import 'prompt_budget.dart';
import 'screenshot_database.dart';
import 'user_memory_service.dart';

class AtomicMemoryService {
  AtomicMemoryService._internal();
  static final AtomicMemoryService instance = AtomicMemoryService._internal();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final AISettingsService _settings = AISettingsService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;

  final Map<String, Future<void>> _serialized = <String, Future<void>>{};

  // FNV-1a 64-bit for stable, lightweight de-dup keys (stored as hex string).
  static const int _fnv64Offset = 0xcbf29ce484222325;
  static const int _fnv64Prime = 0x100000001b3;
  static const int _mask64 = 0xFFFFFFFFFFFFFFFF;

  static String _normalizeForHash(String text) {
    final String t = text.trim();
    if (t.isEmpty) return '';
    return t.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _fnv1a64Hex(String input) {
    final String t = _normalizeForHash(input);
    if (t.isEmpty) return '';
    final List<int> bytes = utf8.encode(t);
    int hash = _fnv64Offset;
    for (final int b in bytes) {
      hash ^= b;
      hash = (hash * _fnv64Prime) & _mask64;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _sanitizeModelText(String text) {
    String t = text.trim();
    if (!t.startsWith('```')) return t;
    t = t.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*```$'), '');
    return t.trim();
  }

  static String _sanitizeFtsQuery(String query) {
    // Keep only common word chars (latin/digits/CJK) + whitespace to avoid
    // FTS query syntax errors on user punctuation.
    final String t = query
        .replaceAll(RegExp(r'[^0-9A-Za-z\u4e00-\u9fff\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  static bool _shouldExtractFromUserMessage(String userMessage) {
    final String t = userMessage.trim();
    if (t.isEmpty) return false;

    // Heuristic triggers to avoid a paid LLM call on trivial turns ("ok", "继续").
    final String lower = t.toLowerCase();
    const List<String> needles = <String>[
      '记住',
      '我叫',
      '我的名字',
      '叫我',
      '我喜欢',
      '我不喜欢',
      '偏好',
      '请用',
      '用中文',
      '用英文',
      'my name',
      'call me',
      'i am ',
      'i\'m ',
      'i like',
      'i prefer',
      'remember',
      'preference',
    ];
    for (final String n in needles) {
      if (lower.contains(n)) return true;
    }
    if (t.length < 12) return false;
    // Also allow extraction for longer, content-dense messages.
    return t.length >= 80;
  }

  Future<int> countAtomicMemories({required String cid}) async {
    try {
      final storage = await _db.database;
      final List<Map<String, Object?>> rows = await storage.rawQuery(
        'SELECT COUNT(1) as c FROM ai_atomic_memories WHERE conversation_id = ?',
        <Object?>[cid],
      );
      if (rows.isEmpty) return 0;
      final Object? v = rows.first['c'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Build a system message that injects "atomic memory" (facts/rules).
  /// Returns empty string if disabled or nothing to inject.
  Future<String> buildAtomicMemoryContextMessage({
    required String cid,
    required String query,
  }) async {
    try {
      final bool enabled = await _settings.getAtomicMemoryInjectionEnabled();
      if (!enabled) return '';
      final int maxTokens = await _settings.getAtomicMemoryPromptTokens();
      final int maxItems = await _settings.getAtomicMemoryMaxItems();

      final List<_AtomicMemoryRow> rules = await _loadRecent(
        kind: 'rule',
        cid: cid,
        limit: 50,
      );
      final List<_AtomicMemoryRow> facts = await _searchOrRecentFacts(
        cid: cid,
        query: query,
        limit: 80,
      );

      // De-dup by row id.
      final Set<int> pickedIds = <int>{};
      final List<_AtomicMemoryRow> pickedRules = <_AtomicMemoryRow>[];
      for (final _AtomicMemoryRow r in rules) {
        if (pickedIds.add(r.id)) pickedRules.add(r);
        if (pickedRules.length >= maxItems) break;
      }
      final List<_AtomicMemoryRow> pickedFacts = <_AtomicMemoryRow>[];
      for (final _AtomicMemoryRow f in facts) {
        if (pickedIds.add(f.id)) pickedFacts.add(f);
        if (pickedRules.length + pickedFacts.length >= maxItems) break;
      }

      if (pickedRules.isEmpty && pickedFacts.isEmpty) return '';

      final int budgetBytes = maxTokens * PromptBudget.approxBytesPerToken;
      final int closeBytes = PromptBudget.utf8Bytes('\n</atomic_memory>');

      final StringBuffer sb = StringBuffer();
      int usedBytes = 0;
      void appendLine(String line) {
        sb.writeln(line);
        usedBytes += PromptBudget.utf8Bytes('$line\n');
      }

      appendLine('<atomic_memory>');
      if (pickedRules.isNotEmpty) {
        appendLine('Rules:');
        for (final _AtomicMemoryRow r in pickedRules) {
          final String line = '- ${r.content}';
          final int addBytes = PromptBudget.utf8Bytes('$line\n');
          if (usedBytes + addBytes + closeBytes > budgetBytes) break;
          appendLine(line);
        }
      }
      if (pickedFacts.isNotEmpty) {
        appendLine('Facts:');
        for (final _AtomicMemoryRow f in pickedFacts) {
          final String line = '- ${f.content}';
          final int addBytes = PromptBudget.utf8Bytes('$line\n');
          if (usedBytes + addBytes + closeBytes > budgetBytes) break;
          appendLine(line);
        }
      }
      sb.write('</atomic_memory>');

      final String out = sb.toString().trim();
      // If we couldn't fit any entries, avoid injecting an empty wrapper.
      if (!out.contains('- ')) return '';
      return out;
    } catch (_) {
      return '';
    }
  }

  /// Best-effort write pipeline: extract atomic facts/rules from the latest user message.
  void scheduleExtractFromTurn({
    required String cid,
    required String userMessage,
  }) {
    _serialized[cid] = (_serialized[cid] ?? Future<void>.value())
        .then((_) async {
          final bool enabled = await _settings
              .getAtomicMemoryAutoExtractEnabled();
          if (!enabled) return;
          if (!_shouldExtractFromUserMessage(userMessage)) return;
          await _extractAndUpsert(cid: cid, userMessage: userMessage);
        })
        .catchError((_) {});
  }

  Future<void> _extractAndUpsert({
    required String cid,
    required String userMessage,
  }) async {
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final List<_AtomicMemoryRow> existing = await _loadRecentAny(
        cid: cid,
        limit: 20,
      );

      final String system = _extractionSystemPrompt();
      final String user = _extractionUserPrompt(
        userMessage: userMessage,
        existing: existing,
      );

      final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
        context: 'chat',
      );
      if (endpoints.isEmpty) return;

      final AIGatewayResult result = await _gateway.complete(
        endpoints: endpoints,
        messages: <AIMessage>[
          AIMessage(role: 'system', content: system),
          AIMessage(role: 'user', content: user),
        ],
        responseStartMarker: '',
        timeout: const Duration(seconds: 30),
        preferStreaming: false,
        logContext: 'atomic_memory_extract',
      );

      final List<_AtomicExtractedItem> items = _parseExtraction(result.content);
      if (items.isEmpty) return;

      final _UpsertStats stats = await _upsertItems(cid: cid, items: items);
      final int tookMs = DateTime.now().millisecondsSinceEpoch - startedAt;
      try {
        unawaited(
          ChatContextService.instance.logContextEvent(
            cid: cid,
            type: 'atomic_memory_extract',
            payload: <String, dynamic>{
              'items': items.length,
              'inserted': stats.inserted,
              'updated': stats.updated,
              'touched': stats.touched,
              'duration_ms': tookMs,
            },
          ),
        );
      } catch (_) {}
    } catch (e) {
      try {
        await FlutterLogger.nativeWarn(
          'AI',
          'atomic_memory_extract failed: $e',
        );
      } catch (_) {}
    }
  }

  String _extractionSystemPrompt() {
    final String today = DateTime.now().toLocal().toIso8601String().substring(
      0,
      10,
    );
    return [
      'You are an information extraction assistant.',
      'Extract durable, user-specific "atomic memories" (facts or rules) from the user message.',
      'Write memories in the same language as the user message.',
      '',
      'Hard rules:',
      '- Output VALID JSON only (no markdown, no code fences).',
      '- Use ONLY the user message + provided existing memory context. Do NOT invent.',
      '- Avoid generic world knowledge. Only store durable user-specific info (identity, preferences, constraints).',
      '- Force disambiguation: no pronouns; avoid relative time words (today/yesterday/tomorrow).',
      '- Today is $today (local date).',
      '',
      'Output schema:',
      '{ "items": [',
      '  { "kind": "fact|rule", "key": "optional", "content": "string", "keywords": ["..."], "confidence": 0.0 }',
      '] }',
      '',
      'If nothing to store: { "items": [] }',
    ].join('\n');
  }

  String _extractionUserPrompt({
    required String userMessage,
    required List<_AtomicMemoryRow> existing,
  }) {
    final StringBuffer sb = StringBuffer();
    sb.writeln(
      'Existing atomic memories (avoid duplication, update by key when appropriate):',
    );
    sb.writeln('<<<');
    if (existing.isEmpty) {
      sb.writeln('(empty)');
    } else {
      for (final _AtomicMemoryRow r in existing) {
        final String k = (r.memoryKey ?? '').trim();
        if (k.isNotEmpty) {
          sb.writeln('- [$k] (${r.kind}) ${r.content}');
        } else {
          sb.writeln('- (${r.kind}) ${r.content}');
        }
      }
    }
    sb.writeln('>>>');
    sb.writeln('');
    sb.writeln('User message:');
    sb.writeln('<<<');
    sb.writeln(userMessage.trim());
    sb.writeln('>>>');
    sb.writeln('');
    sb.writeln('Return JSON only.');
    return sb.toString().trim();
  }

  List<_AtomicExtractedItem> _parseExtraction(String raw) {
    final String t = _sanitizeModelText(raw);
    if (t.isEmpty) return <_AtomicExtractedItem>[];
    dynamic data;
    try {
      data = jsonDecode(t);
    } catch (_) {
      // Best-effort: try to extract the first {...} block.
      final int s = t.indexOf('{');
      final int e = t.lastIndexOf('}');
      if (s >= 0 && e > s) {
        try {
          data = jsonDecode(t.substring(s, e + 1));
        } catch (_) {
          return <_AtomicExtractedItem>[];
        }
      } else {
        return <_AtomicExtractedItem>[];
      }
    }

    final List<dynamic> itemsRaw;
    if (data is Map) {
      final dynamic v = data['items'] ?? data['facts'];
      if (v is List) {
        itemsRaw = v;
      } else {
        return <_AtomicExtractedItem>[];
      }
    } else if (data is List) {
      itemsRaw = data;
    } else {
      return <_AtomicExtractedItem>[];
    }

    final List<_AtomicExtractedItem> out = <_AtomicExtractedItem>[];
    for (final dynamic it in itemsRaw) {
      if (it is String) {
        final String content = it.trim();
        if (content.isEmpty) continue;
        out.add(
          _AtomicExtractedItem(
            kind: 'fact',
            key: null,
            content: content,
            keywords: const <String>[],
            confidence: null,
          ),
        );
        continue;
      }
      if (it is! Map) continue;
      final String kindRaw =
          (it['kind'] as String?)?.trim().toLowerCase() ?? '';
      final String kind = kindRaw == 'rule' ? 'rule' : 'fact';
      final String? key = (it['key'] as String?)?.trim();
      final String content = (it['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) continue;
      if (content.length > 800) continue;

      List<String> keywords = const <String>[];
      final dynamic kw = it['keywords'];
      if (kw is List) {
        keywords = kw
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .take(24)
            .toList(growable: false);
      }
      double? confidence;
      final dynamic c = it['confidence'];
      if (c is num) {
        confidence = c.toDouble().clamp(0.0, 1.0);
      } else if (c is String) {
        final double? parsed = double.tryParse(c.trim());
        if (parsed != null) confidence = parsed.clamp(0.0, 1.0);
      }

      out.add(
        _AtomicExtractedItem(
          kind: kind,
          key: (key == null || key.isEmpty) ? null : key,
          content: content,
          keywords: keywords,
          confidence: confidence,
        ),
      );
    }
    return out;
  }

  Future<_UpsertStats> _upsertItems({
    required String cid,
    required List<_AtomicExtractedItem> items,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final storage = await _db.database;

    int inserted = 0;
    int updated = 0;
    int touched = 0;

    await storage.transaction((txn) async {
      for (final _AtomicExtractedItem it in items) {
        final String content = it.content.trim();
        if (content.isEmpty) continue;
        final String hash = _fnv1a64Hex(content);
        if (hash.isEmpty) continue;

        final String? key = (it.key ?? '').trim().isEmpty
            ? null
            : it.key!.trim();
        final String? keywordsJson = it.keywords.isEmpty
            ? null
            : jsonEncode(it.keywords);
        final double? confidence = it.confidence;

        // Prefer key-based upsert when present.
        if (key != null) {
          try {
            final int n = await txn.rawUpdate(
              'UPDATE ai_atomic_memories SET kind = ?, content = ?, content_hash = ?, keywords_json = ?, confidence = ?, updated_at = ? WHERE conversation_id = ? AND memory_key = ?',
              <Object?>[
                it.kind,
                content,
                hash,
                keywordsJson,
                confidence,
                now,
                cid,
                key,
              ],
            );
            if (n > 0) {
              updated += n;
              continue;
            }
          } catch (_) {}
        }

        // Fallback: de-dup by hash.
        try {
          final int rowid = await txn.rawInsert(
            'INSERT OR IGNORE INTO ai_atomic_memories(conversation_id, kind, memory_key, content, content_hash, keywords_json, confidence, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)',
            <Object?>[
              cid,
              it.kind,
              key,
              content,
              hash,
              keywordsJson,
              confidence,
              now,
              now,
            ],
          );
          if (rowid > 0) {
            inserted += 1;
            continue;
          }
        } catch (_) {}

        // If it already exists, touch updated_at for recency.
        try {
          final int n = await txn.rawUpdate(
            'UPDATE ai_atomic_memories SET updated_at = ? WHERE conversation_id = ? AND content_hash = ?',
            <Object?>[now, cid, hash],
          );
          if (n > 0) touched += n;
        } catch (_) {}
      }
    });

    // Best-effort: also sync durable atomic memories into the global user memory
    // store so new conversations can benefit immediately.
    try {
      if (items.isNotEmpty) {
        final List<ExtractedUserMemoryItem> global = items
            .map(
              (e) => ExtractedUserMemoryItem(
                kind: (e.kind == 'rule') ? 'rule' : 'fact',
                key: e.key,
                content: e.content,
                keywords: e.keywords,
                confidence: e.confidence,
                evidenceFilenames: const <String>[],
              ),
            )
            .toList(growable: false);
        await UserMemoryService.instance.upsertExtractedItems(
          items: global,
          evidence: UserMemoryUpsertEvidenceParams(
            sourceType: 'chat',
            sourceId: 'chat:cid=$cid#ts=$now',
          ),
        );
      }
    } catch (_) {}

    return _UpsertStats(inserted: inserted, updated: updated, touched: touched);
  }

  Future<List<_AtomicMemoryRow>> _loadRecent({
    required String kind,
    required String cid,
    required int limit,
  }) async {
    try {
      final storage = await _db.database;
      final List<Map<String, Object?>> rows = await storage.query(
        'ai_atomic_memories',
        columns: <String>[
          'id',
          'conversation_id',
          'kind',
          'memory_key',
          'content',
          'updated_at',
          'confidence',
        ],
        where: 'conversation_id = ? AND kind = ?',
        whereArgs: <Object?>[cid, kind],
        orderBy: 'updated_at DESC, id DESC',
        limit: limit,
      );
      return rows.map(_AtomicMemoryRow.fromRow).toList(growable: false);
    } catch (_) {
      return const <_AtomicMemoryRow>[];
    }
  }

  Future<List<_AtomicMemoryRow>> _loadRecentAny({
    required String cid,
    required int limit,
  }) async {
    try {
      final storage = await _db.database;
      final List<Map<String, Object?>> rows = await storage.query(
        'ai_atomic_memories',
        columns: <String>[
          'id',
          'conversation_id',
          'kind',
          'memory_key',
          'content',
          'updated_at',
          'confidence',
        ],
        where: 'conversation_id = ?',
        whereArgs: <Object?>[cid],
        orderBy: 'updated_at DESC, id DESC',
        limit: limit,
      );
      return rows.map(_AtomicMemoryRow.fromRow).toList(growable: false);
    } catch (_) {
      return const <_AtomicMemoryRow>[];
    }
  }

  Future<List<_AtomicMemoryRow>> _searchOrRecentFacts({
    required String cid,
    required String query,
    required int limit,
  }) async {
    final String q = _sanitizeFtsQuery(query);
    if (q.isEmpty) {
      return _loadRecent(kind: 'fact', cid: cid, limit: limit);
    }

    // Try FTS5 first.
    try {
      final storage = await _db.database;
      final List<Map<String, Object?>> rows = await storage.rawQuery(
        '''
        SELECT m.id, m.conversation_id, m.kind, m.memory_key, m.content, m.updated_at, m.confidence,
               bm25(ai_atomic_memories_fts) AS score
        FROM ai_atomic_memories_fts
        JOIN ai_atomic_memories m ON m.rowid = ai_atomic_memories_fts.rowid
        WHERE m.conversation_id = ? AND m.kind != 'rule' AND ai_atomic_memories_fts MATCH ?
        ORDER BY score ASC, m.updated_at DESC, m.id DESC
        LIMIT ?
        ''',
        <Object?>[cid, q, limit],
      );
      return rows.map(_AtomicMemoryRow.fromRow).toList(growable: false);
    } catch (_) {}

    // Fallback: LIKE search on content/keywords_json.
    try {
      final storage = await _db.database;
      final String like = '%$q%';
      final List<Map<String, Object?>> rows = await storage.query(
        'ai_atomic_memories',
        columns: <String>[
          'id',
          'conversation_id',
          'kind',
          'memory_key',
          'content',
          'updated_at',
          'confidence',
        ],
        where:
            "conversation_id = ? AND kind != 'rule' AND (content LIKE ? OR keywords_json LIKE ?)",
        whereArgs: <Object?>[cid, like, like],
        orderBy: 'updated_at DESC, id DESC',
        limit: limit,
      );
      return rows.map(_AtomicMemoryRow.fromRow).toList(growable: false);
    } catch (_) {
      return const <_AtomicMemoryRow>[];
    }
  }
}

class _UpsertStats {
  const _UpsertStats({
    required this.inserted,
    required this.updated,
    required this.touched,
  });

  final int inserted;
  final int updated;
  final int touched;
}

class _AtomicExtractedItem {
  const _AtomicExtractedItem({
    required this.kind,
    required this.key,
    required this.content,
    required this.keywords,
    required this.confidence,
  });

  final String kind;
  final String? key;
  final String content;
  final List<String> keywords;
  final double? confidence;
}

class _AtomicMemoryRow {
  const _AtomicMemoryRow({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.memoryKey,
    required this.content,
    required this.updatedAtMs,
    required this.confidence,
  });

  final int id;
  final String conversationId;
  final String kind;
  final String? memoryKey;
  final String content;
  final int? updatedAtMs;
  final double? confidence;

  static int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static _AtomicMemoryRow fromRow(Map<String, Object?> row) {
    return _AtomicMemoryRow(
      id: (_toInt(row['id']) ?? 0),
      conversationId: (row['conversation_id'] as String?)?.trim() ?? '',
      kind: (row['kind'] as String?)?.trim() ?? 'fact',
      memoryKey: (row['memory_key'] as String?)?.trim(),
      content: (row['content'] as String?)?.trim() ?? '',
      updatedAtMs: _toInt(row['updated_at']),
      confidence: _toDouble(row['confidence']),
    );
  }
}
