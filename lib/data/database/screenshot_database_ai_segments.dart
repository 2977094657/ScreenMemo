part of 'screenshot_database.dart';

const String _segmentTimelineDiagTag = 'SegmentTimelineDiag';

void _logSegmentTimelineDiag(String message, {bool warn = false}) {
  final Future<void> log = warn
      ? FlutterLogger.nativeWarn(_segmentTimelineDiagTag, message)
      : FlutterLogger.nativeInfo(_segmentTimelineDiagTag, message);
  unawaited(log.catchError((_) {}));
}

String _segmentTimelineDayInfoPreview(
  List<SegmentTimelineDayInfo> days, {
  int limit = 8,
}) {
  if (days.isEmpty) return '-';
  final Iterable<SegmentTimelineDayInfo> shown = days.take(limit);
  final String suffix = days.length > limit ? ',...' : '';
  return shown
          .map((SegmentTimelineDayInfo info) => '${info.dayKey}:${info.count}')
          .join(',') +
      suffix;
}

String _segmentTimelineRowPreview(
  List<Map<String, dynamic>> rows, {
  int limit = 5,
}) {
  if (rows.isEmpty) return '-';
  final Iterable<Map<String, dynamic>> shown = rows.take(limit);
  final String suffix = rows.length > limit ? ',...' : '';
  return shown
          .map((Map<String, dynamic> row) {
            final Object? id = row['id'];
            final Object? start = row['start_time'];
            final Object? end = row['end_time'];
            final Object? sampleCount = row['sample_count'];
            final Object? hasSummary = row['has_summary'];
            return 'id=$id start=$start end=$end samples=$sampleCount summary=$hasSummary';
          })
          .join(' | ') +
      suffix;
}

extension ScreenshotDatabaseAISegments on ScreenshotDatabase {
  String _segmentsRootWhere([String? alias]) {
    final String p = (alias == null || alias.isEmpty) ? '' : '$alias.';
    return '(${p}merged_into_id IS NULL OR ${p}merged_into_id <= 0 OR NOT EXISTS (SELECT 1 FROM segments t WHERE t.id = ${p}merged_into_id))';
  }

  Future<Map<String, dynamic>?> getActiveSegment() async {
    final db = await database;
    try {
      // 兜底：若某段已产出总结（segment_results 有内容）但 status 仍是 collecting，
      // 不应在 UI 顶部继续显示“进行中”（常见于原生链路合并/网络卡住导致状态未及时落库）。
      // Avoid LOWER(TRIM(..)) on large TEXT values; it can be very expensive and may OOM on some devices.
      const String noSummaryCond =
          "r.segment_id IS NULL OR ((r.output_text IS NULL OR (LENGTH(r.output_text) <= 256 AND LOWER(TRIM(r.output_text)) IN ('','null'))) AND (r.structured_json IS NULL OR (LENGTH(r.structured_json) <= 256 AND LOWER(TRIM(r.structured_json)) IN ('','null'))))";
      final rows = await db.rawQuery(
        '''
        SELECT s.*
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        WHERE s.status = ?
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND ($noSummaryCond)
        ORDER BY s.id DESC
        LIMIT 1
        ''',
        ['collecting'],
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listSegments({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segments',
        where:
            "${_segmentsRootWhere()} AND (segment_kind IS NULL OR segment_kind = 'global')",
        orderBy: 'id DESC',
        limit: limit,
        offset: offset,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<SegmentTimelineBatch> listSegmentTimelineBatch({
    required int distinctDayCount,
    String? beforeDateKey,
    String? pinnedDateKey,
    String? maxDateKeyInclusive,
    bool requireSamples = true,
    bool truncateResultColumns = false,
  }) async {
    final db = await database;
    final int safeDayCount = math.max(1, distinctDayCount);
    final String beforeKey = (beforeDateKey ?? '').trim();
    final String pinnedKey = (pinnedDateKey ?? '').trim();
    final String maxKeyInclusive = (maxDateKeyInclusive ?? '').trim();
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
    const String dayExpr =
        "date(s.start_time / 1000, 'unixepoch', 'localtime')";

    List<String> buildWhereClauses({
      String? beforeKey,
      String? exactKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      String? olderThanKey,
    }) {
      final List<String> whereClauses = <String>[
        _segmentsRootWhere('s'),
        "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
      ];
      if (requireSamples) {
        whereClauses.add(hasSamplesCond);
      }
      final String before = (beforeKey ?? '').trim();
      if (before.isNotEmpty) {
        whereClauses.add("$dayExpr < ?");
      }
      final String exact = (exactKey ?? '').trim();
      if (exact.isNotEmpty) {
        whereClauses.add("$dayExpr = ?");
      }
      final String minKey = (minKeyInclusive ?? '').trim();
      if (minKey.isNotEmpty) {
        whereClauses.add("$dayExpr >= ?");
      }
      final String maxKey = (maxKeyInclusive ?? '').trim();
      if (maxKey.isNotEmpty) {
        whereClauses.add("$dayExpr <= ?");
      }
      final String olderThan = (olderThanKey ?? '').trim();
      if (olderThan.isNotEmpty) {
        whereClauses.add("$dayExpr < ?");
      }
      return whereClauses;
    }

    List<Object?> buildWhereParams({
      String? beforeKey,
      String? exactKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      String? olderThanKey,
    }) {
      final List<Object?> whereParams = <Object?>[];
      final String before = (beforeKey ?? '').trim();
      if (before.isNotEmpty) {
        whereParams.add(before);
      }
      final String exact = (exactKey ?? '').trim();
      if (exact.isNotEmpty) {
        whereParams.add(exact);
      }
      final String minKey = (minKeyInclusive ?? '').trim();
      if (minKey.isNotEmpty) {
        whereParams.add(minKey);
      }
      final String maxKey = (maxKeyInclusive ?? '').trim();
      if (maxKey.isNotEmpty) {
        whereParams.add(maxKey);
      }
      final String olderThan = (olderThanKey ?? '').trim();
      if (olderThan.isNotEmpty) {
        whereParams.add(olderThan);
      }
      return whereParams;
    }

    Future<List<String>> queryDayKeys({
      String? beforeKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      required int limit,
    }) async {
      final List<String> whereClauses = buildWhereClauses(
        beforeKey: beforeKey,
        minKeyInclusive: minKeyInclusive,
        maxKeyInclusive: maxKeyInclusive,
      );
      final List<Object?> whereParams = buildWhereParams(
        beforeKey: beforeKey,
        minKeyInclusive: minKeyInclusive,
        maxKeyInclusive: maxKeyInclusive,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery(
        '''
        SELECT day_key
        FROM (
          SELECT DISTINCT $dayExpr AS day_key
          FROM segments s
          $whereSql
        )
        ORDER BY day_key DESC
        LIMIT ?
        ''',
        <Object?>[...whereParams, limit],
      );
      return rows
          .map((Map<String, Object?> row) => (row['day_key'] as String?) ?? '')
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);
    }

    Future<bool> dayKeyExists(String dateKey) async {
      final String normalized = dateKey.trim();
      if (normalized.isEmpty) return false;
      final List<String> whereClauses = buildWhereClauses(
        exactKey: normalized,
        maxKeyInclusive: maxKeyInclusive,
      );
      final List<Object?> whereParams = buildWhereParams(
        exactKey: normalized,
        maxKeyInclusive: maxKeyInclusive,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT 1
        FROM segments s
        $whereSql
        LIMIT 1
        ''', whereParams);
      return rows.isNotEmpty;
    }

    Future<bool> hasOlderThan(String dateKey) async {
      final String normalized = dateKey.trim();
      if (normalized.isEmpty) return false;
      final List<String> whereClauses = buildWhereClauses(
        maxKeyInclusive: maxKeyInclusive,
        olderThanKey: normalized,
      );
      final List<Object?> whereParams = buildWhereParams(
        maxKeyInclusive: maxKeyInclusive,
        olderThanKey: normalized,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT 1
        FROM (
          SELECT DISTINCT $dayExpr AS day_key
          FROM segments s
          $whereSql
        )
        LIMIT 1
        ''', whereParams);
      return rows.isNotEmpty;
    }

    if (maxKeyInclusive.isEmpty && maxDateKeyInclusive != null) {
      return const SegmentTimelineBatch(
        segments: <Map<String, dynamic>>[],
        dayKeys: <String>[],
        hasMoreOlder: false,
      );
    }

    List<String> dayKeys = await queryDayKeys(
      beforeKey: beforeKey,
      maxKeyInclusive: maxKeyInclusive,
      limit: safeDayCount,
    );
    if (dayKeys.isEmpty) {
      return const SegmentTimelineBatch(
        segments: <Map<String, dynamic>>[],
        dayKeys: <String>[],
        hasMoreOlder: false,
      );
    }

    if (beforeKey.isEmpty &&
        pinnedKey.isNotEmpty &&
        !dayKeys.contains(pinnedKey)) {
      final bool pinnedExists = await dayKeyExists(pinnedKey);
      if (pinnedExists) {
        final List<String> expanded = await queryDayKeys(
          minKeyInclusive: pinnedKey,
          maxKeyInclusive: maxKeyInclusive,
          limit: 1 << 20,
        );
        if (expanded.isNotEmpty) {
          dayKeys = expanded;
        }
      }
    }

    final String newestDayKey = dayKeys.first;
    final String oldestDayKey = dayKeys.last;
    final int? oldestStartMillis = _parseYmdToStartMillis(oldestDayKey);
    final int? newestStartMillis = _parseYmdToStartMillis(newestDayKey);
    if (oldestStartMillis == null || newestStartMillis == null) {
      return const SegmentTimelineBatch(
        segments: <Map<String, dynamic>>[],
        dayKeys: <String>[],
        hasMoreOlder: false,
      );
    }
    final int newestEndMillis =
        DateTime.fromMillisecondsSinceEpoch(
          newestStartMillis,
        ).add(const Duration(days: 1)).millisecondsSinceEpoch -
        1;
    final List<Map<String, dynamic>> segments = await listSegmentsEx(
      limit: 1 << 30,
      onlyNoSummary: false,
      requireSamples: requireSamples,
      startMillis: oldestStartMillis,
      endMillis: newestEndMillis,
      truncateResultColumns: truncateResultColumns,
    );
    final bool hasMoreOlder = await hasOlderThan(oldestDayKey);
    return SegmentTimelineBatch(
      segments: segments,
      dayKeys: dayKeys,
      hasMoreOlder: hasMoreOlder,
    );
  }

  Future<SegmentTimelineDayBatch> listSegmentTimelineDayBatch({
    required int distinctDayCount,
    String? beforeDateKey,
    String? pinnedDateKey,
    String? maxDateKeyInclusive,
    bool requireSamples = true,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final db = await database;
    final int safeDayCount = math.max(1, distinctDayCount);
    final String beforeKey = (beforeDateKey ?? '').trim();
    final String pinnedKey = (pinnedDateKey ?? '').trim();
    final String maxKeyInclusive = (maxDateKeyInclusive ?? '').trim();
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
    const String dayExpr =
        "date(s.start_time / 1000, 'unixepoch', 'localtime')";

    List<String> buildWhereClauses({
      String? beforeKey,
      String? exactKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      String? olderThanKey,
    }) {
      final List<String> whereClauses = <String>[
        _segmentsRootWhere('s'),
        "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
      ];
      if (requireSamples) {
        whereClauses.add(hasSamplesCond);
      }
      final String before = (beforeKey ?? '').trim();
      if (before.isNotEmpty) {
        whereClauses.add("$dayExpr < ?");
      }
      final String exact = (exactKey ?? '').trim();
      if (exact.isNotEmpty) {
        whereClauses.add("$dayExpr = ?");
      }
      final String minKey = (minKeyInclusive ?? '').trim();
      if (minKey.isNotEmpty) {
        whereClauses.add("$dayExpr >= ?");
      }
      final String maxKey = (maxKeyInclusive ?? '').trim();
      if (maxKey.isNotEmpty) {
        whereClauses.add("$dayExpr <= ?");
      }
      final String olderThan = (olderThanKey ?? '').trim();
      if (olderThan.isNotEmpty) {
        whereClauses.add("$dayExpr < ?");
      }
      return whereClauses;
    }

    List<Object?> buildWhereParams({
      String? beforeKey,
      String? exactKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      String? olderThanKey,
    }) {
      final List<Object?> whereParams = <Object?>[];
      final String before = (beforeKey ?? '').trim();
      if (before.isNotEmpty) {
        whereParams.add(before);
      }
      final String exact = (exactKey ?? '').trim();
      if (exact.isNotEmpty) {
        whereParams.add(exact);
      }
      final String minKey = (minKeyInclusive ?? '').trim();
      if (minKey.isNotEmpty) {
        whereParams.add(minKey);
      }
      final String maxKey = (maxKeyInclusive ?? '').trim();
      if (maxKey.isNotEmpty) {
        whereParams.add(maxKey);
      }
      final String olderThan = (olderThanKey ?? '').trim();
      if (olderThan.isNotEmpty) {
        whereParams.add(olderThan);
      }
      return whereParams;
    }

    Future<List<SegmentTimelineDayInfo>> queryDayInfos({
      String? beforeKey,
      String? minKeyInclusive,
      String? maxKeyInclusive,
      required int limit,
      bool ascending = false,
    }) async {
      final List<String> whereClauses = buildWhereClauses(
        beforeKey: beforeKey,
        minKeyInclusive: minKeyInclusive,
        maxKeyInclusive: maxKeyInclusive,
      );
      final List<Object?> whereParams = buildWhereParams(
        beforeKey: beforeKey,
        minKeyInclusive: minKeyInclusive,
        maxKeyInclusive: maxKeyInclusive,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery(
        '''
        SELECT $dayExpr AS day_key, COUNT(*) AS segment_count
        FROM segments s
        $whereSql
        GROUP BY day_key
        ORDER BY day_key ${ascending ? 'ASC' : 'DESC'}
        LIMIT ?
        ''',
        <Object?>[...whereParams, limit],
      );
      return rows
          .map((Map<String, Object?> row) {
            final String dayKey = (row['day_key'] as String?) ?? '';
            final int count = (row['segment_count'] as int?) ?? 0;
            return SegmentTimelineDayInfo(dayKey: dayKey, count: count);
          })
          .where(
            (SegmentTimelineDayInfo info) =>
                info.dayKey.isNotEmpty && info.count > 0,
          )
          .toList(growable: false);
    }

    Future<bool> dayKeyExists(String dateKey) async {
      final String normalized = dateKey.trim();
      if (normalized.isEmpty) return false;
      final List<String> whereClauses = buildWhereClauses(
        exactKey: normalized,
        maxKeyInclusive: maxKeyInclusive,
      );
      final List<Object?> whereParams = buildWhereParams(
        exactKey: normalized,
        maxKeyInclusive: maxKeyInclusive,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT 1
        FROM segments s
        $whereSql
        LIMIT 1
        ''', whereParams);
      return rows.isNotEmpty;
    }

    Future<bool> hasOlderThan(String dateKey) async {
      final String normalized = dateKey.trim();
      if (normalized.isEmpty) return false;
      final List<String> whereClauses = buildWhereClauses(
        maxKeyInclusive: maxKeyInclusive,
        olderThanKey: normalized,
      );
      final List<Object?> whereParams = buildWhereParams(
        maxKeyInclusive: maxKeyInclusive,
        olderThanKey: normalized,
      );
      final String whereSql = 'WHERE ${whereClauses.join(' AND ')}';
      final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT 1
        FROM (
          SELECT $dayExpr AS day_key
          FROM segments s
          $whereSql
          GROUP BY day_key
        )
        LIMIT 1
        ''', whereParams);
      return rows.isNotEmpty;
    }

    if (maxKeyInclusive.isEmpty && maxDateKeyInclusive != null) {
      _logSegmentTimelineDiag(
        'dayBatch.empty reason=blankCutoff distinct=$safeDayCount before=$beforeKey pinned=$pinnedKey max=(blank) requireSamples=$requireSamples ms=${sw.elapsedMilliseconds}',
        warn: true,
      );
      return const SegmentTimelineDayBatch(
        days: <SegmentTimelineDayInfo>[],
        hasMoreOlder: false,
      );
    }

    List<SegmentTimelineDayInfo> days = await queryDayInfos(
      beforeKey: beforeKey,
      maxKeyInclusive: maxKeyInclusive,
      limit: safeDayCount,
    );
    if (days.isEmpty) {
      _logSegmentTimelineDiag(
        'dayBatch.empty reason=noDays distinct=$safeDayCount before=$beforeKey pinned=$pinnedKey max=${maxKeyInclusive.isEmpty ? '(none)' : maxKeyInclusive} requireSamples=$requireSamples ms=${sw.elapsedMilliseconds}',
      );
      return const SegmentTimelineDayBatch(
        days: <SegmentTimelineDayInfo>[],
        hasMoreOlder: false,
      );
    }

    if (beforeKey.isEmpty &&
        pinnedKey.isNotEmpty &&
        !days.any((SegmentTimelineDayInfo info) => info.dayKey == pinnedKey)) {
      final bool pinnedExists = await dayKeyExists(pinnedKey);
      if (pinnedExists) {
        final List<SegmentTimelineDayInfo> expanded = await queryDayInfos(
          minKeyInclusive: pinnedKey,
          maxKeyInclusive: maxKeyInclusive,
          limit: 1 << 20,
        );
        if (expanded.isNotEmpty) {
          days = expanded;
        }
      }
    }

    if (beforeKey.isEmpty && pinnedKey.isNotEmpty) {
      final List<SegmentTimelineDayInfo> newerAndPinnedAsc =
          await queryDayInfos(
            minKeyInclusive: pinnedKey,
            maxKeyInclusive: maxKeyInclusive,
            limit: math.min(1 << 20, safeDayCount),
            ascending: true,
          );
      if (newerAndPinnedAsc.any(
        (SegmentTimelineDayInfo info) => info.dayKey == pinnedKey,
      )) {
        final List<SegmentTimelineDayInfo> older = await queryDayInfos(
          beforeKey: pinnedKey,
          maxKeyInclusive: maxKeyInclusive,
          limit: safeDayCount,
        );
        final Map<String, SegmentTimelineDayInfo>
        byKey = <String, SegmentTimelineDayInfo>{
          for (final SegmentTimelineDayInfo info in newerAndPinnedAsc.reversed)
            info.dayKey: info,
          for (final SegmentTimelineDayInfo info in older) info.dayKey: info,
        };
        days = byKey.values.toList(growable: false)
          ..sort((a, b) => b.dayKey.compareTo(a.dayKey));
      }

      final int pinnedIndex = days.indexWhere(
        (SegmentTimelineDayInfo info) => info.dayKey == pinnedKey,
      );
      if (pinnedIndex >= 0) {
        final DateTabWindow<SegmentTimelineDayInfo> window =
            buildCenteredDateTabWindow<SegmentTimelineDayInfo>(
              items: days,
              targetIndex: pinnedIndex,
              beforeCount: 14,
              afterCount: safeDayCount <= 1 ? 0 : safeDayCount - 15,
            );
        if (window.items.isNotEmpty) {
          days = window.items;
        }
      }
    }

    final bool hasMoreOlder = await hasOlderThan(days.last.dayKey);
    _logSegmentTimelineDiag(
      'dayBatch.result distinct=$safeDayCount before=$beforeKey pinned=$pinnedKey max=${maxKeyInclusive.isEmpty ? '(none)' : maxKeyInclusive} requireSamples=$requireSamples days=${days.length} first=${days.first.dayKey}:${days.first.count} last=${days.last.dayKey}:${days.last.count} hasMoreOlder=$hasMoreOlder preview=${_segmentTimelineDayInfoPreview(days)} ms=${sw.elapsedMilliseconds}',
    );
    return SegmentTimelineDayBatch(days: days, hasMoreOlder: hasMoreOlder);
  }

  Future<List<SegmentTimelineDayInfo>> listSegmentTimelineMonthDayCounts({
    required int year,
    required int month,
    String? maxDateKeyInclusive,
    bool requireSamples = true,
  }) async {
    if (year <= 0 || month < 1 || month > 12) {
      return const <SegmentTimelineDayInfo>[];
    }
    final DateTime firstDay = DateTime(year, month);
    if (firstDay.year != year || firstDay.month != month) {
      return const <SegmentTimelineDayInfo>[];
    }
    final DateTime lastDay = DateTime(year, month + 1, 0);
    final String startKey =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';
    final String naturalEndKey =
        '${lastDay.year.toString().padLeft(4, '0')}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}';
    final String maxKeyInclusive = (maxDateKeyInclusive ?? '').trim();
    if (maxKeyInclusive.isEmpty && maxDateKeyInclusive != null) {
      return const <SegmentTimelineDayInfo>[];
    }
    if (maxKeyInclusive.isNotEmpty && maxKeyInclusive.compareTo(startKey) < 0) {
      return const <SegmentTimelineDayInfo>[];
    }
    final String endKey =
        maxKeyInclusive.isNotEmpty &&
            maxKeyInclusive.compareTo(naturalEndKey) < 0
        ? maxKeyInclusive
        : naturalEndKey;

    final db = await database;
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
    const String dayExpr =
        "date(s.start_time / 1000, 'unixepoch', 'localtime')";
    final List<String> whereClauses = <String>[
      _segmentsRootWhere('s'),
      "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
      "$dayExpr >= ?",
      "$dayExpr <= ?",
      if (requireSamples) hasSamplesCond,
    ];
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT $dayExpr AS day_key, COUNT(*) AS segment_count
      FROM segments s
      WHERE ${whereClauses.join(' AND ')}
      GROUP BY day_key
      ORDER BY day_key DESC
      ''',
      <Object?>[startKey, endKey],
    );
    return rows
        .map((Map<String, Object?> row) {
          final String dayKey = (row['day_key'] as String?) ?? '';
          final int count = (row['segment_count'] as int?) ?? 0;
          return SegmentTimelineDayInfo(dayKey: dayKey, count: count);
        })
        .where(
          (SegmentTimelineDayInfo info) =>
              info.dayKey.isNotEmpty && info.count > 0,
        )
        .toList(growable: false);
  }

  Future<List<int>> listSegmentTimelineYears({
    String? maxDateKeyInclusive,
    bool requireSamples = true,
  }) async {
    final String maxKeyInclusive = (maxDateKeyInclusive ?? '').trim();
    if (maxKeyInclusive.isEmpty && maxDateKeyInclusive != null) {
      return const <int>[];
    }

    final db = await database;
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
    const String dayExpr =
        "date(s.start_time / 1000, 'unixepoch', 'localtime')";
    final List<String> whereClauses = <String>[
      _segmentsRootWhere('s'),
      "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
      if (maxKeyInclusive.isNotEmpty) "$dayExpr <= ?",
      if (requireSamples) hasSamplesCond,
    ];
    final List<Object?> whereParams = <Object?>[
      if (maxKeyInclusive.isNotEmpty) maxKeyInclusive,
    ];
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT DISTINCT substr($dayExpr, 1, 4) AS year_key
      FROM segments s
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY year_key DESC
      ''', whereParams);
    return rows
        .map((Map<String, Object?> row) {
          final String raw = (row['year_key'] as String?) ?? '';
          return int.tryParse(raw);
        })
        .whereType<int>()
        .where((int year) => year > 0)
        .toList(growable: false);
  }

  Future<Map<String, int>> _segmentTimelineDayDiagCounts(
    Database db, {
    required String dateKey,
    required int startMillis,
    required int endMillis,
  }) async {
    const String dayExpr =
        "date(s.start_time / 1000, 'unixepoch', 'localtime')";
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";
    final String rootGlobalCond =
        "${_segmentsRootWhere('s')} AND (s.segment_kind IS NULL OR s.segment_kind = 'global')";
    try {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        '''
        SELECT
          SUM(CASE WHEN $rootGlobalCond AND s.start_time >= ? AND s.start_time <= ? THEN 1 ELSE 0 END) AS range_root,
          SUM(CASE WHEN $rootGlobalCond AND s.start_time >= ? AND s.start_time <= ? AND $hasSamplesCond THEN 1 ELSE 0 END) AS range_samples,
          SUM(CASE WHEN $rootGlobalCond AND $dayExpr = ? THEN 1 ELSE 0 END) AS dayexpr_root,
          SUM(CASE WHEN $rootGlobalCond AND $dayExpr = ? AND $hasSamplesCond THEN 1 ELSE 0 END) AS dayexpr_samples
        FROM segments s
        ''',
        <Object?>[
          startMillis,
          endMillis,
          startMillis,
          endMillis,
          dateKey,
          dateKey,
        ],
      );
      final Map<String, Object?> row = rows.isEmpty
          ? const <String, Object?>{}
          : rows.first;
      int read(String key) => ((row[key] as num?) ?? 0).toInt();
      return <String, int>{
        'range_root': read('range_root'),
        'range_samples': read('range_samples'),
        'dayexpr_root': read('dayexpr_root'),
        'dayexpr_samples': read('dayexpr_samples'),
      };
    } catch (e) {
      _logSegmentTimelineDiag(
        'daySegments.diagCounts.error date=$dateKey error=$e',
        warn: true,
      );
      return const <String, int>{};
    }
  }

  Future<List<Map<String, dynamic>>> listSegmentTimelineDaySegments({
    required String dateKey,
    bool onlyNoSummary = false,
    bool requireSamples = true,
    String? maxDateKeyInclusive,
    bool truncateResultColumns = false,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final String normalized = dateKey.trim();
    if (normalized.isEmpty) return <Map<String, dynamic>>[];
    final String maxKeyInclusive = (maxDateKeyInclusive ?? '').trim();
    if (maxKeyInclusive.isEmpty && maxDateKeyInclusive != null) {
      _logSegmentTimelineDiag(
        'daySegments.empty reason=blankCutoff date=$normalized requireSamples=$requireSamples onlyNoSummary=$onlyNoSummary truncate=$truncateResultColumns ms=${sw.elapsedMilliseconds}',
        warn: true,
      );
      return <Map<String, dynamic>>[];
    }
    if (maxKeyInclusive.isNotEmpty &&
        normalized.compareTo(maxKeyInclusive) > 0) {
      _logSegmentTimelineDiag(
        'daySegments.empty reason=afterCutoff date=$normalized max=$maxKeyInclusive requireSamples=$requireSamples onlyNoSummary=$onlyNoSummary truncate=$truncateResultColumns ms=${sw.elapsedMilliseconds}',
        warn: true,
      );
      return <Map<String, dynamic>>[];
    }
    final int? startMillis = _parseYmdToStartMillis(normalized);
    if (startMillis == null) {
      _logSegmentTimelineDiag(
        'daySegments.empty reason=badDateKey date=$normalized requireSamples=$requireSamples onlyNoSummary=$onlyNoSummary truncate=$truncateResultColumns ms=${sw.elapsedMilliseconds}',
        warn: true,
      );
      return <Map<String, dynamic>>[];
    }
    final int endMillis =
        DateTime.fromMillisecondsSinceEpoch(
          startMillis,
        ).add(const Duration(days: 1)).millisecondsSinceEpoch -
        1;
    final List<Map<String, dynamic>> rows = await listSegmentsEx(
      limit: 1 << 30,
      onlyNoSummary: onlyNoSummary,
      requireSamples: requireSamples,
      startMillis: startMillis,
      endMillis: endMillis,
      truncateResultColumns: truncateResultColumns,
    );
    Map<String, int> diagCounts = const <String, int>{};
    final bool warn = rows.isEmpty;
    if (warn) {
      final db = await database;
      diagCounts = await _segmentTimelineDayDiagCounts(
        db,
        dateKey: normalized,
        startMillis: startMillis,
        endMillis: endMillis,
      );
    }
    _logSegmentTimelineDiag(
      'daySegments.result date=$normalized rows=${rows.length} range=$startMillis..$endMillis max=${maxKeyInclusive.isEmpty ? '(none)' : maxKeyInclusive} requireSamples=$requireSamples onlyNoSummary=$onlyNoSummary truncate=$truncateResultColumns preview=${_segmentTimelineRowPreview(rows)}${diagCounts.isEmpty ? '' : ' diagCounts=$diagCounts'} ms=${sw.elapsedMilliseconds}',
      warn: warn,
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> _attachSegmentSampleStats(
    Database db,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;

    final List<int> segmentIds = <int>[];
    final Set<int> seenSegmentIds = <int>{};
    for (final Map<String, dynamic> row in rows) {
      final int segmentId = ((row['id'] as num?) ?? 0).toInt();
      if (segmentId > 0 && seenSegmentIds.add(segmentId)) {
        segmentIds.add(segmentId);
      }
    }

    final Map<int, int> sampleCountBySegmentId = <int, int>{};
    final Map<int, String> appPackagesBySegmentId = <int, String>{};
    if (segmentIds.isNotEmpty) {
      try {
        const int chunkSize = 400;
        for (int i = 0; i < segmentIds.length; i += chunkSize) {
          final int end = (i + chunkSize) > segmentIds.length
              ? segmentIds.length
              : (i + chunkSize);
          final List<int> chunk = segmentIds.sublist(i, end);
          final String placeholders = List.filled(chunk.length, '?').join(',');
          final List<Map<String, Object?>> statsRows = await db.rawQuery('''
            SELECT
              segment_id,
              COUNT(*) AS sample_count,
              GROUP_CONCAT(DISTINCT app_package_name) AS app_packages_display
            FROM segment_samples
            WHERE segment_id IN ($placeholders)
            GROUP BY segment_id
            ''', chunk);
          for (final Map<String, Object?> item in statsRows) {
            final int segmentId = ((item['segment_id'] as num?) ?? 0).toInt();
            if (segmentId <= 0) continue;
            sampleCountBySegmentId[segmentId] =
                ((item['sample_count'] as num?) ?? 0).toInt();
            final String appPackages =
                ((item['app_packages_display'] as String?) ?? '').trim();
            if (appPackages.isNotEmpty) {
              appPackagesBySegmentId[segmentId] = appPackages;
            }
          }
        }
      } catch (e) {
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'attachSegmentSampleStats failed err=${e.toString()} rows=${rows.length}',
          );
        } catch (_) {}
      }
    }

    for (final Map<String, dynamic> row in rows) {
      final int segmentId = ((row['id'] as num?) ?? 0).toInt();
      final String appPackages = ((row['app_packages'] as String?) ?? '')
          .trim();
      final String aggregatedPackages =
          (appPackagesBySegmentId[segmentId] ?? '').trim();
      row['sample_count'] = sampleCountBySegmentId[segmentId] ?? 0;
      final String appPackagesDisplay = appPackages.isNotEmpty
          ? appPackages
          : aggregatedPackages;
      row['app_packages_display'] = appPackagesDisplay.isEmpty
          ? null
          : appPackagesDisplay;
    }
    return rows;
  }

  /// 列出段落（带是否有总结标记），可选仅返回“无总结”的事件
  /// - has_summary: 0 表示无总结；1 表示已有总结
  /// - 默认仅返回“至少有一张样本图片”的事件（避免前端渲染后再隐藏导致滚动抖动）
  ///   - requireSamples=false 时允许返回“样本数为 0”的段落（用于故障排查/降级展示）
  /// - 可选按 start_time 进行时间范围过滤（用于“动态”页按日期窗口增量加载）
  /// - 可选按 appPackageName / appPackageNames 过滤（按 segment_samples.app_package_name）。
  Future<List<Map<String, dynamic>>> listSegmentsEx({
    int limit = 50,
    int offset = 0,
    bool onlyNoSummary = false,
    bool requireSamples = true,
    int? startMillis,
    int? endMillis,
    List<String>? appPackageNames,
    String? appPackageName,
    bool truncateResultColumns = false,
  }) async {
    final db = await database;
    int safeOffset = offset;
    if (safeOffset < 0) safeOffset = 0;

    // Avoid LOWER(TRIM(..)) on huge TEXT blobs (can cause CursorWindow/oom when scanning many rows).
    const String noSummaryCond =
        "r.segment_id IS NULL OR ((r.output_text IS NULL OR (LENGTH(r.output_text) <= 256 AND LOWER(TRIM(r.output_text)) IN ('','null'))) AND (r.structured_json IS NULL OR (LENGTH(r.structured_json) <= 256 AND LOWER(TRIM(r.structured_json)) IN ('','null'))))";
    const String hasSamplesCond =
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)";

    // 组合 WHERE 子句
    final List<String> whereClauses = <String>[
      _segmentsRootWhere('s'),
      "(s.segment_kind IS NULL OR s.segment_kind = 'global')",
    ];
    final List<Object?> whereParams = <Object?>[];

    List<String> pkgs = (appPackageNames ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (pkgs.isEmpty) {
      final String single = (appPackageName ?? '').trim();
      if (single.isNotEmpty) pkgs = <String>[single];
    }
    pkgs.sort();
    if (pkgs.length > 30) {
      pkgs = pkgs.take(30).toList(growable: false);
    }

    if (pkgs.isNotEmpty) {
      final String placeholders = List.filled(pkgs.length, '?').join(',');
      whereClauses.add(
        "EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id AND ss.app_package_name IN ($placeholders))",
      );
      whereParams.addAll(pkgs);
    } else if (requireSamples) {
      whereClauses.add(hasSamplesCond);
    }

    if (startMillis != null) {
      whereClauses.add('s.start_time >= ?');
      whereParams.add(startMillis);
    }
    if (endMillis != null) {
      whereClauses.add('s.start_time <= ?');
      whereParams.add(endMillis);
    }
    if (onlyNoSummary) {
      whereClauses.add('(' + noSummaryCond + ')');
    }

    final String whereSql = whereClauses.isEmpty
        ? ''
        : ('WHERE ' + whereClauses.join(' AND '));

    const int previewOutputTextChars = 2048;
    const int previewStructuredJsonChars = 32768;
    const int previewCategoriesChars = 2048;
    const int previewOverallSummaryChars = 8192;
    const String overallSummaryKeyPosSql = '''
      CASE
        WHEN INSTR(r.structured_json, '"overall_summary"') > 0
          THEN INSTR(r.structured_json, '"overall_summary"')
        WHEN INSTR(r.structured_json, char(92) || '"overall_summary' || char(92) || '"') > 0
          THEN INSTR(r.structured_json, char(92) || '"overall_summary' || char(92) || '"')
        ELSE 0
      END
    ''';
    final String resultColumnsSql = truncateResultColumns
        ? '''
          SUBSTR(r.output_text, 1, ?) AS output_text,
          CASE
            WHEN r.structured_json IS NULL THEN NULL
            WHEN LENGTH(r.structured_json) <= ? THEN r.structured_json
            ELSE SUBSTR(
              r.structured_json,
              MAX(1, $overallSummaryKeyPosSql),
              ?
            )
          END AS structured_json,
          SUBSTR(r.categories, 1, ?) AS categories,
          CASE WHEN r.output_text IS NOT NULL AND LENGTH(r.output_text) > ? THEN 1 ELSE 0 END AS output_text_truncated,
          CASE WHEN r.structured_json IS NOT NULL AND LENGTH(r.structured_json) > ? THEN 1 ELSE 0 END AS structured_json_truncated,
          CASE WHEN r.categories IS NOT NULL AND LENGTH(r.categories) > ? THEN 1 ELSE 0 END AS categories_truncated,
          CASE
            WHEN r.structured_json IS NULL THEN NULL
            WHEN $overallSummaryKeyPosSql <= 0 THEN NULL
            ELSE SUBSTR(
              r.structured_json,
              $overallSummaryKeyPosSql,
              ?
            )
          END AS overall_summary_preview
        '''
        : '''
          r.output_text,
          r.structured_json,
          r.categories,
          CASE
            WHEN r.structured_json IS NULL THEN NULL
            WHEN $overallSummaryKeyPosSql <= 0 THEN NULL
            ELSE SUBSTR(
              r.structured_json,
              $overallSummaryKeyPosSql,
              ?
            )
          END AS overall_summary_preview
        ''';
    final List<Object?> resultColumnParams = truncateResultColumns
        ? <Object?>[
            previewOutputTextChars,
            previewStructuredJsonChars,
            previewStructuredJsonChars,
            previewCategoriesChars,
            previewOutputTextChars,
            previewStructuredJsonChars,
            previewCategoriesChars,
            previewOverallSummaryChars,
          ]
        : const <Object?>[previewOverallSummaryChars];

    const int previewMergeDecisionJsonChars = 4096;
    const int previewMergeDecisionReasonChars = 2048;
    const String segmentColumnsSql = '''
          s.id,
          s.start_time,
          s.end_time,
          s.duration_sec,
          s.sample_interval_sec,
          s.status,
          s.segment_kind,
          s.app_packages,
          s.merge_attempted,
          s.merged_flag,
          s.merged_into_id,
          s.merge_prev_id,
          SUBSTR(s.merge_decision_json, 1, ?) AS merge_decision_json,
          SUBSTR(s.merge_decision_reason, 1, ?) AS merge_decision_reason,
          s.merge_forced,
          s.merge_decision_at,
          s.created_at,
          s.updated_at
        ''';
    final List<Object?> segmentColumnParams = <Object?>[
      previewMergeDecisionJsonChars,
      previewMergeDecisionReasonChars,
    ];

    final String sql =
        '''
        SELECT
          $segmentColumnsSql,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary,
          $resultColumnsSql
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        $whereSql
        ORDER BY s.start_time DESC, s.id DESC
        LIMIT ? OFFSET ?
      ''';

    try {
      final List<Object?> params = <Object?>[
        ...segmentColumnParams,
        ...resultColumnParams,
        ...whereParams,
        limit,
        safeOffset,
      ];
      final rows = await db.rawQuery(sql, params);
      return _attachSegmentSampleStats(
        db,
        rows.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    } catch (e) {
      try {
        await FlutterLogger.nativeWarn(
          'DB',
          'listSegmentsEx primary query failed, retrying with truncated result columns err=${e.toString()} onlyNoSummary=$onlyNoSummary requireSamples=$requireSamples startMillis=${startMillis?.toString() ?? 'null'} endMillis=${endMillis?.toString() ?? 'null'} limit=$limit offset=$offset',
        );
      } catch (_) {}

      // Fallback: Some Android devices/DB states can hit CursorWindow/row-too-big errors when
      // selecting large TEXT columns (output_text / structured_json) across many rows.
      // Retry with truncated result columns so the timeline won't go empty.
      try {
        const int maxOutputTextChars = 2048;
        const int maxStructuredJsonChars = 32768;
        const int maxCategoriesChars = 2048;
        final String fallbackSql =
            '''
        SELECT
          $segmentColumnsSql,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary,
          SUBSTR(r.output_text, 1, ?) AS output_text,
          CASE
            WHEN r.structured_json IS NULL THEN NULL
            -- Small JSON blobs are safe to return whole (keeps key_actions/image_tags usable on UI).
            WHEN LENGTH(r.structured_json) <= ? THEN r.structured_json
            -- For large JSON, return a window around overall_summary so the timeline can still show the summary
            -- without fetching megabytes into CursorWindow.
            ELSE SUBSTR(
              r.structured_json,
              MAX(1, $overallSummaryKeyPosSql),
              ?
            )
          END AS structured_json,
          SUBSTR(r.categories, 1, ?) AS categories,
          CASE WHEN r.output_text IS NOT NULL AND LENGTH(r.output_text) > ? THEN 1 ELSE 0 END AS output_text_truncated,
          CASE WHEN r.structured_json IS NOT NULL AND LENGTH(r.structured_json) > ? THEN 1 ELSE 0 END AS structured_json_truncated,
          CASE WHEN r.categories IS NOT NULL AND LENGTH(r.categories) > ? THEN 1 ELSE 0 END AS categories_truncated,
          CASE
            WHEN r.structured_json IS NULL THEN NULL
            WHEN $overallSummaryKeyPosSql <= 0 THEN NULL
            ELSE SUBSTR(
              r.structured_json,
              $overallSummaryKeyPosSql,
              ?
            )
          END AS overall_summary_preview
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        $whereSql
        ORDER BY s.start_time DESC, s.id DESC
        LIMIT ? OFFSET ?
      ''';

        final List<Object?> fallbackParams = <Object?>[
          // Placeholders appear in SELECT first (segment SUBSTR, result SUBSTR), then WHERE, then LIMIT/OFFSET.
          ...segmentColumnParams,
          maxOutputTextChars,
          maxStructuredJsonChars,
          maxStructuredJsonChars,
          maxCategoriesChars,
          maxOutputTextChars,
          maxStructuredJsonChars,
          maxCategoriesChars,
          previewOverallSummaryChars,
          ...whereParams,
          limit,
          safeOffset,
        ];
        final rows = await db.rawQuery(fallbackSql, fallbackParams);
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'listSegmentsEx fallback used (truncated result columns) limit=$limit offset=$offset',
          );
        } catch (_) {}
        return _attachSegmentSampleStats(
          db,
          rows.map((e) => Map<String, dynamic>.from(e)).toList(),
        );
      } catch (e2) {
        try {
          await FlutterLogger.nativeError(
            'DB',
            'listSegmentsEx fallback failed err=${e2.toString()}',
          );
        } catch (_) {}
        return <Map<String, dynamic>>[];
      }
    }
  }

  /// 触发一次原生端的段落推进/补救扫描（用于点击刷新时重试缺失总结）
  Future<bool> triggerSegmentTick() async {
    try {
      try {
        await FlutterLogger.nativeInfo('DB', 'triggerSegmentTick 调用');
      } catch (_) {}
      final res = await ScreenshotDatabase._channel.invokeMethod(
        'triggerSegmentTick',
      );
      try {
        await FlutterLogger.nativeInfo(
          'DB',
          'triggerSegmentTick 结果=${res == true} raw=${res?.toString() ?? 'null'}',
        );
      } catch (_) {}
      return res == true;
    } catch (e) {
      try {
        await FlutterLogger.nativeError(
          'DB',
          'triggerSegmentTick 失败 err=${e.toString()}',
        );
      } catch (_) {}
      return false;
    }
  }

  Future<bool> getDynamicAutoRepairEnabled() async {
    try {
      final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
        'getDynamicAutoRepairEnabled',
      );
      return raw == null ? true : raw == true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> setDynamicAutoRepairEnabled(bool enabled) async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'setDynamicAutoRepairEnabled',
      <String, dynamic>{'enabled': enabled},
    );
    return raw == null ? enabled : raw == true;
  }

  /// 通过原生接口按ID批量重试生成总结
  /// force=true 时无视已有结果与时间范围，直接强制重跑
  Future<int> retrySegments(List<int> ids, {bool force = false}) async {
    try {
      final res = await ScreenshotDatabase._channel.invokeMethod(
        'retrySegments',
        {'ids': ids, 'force': force},
      );
      if (res is int) return res;
      if (res is num) return res.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<DynamicRebuildTaskStatus> startDynamicRebuildTask({
    bool resumeExisting = false,
    int dayConcurrency = 1,
    String taskMode = 'rebuild',
    String? targetDayKey,
  }) async {
    final String normalizedTargetDayKey = (targetDayKey ?? '').trim();
    final dynamic raw = await ScreenshotDatabase._channel
        .invokeMethod('startDynamicRebuildTask', <String, dynamic>{
          'resumeExisting': resumeExisting,
          'dayConcurrency': dayConcurrency,
          'taskMode': taskMode,
          if (normalizedTargetDayKey.isNotEmpty)
            'targetDayKey': normalizedTargetDayKey,
        });
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  Future<DynamicRebuildTaskStatus> getDynamicRebuildTaskStatus() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'getDynamicRebuildTaskStatus',
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  Future<DynamicRebuildTaskStatus> ensureDynamicRebuildTaskResumed() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'ensureDynamicRebuildTaskResumed',
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  Future<DynamicRebuildTaskStatus> cancelDynamicRebuildTask() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'cancelDynamicRebuildTask',
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  Future<DynamicRebuildTaskStatus> clearDynamicRebuildTask() async {
    final dynamic raw = await ScreenshotDatabase._channel.invokeMethod(
      'clearDynamicRebuildTask',
    );
    if (raw is Map) {
      return DynamicRebuildTaskStatus.fromMap(raw);
    }
    return DynamicRebuildTaskStatus.fromMap(null);
  }

  /// 强制将某个事件与其上一事件合并（跳过 same_event 判定，直接执行合并总结）
  /// - prevId 可选：指定要合并的上一事件ID（否则由原生侧自动选择）
  Future<bool> forceMergeSegment(int id, {int? prevId}) async {
    try {
      final res = await ScreenshotDatabase._channel.invokeMethod(
        'forceMergeSegment',
        {'id': id, if (prevId != null && prevId > 0) 'prev_id': prevId},
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listSegmentSamples(int segmentId) async {
    final db = await database;
    try {
      final String sql = '''
        SELECT
          s.id,
          s.segment_id,
          s.capture_time,
          s.file_path,
          s.app_package_name,
          s.app_name,
          s.position_index,
          totals.appearance_count,
          totals.appearance_count AS segment_occurrence_count,
          totals.distinct_day_count,
          totals.distinct_day_count AS cross_day_count
        FROM segment_samples s
        JOIN (
          SELECT
            segment_id,
            COUNT(*) AS appearance_count,
            COUNT(
              DISTINCT strftime(
                '%Y-%m-%d',
                datetime(capture_time / 1000, 'unixepoch', 'localtime')
              )
            ) AS distinct_day_count
          FROM segment_samples
          WHERE segment_id = ?
          GROUP BY segment_id
        ) totals ON totals.segment_id = s.segment_id
        WHERE s.segment_id = ?
        ORDER BY s.position_index ASC
      ''';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ${sql.replaceAll('?', segmentId.toString())}',
        );
      } catch (_) {}
      final List<Map<String, Object?>> rows = await db.rawQuery(sql, <Object?>[
        segmentId,
        segmentId,
      ]);
      return rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> listLatestSamples({int limit = 10}) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segment_samples',
        orderBy: 'capture_time DESC, id DESC',
        limit: limit,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 列出某个 segment 内最新的 N 条样本（按 capture_time DESC）。
  Future<List<Map<String, dynamic>>> listLatestSamplesInSegment(
    int segmentId, {
    int limit = 1000,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'segment_samples',
        where: 'segment_id = ?',
        whereArgs: <Object?>[segmentId],
        orderBy: 'capture_time DESC, id DESC',
        limit: limit,
      );
      return rows;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getSegmentResult(int segmentId) async {
    final db = await database;
    try {
      final String sql =
          'SELECT segment_id, ai_provider, ai_model, output_text, structured_json, categories, created_at FROM segment_results WHERE segment_id = ? LIMIT 1';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ' + sql.replaceAll('?', segmentId.toString()),
        );
      } catch (_) {}
      final rows = await db.query(
        'segment_results',
        where: 'segment_id = ?',
        whereArgs: [segmentId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  bool _isBlankDynamicResultText(String? value) {
    final String v = (value ?? '').trim();
    return v.isEmpty || v.toLowerCase() == 'null';
  }

  bool _isTruthyJsonFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value.toInt() != 0;
    if (value is String) {
      final String v = value.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'yes';
    }
    return false;
  }

  bool _isDynamicStructuredJsonCompliantForBackfill(String? value) {
    final String sj = (value ?? '').trim();
    if (sj.isEmpty || sj.toLowerCase() == 'null') return false;
    try {
      final dynamic decoded = jsonDecode(sj);
      if (decoded is! Map) return false;
      final dynamic meta = decoded['_meta'];
      if (meta is Map && _isTruthyJsonFlag(meta['needs_manual_retry'])) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _needsDynamicSummaryRepairForBackfill({
    required String? outputText,
    required String? structuredJson,
  }) {
    if (_isBlankDynamicResultText(outputText) &&
        _isBlankDynamicResultText(structuredJson)) {
      return true;
    }
    return !_isDynamicStructuredJsonCompliantForBackfill(structuredJson);
  }

  Future<Map<String, dynamic>?> getDynamicBackfillEligibility(
    int segmentId,
  ) async {
    if (segmentId <= 0) return null;
    final db = await database;
    try {
      final rows = await db.rawQuery(
        '''
        SELECT
          s.id,
          s.status,
          s.segment_kind,
          s.merged_into_id,
          CASE
            WHEN s.merged_into_id IS NULL OR s.merged_into_id <= 0
              OR NOT EXISTS (SELECT 1 FROM segments root WHERE root.id = s.merged_into_id)
            THEN 1 ELSE 0
          END AS is_root,
          r.output_text,
          r.structured_json
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        WHERE s.id = ?
        LIMIT 1
        ''',
        <Object?>[segmentId],
      );
      if (rows.isEmpty) {
        return <String, dynamic>{
          'segment_id': segmentId,
          'exists': false,
          'would_queue': false,
          'reason': '动态不存在，补全队列无法选中。',
        };
      }

      final row = rows.first;
      final String status = (row['status'] as String?)?.trim() ?? '';
      final String segmentKind = (row['segment_kind'] as String?)?.trim() ?? '';
      final bool isGlobalKind = segmentKind.isEmpty || segmentKind == 'global';
      final bool isRoot = ((row['is_root'] as int?) ?? 0) != 0;
      final String? outputText = row['output_text'] as String?;
      final String? structuredJson = row['structured_json'] as String?;
      final bool outputBlank = _isBlankDynamicResultText(outputText);
      final bool structuredCompliant =
          _isDynamicStructuredJsonCompliantForBackfill(structuredJson);
      final bool needsRepair = _needsDynamicSummaryRepairForBackfill(
        outputText: outputText,
        structuredJson: structuredJson,
      );
      final bool wouldQueue =
          status == 'completed' && isGlobalKind && isRoot && needsRepair;

      String reason;
      if (wouldQueue) {
        reason = '当前数据库状态符合手动“补全”的队列条件，会被加入待补全清单。';
      } else if (status != 'completed') {
        reason = '当前动态状态为 $status，不是 completed，手动补全队列会跳过。';
      } else if (!isGlobalKind) {
        reason = '当前动态不是 global 顶层动态类型，手动补全队列会跳过。';
      } else if (!isRoot) {
        reason = '当前动态已合并到其它动态，手动补全只处理顶层动态。';
      } else if (!needsRepair) {
        reason = '当前结果已存在且 structured_json 合规，手动补全会认为无需重跑。';
      } else {
        reason = '当前数据库状态不符合手动补全队列条件。';
      }

      return <String, dynamic>{
        'segment_id': segmentId,
        'exists': true,
        'would_queue': wouldQueue,
        'reason': reason,
        'status': status,
        'segment_kind': segmentKind,
        'is_root': isRoot,
        'output_blank': outputBlank,
        'structured_json_compliant': structuredCompliant,
        'needs_repair': needsRepair,
      };
    } catch (e) {
      return <String, dynamic>{
        'segment_id': segmentId,
        'exists': null,
        'would_queue': null,
        'reason': '读取补全队列状态失败：$e',
      };
    }
  }

  // ===================== AI 图片元数据（全局复用） =====================

  Future<Map<String, dynamic>?> getAiImageMetaByFilePath(
    String filePath,
  ) async {
    final String p = filePath.trim();
    if (p.isEmpty) return null;
    final db = await database;
    try {
      final rows = await db.query(
        'ai_image_meta',
        where: 'file_path = ?',
        whereArgs: <Object?>[p],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// 批量查询 AI 图片元数据（key=file_path）。
  ///
  /// - 内部会自动去重与分批，避免 SQLite 参数上限。
  Future<Map<String, Map<String, dynamic>>> getAiImageMetaByFilePaths(
    List<String> filePaths,
  ) async {
    final List<String> paths = filePaths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (paths.isEmpty) return <String, Map<String, dynamic>>{};

    final db = await database;
    final Map<String, Map<String, dynamic>> out =
        <String, Map<String, dynamic>>{};

    // SQLite 参数默认上限 999，这里保守分批。
    const int chunkSize = 400;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final int end = (i + chunkSize) > paths.length
          ? paths.length
          : (i + chunkSize);
      final List<String> chunk = paths.sublist(i, end);
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final List<Map<String, Object?>> rows = await db.query(
        'ai_image_meta',
        where: 'file_path IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final r in rows) {
        final String? fp = r['file_path'] as String?;
        if (fp == null || fp.isEmpty) continue;
        out[fp] = Map<String, dynamic>.from(r);
      }
    }
    return out;
  }

  /// 批量查询“动态（segment）里标记为 NSFW”的截图文件路径集合。
  ///
  /// 说明：
  /// - 用于把“动态里的 NSFW 标签”传播到全局（截图列表/时间线/搜索）。
  /// - 仅返回命中 NSFW 的 file_path 集合；未命中的 file_path 视为“非 NSFW”。
  Future<Set<String>> getSegmentNsfwFilePaths(List<String> filePaths) async {
    final List<String> paths = filePaths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (paths.isEmpty) return <String>{};

    final db = await database;

    String basenameOf(String path) {
      final normalized = path.trim().replaceAll('\\', '/');
      final int idx = normalized.lastIndexOf('/');
      return idx >= 0 ? normalized.substring(idx + 1) : normalized;
    }

    Set<String> parseNsfwBasenamesFromStructuredJson(String raw) {
      final String s = raw.trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return <String>{};
      try {
        final decoded = jsonDecode(s);
        if (decoded is! Map) return <String>{};
        final dynamic rawTags = decoded['image_tags'];
        if (rawTags is! List) return <String>{};
        final Set<String> out = <String>{};

        bool containsExactNsfw(dynamic tags) {
          if (tags == null) return false;
          if (tags is List) {
            return tags.any((t) => t.toString().trim().toLowerCase() == 'nsfw');
          }
          if (tags is String) {
            final String tt = tags.trim();
            if (tt.isEmpty) return false;
            try {
              final dynamic v = jsonDecode(tt);
              if (v is List) {
                return v.any(
                  (t) => t.toString().trim().toLowerCase() == 'nsfw',
                );
              }
              if (v is String) {
                return v
                    .split(RegExp(r'[，,;；\s]+'))
                    .any((e) => e.trim().toLowerCase() == 'nsfw');
              }
            } catch (_) {}
            return tt
                .split(RegExp(r'[，,;；\s]+'))
                .any((e) => e.trim().toLowerCase() == 'nsfw');
          }
          return false;
        }

        for (final e in rawTags) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final String file = (m['file'] ?? '').toString().trim();
          if (file.isEmpty) continue;
          final String bn = basenameOf(file);

          final bool nsfw = containsExactNsfw(m['tags']);

          if (nsfw) out.add(bn);
        }
        return out;
      } catch (_) {
        return <String>{};
      }
    }

    // 1) 先查 file_path -> segment_id 映射
    final Map<int, List<String>> filePathsBySegment = <int, List<String>>{};
    const int chunkSize = 400;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final int end = (i + chunkSize) > paths.length
          ? paths.length
          : (i + chunkSize);
      final List<String> chunk = paths.sublist(i, end);
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final String sql =
          '''
        SELECT file_path, segment_id
        FROM segment_samples
        WHERE file_path IN ($placeholders)
      ''';
      final rows = await db.rawQuery(sql, chunk);
      for (final r in rows) {
        final String? fp = r['file_path'] as String?;
        final int sid = (r['segment_id'] as int?) ?? 0;
        if (fp == null || fp.trim().isEmpty) continue;
        if (sid <= 0) continue;
        filePathsBySegment.putIfAbsent(sid, () => <String>[]).add(fp.trim());
      }
    }
    if (filePathsBySegment.isEmpty) return <String>{};

    // 2) 批量取 segment_results.structured_json，并解析 image_tags[] 里的 nsfw 文件名
    final List<int> segmentIds = filePathsBySegment.keys.toList(
      growable: false,
    );
    final Map<int, Set<String>> nsfwBasenamesBySegment = <int, Set<String>>{};

    for (int i = 0; i < segmentIds.length; i += chunkSize) {
      final int end = (i + chunkSize) > segmentIds.length
          ? segmentIds.length
          : (i + chunkSize);
      final List<int> chunk = segmentIds.sublist(i, end);
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final String sql =
          '''
        SELECT segment_id, structured_json
        FROM segment_results
        WHERE segment_id IN ($placeholders)
      ''';
      final rows = await db.rawQuery(sql, chunk);
      for (final r in rows) {
        final int sid = (r['segment_id'] as int?) ?? 0;
        if (sid <= 0) continue;
        final String sj = (r['structured_json'] as String?)?.toString() ?? '';
        final Set<String> basenames = parseNsfwBasenamesFromStructuredJson(sj);
        if (basenames.isNotEmpty) {
          nsfwBasenamesBySegment[sid] = basenames;
        }
      }
    }

    // 3) 将 nsfw basenames 映射回入参 file_path（按 basename 匹配）
    final Set<String> out = <String>{};
    for (final entry in filePathsBySegment.entries) {
      final Set<String>? basenames = nsfwBasenamesBySegment[entry.key];
      if (basenames == null || basenames.isEmpty) continue;
      for (final fp in entry.value) {
        final String bn = basenameOf(fp);
        if (basenames.contains(bn)) {
          out.add(fp);
        }
      }
    }
    return out;
  }

  /// 索引可用性：检测 SQLite 是否支持 AI 图片元数据 FTS（fts5）。
  Future<bool> isAiImageMetaIndexAvailable() async {
    try {
      final db = await database;
      return await _tableExists(db, 'ai_image_meta_fts');
    } catch (_) {
      return false;
    }
  }

  /// Resolve app package names by app display names using app_registry.
  ///
  /// Notes:
  /// - Tool calling prefers human app names to avoid hallucinated package names.
  /// - We still search/filter by package name internally (more stable/unique).
  Future<List<String>> findPackagesByAppNames(List<String> appNames) async {
    final List<String> names = appNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (names.isEmpty) return <String>[];

    // Guard: SQLite has a hard parameter limit; keep this small.
    final List<String> limited = (names.length > 30)
        ? (names..sort()).take(30).toList(growable: false)
        : (names..sort());

    try {
      final db = await database;
      final String placeholders = List.filled(limited.length, '?').join(',');
      final rows = await db.query(
        'app_registry',
        columns: ['app_package_name'],
        where: 'app_name COLLATE NOCASE IN ($placeholders)',
        whereArgs: limited,
      );
      return rows
          .map((r) => (r['app_package_name'] as String?)?.trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } catch (_) {
      return <String>[];
    }
  }

  /// 列出“有动态总结”的应用显示名（去重）。
  ///
  /// 口径：
  /// - 仅统计全局段落（global），并排除已被合并的子段。
  /// - 仅包含存在有效总结结果的段落（output_text / structured_json 任一非空且非 "null"）。
  /// - 应用名优先取 segment_samples.app_name；为空时回退 app_registry.app_name。
  Future<List<String>> listAppDisplayNamesWithSegmentSummaries({
    int limit = 200,
  }) async {
    final int safeLimit = limit.clamp(1, 500).toInt();
    try {
      final db = await database;
      final String sql =
          '''
        SELECT DISTINCT
          COALESCE(NULLIF(TRIM(ss.app_name), ''), NULLIF(TRIM(ar.app_name), '')) AS app_name
        FROM segments s
        JOIN segment_results r ON r.segment_id = s.id
        JOIN segment_samples ss ON ss.segment_id = s.id
        LEFT JOIN app_registry ar ON ar.app_package_name = ss.app_package_name
        WHERE ${_segmentsRootWhere('s')}
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND (
            (r.output_text IS NOT NULL AND LOWER(TRIM(r.output_text)) NOT IN ('','null'))
            OR
            (r.structured_json IS NOT NULL AND LOWER(TRIM(r.structured_json)) NOT IN ('','null'))
          )
          AND COALESCE(NULLIF(TRIM(ss.app_name), ''), NULLIF(TRIM(ar.app_name), '')) IS NOT NULL
        ORDER BY LOWER(app_name) COLLATE NOCASE ASC
        LIMIT ?
      ''';
      final List<Map<String, Object?>> rows = await db.rawQuery(sql, <Object?>[
        safeLimit,
      ]);
      final List<String> out = <String>[];
      final Set<String> dedup = <String>{};
      for (final Map<String, Object?> row in rows) {
        final String name = (row['app_name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final String key = name.toLowerCase();
        if (dedup.add(key)) out.add(name);
      }
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  /// 搜索 AI 图片元数据（tags/description），用于“无 OCR 或 OCR 不足”的图片检索。
  ///
  /// - 优先使用 FTS；如 FTS 不可用或命中为空，则回退 LIKE（更适配中文子串）。
  /// - 支持按时间范围过滤（capture_time）。
  Future<List<Map<String, dynamic>>> searchAiImageMetaByText(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    bool includeNsfw = false,
    List<String>? appPackageNames,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database;
    final AdvancedSearchQuery? adv = queryAdvanced;
    final String q0 = query.trim();
    final String q = (adv != null) ? adv.toPlainText() : q0;
    if (q.isEmpty) return <Map<String, dynamic>>[];

    final int fetchLimit = (limit ?? 50).clamp(1, 50);
    int fetchOffset = offset ?? 0;
    if (fetchOffset < 0) fetchOffset = 0;

    bool isLikelyCjkNoSpaces() {
      if (q.contains(' ')) return false;
      return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
    }

    Future<List<Map<String, dynamic>>> runFts() async {
      final bool ftsExists = await _tableExists(db, 'ai_image_meta_fts');
      if (!ftsExists) return <Map<String, dynamic>>[];

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 6,
              matchAllTerms: true,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
      final List<Object?> args = <Object?>[match];
      final List<String> filters = <String>[];
      if (!includeNsfw) {
        filters.add('m.nsfw = 0');
      }
      if (startMillis != null) {
        filters.add('m.capture_time >= ?');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('m.capture_time <= ?');
        args.add(endMillis);
      }

      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        filters.add('ss.app_package_name IN ($placeholders)');
        args.addAll(appPkgs);
      }

      final String whereClause = filters.isEmpty
          ? ''
          : 'AND ${filters.join(' AND ')}';
      final String sql =
          '''
        SELECT
          m.file_path,
          m.tags_json,
          m.description,
          m.description_range,
          m.nsfw,
          m.segment_id,
          m.capture_time,
          m.lang,
          m.updated_at,
          ss.app_package_name,
          ss.app_name
        FROM ai_image_meta_fts fts
        JOIN ai_image_meta m ON m.rowid = fts.rowid
        LEFT JOIN segment_samples ss
          ON ss.segment_id = m.segment_id AND ss.file_path = m.file_path
        WHERE ai_image_meta_fts MATCH ?
          $whereClause
        ORDER BY bm25(ai_image_meta_fts, 3.0, 2.0, 1.0) ASC, m.capture_time DESC
        LIMIT ? OFFSET ?
      ''';
      args.add(fetchLimit);
      args.add(fetchOffset);
      final rows = await db.rawQuery(sql, args);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    Future<List<Map<String, dynamic>>> runLike() async {
      bool addTermLike(String term, List<Object?> args, List<String> filters) {
        final String t = term.trim();
        if (t.isEmpty) return false;
        final String likeTerm = '%$t%';
        args.add(likeTerm);
        args.add(likeTerm);
        filters.add('(m.description LIKE ? OR m.tags_json LIKE ?)');
        return true;
      }

      // Build LIKE filters from advanced spec when provided.
      final List<Object?> args = <Object?>[];
      final List<String> filters = <String>[];

      if (adv != null) {
        final AdvancedSearchLikeQuery like = adv.toLikeSpec(
          maxGroups: 10,
          maxTokensPerGroup: 6,
        );

        for (final phrase in like.mustPhrases) {
          addTermLike(phrase, args, filters);
        }

        for (final group in like.mustGroups) {
          for (final tok in group) {
            addTermLike(tok, args, filters);
          }
        }

        final List<String> anyClauses = <String>[];
        final List<Object?> anyArgs = <Object?>[];
        for (final phrase in like.anyPhrases) {
          final List<Object?> gArgs = <Object?>[];
          final List<String> gFilters = <String>[];
          if (addTermLike(phrase, gArgs, gFilters)) {
            anyClauses.add(gFilters.single);
            anyArgs.addAll(gArgs);
          }
        }
        for (final group in like.anyGroups) {
          final List<String> gClauses = <String>[];
          final List<Object?> gArgs = <Object?>[];
          for (final tok in group) {
            final List<Object?> tArgs = <Object?>[];
            final List<String> tFilters = <String>[];
            if (addTermLike(tok, tArgs, tFilters)) {
              gClauses.add(tFilters.single);
              gArgs.addAll(tArgs);
            }
          }
          if (gClauses.isNotEmpty) {
            anyClauses.add(
              gClauses.length == 1
                  ? gClauses.single
                  : '(${gClauses.join(' AND ')})',
            );
            anyArgs.addAll(gArgs);
          }
        }
        if (anyClauses.isNotEmpty) {
          filters.add(
            anyClauses.length == 1
                ? anyClauses.single
                : '(${anyClauses.join(' OR ')})',
          );
          args.addAll(anyArgs);
        }

        for (final group in like.notGroups) {
          final List<String> gClauses = <String>[];
          final List<Object?> gArgs = <Object?>[];
          for (final tok in group) {
            final String t = tok.trim();
            if (t.isEmpty) continue;
            final String likeTerm = '%$t%';
            gArgs.addAll(<Object?>[likeTerm, likeTerm]);
            gClauses.add('(m.description LIKE ? OR m.tags_json LIKE ?)');
          }
          if (gClauses.isNotEmpty) {
            final String inner = gClauses.length == 1
                ? gClauses.single
                : '(${gClauses.join(' AND ')})';
            filters.add('NOT ($inner)');
            args.addAll(gArgs);
          }
        }
      } else {
        // Simple query: substring match (better for CJK) across description/tags.
        addTermLike(q, args, filters);
      }

      if (filters.isEmpty) return <Map<String, dynamic>>[];
      if (!includeNsfw) {
        filters.add('m.nsfw = 0');
      }
      if (startMillis != null) {
        filters.add('m.capture_time >= ?');
        args.add(startMillis);
      }
      if (endMillis != null) {
        filters.add('m.capture_time <= ?');
        args.add(endMillis);
      }

      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        filters.add('ss.app_package_name IN ($placeholders)');
        args.addAll(appPkgs);
      }
      args.add(fetchLimit);
      args.add(fetchOffset);
      final String sql =
          '''
        SELECT
          m.file_path,
          m.tags_json,
          m.description,
          m.description_range,
          m.nsfw,
          m.segment_id,
          m.capture_time,
          m.lang,
          m.updated_at,
          ss.app_package_name,
          ss.app_name
        FROM ai_image_meta m
        LEFT JOIN segment_samples ss
          ON ss.segment_id = m.segment_id AND ss.file_path = m.file_path
        WHERE ${filters.join(' AND ')}
        ORDER BY m.capture_time DESC
        LIMIT ? OFFSET ?
      ''';
      final rows = await db.rawQuery(sql, args);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    try {
      // 中文无空格关键词更偏向子串检索，先走 LIKE 可减少“FTS 命中为空”的误判。
      if (isLikelyCjkNoSpaces()) {
        final likeRows = await runLike();
        if (likeRows.isNotEmpty) return likeRows;
      }

      final ftsRows = await runFts();
      if (ftsRows.isNotEmpty) return ftsRows;

      // FTS 命中为空时再回退 LIKE，提升中文/短词命中率。
      return await runLike();
    } catch (e) {
      try {
        await FlutterLogger.nativeWarn(
          'DB',
          'searchAiImageMetaByText failed, fallback to LIKE: $e',
        );
      } catch (_) {}
      try {
        return await runLike();
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
  }

  /// 搜索动态（segment）内容
  /// 支持搜索 AI 摘要文本和分类标签
  Future<List<Map<String, dynamic>>> searchSegmentsByText(
    String query, {
    int? limit,
    int? offset,
    int? startMillis,
    int? endMillis,
    List<String>? appPackageNames,
    bool matchAllTerms = true,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database;
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
      if (q.isEmpty) return <Map<String, dynamic>>[];

      final int fetchLimit = limit ?? 50;
      final int fetchOffset = offset ?? 0;

      bool isLikelyCjkNoSpaces() {
        if (q.contains(' ')) return false;
        return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
      }

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: matchAllTerms,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
      final List<String> baseFilters = <String>[];
      final List<Object?> baseArgs = <Object?>[];

      baseFilters.add(_segmentsRootWhere('s'));
      if (startMillis != null) {
        baseFilters.add('s.start_time >= ?');
        baseArgs.add(startMillis);
      }
      if (endMillis != null) {
        baseFilters.add('s.start_time <= ?');
        baseArgs.add(endMillis);
      }
      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        baseFilters.add(
          'EXISTS (SELECT 1 FROM segment_samples ss0 WHERE ss0.segment_id = s.id AND ss0.app_package_name IN ($placeholders))',
        );
        baseArgs.addAll(appPkgs);
      }

      final String whereClause = baseFilters.isEmpty
          ? ''
          : 'AND ${baseFilters.join(' AND ')}';

      Future<List<Map<String, dynamic>>> runFts() async {
        final bool ftsExists = await _tableExists(db, 'segment_results_fts');
        if (!ftsExists) return <Map<String, dynamic>>[];

        final List<Object?> args = <Object?>[
          match,
          ...baseArgs,
          fetchLimit,
          fetchOffset,
        ];
        final String sql =
            '''
          SELECT
            s.*,
            r.output_text,
            r.structured_json,
            r.categories,
            r.ai_provider,
            r.ai_model,
            COALESCE(
              NULLIF(TRIM(s.app_packages), ''),
              (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
            ) AS app_packages_display,
            (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count
          FROM segment_results_fts fts
          JOIN segment_results r ON r.segment_id = fts.rowid
          JOIN segments s ON s.id = r.segment_id
        WHERE segment_results_fts MATCH ?
            $whereClause
          ORDER BY bm25(segment_results_fts, 4.0, 1.0, 3.0) ASC, s.start_time DESC
          LIMIT ? OFFSET ?
        ''';
        final rows = await db.rawQuery(sql, args);
        return rows.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      Future<List<Map<String, dynamic>>> runLike() async {
        bool addLikeTermClause(
          String term,
          List<Object?> args,
          List<String> clauses,
        ) {
          final String t = term.trim();
          if (t.isEmpty) return false;
          final String likeTerm = '%$t%';
          args.addAll(<Object?>[likeTerm, likeTerm, likeTerm]);
          clauses.add(
            '(r.output_text LIKE ? OR r.categories LIKE ? OR r.structured_json LIKE ?)',
          );
          return true;
        }

        final List<Object?> args = <Object?>[];
        final List<String> filters = <String>[];

        if (adv != null) {
          final AdvancedSearchLikeQuery like = adv.toLikeSpec(
            maxGroups: 10,
            maxTokensPerGroup: 6,
          );

          // Required phrases.
          for (final phrase in like.mustPhrases) {
            addLikeTermClause(phrase, args, filters);
          }

          // Required keyword groups (AND across groups; within group: AND).
          for (final group in like.mustGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              filters.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              args.addAll(gArgs);
            }
          }

          // Optional OR group(s).
          final List<String> anyClauses = <String>[];
          final List<Object?> anyArgs = <Object?>[];

          for (final phrase in like.anyPhrases) {
            final List<String> pClauses = <String>[];
            final List<Object?> pArgs = <Object?>[];
            if (addLikeTermClause(phrase, pArgs, pClauses)) {
              anyClauses.add(pClauses.single);
              anyArgs.addAll(pArgs);
            }
          }

          for (final group in like.anyGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              anyClauses.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              anyArgs.addAll(gArgs);
            }
          }

          if (anyClauses.isNotEmpty) {
            filters.add(
              anyClauses.length == 1
                  ? anyClauses.single
                  : '(${anyClauses.join(' OR ')})',
            );
            args.addAll(anyArgs);
          }

          // Exclusions.
          for (final group in like.notGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              final String inner = gClauses.length == 1
                  ? gClauses.single
                  : '(${gClauses.join(' AND ')})';
              filters.add('NOT ($inner)');
              args.addAll(gArgs);
            }
          }
        } else {
          final parts = q
              .split(RegExp(r'\s+'))
              .where((e) => e.isNotEmpty)
              .toList();
          final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
          final List<String> tokenFilters = <String>[];
          for (final w in limited) {
            final List<String> tClauses = <String>[];
            final List<Object?> tArgs = <Object?>[];
            if (addLikeTermClause(w, tArgs, tClauses)) {
              tokenFilters.add(tClauses.single);
              args.addAll(tArgs);
            }
          }
          final String tokensClause = tokenFilters.isEmpty
              ? '1 = 1'
              : (tokenFilters.length == 1
                    ? tokenFilters.single
                    : '(${tokenFilters.join(matchAllTerms ? ' AND ' : ' OR ')})');
          filters.insert(0, tokensClause);
        }

        // Keep arg order aligned: LIKE terms first, then base filters.
        filters.addAll(baseFilters);
        if (filters.isEmpty) return <Map<String, dynamic>>[];
        args.addAll(baseArgs);
        args.addAll(<Object?>[fetchLimit, fetchOffset]);
        final String sql =
            '''
          SELECT
            s.*,
            r.output_text,
            r.structured_json,
            r.categories,
            r.ai_provider,
            r.ai_model,
            COALESCE(
              NULLIF(TRIM(s.app_packages), ''),
              (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
            ) AS app_packages_display,
            (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count
          FROM segments s
          JOIN segment_results r ON r.segment_id = s.id
          WHERE ${filters.join(' AND ')}
          ORDER BY s.start_time DESC
          LIMIT ? OFFSET ?
        ''';
        final rows = await db.rawQuery(sql, args);
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

        // FTS 命中为空时回退 LIKE，覆盖 structured_json（合并原始事件等）与短词场景。
        return await runLike();
      } catch (ftsError) {
        // FTS 不可用/异常：回退 LIKE
        try {
          await FlutterLogger.nativeWarn('DB', 'FTS 搜索失败，回退到 LIKE：$ftsError');
        } catch (_) {}
        return await runLike();
      }
    } catch (e) {
      try {
        await FlutterLogger.nativeError('DB', 'searchSegmentsByText 失败：$e');
      } catch (_) {}
      return <Map<String, dynamic>>[];
    }
  }

  /// 统计搜索动态结果总数
  Future<int> countSegmentsByText(
    String query, {
    int? startMillis,
    int? endMillis,
    List<String>? appPackageNames,
    bool matchAllTerms = true,
    bool allowAdvanced = true,
    AdvancedSearchQuery? queryAdvanced,
  }) async {
    final db = await database;
    try {
      final AdvancedSearchQuery? adv = queryAdvanced;
      final String q0 = query.trim();
      final String q = (adv != null) ? adv.toPlainText() : q0;
      if (q.isEmpty) return 0;

      bool isLikelyCjkNoSpaces() {
        if (q.contains(' ')) return false;
        return RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
      }

      final String match = (adv != null)
          ? adv.toFtsMatch(maxGroups: 10, maxTokensPerGroup: 6)
          : ScreenshotDatabase._buildFtsMatchQuery(
              q,
              maxTerms: 5,
              matchAllTerms: matchAllTerms,
              prefix: true,
              allowAdvanced: allowAdvanced,
            );
      final List<String> baseFilters = <String>[];
      final List<Object?> baseArgs = <Object?>[];

      baseFilters.add(_segmentsRootWhere('s'));
      if (startMillis != null) {
        baseFilters.add('s.start_time >= ?');
        baseArgs.add(startMillis);
      }
      if (endMillis != null) {
        baseFilters.add('s.start_time <= ?');
        baseArgs.add(endMillis);
      }
      final List<String> appPkgs = (appPackageNames ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (appPkgs.isNotEmpty) {
        final String placeholders = List.filled(appPkgs.length, '?').join(',');
        baseFilters.add(
          'EXISTS (SELECT 1 FROM segment_samples ss0 WHERE ss0.segment_id = s.id AND ss0.app_package_name IN ($placeholders))',
        );
        baseArgs.addAll(appPkgs);
      }

      final String whereClause = baseFilters.isEmpty
          ? ''
          : 'AND ${baseFilters.join(' AND ')}';

      Future<int> runFtsCount() async {
        final bool ftsExists = await _tableExists(db, 'segment_results_fts');
        if (!ftsExists) return 0;
        final List<Object?> args = <Object?>[match, ...baseArgs];
        final String sql =
            '''
          SELECT COUNT(*) AS c
          FROM segment_results_fts fts
          JOIN segment_results r ON r.segment_id = fts.rowid
          JOIN segments s ON s.id = r.segment_id
          WHERE segment_results_fts MATCH ?
            $whereClause
        ''';
        final rows = await db.rawQuery(sql, args);
        return (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
      }

      Future<int> runLikeCount() async {
        bool addLikeTermClause(
          String term,
          List<Object?> args,
          List<String> clauses,
        ) {
          final String t = term.trim();
          if (t.isEmpty) return false;
          final String likeTerm = '%$t%';
          args.addAll(<Object?>[likeTerm, likeTerm, likeTerm]);
          clauses.add(
            '(r.output_text LIKE ? OR r.categories LIKE ? OR r.structured_json LIKE ?)',
          );
          return true;
        }

        final List<Object?> args = <Object?>[];
        final List<String> filters = <String>[];

        if (adv != null) {
          final AdvancedSearchLikeQuery like = adv.toLikeSpec(
            maxGroups: 10,
            maxTokensPerGroup: 6,
          );

          for (final phrase in like.mustPhrases) {
            addLikeTermClause(phrase, args, filters);
          }

          for (final group in like.mustGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              filters.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              args.addAll(gArgs);
            }
          }

          final List<String> anyClauses = <String>[];
          final List<Object?> anyArgs = <Object?>[];

          for (final phrase in like.anyPhrases) {
            final List<String> pClauses = <String>[];
            final List<Object?> pArgs = <Object?>[];
            if (addLikeTermClause(phrase, pArgs, pClauses)) {
              anyClauses.add(pClauses.single);
              anyArgs.addAll(pArgs);
            }
          }

          for (final group in like.anyGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              anyClauses.add(
                gClauses.length == 1
                    ? gClauses.single
                    : '(${gClauses.join(' AND ')})',
              );
              anyArgs.addAll(gArgs);
            }
          }

          if (anyClauses.isNotEmpty) {
            filters.add(
              anyClauses.length == 1
                  ? anyClauses.single
                  : '(${anyClauses.join(' OR ')})',
            );
            args.addAll(anyArgs);
          }

          for (final group in like.notGroups) {
            final List<String> gClauses = <String>[];
            final List<Object?> gArgs = <Object?>[];
            for (final tok in group) {
              final List<String> tClauses = <String>[];
              final List<Object?> tArgs = <Object?>[];
              if (addLikeTermClause(tok, tArgs, tClauses)) {
                gClauses.add(tClauses.single);
                gArgs.addAll(tArgs);
              }
            }
            if (gClauses.isNotEmpty) {
              final String inner = gClauses.length == 1
                  ? gClauses.single
                  : '(${gClauses.join(' AND ')})';
              filters.add('NOT ($inner)');
              args.addAll(gArgs);
            }
          }
        } else {
          final parts = q
              .split(RegExp(r'\s+'))
              .where((e) => e.isNotEmpty)
              .toList();
          final limited = parts.length > 5 ? parts.sublist(0, 5) : parts;
          final List<String> tokenFilters = <String>[];
          for (final w in limited) {
            final List<String> tClauses = <String>[];
            final List<Object?> tArgs = <Object?>[];
            if (addLikeTermClause(w, tArgs, tClauses)) {
              tokenFilters.add(tClauses.single);
              args.addAll(tArgs);
            }
          }
          final String tokensClause = tokenFilters.isEmpty
              ? '1 = 1'
              : (tokenFilters.length == 1
                    ? tokenFilters.single
                    : '(${tokenFilters.join(matchAllTerms ? ' AND ' : ' OR ')})');
          filters.add(tokensClause);
        }

        filters.addAll(baseFilters);
        args.addAll(baseArgs);
        final String sql =
            '''
          SELECT COUNT(*) AS c
          FROM segments s
          JOIN segment_results r ON r.segment_id = s.id
          WHERE ${filters.join(' AND ')}
        ''';
        final rows = await db.rawQuery(sql, args);
        return (rows.isNotEmpty ? ((rows.first['c'] as int?) ?? 0) : 0);
      }

      try {
        if (isLikelyCjkNoSpaces()) {
          final c = await runLikeCount();
          if (c > 0) return c;
        }
        final c = await runFtsCount();
        if (c > 0) return c;
        return await runLikeCount();
      } catch (ftsError) {
        try {
          await FlutterLogger.nativeWarn(
            'DB',
            'countSegmentsByText: FTS 失败，回退 LIKE：$ftsError',
          );
        } catch (_) {}
        return await runLikeCount();
      }
    } catch (e) {
      try {
        await FlutterLogger.nativeError('DB', 'countSegmentsByText 失败：$e');
      } catch (_) {}
      return 0;
    }
  }

  /// 删除单个段落事件（仅删除事件及其结果/样本，不删除月表中的图片记录/文件）
  Future<bool> deleteSegmentOnly(int segmentId) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        final int now = DateTime.now().millisecondsSinceEpoch;

        // If the user deletes a root segment that other segments were merged into,
        // those children become "orphaned" and would disappear from the UI if we
        // only query merged_into_id IS NULL. Unmerge them back to roots.
        try {
          await txn.update(
            'segments',
            {'merged_into_id': null, 'updated_at': now},
            where: 'merged_into_id = ?',
            whereArgs: [segmentId],
          );
        } catch (_) {
          try {
            await txn.update(
              'segments',
              {'merged_into_id': null},
              where: 'merged_into_id = ?',
              whereArgs: [segmentId],
            );
          } catch (_) {}
        }
        // Clear stale merge_prev_id pointers so "force merge" won't reference a deleted row.
        try {
          await txn.update(
            'segments',
            {'merge_prev_id': null, 'updated_at': now},
            where: 'merge_prev_id = ?',
            whereArgs: [segmentId],
          );
        } catch (_) {
          try {
            await txn.update(
              'segments',
              {'merge_prev_id': null},
              where: 'merge_prev_id = ?',
              whereArgs: [segmentId],
            );
          } catch (_) {}
        }

        // 先抓取该段落关联的图片路径：即使 ai_image_meta.segment_id 被后续流程覆盖，
        // 也能按 file_path 兜底清理，避免“图片描述/标签”残留在查看器/搜索中。
        final List<String> sampleFilePaths = <String>[];
        try {
          final rows = await txn.query(
            'segment_samples',
            columns: const ['file_path'],
            where: 'segment_id = ?',
            whereArgs: [segmentId],
          );
          for (final r in rows) {
            final String p = (r['file_path'] as String?)?.trim() ?? '';
            if (p.isNotEmpty) sampleFilePaths.add(p);
          }
        } catch (_) {}

        await txn.delete(
          'segment_results',
          where: 'segment_id = ?',
          whereArgs: [segmentId],
        );
        await txn.delete(
          'segment_samples',
          where: 'segment_id = ?',
          whereArgs: [segmentId],
        );
        // 同步删除该段落生成的图片标签/描述，避免删除事件后“图片描述”仍残留在查看器/搜索中。
        try {
          await txn.delete(
            'ai_image_meta',
            where: 'segment_id = ?',
            whereArgs: [segmentId],
          );
        } catch (_) {}

        // 兜底：按 file_path 再删一遍（分批避免 SQLite 参数上限）。
        final List<String> paths = sampleFilePaths
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(growable: false);
        if (paths.isNotEmpty) {
          const int chunkSize = 400;
          for (int i = 0; i < paths.length; i += chunkSize) {
            final int end = (i + chunkSize) > paths.length
                ? paths.length
                : (i + chunkSize);
            final List<String> chunk = paths.sublist(i, end);
            final String placeholders = List.filled(
              chunk.length,
              '?',
            ).join(',');
            try {
              await txn.delete(
                'ai_image_meta',
                where: 'file_path IN ($placeholders)',
                whereArgs: chunk,
              );
            } catch (_) {}
          }
        }
        await txn.delete('segments', where: 'id = ?', whereArgs: [segmentId]);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ======= 每日总结（daily_summaries） =======
  Future<Map<String, dynamic>?> getDailySummary(String dateKey) async {
    final db = await database;
    try {
      final rows = await db.query(
        'daily_summaries',
        where: 'date_key = ?',
        whereArgs: [dateKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertDailySummary({
    required String dateKey,
    String? aiProvider,
    String? aiModel,
    required String outputText,
    String? structuredJson,
  }) async {
    final db = await database;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('daily_summaries', {
        'date_key': dateKey,
        'ai_provider': aiProvider,
        'ai_model': aiModel,
        'output_text': outputText,
        'structured_json': structuredJson,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // ignore: unawaited_futures
      this.upsertSearchDoc(
        docKey: _dailySummaryDocKey(dateKey),
        docType: kSearchDocTypeDailySummary,
        title: '每日总结 $dateKey',
        content: outputText,
        dateKey: dateKey,
        startTime: _parseYmdToStartMillis(dateKey),
        updatedAt: now,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getWeeklySummary(String weekStartDate) async {
    final db = await database;
    try {
      final rows = await db.query(
        'weekly_summaries',
        where: 'week_start_date = ?',
        whereArgs: [weekStartDate],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertWeeklySummary({
    required String weekStartDate,
    required String weekEndDate,
    String? aiProvider,
    String? aiModel,
    required String outputText,
    String? structuredJson,
  }) async {
    final db = await database;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('weekly_summaries', {
        'week_start_date': weekStartDate,
        'week_end_date': weekEndDate,
        'ai_provider': aiProvider,
        'ai_model': aiModel,
        'output_text': outputText,
        'structured_json': structuredJson,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final String title = weekEndDate.trim().isEmpty
          ? '周总结 $weekStartDate'
          : '周总结 $weekStartDate ~ $weekEndDate';
      // ignore: unawaited_futures
      this.upsertSearchDoc(
        docKey: _weeklySummaryDocKey(weekStartDate),
        docType: kSearchDocTypeWeeklySummary,
        title: title,
        content: outputText,
        dateKey: weekStartDate,
        startTime: _parseYmdToStartMillis(weekStartDate),
        updatedAt: now,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listWeeklySummaries({
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'weekly_summaries',
        orderBy: 'week_start_date DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getMorningInsights(String dateKey) async {
    final db = await database;
    try {
      final rows = await db.query(
        'morning_insights',
        where: 'date_key = ?',
        whereArgs: [dateKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertMorningInsights({
    required String dateKey,
    required String sourceDateKey,
    required String tipsJson,
    String? rawResponse,
  }) async {
    final db = await database;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('morning_insights', {
        'date_key': dateKey,
        'source_date_key': sourceDateKey,
        'tips_json': tipsJson,
        if (rawResponse != null) 'raw_response': rawResponse,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // ignore: unawaited_futures
      this.upsertSearchDoc(
        docKey: _morningInsightsDocKey(dateKey),
        docType: kSearchDocTypeMorningInsights,
        title: '早报 $dateKey',
        content: _renderMorningInsightsMarkdown(
          (rawResponse != null && rawResponse.trim().isNotEmpty)
              ? rawResponse
              : tipsJson,
        ),
        dateKey: dateKey,
        startTime: _parseYmdToStartMillis(dateKey),
        updatedAt: now,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> deleteMorningInsights(String dateKey) async {
    final db = await database;
    try {
      return await db.delete(
        'morning_insights',
        where: 'date_key = ?',
        whereArgs: [dateKey],
      );
    } catch (_) {
      return 0;
    }
  }

  /// 按时间范围获取“已有AI结果”的段落（含结果元数据），用于拼装每日总结上下文
  Future<List<Map<String, dynamic>>> listSegmentsWithResultsBetween({
    required int startMillis,
    required int endMillis,
  }) async {
    final db = await database;
    try {
      final String sql =
          '''
        SELECT
          s.*,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        JOIN segment_results r ON r.segment_id = s.id
        WHERE ${_segmentsRootWhere('s')}
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND s.start_time >= ? AND s.start_time <= ?
        ORDER BY s.start_time ASC
      ''';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ' +
              sql
                  .replaceFirst('?', startMillis.toString())
                  .replaceFirst('?', endMillis.toString()),
        );
      } catch (_) {}
      final rows = await db.rawQuery(sql, [startMillis, endMillis]);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 列出与时间窗“有重叠”的段落（要求至少有样本图片），同时返回可能存在的 AI 结果
  /// - 选择逻辑：s.start_time <= endMillis AND s.end_time >= startMillis
  /// - 目的：避免仅按 start_time 命中导致跨窗事件被漏掉
  Future<List<Map<String, dynamic>>> listSegmentsOverlapWithSamplesBetween({
    required int startMillis,
    required int endMillis,
  }) async {
    final db = await database;
    try {
      final String sql =
          '''
        SELECT
          s.*,
          -- 展示用应用集合：优先 segments.app_packages；为空则回退样本去重聚合
          COALESCE(
            NULLIF(TRIM(s.app_packages), ''),
            (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
          ) AS app_packages_display,
          r.output_text,
          r.structured_json,
          r.categories
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        WHERE ${_segmentsRootWhere('s')}
          AND (s.segment_kind IS NULL OR s.segment_kind = 'global')
          AND s.start_time <= ? AND s.end_time >= ?
          AND EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)
        ORDER BY s.start_time ASC
      ''';
      try {
        await FlutterLogger.nativeDebug(
          'DB',
          'SQL: ' +
              sql
                  .replaceFirst('?', endMillis.toString())
                  .replaceFirst('?', startMillis.toString()),
        );
      } catch (_) {}
      final rows = await db.rawQuery(sql, [endMillis, startMillis]);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
