import 'dart:async';
import 'dart:convert';

import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'prompt_budget.dart';
import 'screenshot_database.dart';

class UserMemoryProfile {
  const UserMemoryProfile({
    required this.userMarkdown,
    required this.autoMarkdown,
    required this.userUpdatedAtMs,
    required this.autoUpdatedAtMs,
  });

  final String userMarkdown;
  final String autoMarkdown;
  final int? userUpdatedAtMs;
  final int? autoUpdatedAtMs;

  bool get hasAny =>
      userMarkdown.trim().isNotEmpty || autoMarkdown.trim().isNotEmpty;

  String get effectiveMarkdown {
    final String u = userMarkdown.trim();
    if (u.isNotEmpty) return u;
    return autoMarkdown.trim();
  }
}

class UserMemoryEvidence {
  const UserMemoryEvidence({
    required this.sourceType,
    required this.sourceId,
    required this.filenames,
    required this.startTime,
    required this.endTime,
    required this.createdAtMs,
  });

  final String sourceType;
  final String sourceId;
  final List<String> filenames;
  final int? startTime;
  final int? endTime;
  final int createdAtMs;
}

class UserMemoryItem {
  const UserMemoryItem({
    required this.id,
    required this.kind,
    required this.memoryKey,
    required this.content,
    required this.pinned,
    required this.userEdited,
    required this.updatedAtMs,
    required this.confidence,
  });

  final int id;
  final String kind; // rule | fact | habit
  final String? memoryKey;
  final String content;
  final bool pinned;
  final bool userEdited;
  final int? updatedAtMs;
  final double? confidence;
}

class ExtractedUserMemoryItem {
  const ExtractedUserMemoryItem({
    required this.kind,
    required this.key,
    required this.content,
    required this.keywords,
    required this.confidence,
    required this.evidenceFilenames,
  });

  final String kind; // rule | fact | habit
  final String? key;
  final String content;
  final List<String> keywords;
  final double? confidence;
  final List<String> evidenceFilenames; // basenames
}

enum UserMemoryPathKind {
  profileUser,
  profileAuto,
  item,
  daily,
  weekly,
  morning,
  unknown,
}

class UserMemoryPath {
  const UserMemoryPath({
    required this.kind,
    required this.raw,
    this.itemId,
    this.dateKey,
  });

  final UserMemoryPathKind kind;
  final String raw;
  final int? itemId;
  final String? dateKey;

  static UserMemoryPath parse(String path) {
    final String t = path.trim();
    if (t == 'profile:user') {
      return const UserMemoryPath(
        kind: UserMemoryPathKind.profileUser,
        raw: 'profile:user',
      );
    }
    if (t == 'profile:auto') {
      return const UserMemoryPath(
        kind: UserMemoryPathKind.profileAuto,
        raw: 'profile:auto',
      );
    }
    if (t.startsWith('item:')) {
      final int id = int.tryParse(t.substring('item:'.length).trim()) ?? 0;
      return UserMemoryPath(
        kind: (id > 0) ? UserMemoryPathKind.item : UserMemoryPathKind.unknown,
        raw: t,
        itemId: id > 0 ? id : null,
      );
    }
    if (t.startsWith('daily:')) {
      final String dateKey = t.substring('daily:'.length).trim();
      return UserMemoryPath(
        kind: dateKey.isEmpty
            ? UserMemoryPathKind.unknown
            : UserMemoryPathKind.daily,
        raw: t,
        dateKey: dateKey.isEmpty ? null : dateKey,
      );
    }
    if (t.startsWith('weekly:')) {
      final String dateKey = t.substring('weekly:'.length).trim();
      return UserMemoryPath(
        kind: dateKey.isEmpty
            ? UserMemoryPathKind.unknown
            : UserMemoryPathKind.weekly,
        raw: t,
        dateKey: dateKey.isEmpty ? null : dateKey,
      );
    }
    if (t.startsWith('morning:')) {
      final String dateKey = t.substring('morning:'.length).trim();
      return UserMemoryPath(
        kind: dateKey.isEmpty
            ? UserMemoryPathKind.unknown
            : UserMemoryPathKind.morning,
        raw: t,
        dateKey: dateKey.isEmpty ? null : dateKey,
      );
    }
    return UserMemoryPath(kind: UserMemoryPathKind.unknown, raw: t);
  }
}

class UserMemoryUpsertEvidenceParams {
  const UserMemoryUpsertEvidenceParams({
    required this.sourceType,
    required this.sourceId,
    this.startTime,
    this.endTime,
  });

  final String
  sourceType; // segment | chat | daily_summary | weekly_summary | morning_insights
  final String sourceId;
  final int? startTime;
  final int? endTime;
}

class UserMemoryUpsertStats {
  const UserMemoryUpsertStats({
    required this.inserted,
    required this.updated,
    required this.touched,
  });

  final int inserted;
  final int updated;
  final int touched;
}

class UserMemoryService {
  UserMemoryService._internal();
  static final UserMemoryService instance = UserMemoryService._internal();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final AISettingsService _settings = AISettingsService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;

  // FNV-1a 64-bit for stable, lightweight de-dup keys (stored as hex string).
  static const int _fnv64Offset = 0xcbf29ce484222325;
  static const int _fnv64Prime = 0x100000001b3;
  static const int _mask64 = 0xFFFFFFFFFFFFFFFF;

  static String _normalizeForHash(String text) {
    final String t = text.trim();
    if (t.isEmpty) return '';
    return t.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String fnv1a64Hex(String input) {
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

  static bool _toBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final String s = (v ?? '').toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'y';
  }

  static String _sanitizeKind(String? value) {
    final String k = (value ?? '').trim().toLowerCase();
    if (k == 'rule' || k == 'fact' || k == 'habit') return k;
    return 'fact';
  }

  static String _sanitizeKeywordsJson(List<String> keywords) {
    final List<String> out = keywords
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(24)
        .toList(growable: false);
    if (out.isEmpty) return '[]';
    try {
      return jsonEncode(out);
    } catch (_) {
      return '[]';
    }
  }

  static List<String> _decodeStringListJson(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return const <String>[];
    try {
      final dynamic v = jsonDecode(t);
      if (v is List) {
        return v
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  /// Parse model output for the "global user memory" extraction format.
  ///
  /// Expected schema (JSON-only):
  /// { "items": [ {kind,key,content,keywords,confidence,evidence:[...]} ] }
  static List<ExtractedUserMemoryItem> parseExtractionFromModelText(
    String raw, {
    required Set<String> allowedEvidenceFilenames,
  }) {
    final String t = _sanitizeModelText(raw);
    if (t.isEmpty) return const <ExtractedUserMemoryItem>[];

    dynamic data;
    try {
      data = jsonDecode(t);
    } catch (_) {
      final int s = t.indexOf('{');
      final int e = t.lastIndexOf('}');
      if (s >= 0 && e > s) {
        try {
          data = jsonDecode(t.substring(s, e + 1));
        } catch (_) {
          return const <ExtractedUserMemoryItem>[];
        }
      } else {
        return const <ExtractedUserMemoryItem>[];
      }
    }

    final List<dynamic> itemsRaw;
    if (data is Map) {
      final dynamic v = data['items'] ?? data['memories'];
      if (v is List) {
        itemsRaw = v;
      } else {
        return const <ExtractedUserMemoryItem>[];
      }
    } else if (data is List) {
      itemsRaw = data;
    } else {
      return const <ExtractedUserMemoryItem>[];
    }

    final Set<String> allow = allowedEvidenceFilenames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final List<ExtractedUserMemoryItem> out = <ExtractedUserMemoryItem>[];
    for (final dynamic it in itemsRaw) {
      if (it is String) {
        final String content = it.trim();
        if (content.isEmpty) continue;
        if (content.length > 800) continue;
        out.add(
          ExtractedUserMemoryItem(
            kind: 'fact',
            key: null,
            content: content,
            keywords: const <String>[],
            confidence: null,
            evidenceFilenames: const <String>[],
          ),
        );
        continue;
      }
      if (it is! Map) continue;

      final String kind = _sanitizeKind((it['kind'] as String?)?.trim());
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
      } else if (kw is String) {
        final String s = kw.trim();
        if (s.isNotEmpty) keywords = <String>[s];
      }

      double? confidence;
      final dynamic c = it['confidence'];
      if (c is num) {
        confidence = c.toDouble().clamp(0.0, 1.0);
      } else if (c is String) {
        final double? parsed = double.tryParse(c.trim());
        if (parsed != null) confidence = parsed.clamp(0.0, 1.0);
      }

      final List<String> evidence = <String>[];
      final dynamic ev = it['evidence'];
      if (ev is List) {
        for (final dynamic v in ev) {
          final String name = v?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          if (!allow.contains(name)) continue;
          evidence.add(name);
          if (evidence.length >= 5) break;
        }
      } else if (ev is String) {
        final String name = ev.trim();
        if (name.isNotEmpty && allow.contains(name)) evidence.add(name);
      }

      out.add(
        ExtractedUserMemoryItem(
          kind: kind,
          key: (key == null || key.trim().isEmpty) ? null : key.trim(),
          content: content,
          keywords: keywords,
          confidence: confidence,
          evidenceFilenames: evidence.toSet().toList(growable: false),
        ),
      );
    }
    return out;
  }

  static String sliceLines(
    String text, {
    int fromLine = 1,
    int lines = 80,
    int maxLines = 400,
  }) {
    final String t = text.replaceAll('\r\n', '\n');
    if (t.trim().isEmpty) return '';
    final List<String> parts = t.split('\n');
    if (parts.isEmpty) return '';
    final int from0 = (fromLine <= 1 ? 0 : fromLine - 1).clamp(0, parts.length);
    final int take = lines.clamp(1, maxLines);
    final int end = (from0 + take).clamp(0, parts.length);
    return parts.sublist(from0, end).join('\n').trimRight();
  }

  /// Deterministically build an injection block from in-memory data (pure fn).
  ///
  /// This is used both in production (after DB reads) and in unit tests.
  static String buildUserMemoryContextFromData({
    required String profileMarkdown,
    required List<UserMemoryItem> pinned,
    required List<UserMemoryItem> relevant,
    required int maxTokens,
    required int maxRelevantItems,
  }) {
    final int maxTok = maxTokens.clamp(0, 1 << 30);
    if (maxTok <= 0) return '';
    final int maxRel = maxRelevantItems.clamp(0, 200);

    final String profileText = profileMarkdown.trim();

    final Set<int> pickedIds = <int>{};
    final List<UserMemoryItem> picked = <UserMemoryItem>[];
    for (final e in pinned) {
      if (pickedIds.add(e.id)) picked.add(e);
    }
    int relevantAdded = 0;
    for (final e in relevant) {
      if (relevantAdded >= maxRel) break;
      if (pickedIds.add(e.id)) {
        picked.add(e);
        relevantAdded += 1;
      }
    }

    if (profileText.isEmpty && picked.isEmpty) return '';

    final int budgetBytes = maxTok * PromptBudget.approxBytesPerToken;
    final int closeBytes = PromptBudget.utf8Bytes('\n</user_memory>');

    final StringBuffer sb = StringBuffer();
    int usedBytes = 0;
    void appendLine(String line) {
      sb.writeln(line);
      usedBytes += PromptBudget.utf8Bytes('$line\n');
    }

    void appendTextBlock(
      String header,
      String content, {
      int reserveTailBytes = 0,
    }) {
      final String c = content.trim();
      if (c.isEmpty) return;
      final int headerBytes = PromptBudget.utf8Bytes('$header\n');
      if (usedBytes + headerBytes + closeBytes > budgetBytes) return;
      appendLine(header);

      final int remaining0 = budgetBytes - usedBytes - closeBytes;
      final int remaining = (remaining0 - reserveTailBytes).clamp(
        0,
        remaining0,
      );
      if (remaining <= 0) return;
      final String t = PromptBudget.truncateTextByBytes(
        text: c,
        maxBytes: remaining,
        marker: '…truncated…',
      );
      sb.writeln(t);
      usedBytes += PromptBudget.utf8Bytes('$t\n');
    }

    appendLine('<user_memory>');
    if (profileText.isNotEmpty) {
      final int reserveForItems = picked.isNotEmpty
          ? (budgetBytes * 0.3).round()
          : 0;
      appendTextBlock(
        'Profile:',
        profileText,
        reserveTailBytes: reserveForItems,
      );
    }

    void appendItemsOfKind(String kind, String header) {
      final List<UserMemoryItem> items = picked
          .where((e) => e.kind == kind)
          .toList(growable: false);
      if (items.isEmpty) return;
      final int headerBytes = PromptBudget.utf8Bytes('$header\n');
      if (usedBytes + headerBytes + closeBytes > budgetBytes) return;
      appendLine(header);
      for (final e in items) {
        final String line = '- ${e.content.trim()}';
        final int addBytes = PromptBudget.utf8Bytes('$line\n');
        if (usedBytes + addBytes + closeBytes > budgetBytes) break;
        appendLine(line);
      }
    }

    appendItemsOfKind('rule', 'Rules:');
    appendItemsOfKind('habit', 'Habits:');
    appendItemsOfKind('fact', 'Facts:');
    sb.write('</user_memory>');

    final String out = sb.toString().trim();
    if (!out.contains('Profile:') && !out.contains('- ')) return '';
    return out;
  }

  Future<UserMemoryProfile> getProfile() async {
    try {
      final storage = await _db.database;
      final rows = await storage.query(
        'user_memory_profile',
        columns: const <String>[
          'user_markdown',
          'auto_markdown',
          'user_updated_at',
          'auto_updated_at',
        ],
        where: 'id = 1',
        limit: 1,
      );
      if (rows.isEmpty) {
        return const UserMemoryProfile(
          userMarkdown: '',
          autoMarkdown: '',
          userUpdatedAtMs: null,
          autoUpdatedAtMs: null,
        );
      }
      final row = rows.first;
      return UserMemoryProfile(
        userMarkdown: (row['user_markdown'] as String?)?.trim() ?? '',
        autoMarkdown: (row['auto_markdown'] as String?)?.trim() ?? '',
        userUpdatedAtMs: _toInt(row['user_updated_at']),
        autoUpdatedAtMs: _toInt(row['auto_updated_at']),
      );
    } catch (_) {
      return const UserMemoryProfile(
        userMarkdown: '',
        autoMarkdown: '',
        userUpdatedAtMs: null,
        autoUpdatedAtMs: null,
      );
    }
  }

  Future<void> setUserProfileMarkdown(String markdown) async {
    final String text = markdown.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final storage = await _db.database;
      await storage.execute(
        '''
        INSERT OR REPLACE INTO user_memory_profile(id, user_markdown, auto_markdown, user_updated_at, auto_updated_at, created_at)
        VALUES(
          1,
          ?,
          COALESCE((SELECT auto_markdown FROM user_memory_profile WHERE id = 1), NULL),
          ?,
          COALESCE((SELECT auto_updated_at FROM user_memory_profile WHERE id = 1), NULL),
          COALESCE((SELECT created_at FROM user_memory_profile WHERE id = 1), ?)
        )
        ''',
        <Object?>[text, now, now],
      );
    } catch (_) {}
  }

  Future<void> setAutoProfileMarkdown(String markdown) async {
    final String text = markdown.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final storage = await _db.database;
      await storage.execute(
        '''
        INSERT OR REPLACE INTO user_memory_profile(id, user_markdown, auto_markdown, user_updated_at, auto_updated_at, created_at)
        VALUES(
          1,
          COALESCE((SELECT user_markdown FROM user_memory_profile WHERE id = 1), NULL),
          ?,
          COALESCE((SELECT user_updated_at FROM user_memory_profile WHERE id = 1), NULL),
          ?,
          COALESCE((SELECT created_at FROM user_memory_profile WHERE id = 1), ?)
        )
        ''',
        <Object?>[text, now, now],
      );
    } catch (_) {}
  }

  Future<List<UserMemoryItem>> listItems({
    String? kind,
    bool? pinned,
    int limit = 50,
    int offset = 0,
  }) async {
    final int lim = limit.clamp(1, 200);
    final int off = offset < 0 ? 0 : offset;
    final List<String> filters = <String>[];
    final List<Object?> args = <Object?>[];
    final String k = _sanitizeKind(kind);
    if (kind != null && kind.trim().isNotEmpty) {
      filters.add('kind = ?');
      args.add(k);
    }
    if (pinned != null) {
      filters.add('pinned = ?');
      args.add(pinned ? 1 : 0);
    }
    final String where = filters.isEmpty
        ? ''
        : 'WHERE ${filters.join(' AND ')}';
    try {
      final storage = await _db.database;
      final rows = await storage.rawQuery(
        '''
        SELECT id, kind, memory_key, content, pinned, user_edited, updated_at, confidence
        FROM user_memory_items
        $where
        ORDER BY pinned DESC, updated_at DESC, id DESC
        LIMIT ? OFFSET ?
        ''',
        <Object?>[...args, lim, off],
      );
      return rows
          .map((r) {
            final int id = (_toInt(r['id']) ?? 0);
            return UserMemoryItem(
              id: id,
              kind: _sanitizeKind(r['kind'] as String?),
              memoryKey: (r['memory_key'] as String?)?.trim(),
              content: (r['content'] as String?)?.trim() ?? '',
              pinned: _toBool(r['pinned']),
              userEdited: _toBool(r['user_edited']),
              updatedAtMs: _toInt(r['updated_at']),
              confidence: _toDouble(r['confidence']),
            );
          })
          .where((e) => e.id > 0 && e.content.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <UserMemoryItem>[];
    }
  }

  Future<List<UserMemoryItem>> searchItems(
    String query, {
    int limit = 50,
    int offset = 0,
    String? kind,
    bool? pinned,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return const <UserMemoryItem>[];
    final int lim = limit.clamp(1, 200);
    final int off = offset < 0 ? 0 : offset;

    String buildMatch(String text) {
      final parts = text
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) return text;
      final limited = parts.length > 6 ? parts.sublist(0, 6) : parts;
      return limited.map((w) => '${w.replaceAll('"', '')}*').join(' AND ');
    }

    final List<String> filters = <String>[];
    final List<Object?> args = <Object?>[];
    if (kind != null && kind.trim().isNotEmpty) {
      filters.add('m.kind = ?');
      args.add(_sanitizeKind(kind));
    }
    if (pinned != null) {
      filters.add('m.pinned = ?');
      args.add(pinned ? 1 : 0);
    }
    final String extraWhere = filters.isEmpty
        ? ''
        : 'AND ${filters.join(' AND ')}';

    Future<List<UserMemoryItem>> runFts() async {
      final storage = await _db.database;
      final bool ftsExists = await _db.tableExists('user_memory_items_fts');
      if (!ftsExists) return const <UserMemoryItem>[];
      final String match = buildMatch(q);
      final rows = await storage.rawQuery(
        '''
        SELECT m.id, m.kind, m.memory_key, m.content, m.pinned, m.user_edited, m.updated_at, m.confidence
        FROM user_memory_items_fts fts
        JOIN user_memory_items m ON m.rowid = fts.rowid
        WHERE user_memory_items_fts MATCH ?
          $extraWhere
        ORDER BY bm25(user_memory_items_fts) ASC, m.pinned DESC, m.updated_at DESC, m.id DESC
        LIMIT ? OFFSET ?
        ''',
        <Object?>[match, ...args, lim, off],
      );
      return rows
          .map((r) {
            final int id = (_toInt(r['id']) ?? 0);
            return UserMemoryItem(
              id: id,
              kind: _sanitizeKind(r['kind'] as String?),
              memoryKey: (r['memory_key'] as String?)?.trim(),
              content: (r['content'] as String?)?.trim() ?? '',
              pinned: _toBool(r['pinned']),
              userEdited: _toBool(r['user_edited']),
              updatedAtMs: _toInt(r['updated_at']),
              confidence: _toDouble(r['confidence']),
            );
          })
          .where((e) => e.id > 0 && e.content.trim().isNotEmpty)
          .toList(growable: false);
    }

    Future<List<UserMemoryItem>> runLike() async {
      final storage = await _db.database;
      final String like = '%$q%';
      final List<String> where = <String>[
        '(m.content LIKE ? OR m.memory_key LIKE ? OR m.keywords_json LIKE ?)',
        ...filters,
      ];
      final rows = await storage.rawQuery(
        '''
        SELECT m.id, m.kind, m.memory_key, m.content, m.pinned, m.user_edited, m.updated_at, m.confidence
        FROM user_memory_items m
        WHERE ${where.join(' AND ')}
        ORDER BY m.pinned DESC, m.updated_at DESC, m.id DESC
        LIMIT ? OFFSET ?
        ''',
        <Object?>[like, like, like, ...args, lim, off],
      );
      return rows
          .map((r) {
            final int id = (_toInt(r['id']) ?? 0);
            return UserMemoryItem(
              id: id,
              kind: _sanitizeKind(r['kind'] as String?),
              memoryKey: (r['memory_key'] as String?)?.trim(),
              content: (r['content'] as String?)?.trim() ?? '',
              pinned: _toBool(r['pinned']),
              userEdited: _toBool(r['user_edited']),
              updatedAtMs: _toInt(r['updated_at']),
              confidence: _toDouble(r['confidence']),
            );
          })
          .where((e) => e.id > 0 && e.content.trim().isNotEmpty)
          .toList(growable: false);
    }

    try {
      final ftsRows = await runFts();
      if (ftsRows.isNotEmpty) return ftsRows;
      return await runLike();
    } catch (_) {
      try {
        return await runLike();
      } catch (_) {
        return const <UserMemoryItem>[];
      }
    }
  }

  Future<void> setPinned(int id, bool pinned) async {
    final int mid = id;
    if (mid <= 0) return;
    try {
      final storage = await _db.database;
      await storage.execute(
        'UPDATE user_memory_items SET pinned = ?, updated_at = ? WHERE id = ?',
        <Object?>[pinned ? 1 : 0, DateTime.now().millisecondsSinceEpoch, mid],
      );
    } catch (_) {}
  }

  Future<void> deleteItem(int id) async {
    final int mid = id;
    if (mid <= 0) return;
    try {
      final storage = await _db.database;
      await storage.transaction((txn) async {
        try {
          await txn.delete(
            'user_memory_evidence',
            where: 'memory_item_id = ?',
            whereArgs: <Object?>[mid],
          );
        } catch (_) {}
        try {
          await txn.delete(
            'user_memory_items',
            where: 'id = ?',
            whereArgs: <Object?>[mid],
          );
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getItemRow(int id) async {
    final int mid = id;
    if (mid <= 0) return null;
    try {
      final storage = await _db.database;
      final rows = await storage.query(
        'user_memory_items',
        where: 'id = ?',
        whereArgs: <Object?>[mid],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateItem({
    required int id,
    String? kind,
    String? memoryKey,
    String? content,
    List<String>? keywords,
    double? confidence,
  }) async {
    final int mid = id;
    if (mid <= 0) return false;

    final int now = DateTime.now().millisecondsSinceEpoch;
    final String? k0 = kind == null ? null : _sanitizeKind(kind);
    final String? key0 = memoryKey == null
        ? null
        : (memoryKey.trim().isEmpty ? null : memoryKey.trim());
    final String? content0 = content == null ? null : content.trim();
    final String? hash0 = content0 == null ? null : fnv1a64Hex(content0);
    if (content0 != null && content0.isEmpty) return false;
    if (content0 != null && content0.length > 800) return false;

    String? keywordsJson;
    if (keywords != null) {
      keywordsJson = _sanitizeKeywordsJson(keywords);
    }
    final double? conf0 = confidence == null
        ? null
        : confidence.clamp(0.0, 1.0);

    final List<String> sets = <String>[];
    final List<Object?> args = <Object?>[];
    if (k0 != null) {
      sets.add('kind = ?');
      args.add(k0);
    }
    if (memoryKey != null) {
      sets.add('memory_key = ?');
      args.add(key0);
    }
    if (content != null) {
      sets.add('content = ?');
      args.add(content0);
      sets.add('content_hash = ?');
      args.add(hash0);
    }
    if (keywords != null) {
      sets.add('keywords_json = ?');
      args.add(keywordsJson);
    }
    if (confidence != null) {
      sets.add('confidence = ?');
      args.add(conf0);
    }

    // Mark user-edited so automated refreshes won't overwrite content.
    sets.add('user_edited = 1');
    sets.add('updated_at = ?');
    args.add(now);

    if (sets.isEmpty) return false;

    args.add(mid);
    final String sql =
        'UPDATE user_memory_items SET ${sets.join(', ')} WHERE id = ?';
    try {
      final storage = await _db.database;
      final int n = await storage.rawUpdate(sql, args);
      return n > 0;
    } catch (_) {
      return false;
    }
  }

  Future<List<UserMemoryEvidence>> listEvidenceForItem(int itemId) async {
    if (itemId <= 0) return const <UserMemoryEvidence>[];
    try {
      final storage = await _db.database;
      final rows = await storage.query(
        'user_memory_evidence',
        columns: const <String>[
          'source_type',
          'source_id',
          'evidence_filenames_json',
          'start_time',
          'end_time',
          'created_at',
        ],
        where: 'memory_item_id = ?',
        whereArgs: <Object?>[itemId],
        orderBy: 'created_at DESC, id DESC',
        limit: 50,
      );
      return rows
          .map((r) {
            final String st = (r['source_type'] as String?)?.trim() ?? '';
            final String sid = (r['source_id'] as String?)?.trim() ?? '';
            final List<String> files = _decodeStringListJson(
              (r['evidence_filenames_json'] as String?) ?? '',
            );
            return UserMemoryEvidence(
              sourceType: st,
              sourceId: sid,
              filenames: files,
              startTime: _toInt(r['start_time']),
              endTime: _toInt(r['end_time']),
              createdAtMs: _toInt(r['created_at']) ?? 0,
            );
          })
          .where((e) => e.sourceType.isNotEmpty && e.sourceId.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <UserMemoryEvidence>[];
    }
  }

  Future<UserMemoryUpsertStats> upsertExtractedItems({
    required List<ExtractedUserMemoryItem> items,
    required UserMemoryUpsertEvidenceParams evidence,
  }) async {
    if (items.isEmpty) {
      return const UserMemoryUpsertStats(inserted: 0, updated: 0, touched: 0);
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    int inserted = 0;
    int updated = 0;
    int touched = 0;

    final storage = await _db.database;
    await storage.transaction((txn) async {
      for (final it in items) {
        final String kind = _sanitizeKind(it.kind);
        final String content = it.content.trim();
        if (content.isEmpty) continue;
        if (content.length > 800) continue;

        final String? key = (it.key ?? '').trim().isEmpty
            ? null
            : it.key!.trim();
        final String hash = fnv1a64Hex(content);
        if (hash.isEmpty) continue;

        final String keywordsJson = _sanitizeKeywordsJson(it.keywords);
        final double? confidence = it.confidence == null
            ? null
            : it.confidence!.clamp(0.0, 1.0);

        int? id;
        bool existingUserEdited = false;
        String? existingKey;
        bool insertedThis = false;

        // Prefer key-based upsert when available.
        if (key != null) {
          try {
            final rows = await txn.query(
              'user_memory_items',
              columns: const <String>['id', 'user_edited', 'memory_key'],
              where: 'memory_key = ?',
              whereArgs: <Object?>[key],
              limit: 1,
            );
            if (rows.isNotEmpty) {
              id = _toInt(rows.first['id']);
              existingUserEdited = _toBool(rows.first['user_edited']);
              existingKey = (rows.first['memory_key'] as String?)?.trim();
            }
          } catch (_) {}
        }

        if (id == null) {
          // Fallback: de-dup by hash.
          try {
            final rows = await txn.query(
              'user_memory_items',
              columns: const <String>['id', 'user_edited', 'memory_key'],
              where: 'content_hash = ?',
              whereArgs: <Object?>[hash],
              limit: 1,
            );
            if (rows.isNotEmpty) {
              id = _toInt(rows.first['id']);
              existingUserEdited = _toBool(rows.first['user_edited']);
              existingKey = (rows.first['memory_key'] as String?)?.trim();
            }
          } catch (_) {}
        }

        if (id == null) {
          // Insert new.
          try {
            final int rowid = await txn.rawInsert(
              '''
              INSERT OR IGNORE INTO user_memory_items(
                kind,
                memory_key,
                content,
                content_hash,
                keywords_json,
                confidence,
                pinned,
                user_edited,
                first_seen_at,
                last_seen_at,
                created_at,
                updated_at
              ) VALUES(?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, ?)
              ''',
              <Object?>[
                kind,
                key,
                content,
                hash,
                keywordsJson,
                confidence,
                now,
                now,
                now,
                now,
              ],
            );
            if (rowid > 0) {
              id = rowid;
              insertedThis = true;
              inserted += 1;
            }
          } catch (_) {}
        }

        // Handle a potential race where INSERT OR IGNORE didn't return rowid
        // but the row already exists (e.g. unique key/hash conflict).
        if (!insertedThis && (id ?? 0) <= 0) {
          try {
            if (key != null) {
              final rows = await txn.query(
                'user_memory_items',
                columns: const <String>['id', 'user_edited', 'memory_key'],
                where: 'memory_key = ?',
                whereArgs: <Object?>[key],
                limit: 1,
              );
              if (rows.isNotEmpty) {
                id = _toInt(rows.first['id']);
                existingUserEdited = _toBool(rows.first['user_edited']);
                existingKey = (rows.first['memory_key'] as String?)?.trim();
              }
            }
          } catch (_) {}
          if ((id ?? 0) <= 0) {
            try {
              final rows = await txn.query(
                'user_memory_items',
                columns: const <String>['id', 'user_edited', 'memory_key'],
                where: 'content_hash = ?',
                whereArgs: <Object?>[hash],
                limit: 1,
              );
              if (rows.isNotEmpty) {
                id = _toInt(rows.first['id']);
                existingUserEdited = _toBool(rows.first['user_edited']);
                existingKey = (rows.first['memory_key'] as String?)?.trim();
              }
            } catch (_) {}
          }
        }

        if ((id ?? 0) > 0) {
          if (!insertedThis) {
            // Existing row: update or touch.
            if (existingUserEdited) {
              try {
                final int n = await txn.rawUpdate(
                  'UPDATE user_memory_items SET last_seen_at = ?, updated_at = ? WHERE id = ?',
                  <Object?>[now, now, id],
                );
                if (n > 0) touched += n;
              } catch (_) {}
            } else {
              try {
                // Only adopt a new key when the existing row has no key.
                String? keyToWrite = key;
                final String ek = (existingKey ?? '').trim();
                if (ek.isNotEmpty) keyToWrite = ek;

                final int n = await txn.rawUpdate(
                  '''
                  UPDATE user_memory_items
                  SET kind = ?, memory_key = ?, content = ?, content_hash = ?, keywords_json = ?, confidence = ?,
                      last_seen_at = ?, updated_at = ?
                  WHERE id = ?
                  ''',
                  <Object?>[
                    kind,
                    keyToWrite,
                    content,
                    hash,
                    keywordsJson,
                    confidence,
                    now,
                    now,
                    id,
                  ],
                );
                if (n > 0) updated += n;
              } catch (_) {}
            }
          }

          // Evidence upsert (best-effort).
          final List<String> files = it.evidenceFilenames
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(5)
              .toSet()
              .toList(growable: false);
          String? filesJson;
          if (files.isNotEmpty) {
            try {
              filesJson = jsonEncode(files);
            } catch (_) {
              filesJson = null;
            }
          }

          try {
            final int insertedRow = await txn.rawInsert(
              '''
              INSERT OR IGNORE INTO user_memory_evidence(
                memory_item_id,
                source_type,
                source_id,
                evidence_filenames_json,
                start_time,
                end_time,
                created_at
              ) VALUES(?, ?, ?, ?, ?, ?, ?)
              ''',
              <Object?>[
                id,
                evidence.sourceType.trim(),
                evidence.sourceId.trim(),
                filesJson,
                evidence.startTime,
                evidence.endTime,
                now,
              ],
            );
            if (insertedRow <= 0) {
              await txn.rawUpdate(
                '''
                UPDATE user_memory_evidence
                SET evidence_filenames_json = ?, start_time = ?, end_time = ?
                WHERE memory_item_id = ? AND source_type = ? AND source_id = ?
                ''',
                <Object?>[
                  filesJson,
                  evidence.startTime,
                  evidence.endTime,
                  id,
                  evidence.sourceType.trim(),
                  evidence.sourceId.trim(),
                ],
              );
            }
          } catch (_) {}
        }
      }
    });

    return UserMemoryUpsertStats(
      inserted: inserted,
      updated: updated,
      touched: touched,
    );
  }

  /// Build a system message that injects global user memory (profile + pinned + relevant items).
  /// Returns empty string if disabled or nothing to inject.
  Future<String> buildUserMemoryContextMessage({required String query}) async {
    try {
      final bool enabled = await _settings.getUserMemoryInjectionEnabled();
      if (!enabled) return '';
      final int maxTokens = await _settings.getUserMemoryPromptTokens();
      final int maxItems = await _settings.getUserMemoryMaxItems();

      final UserMemoryProfile profile = await getProfile();

      final List<UserMemoryItem> pinned = await listItems(
        pinned: true,
        limit: 80,
        offset: 0,
      );
      final List<UserMemoryItem> relevant = query.trim().isEmpty
          ? const <UserMemoryItem>[]
          : await searchItems(query, limit: 120, offset: 0);
      return buildUserMemoryContextFromData(
        profileMarkdown: profile.effectiveMarkdown,
        pinned: pinned,
        relevant: relevant,
        maxTokens: maxTokens,
        maxRelevantItems: maxItems,
      );
    } catch (_) {
      return '';
    }
  }

  Future<void> refreshAutoProfile({int maxItems = 200}) async {
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final List<UserMemoryItem> pinned = await listItems(
        pinned: true,
        limit: 200,
        offset: 0,
      );
      final List<UserMemoryItem> recent = await listItems(
        pinned: false,
        limit: maxItems.clamp(50, 500),
        offset: 0,
      );
      final List<UserMemoryItem> merged = <UserMemoryItem>[
        ...pinned,
        ...recent,
      ];

      final Map<int, UserMemoryItem> dedup = <int, UserMemoryItem>{};
      for (final e in merged) {
        if (e.id <= 0) continue;
        dedup[e.id] = e;
      }
      final List<UserMemoryItem> items = dedup.values.toList();
      if (items.isEmpty) return;

      final UserMemoryProfile profile = await getProfile();
      final String previous = profile.autoMarkdown.trim();

      final DateTime now = DateTime.now().toLocal();
      final String today = now.toIso8601String().substring(0, 10);
      final String sys = [
        'You are a user-profile summarizer.',
        'Given a list of durable user-specific atomic memories, produce a concise Markdown "User Profile" for future chats.',
        '',
        'Rules:',
        '- Output Markdown only (no JSON, no code fences).',
        '- Do NOT invent facts. Only summarize what is supported by the provided items.',
        '- Prefer stable preferences/habits/constraints. Avoid transient tasks.',
        '- Keep it compact and skimmable.',
        '- Today is $today (local date).',
      ].join('\n');

      final StringBuffer sb = StringBuffer();
      sb.writeln('Previous auto profile (may be empty):');
      sb.writeln('<<<');
      sb.writeln(previous.isEmpty ? '(empty)' : previous);
      sb.writeln('>>>');
      sb.writeln();
      sb.writeln('Atomic memory items:');
      sb.writeln('<<<');
      int emitted = 0;
      for (final e in items) {
        if (emitted >= maxItems) break;
        final String k = (e.memoryKey ?? '').trim();
        final String tag = e.kind;
        if (k.isNotEmpty) {
          sb.writeln('- [$k] ($tag) ${e.content}');
        } else {
          sb.writeln('- ($tag) ${e.content}');
        }
        emitted += 1;
      }
      sb.writeln('>>>');
      sb.writeln();
      sb.writeln('Write the UPDATED auto profile in Markdown.');

      final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
        context: 'memory',
      );
      if (endpoints.isEmpty) return;

      final AIGatewayResult result = await _gateway.complete(
        endpoints: endpoints,
        messages: <AIMessage>[
          AIMessage(role: 'system', content: sys),
          AIMessage(role: 'user', content: sb.toString().trim()),
        ],
        responseStartMarker: '',
        timeout: const Duration(seconds: 45),
        preferStreaming: false,
        logContext: 'user_memory_profile_refresh',
      );

      final String out = _sanitizeModelText(result.content).trim();
      if (out.isEmpty) return;

      // Keep auto profile reasonably small (avoid bloating injections).
      final String clipped = PromptBudget.truncateTextByBytes(
        text: out,
        maxBytes: 24 * 1024,
        marker: '…profile truncated…',
      );

      await setAutoProfileMarkdown(clipped);

      final int tookMs = DateTime.now().millisecondsSinceEpoch - startedAt;
      try {
        await FlutterLogger.nativeInfo(
          'Memory',
          'refreshAutoProfile ok items=${items.length} tookMs=$tookMs',
        );
      } catch (_) {}
    } catch (e) {
      try {
        await FlutterLogger.nativeWarn(
          'Memory',
          'refreshAutoProfile failed: $e',
        );
      } catch (_) {}
    }
  }
}
