part of 'screenshot_database.dart';

// ===================== 统一 SearchIndex（search_docs + FTS） =====================
//
// 目标：
// - 为“非 OCR / 非分库月表”的数据源提供统一的全文检索入口（FTS5），并可按 doc_type 过滤。
// - 避免在 UI 层堆叠多表搜索；同时保持“按需触发”策略（仅在用户切到对应 Tab 时触发）。
//
// 说明：
// - 截图 OCR 仍走分库月表的 OCR FTS（数量级更大，不建议全部回填到主库）。
// - 本索引主要覆盖：收藏备注、每日/每周总结、早报、画像文章等（规模相对可控）。

// ---- doc_type 常量（SearchPage 等 UI 会用到） ----
const String kSearchDocTypeFavoriteNote = 'favorite_note';
const String kSearchDocTypeDailySummary = 'daily_summary';
const String kSearchDocTypeWeeklySummary = 'weekly_summary';
const String kSearchDocTypeMorningInsights = 'morning_insights';
const String kSearchDocTypePersonaArticle = 'persona_article';

// ---- index source 常量（用于增量同步） ----
const String kSearchIndexSourceFavorites = 'favorites';
const String kSearchIndexSourceDailySummaries = 'daily_summaries';
const String kSearchIndexSourceWeeklySummaries = 'weekly_summaries';
const String kSearchIndexSourceMorningInsights = 'morning_insights';
const String kSearchIndexSourcePersonaArticles = 'persona_articles';

String _favoriteNoteDocKey(String appPackageName, int screenshotId) {
  final pkg = appPackageName.trim().toLowerCase();
  return 'fav_note:$pkg:$screenshotId';
}

String _dailySummaryDocKey(String dateKey) => 'daily:${dateKey.trim()}';
String _weeklySummaryDocKey(String weekStartDate) =>
    'weekly:${weekStartDate.trim()}';
String _morningInsightsDocKey(String dateKey) => 'morning:${dateKey.trim()}';
String _personaArticleDocKey(String style) => 'persona:${style.trim()}';

int? _parseYmdToStartMillis(String ymd) {
  final s = ymd.trim();
  final parts = s.split('-');
  if (parts.length != 3) return null;
  try {
    final int y = int.parse(parts[0]);
    final int m = int.parse(parts[1]);
    final int d = int.parse(parts[2]);
    return DateTime(y, m, d).millisecondsSinceEpoch;
  } catch (_) {
    return null;
  }
}

String _renderMorningInsightsMarkdown(String raw) {
  final String s = raw.trim();
  if (s.isEmpty) return '';

  dynamic decoded;
  try {
    decoded = jsonDecode(s);
  } catch (_) {
    return s;
  }

  Iterable<dynamic>? source;
  if (decoded is Map) {
    final dynamic candidate =
        decoded['items'] ?? decoded['tips'] ?? decoded['entries'];
    if (candidate is List) {
      source = candidate;
    } else if (candidate is Map) {
      source = candidate.values;
    }
  } else if (decoded is List) {
    source = decoded;
  }

  if (source == null) return s;

  final StringBuffer out = StringBuffer();
  int emitted = 0;

  List<String> normalizeActions(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return v
        .toString()
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  for (final dynamic item in source) {
    String title = '';
    String summary = '';
    List<String> actions = const <String>[];

    if (item is Map) {
      final Map<String, dynamic> m =
          item.map((k, v) => MapEntry(k.toString(), v));
      title = (m['title'] ?? '').toString().trim();
      summary = (m['summary'] ?? m['desc'] ?? m['description'] ?? '')
          .toString()
          .trim();
      actions = normalizeActions(m['actions'] ?? m['action'] ?? m['steps']);
    } else if (item is String) {
      summary = item.trim();
    } else {
      summary = item?.toString().trim() ?? '';
    }

    if (title.isEmpty) {
      title = summary;
    }
    if (title.isEmpty && actions.isNotEmpty) {
      title = actions.first;
    }

    if (title.isEmpty && summary.isEmpty && actions.isEmpty) continue;

    if (emitted > 0) out.writeln();
    if (title.isNotEmpty) out.writeln('## $title');
    if (summary.isNotEmpty && summary != title) {
      out.writeln(summary);
    }
    if (actions.isNotEmpty) {
      if (summary.isNotEmpty || title.isNotEmpty) out.writeln();
      for (final a in actions) {
        if (a.trim().isEmpty) continue;
        out.writeln('- ${a.trim()}');
      }
    }
    emitted++;
  }

  final String rendered = out.toString().trim();
  return rendered.isNotEmpty ? rendered : s;
}

Future<void> _createSearchIndexTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS search_index_state (
      source TEXT PRIMARY KEY,
      last_indexed_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS search_docs (
      doc_key TEXT PRIMARY KEY,
      doc_type TEXT NOT NULL,
      title TEXT,
      content TEXT,
      tags TEXT,
      app_package_name TEXT,
      app_name TEXT,
      file_path TEXT,
      screenshot_id INTEGER,
      segment_id INTEGER,
      date_key TEXT,
      start_time INTEGER,
      end_time INTEGER,
      nsfw INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_search_docs_type_updated ON search_docs(doc_type, updated_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_search_docs_screenshot ON search_docs(app_package_name, screenshot_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_search_docs_segment ON search_docs(segment_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_search_docs_start_time ON search_docs(start_time)',
  );

  await _createSearchDocsFts(db);
}

Future<void> _createSearchDocsFts(DatabaseExecutor db) async {
  try {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS search_docs_fts USING fts5(
        title,
        content,
        tags,
        app_name,
        content='search_docs',
        content_rowid='rowid'
      )
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_docs_ai AFTER INSERT ON search_docs BEGIN
        INSERT INTO search_docs_fts(rowid, title, content, tags, app_name)
        VALUES (NEW.rowid, NEW.title, NEW.content, NEW.tags, NEW.app_name);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_docs_ad AFTER DELETE ON search_docs BEGIN
        INSERT INTO search_docs_fts(search_docs_fts, rowid, title, content, tags, app_name)
        VALUES ('delete', OLD.rowid, OLD.title, OLD.content, OLD.tags, OLD.app_name);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS search_docs_au AFTER UPDATE ON search_docs BEGIN
        INSERT INTO search_docs_fts(search_docs_fts, rowid, title, content, tags, app_name)
        VALUES ('delete', OLD.rowid, OLD.title, OLD.content, OLD.tags, OLD.app_name);
        INSERT INTO search_docs_fts(rowid, title, content, tags, app_name)
        VALUES (NEW.rowid, NEW.title, NEW.content, NEW.tags, NEW.app_name);
      END
    ''');
  } catch (e) {
    try {
      FlutterLogger.nativeWarn('DB', 'FTS5（search_docs）不支持：$e');
    } catch (_) {}
  }
}

extension ScreenshotDatabaseSearchIndex on ScreenshotDatabase {
  Future<int> _getSearchIndexState(DatabaseExecutor db, String source) async {
    try {
      final rows = await db.query(
        'search_index_state',
        columns: ['last_indexed_at'],
        where: 'source = ?',
        whereArgs: [source],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      return (rows.first['last_indexed_at'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _setSearchIndexState(
    DatabaseExecutor db,
    String source,
    int lastIndexedAt,
  ) async {
    try {
      await db.insert(
        'search_index_state',
        {
          'source': source,
          'last_indexed_at': lastIndexedAt,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<bool> upsertSearchDoc({
    required String docKey,
    required String docType,
    String? title,
    String? content,
    String? tags,
    String? appPackageName,
    String? appName,
    String? filePath,
    int? screenshotId,
    int? segmentId,
    String? dateKey,
    int? startTime,
    int? endTime,
    bool nsfw = false,
    int? updatedAt,
    DatabaseExecutor? exec,
  }) async {
    final DatabaseExecutor db = exec ?? await database;
    final int ts = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final String key = docKey.trim();
    final String type = docType.trim();
    if (key.isEmpty || type.isEmpty) return false;

    final row = <String, Object?>{
      'doc_key': key,
      'doc_type': type,
      'title': title,
      'content': content,
      'tags': tags,
      'app_package_name': appPackageName,
      'app_name': appName,
      'file_path': filePath,
      'screenshot_id': screenshotId,
      'segment_id': segmentId,
      'date_key': dateKey,
      'start_time': startTime,
      'end_time': endTime,
      'nsfw': nsfw ? 1 : 0,
      'updated_at': ts,
    };

    try {
      await db.insert(
        'search_docs',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (_) {
      // 兼容：若旧库尚未创建该表，尝试补建后重试一次
      try {
        await _createSearchIndexTables(db);
        await db.insert(
          'search_docs',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> deleteSearchDoc(String docKey, {DatabaseExecutor? exec}) async {
    final DatabaseExecutor db = exec ?? await database;
    final key = docKey.trim();
    if (key.isEmpty) return false;
    try {
      final n = await db.delete(
        'search_docs',
        where: 'doc_key = ?',
        whereArgs: [key],
      );
      return n > 0;
    } catch (_) {
      return false;
    }
  }

  Future<int> deleteSearchDocsByType(
    String docType, {
    DatabaseExecutor? exec,
  }) async {
    final DatabaseExecutor db = exec ?? await database;
    final type = docType.trim();
    if (type.isEmpty) return 0;
    try {
      return await db.delete(
        'search_docs',
        where: 'doc_type = ?',
        whereArgs: [type],
      );
    } catch (_) {
      return 0;
    }
  }

  /// 增量同步 SearchIndex：把主库中已有的“可控规模内容”写入 search_docs 供统一检索。
  ///
  /// 注意：
  /// - 这是“索引回填/追赶”的兜底策略，用于兼容原生端写入。
  /// - 对于“写入点在 Flutter 侧”的表，我们也会在写入时直接 upsert，进一步降低同步成本。
  Future<void> syncSearchIndex({Set<String>? sources}) async {
    final db = await database;
    await _createSearchIndexTables(db);

    final Set<String> targets = sources ??
        <String>{
          kSearchIndexSourceFavorites,
          kSearchIndexSourceDailySummaries,
          kSearchIndexSourceWeeklySummaries,
          kSearchIndexSourceMorningInsights,
          kSearchIndexSourcePersonaArticles,
        };

    for (final source in targets) {
      final int last = await _getSearchIndexState(db, source);
      int maxProcessed = last;
      try {
        switch (source) {
          case kSearchIndexSourceFavorites:
            maxProcessed = await _syncFavoritesNotes(db, last);
            break;
          case kSearchIndexSourceDailySummaries:
            maxProcessed = await _syncDailySummaries(db, last);
            break;
          case kSearchIndexSourceWeeklySummaries:
            maxProcessed = await _syncWeeklySummaries(db, last);
            break;
          case kSearchIndexSourceMorningInsights:
            maxProcessed = await _syncMorningInsights(db, last);
            break;
          case kSearchIndexSourcePersonaArticles:
            maxProcessed = await _syncPersonaArticles(db, last);
            break;
        }
      } catch (_) {}
      if (maxProcessed > last) {
        await _setSearchIndexState(db, source, maxProcessed);
      } else if (last == 0) {
        // 首次同步，即使没有数据也写入一次 state，避免反复全量扫描
        await _setSearchIndexState(
          db,
          source,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
  }

  Future<int> _syncFavoritesNotes(DatabaseExecutor db, int last) async {
    final rows = await db.query(
      'favorites',
      where: 'updated_at > ? AND note IS NOT NULL AND TRIM(note) != ""',
      whereArgs: [last],
      orderBy: 'updated_at ASC, id ASC',
    );
    if (rows.isEmpty) return last;

    final batch = (db as Database).batch();
    int maxTs = last;
    for (final r in rows) {
      final int sid = (r['screenshot_id'] as int?) ?? 0;
      final String pkg = (r['app_package_name'] as String?) ?? '';
      final String note = (r['note'] as String?)?.trim() ?? '';
      final int updatedAt = (r['updated_at'] as int?) ?? 0;
      if (sid <= 0 || pkg.trim().isEmpty || note.isEmpty) continue;
      if (updatedAt > maxTs) maxTs = updatedAt;

      batch.insert(
        'search_docs',
        {
          'doc_key': _favoriteNoteDocKey(pkg, sid),
          'doc_type': kSearchDocTypeFavoriteNote,
          'title': '收藏备注',
          'content': note,
          'tags': null,
          'app_package_name': pkg,
          'app_name': null,
          'file_path': null,
          'screenshot_id': sid,
          'segment_id': null,
          'date_key': null,
          'start_time': null,
          'end_time': null,
          'nsfw': 0,
          'updated_at': updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return maxTs;
  }

  Future<int> _syncDailySummaries(DatabaseExecutor db, int last) async {
    final rows = await db.query(
      'daily_summaries',
      where: 'created_at > ? AND output_text IS NOT NULL AND TRIM(output_text) != ""',
      whereArgs: [last],
      orderBy: 'created_at ASC, date_key ASC',
    );
    if (rows.isEmpty) return last;

    final batch = (db as Database).batch();
    int maxTs = last;
    for (final r in rows) {
      final String dateKey = (r['date_key'] as String?) ?? '';
      final String output = (r['output_text'] as String?) ?? '';
      final int createdAt = (r['created_at'] as int?) ?? 0;
      if (dateKey.trim().isEmpty || output.trim().isEmpty) continue;
      if (createdAt > maxTs) maxTs = createdAt;
      batch.insert(
        'search_docs',
        {
          'doc_key': _dailySummaryDocKey(dateKey),
          'doc_type': kSearchDocTypeDailySummary,
          'title': '每日总结 $dateKey',
          'content': output,
          'tags': null,
          'app_package_name': null,
          'app_name': null,
          'file_path': null,
          'screenshot_id': null,
          'segment_id': null,
          'date_key': dateKey,
          'start_time': _parseYmdToStartMillis(dateKey),
          'end_time': null,
          'nsfw': 0,
          'updated_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return maxTs;
  }

  Future<int> _syncWeeklySummaries(DatabaseExecutor db, int last) async {
    final rows = await db.query(
      'weekly_summaries',
      where: 'created_at > ? AND output_text IS NOT NULL AND TRIM(output_text) != ""',
      whereArgs: [last],
      orderBy: 'created_at ASC, week_start_date ASC',
    );
    if (rows.isEmpty) return last;

    final batch = (db as Database).batch();
    int maxTs = last;
    for (final r in rows) {
      final String ws = (r['week_start_date'] as String?) ?? '';
      final String we = (r['week_end_date'] as String?) ?? '';
      final String output = (r['output_text'] as String?) ?? '';
      final int createdAt = (r['created_at'] as int?) ?? 0;
      if (ws.trim().isEmpty || output.trim().isEmpty) continue;
      if (createdAt > maxTs) maxTs = createdAt;
      final String title =
          we.trim().isEmpty ? '周总结 $ws' : '周总结 $ws ~ $we';
      batch.insert(
        'search_docs',
        {
          'doc_key': _weeklySummaryDocKey(ws),
          'doc_type': kSearchDocTypeWeeklySummary,
          'title': title,
          'content': output,
          'tags': null,
          'app_package_name': null,
          'app_name': null,
          'file_path': null,
          'screenshot_id': null,
          'segment_id': null,
          'date_key': ws,
          'start_time': _parseYmdToStartMillis(ws),
          'end_time': null,
          'nsfw': 0,
          'updated_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return maxTs;
  }

  Future<int> _syncMorningInsights(DatabaseExecutor db, int last) async {
    final rows = await db.query(
      'morning_insights',
      where: 'created_at > ?',
      whereArgs: [last],
      orderBy: 'created_at ASC, date_key ASC',
    );
    if (rows.isEmpty) return last;

    final batch = (db as Database).batch();
    int maxTs = last;
    for (final r in rows) {
      final String dateKey = (r['date_key'] as String?) ?? '';
      final String tipsJson = (r['tips_json'] as String?) ?? '';
      final String raw = (r['raw_response'] as String?) ?? '';
      final int createdAt = (r['created_at'] as int?) ?? 0;
      final String contentRaw = raw.trim().isNotEmpty ? raw : tipsJson;
      final String content = _renderMorningInsightsMarkdown(contentRaw);
      if (dateKey.trim().isEmpty || content.trim().isEmpty) continue;
      if (createdAt > maxTs) maxTs = createdAt;
      batch.insert(
        'search_docs',
        {
          'doc_key': _morningInsightsDocKey(dateKey),
          'doc_type': kSearchDocTypeMorningInsights,
          'title': '早报 $dateKey',
          'content': content,
          'tags': null,
          'app_package_name': null,
          'app_name': null,
          'file_path': null,
          'screenshot_id': null,
          'segment_id': null,
          'date_key': dateKey,
          'start_time': _parseYmdToStartMillis(dateKey),
          'end_time': null,
          'nsfw': 0,
          'updated_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return maxTs;
  }

  Future<int> _syncPersonaArticles(DatabaseExecutor db, int last) async {
    final rows = await db.query(
      'persona_articles',
      where: 'updated_at > ? AND article IS NOT NULL AND TRIM(article) != ""',
      whereArgs: [last],
      orderBy: 'updated_at ASC, style ASC',
    );
    if (rows.isEmpty) return last;

    final batch = (db as Database).batch();
    int maxTs = last;
    for (final r in rows) {
      final String style = (r['style'] as String?) ?? '';
      final String article = (r['article'] as String?) ?? '';
      final String locale = (r['locale'] as String?) ?? '';
      final int updatedAt = (r['updated_at'] as int?) ?? 0;
      if (style.trim().isEmpty || article.trim().isEmpty) continue;
      if (updatedAt > maxTs) maxTs = updatedAt;

      batch.insert(
        'search_docs',
        {
          'doc_key': _personaArticleDocKey(style),
          'doc_type': kSearchDocTypePersonaArticle,
          'title': '画像文章 · $style',
          'content': article,
          'tags': (locale.trim().isEmpty) ? null : locale.trim(),
          'app_package_name': null,
          'app_name': null,
          'file_path': null,
          'screenshot_id': null,
          'segment_id': null,
          'date_key': null,
          'start_time': null,
          'end_time': null,
          'nsfw': 0,
          'updated_at': updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return maxTs;
  }

  /// 查询 SearchIndex（search_docs_fts），支持 doc_type/time 过滤。
  Future<List<Map<String, dynamic>>> searchSearchDocsByText(
    String query, {
    Set<String>? docTypes,
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
  }) async {
    final db = await database;
    final String q = query.trim();
    if (q.isEmpty) return <Map<String, dynamic>>[];

    final int fetchLimit = (limit ?? 50).clamp(1, 50);
    int fetchOffset = offset ?? 0;
    if (fetchOffset < 0) fetchOffset = 0;

    bool isLikelyCjkNoSpaces() {
      if (q.contains(' ')) return false;
      return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
    }

    String buildMatch(String text) {
      final parts = text
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) return text;
      final limited = parts.length > 6 ? parts.sublist(0, 6) : parts;
      return limited.map((w) => '${w.replaceAll('"', '')}*').join(' AND ');
    }

    List<Object?> _buildTypeArgs(List<String> filters) {
      final List<Object?> typeArgs = <Object?>[];
      if (docTypes != null && docTypes.isNotEmpty) {
        final types = docTypes.map((e) => e.trim()).where((e) => e.isNotEmpty);
        final list = types.toList(growable: false);
        if (list.isNotEmpty) {
          final String placeholders = List.filled(list.length, '?').join(',');
          filters.add('d.doc_type IN ($placeholders)');
          typeArgs.addAll(list);
        }
      }
      return typeArgs;
    }

    Future<List<Map<String, dynamic>>> runLike() async {
      final String likeTerm = '%$q%';
      final List<Object?> args = <Object?>[
        likeTerm,
        likeTerm,
        likeTerm,
        likeTerm,
      ];
      final List<String> filters = <String>[
        '(d.title LIKE ? OR d.content LIKE ? OR d.tags LIKE ? OR d.app_name LIKE ?)',
      ];
      args.addAll(_buildTypeArgs(filters));
      if (startMillis != null) {
        filters.add('(d.start_time IS NULL OR d.start_time >= ?)');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('(d.start_time IS NULL OR d.start_time <= ?)');
        args.add(endMillis);
      }
      args.addAll(<Object?>[fetchLimit, fetchOffset]);
      final String sql = '''
        SELECT d.*
        FROM search_docs d
        WHERE ${filters.join(' AND ')}
        ORDER BY d.updated_at DESC
        LIMIT ? OFFSET ?
      ''';
      final rows = await (db as Database).rawQuery(sql, args);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    Future<List<Map<String, dynamic>>> runFts() async {
      final bool ftsExists = await _tableExists(db, 'search_docs_fts');
      if (!ftsExists) return <Map<String, dynamic>>[];

      final String match = buildMatch(q);
      final List<Object?> args = <Object?>[match];
      final List<String> filters = <String>[];
      args.addAll(_buildTypeArgs(filters));
      if (startMillis != null) {
        filters.add('(d.start_time IS NULL OR d.start_time >= ?)');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('(d.start_time IS NULL OR d.start_time <= ?)');
        args.add(endMillis);
      }
      final String extraWhere =
          filters.isEmpty ? '' : 'AND ${filters.join(' AND ')}';
      args.addAll(<Object?>[fetchLimit, fetchOffset]);

      final String sql = '''
        SELECT d.*
        FROM search_docs_fts fts
        JOIN search_docs d ON d.rowid = fts.rowid
        WHERE search_docs_fts MATCH ?
          $extraWhere
        ORDER BY bm25(search_docs_fts) ASC, d.updated_at DESC
        LIMIT ? OFFSET ?
      ''';
      final rows = await (db as Database).rawQuery(sql, args);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    try {
      // 中文无空格：优先 LIKE，减少“FTS 命中为空”的误判。
      if (isLikelyCjkNoSpaces()) {
        final likeRows = await runLike();
        if (likeRows.isNotEmpty) return likeRows;
      }

      final ftsRows = await runFts();
      if (ftsRows.isNotEmpty) return ftsRows;
      return await runLike();
    } catch (e) {
      try {
        await FlutterLogger.nativeWarn(
          'DB',
          'search_docs 搜索失败，回退 LIKE：$e',
        );
      } catch (_) {}
      try {
        return await runLike();
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
  }
}
