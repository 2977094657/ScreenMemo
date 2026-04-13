import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'memory_entity_models.dart';
import 'memory_entity_policy.dart';
import 'nocturne_memory_service.dart';
import 'screenshot_database.dart';

class MemoryEntityStore {
  MemoryEntityStore._internal();

  static final MemoryEntityStore instance = MemoryEntityStore._internal();

  static const String rootAggregateCanonicalKey = '__root__';
  static const String managedUriAliasSource = 'managed_uri';

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final NocturneMemoryService _mem = NocturneMemoryService.instance;

  Future<void> resetAll() async {
    final Database db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('memory_entity_batch_runs');
      await txn.delete('memory_entity_review_queue');
      await txn.delete('memory_entity_resolution_audits');
      await txn.delete('memory_entity_events');
      await txn.delete('memory_entity_exemplars');
      await txn.delete('memory_entity_evidence');
      await txn.delete('memory_entity_episodes');
      await txn.delete('memory_entity_claims');
      await txn.delete('memory_entity_aliases');
      await txn.delete('memory_entities');
      await txn.delete('memory_signal_episodes');
      await txn.delete('memory_signal_profiles');
      try {
        await txn.delete('legacy_memory_signal_episodes');
        await txn.delete('legacy_memory_signal_profiles');
      } catch (_) {}
      await txn.delete('memory_entity_search_fts');
    });
  }

  Future<void> migrateLegacySignalTablesIfNeeded() async {
    final Database db = await _db.database;
    // Legacy uri-first signal tables are migration-only. Fresh installs no
    // longer create or write them; we only import old rows if a user upgrades
    // from a pre-entity database.
    final bool hasLegacyProfiles = await _tableExists(
      db,
      'legacy_memory_signal_profiles',
    );
    final bool hasLegacyEpisodes = await _tableExists(
      db,
      'legacy_memory_signal_episodes',
    );
    if (!hasLegacyProfiles || !hasLegacyEpisodes) return;

    final int entityCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM memory_entities'),
        ) ??
        0;
    if (entityCount > 0) return;

    final int legacyProfileCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) AS c FROM legacy_memory_signal_profiles',
          ),
        ) ??
        0;
    if (legacyProfileCount <= 0) return;

    final List<Map<String, Object?>> legacyProfiles = await db.query(
      'legacy_memory_signal_profiles',
      orderBy: 'created_at ASC, uri ASC',
    );
    final List<Map<String, Object?>> legacyEpisodes = await db.query(
      'legacy_memory_signal_episodes',
      orderBy: 'created_at ASC, last_seen_at ASC, id ASC',
    );
    final Map<String, List<Map<String, Object?>>> episodesByUri =
        <String, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> row in legacyEpisodes) {
      final String uri = canonicalizeUri((row['uri'] ?? '').toString());
      if (uri.isEmpty) continue;
      episodesByUri.putIfAbsent(uri, () => <Map<String, Object?>>[]).add(row);
    }

    final List<(String, MemoryEntityStatus, int, int)> imported =
        <(String, MemoryEntityStatus, int, int)>[];
    await db.transaction((txn) async {
      for (final Map<String, Object?> profile in legacyProfiles) {
        final String displayUri = canonicalizeUri(
          (profile['uri'] ?? '').toString(),
        );
        final String rootUri = canonicalizeUri(
          (profile['root_uri'] ?? '').toString(),
        );
        if (displayUri.isEmpty || rootUri.isEmpty) continue;

        final MemoryEntityRootPolicy? policy = MemoryEntityPolicies.forRootUri(
          rootUri,
        );
        if (policy == null) continue;

        final MemoryEntityStatus status = MemoryEntityStatus.fromWire(
          (profile['status'] ?? '').toString(),
        );
        final String latestContent = _normalizeContent(
          (profile['latest_content'] ?? '').toString(),
        );
        final String preferredName = displayUri == policy.rootUri
            ? policy.rootKey
            : _humanizeLeafFromUri(displayUri);
        final String canonicalKey = deriveCanonicalKey(
          policy: policy,
          preferredName: preferredName,
          displayUri: displayUri,
        );
        final String entityId = _uuidV4();
        final int createdAt = _toInt(profile['created_at']) > 0
            ? _toInt(profile['created_at'])
            : DateTime.now().millisecondsSinceEpoch;
        final int updatedAt = _toInt(profile['updated_at']) > 0
            ? _toInt(profile['updated_at'])
            : createdAt;
        final int firstSeenAt = _toInt(profile['first_seen_at']);
        final int lastSeenAt = _toInt(profile['last_seen_at']);
        final int activatedAt = _toInt(profile['activated_at']);
        final int archivedAt = _toInt(profile['archived_at']);

        await txn.insert('memory_entities', <String, Object?>{
          'entity_id': entityId,
          'root_uri': policy.rootUri,
          'entity_type': policy.entityType,
          'preferred_name': preferredName,
          'preferred_name_norm': normalizeForSearch(preferredName),
          'canonical_key': canonicalKey,
          'display_uri': displayUri,
          'status': status.wireName,
          'current_summary': _summarizeContent(latestContent),
          'latest_content': latestContent,
          'visual_signature_summary': '',
          'raw_score': 0,
          'decayed_score': 0,
          'activation_score': policy.activationScore,
          'evidence_count': 0,
          'distinct_segment_count': 0,
          'distinct_day_count': 0,
          'strong_signal_count': 0,
          'min_distinct_days': policy.minDistinctDays,
          'allow_single_strong_activation': policy.allowSingleStrongActivation
              ? 1
              : 0,
          'allow_root_materialization': policy.allowRootMaterialization ? 1 : 0,
          'needs_review': 0,
          'review_reason': null,
          'first_seen_at': firstSeenAt > 0 ? firstSeenAt : null,
          'last_seen_at': lastSeenAt > 0 ? lastSeenAt : null,
          'activated_at': activatedAt > 0 ? activatedAt : null,
          'archived_at': archivedAt > 0 ? archivedAt : null,
          'last_materialized_at': _toInt(profile['last_materialized_at']) > 0
              ? _toInt(profile['last_materialized_at'])
              : null,
          'last_evidence_summary': _nullIfBlank(
            profile['last_evidence_summary'],
          ),
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        final List<Map<String, Object?>> rows =
            episodesByUri[displayUri] ?? const <Map<String, Object?>>[];
        for (final Map<String, Object?> episode in rows) {
          final int segmentId = _toInt(episode['segment_id']);
          if (segmentId <= 0) continue;
          final int episodeCreatedAt = _toInt(episode['created_at']) > 0
              ? _toInt(episode['created_at'])
              : createdAt;
          final int episodeUpdatedAt = _toInt(episode['updated_at']) > 0
              ? _toInt(episode['updated_at'])
              : episodeCreatedAt;
          final int firstSeen = _toInt(episode['first_seen_at']);
          final int lastSeen = _toInt(episode['last_seen_at']);
          final String evidenceSummary = (episode['evidence_summary'] ?? '')
              .toString()
              .trim();
          final String appNamesJson = (episode['app_names_json'] ?? '')
              .toString()
              .trim();
          final List<String> appNames = _decodeStringListJson(appNamesJson);

          await txn.insert('memory_entity_episodes', <String, Object?>{
            'entity_id': entityId,
            'root_uri': policy.rootUri,
            'display_uri': displayUri,
            'segment_id': segmentId,
            'batch_index': _toInt(episode['batch_index']),
            'day_key': (episode['day_key'] ?? '').toString().trim(),
            'first_seen_at': firstSeen > 0 ? firstSeen : createdAt,
            'last_seen_at': lastSeen > 0 ? lastSeen : firstSeen,
            'score': _toDouble(episode['score']),
            'strong_signal': _toInt(episode['strong_signal']) > 0 ? 1 : 0,
            'action_kind': (episode['action_kind'] ?? '').toString().trim(),
            'evidence_summary': evidenceSummary,
            'app_names_json': appNamesJson.isEmpty ? null : appNamesJson,
            'content_snapshot': _normalizeContent(
              (episode['content'] ?? '').toString(),
            ),
            'created_at': episodeCreatedAt,
            'updated_at': episodeUpdatedAt,
          });

          await txn.insert('memory_entity_evidence', <String, Object?>{
            'entity_id': entityId,
            'segment_id': segmentId,
            'batch_index': _toInt(episode['batch_index']),
            'evidence_summary': evidenceSummary.isEmpty
                ? '迁移自旧版信号层'
                : evidenceSummary,
            'apps_json': appNames.isEmpty
                ? null
                : jsonEncode(appNames.toSet().toList()..sort()),
            'frame_count': 0,
            'start_at': firstSeen > 0 ? firstSeen : null,
            'end_at': lastSeen > 0 ? lastSeen : null,
            'created_at': episodeCreatedAt,
          });
        }

        imported.add((entityId, status, activatedAt, archivedAt));
      }
    });

    for (final (String, MemoryEntityStatus, int, int) item in imported) {
      await _recalculateEntitySignals(item.$1);
      if (item.$2 != MemoryEntityStatus.candidate) {
        await _restoreLegacyStatus(
          entityId: item.$1,
          status: item.$2,
          activatedAt: item.$3,
          archivedAt: item.$4,
        );
      }
    }
    await rebuildSignalReadModels();
    await _ensureSearchIndexSynced(force: true);
  }

  Future<MemoryEntityRecord?> getRecordById(String entityId) async {
    final String normalized = entityId.trim();
    if (normalized.isEmpty) return null;
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityRecord.fromMap(rows.first);
  }

  Future<MemoryEntityRecord?> getRecordByDisplayUri(String uri) async {
    final String normalized = canonicalizeUri(uri);
    if (normalized.isEmpty) return null;
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      where: 'display_uri = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityRecord.fromMap(rows.first);
  }

  Future<MemoryEntityRecord?> getSignalRecordById(String entityId) async {
    final String normalized = entityId.trim();
    if (normalized.isEmpty) return null;
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_signal_profiles',
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityRecord.fromMap(rows.first);
  }

  Future<MemoryEntityRecord?> getSignalRecordByDisplayUri(String uri) async {
    final String normalized = canonicalizeUri(uri);
    if (normalized.isEmpty) return null;
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_signal_profiles',
      where: 'uri = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityRecord.fromMap(rows.first);
  }

  Future<List<MemoryEntityRecord>> listSignalRecords({
    MemoryEntityStatus? status,
    String? rootUri,
  }) async {
    final Database db = await _db.database;
    final List<String> whereClauses = <String>[];
    final List<Object?> args = <Object?>[];
    if (status != null) {
      whereClauses.add('status = ?');
      args.add(status.wireName);
    }
    final String normalizedRoot = rootUri == null
        ? ''
        : canonicalizeUri(rootUri);
    if (normalizedRoot.isNotEmpty) {
      whereClauses.add('root_uri = ?');
      args.add(normalizedRoot);
    }
    final List<Map<String, Object?>> rows = await db.query(
      'memory_signal_profiles',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy:
          "CASE status WHEN 'candidate' THEN 0 WHEN 'active' THEN 1 ELSE 2 END ASC, decayed_score DESC, raw_score DESC, last_seen_at DESC",
    );
    return rows.map(MemoryEntityRecord.fromMap).toList(growable: false);
  }

  Future<List<MemoryEntityRecord>> listRecords({
    MemoryEntityStatus? status,
    String? rootUri,
  }) async {
    final Database db = await _db.database;
    final List<String> whereClauses = <String>[];
    final List<Object?> args = <Object?>[];
    if (status != null) {
      whereClauses.add('status = ?');
      args.add(status.wireName);
    }
    final String normalizedRoot = rootUri == null
        ? ''
        : canonicalizeUri(rootUri);
    if (normalizedRoot.isNotEmpty) {
      whereClauses.add('root_uri = ?');
      args.add(normalizedRoot);
    }
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy:
          "CASE status WHEN 'candidate' THEN 0 WHEN 'active' THEN 1 ELSE 2 END ASC, decayed_score DESC, raw_score DESC, last_seen_at DESC",
    );
    return rows.map(MemoryEntityRecord.fromMap).toList(growable: false);
  }

  Future<void> refreshSignals({String? entityId, String? rootUri}) async {
    final Database db = await _db.database;
    final String normalizedEntityId = (entityId ?? '').trim();
    final String normalizedRoot = (rootUri ?? '').trim().isEmpty
        ? ''
        : canonicalizeUri(rootUri!);
    final List<String> whereClauses = <String>[];
    final List<Object?> args = <Object?>[];
    if (normalizedEntityId.isNotEmpty) {
      whereClauses.add('entity_id = ?');
      args.add(normalizedEntityId);
    }
    if (normalizedRoot.isNotEmpty) {
      whereClauses.add('root_uri = ?');
      args.add(normalizedRoot);
    }

    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      columns: const <String>['entity_id'],
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at ASC, created_at ASC',
    );
    for (final Map<String, Object?> row in rows) {
      final String nextEntityId = (row['entity_id'] ?? '').toString().trim();
      if (nextEntityId.isEmpty) continue;
      await _recalculateEntitySignals(nextEntityId);
    }
  }

  Future<void> ensureSignalReadModelsReady() async {
    final Database db = await _db.database;
    if (!await _tableExists(db, 'memory_signal_profiles') ||
        !await _tableExists(db, 'memory_signal_episodes')) {
      return;
    }
    final int entityCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM memory_entities'),
        ) ??
        0;
    final int signalProfileCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM memory_signal_profiles'),
        ) ??
        0;
    final int episodeCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM memory_entity_episodes'),
        ) ??
        0;
    final int signalEpisodeCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM memory_signal_episodes'),
        ) ??
        0;
    if (entityCount == signalProfileCount &&
        episodeCount == signalEpisodeCount) {
      return;
    }
    await rebuildSignalReadModels();
  }

  Future<void> rebuildSignalReadModels() async {
    final Database db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('memory_signal_episodes');
      await txn.delete('memory_signal_profiles');
      final List<Map<String, Object?>> rows = await txn.query(
        'memory_entities',
        columns: const <String>['entity_id'],
        orderBy: 'created_at ASC, updated_at ASC',
      );
      for (final Map<String, Object?> row in rows) {
        final String entityId = (row['entity_id'] ?? '').toString().trim();
        if (entityId.isEmpty) continue;
        await _syncSignalReadModelsForEntityTxn(txn, entityId);
      }
    });
  }

  Future<void> recordBatchRun({
    required int segmentId,
    required int batchIndex,
    required String status,
    required int sampleCount,
    required int candidateCount,
    required int appliedCount,
    required int reviewCount,
    required int skippedCount,
    String? modelName,
  }) async {
    final String normalizedStatus = status.trim().isEmpty
        ? 'completed'
        : status.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    await (await _db.database)
        .insert('memory_entity_batch_runs', <String, Object?>{
          'segment_id': segmentId,
          'batch_index': batchIndex,
          'status': normalizedStatus,
          'sample_count': sampleCount,
          'candidate_count': candidateCount,
          'applied_count': appliedCount,
          'review_count': reviewCount,
          'skipped_count': skippedCount,
          'model_name': modelName?.trim().isEmpty == true
              ? null
              : modelName?.trim(),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<MemoryEntityQualityMetrics> loadQualityMetrics() async {
    final Database db = await _db.database;
    final Map<String, int> applyCounts = await _countAuditActions(
      db,
      stage: 'apply_commit',
    );
    final Map<String, int> auditCounts = await _countAuditActions(
      db,
      stage: 'audit',
    );
    final int totalBatchCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) AS c FROM memory_entity_batch_runs',
          ),
        ) ??
        0;
    final int emptyBatchCount =
        Sqflite.firstIntValue(
          await db.rawQuery('''
            SELECT COUNT(*) AS c
            FROM memory_entity_batch_runs
            WHERE status = 'empty'
               OR (
                 status = 'completed'
                 AND applied_count <= 0
                 AND review_count <= 0
               )
            '''),
        ) ??
        0;
    final int manualReviewApprovedCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*) AS c
            FROM memory_entity_review_queue
            WHERE status = ?
            ''',
            <Object?>[MemoryEntityReviewStatus.approved.wireName],
          ),
        ) ??
        0;
    final int materializedEntityCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*) AS c
            FROM memory_entities
            WHERE status <> ? AND needs_review = 0
            ''',
            <Object?>[MemoryEntityStatus.candidate.wireName],
          ),
        ) ??
        0;
    final int materializedNodeCount = await _countExpectedMaterializedPaths(db);
    final int duplicateClusterCount = await _countApproxDuplicateClusters();
    return MemoryEntityQualityMetrics(
      createdNewCount: applyCounts['CREATE_NEW_ENTITY'] ?? 0,
      matchedExistingCount:
          (applyCounts['MERGE_EXISTING_ENTITY'] ?? 0) +
          (applyCounts['MERGE_EXISTING_ALIAS'] ?? 0),
      reviewQueuedCount: applyCounts['QUEUE_REVIEW'] ?? 0,
      duplicateBlockCount:
          auditCounts[MemoryEntityAuditAction.blockDuplicate.wireName] ?? 0,
      ambiguousBlockCount:
          auditCounts[MemoryEntityAuditAction.blockAmbiguous.wireName] ?? 0,
      lowEvidenceBlockCount:
          auditCounts[MemoryEntityAuditAction.blockLowEvidence.wireName] ?? 0,
      totalBatchCount: totalBatchCount,
      emptyBatchCount: emptyBatchCount,
      emptyBatchRate: totalBatchCount <= 0
          ? 0
          : emptyBatchCount / totalBatchCount,
      duplicateClusterCount: duplicateClusterCount,
      materializedNodeCount: materializedNodeCount,
      materializedEntityCount: materializedEntityCount,
      materializationDrift: materializedNodeCount - materializedEntityCount,
      manualReviewApprovedCount: manualReviewApprovedCount,
    );
  }

  Future<Map<String, int>> _countAuditActions(
    Database db, {
    required String stage,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT action, COUNT(*) AS c
      FROM memory_entity_resolution_audits
      WHERE stage = ?
      GROUP BY action
      ''',
      <Object?>[stage.trim()],
    );
    final Map<String, int> out = <String, int>{};
    for (final Map<String, Object?> row in rows) {
      final String action = (row['action'] ?? '').toString().trim();
      if (action.isEmpty) continue;
      out[action] = _toInt(row['c']);
    }
    return out;
  }

  Future<int> _countExpectedMaterializedPaths(Database db) async {
    if (!await _tableExists(db, 'paths')) return 0;
    final List<Map<String, Object?>> rows = await db.query(
      'paths',
      columns: const <String>['domain', 'path'],
    );
    int count = 0;
    for (final Map<String, Object?> row in rows) {
      final String domain = (row['domain'] ?? '').toString().trim();
      final String path = (row['path'] ?? '').toString().trim();
      if (domain.isEmpty) continue;
      final String uri = _mem.makeUri(domain, path);
      if (_isManagedRootUri(uri)) {
        count += 1;
      }
    }
    return count;
  }

  bool _isManagedRootUri(String uri) {
    final String normalized = canonicalizeUri(uri);
    for (final MemoryEntityRootPolicy policy
        in MemoryEntityPolicies.byRootUri.values) {
      if (normalized == policy.rootUri ||
          normalized.startsWith('${policy.rootUri}/')) {
        return true;
      }
    }
    return false;
  }

  Future<int> _countApproxDuplicateClusters() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      where: 'status <> ?',
      whereArgs: <Object?>[MemoryEntityStatus.archived.wireName],
      orderBy: 'root_uri ASC, entity_type ASC, last_seen_at DESC',
    );
    if (rows.length < 2) return 0;
    final List<MemoryEntityRecord> records = rows
        .map(MemoryEntityRecord.fromMap)
        .toList(growable: false);
    final Map<String, List<String>> aliasMap = await _loadAliasMap(
      db,
      records.map((item) => item.entityId).toList(growable: false),
    );

    final Map<String, List<MemoryEntityRecord>> grouped =
        <String, List<MemoryEntityRecord>>{};
    for (final MemoryEntityRecord record in records) {
      final String groupKey = '${record.rootUri}::${record.entityType}';
      grouped.putIfAbsent(groupKey, () => <MemoryEntityRecord>[]).add(record);
    }

    int clusterCount = 0;
    for (final List<MemoryEntityRecord> group in grouped.values) {
      if (group.length < 2) continue;
      final Map<String, String> parent = <String, String>{
        for (final MemoryEntityRecord record in group)
          record.entityId: record.entityId,
      };

      String find(String id) {
        String current = parent[id] ?? id;
        while (parent[current] != null && parent[current] != current) {
          current = parent[current]!;
        }
        String cursor = id;
        while (parent[cursor] != null && parent[cursor] != current) {
          final String next = parent[cursor]!;
          parent[cursor] = current;
          cursor = next;
        }
        return current;
      }

      void unite(String a, String b) {
        final String left = find(a);
        final String right = find(b);
        if (left == right) return;
        parent[right] = left;
      }

      for (int i = 0; i < group.length; i += 1) {
        for (int j = i + 1; j < group.length; j += 1) {
          final MemoryEntityRecord left = group[i];
          final MemoryEntityRecord right = group[j];
          if (_looksLikeApproxDuplicate(
            left: left,
            right: right,
            leftAliases: aliasMap[left.entityId] ?? const <String>[],
            rightAliases: aliasMap[right.entityId] ?? const <String>[],
          )) {
            unite(left.entityId, right.entityId);
          }
        }
      }

      final Map<String, int> componentSizes = <String, int>{};
      for (final MemoryEntityRecord record in group) {
        final String root = find(record.entityId);
        componentSizes[root] = (componentSizes[root] ?? 0) + 1;
      }
      clusterCount += componentSizes.values.where((count) => count > 1).length;
    }
    return clusterCount;
  }

  bool _looksLikeApproxDuplicate({
    required MemoryEntityRecord left,
    required MemoryEntityRecord right,
    required List<String> leftAliases,
    required List<String> rightAliases,
  }) {
    if (left.entityId == right.entityId) return false;
    if (left.rootUri != right.rootUri || left.entityType != right.entityType) {
      return false;
    }

    final String leftName = left.preferredNameNorm;
    final String rightName = right.preferredNameNorm;
    if (leftName.isNotEmpty && leftName == rightName) {
      return true;
    }

    final double nameSimilarity = _normalizedStringSimilarity(
      leftName,
      rightName,
    );
    final double trigramSimilarity = _trigramSimilarity(leftName, rightName);
    if (nameSimilarity >= 0.92 || trigramSimilarity >= 0.86) {
      return true;
    }

    final Set<String> leftAliasNorms = leftAliases
        .map(normalizeForSearch)
        .where((value) => value.isNotEmpty)
        .toSet();
    final Set<String> rightAliasNorms = rightAliases
        .map(normalizeForSearch)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (leftAliasNorms.intersection(rightAliasNorms).isNotEmpty) {
      return true;
    }

    double aliasSimilarity = 0;
    for (final String leftAlias in leftAliasNorms) {
      for (final String rightAlias in rightAliasNorms) {
        aliasSimilarity = math.max(
          aliasSimilarity,
          math.max(
            _normalizedStringSimilarity(leftAlias, rightAlias),
            _trigramSimilarity(leftAlias, rightAlias),
          ),
        );
      }
    }
    if (aliasSimilarity >= 0.9) {
      return true;
    }

    final double visualOverlap = _tokenOverlapRatio(
      normalizeForSearch(left.visualSignatureSummary),
      normalizeForSearch(right.visualSignatureSummary),
    );
    return (nameSimilarity >= 0.82 || trigramSimilarity >= 0.76) &&
        visualOverlap >= 0.3;
  }

  Future<bool> hasDescendants(String uri) async {
    final String normalized = canonicalizeUri(uri);
    if (normalized.isEmpty) return false;
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      columns: const <String>['entity_id'],
      where: 'display_uri LIKE ?',
      whereArgs: <Object?>['$normalized/%'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<String>> listAliases(String entityId) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_aliases',
      columns: const <String>['alias', 'alias_text', 'source'],
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId.trim()],
      orderBy: 'alias_norm ASC',
    );
    final List<String> out = <String>[];
    for (final Map<String, Object?> row in rows) {
      final String source = (row['source'] ?? '').toString().trim();
      if (source == managedUriAliasSource) continue;
      final String alias = (row['alias_text'] ?? row['alias'] ?? '')
          .toString()
          .trim();
      if (alias.isNotEmpty) out.add(alias);
    }
    return out;
  }

  Future<List<String>> listManagedUriAliases(String entityId) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_aliases',
      columns: const <String>['alias', 'alias_text'],
      where: 'entity_id = ? AND source = ?',
      whereArgs: <Object?>[entityId.trim(), managedUriAliasSource],
      orderBy: 'alias_norm ASC',
    );
    return rows
        .map(
          (row) => (row['alias_text'] ?? row['alias'] ?? '').toString().trim(),
        )
        .where((alias) => alias.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<int>> listExemplarSampleIds(
    String entityId, {
    int limit = 3,
  }) async {
    final List<MemoryEntityExemplar> exemplars = await listExemplars(
      entityId,
      limit: limit,
    );
    final List<int> out = <int>[];
    for (final MemoryEntityExemplar exemplar in exemplars) {
      final int value = exemplar.sampleId ?? 0;
      if (value > 0) out.add(value);
    }
    return out;
  }

  Future<List<MemoryEntityExemplar>> listExemplars(
    String entityId, {
    int limit = 3,
  }) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_exemplars',
      columns: const <String>[
        'sample_id',
        'file_path',
        'capture_time',
        'app_name',
        'position_index',
        'rank',
        'reason',
      ],
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId.trim()],
      orderBy: 'rank ASC, capture_time DESC, position_index ASC',
      limit: limit.clamp(1, 20),
    );
    final List<MemoryEntityExemplar> out = <MemoryEntityExemplar>[];
    for (final Map<String, Object?> row in rows) {
      final MemoryEntityExemplar exemplar = MemoryEntityExemplar.fromMap(
        Map<String, dynamic>.from(row),
      );
      if (exemplar.filePath.isEmpty) continue;
      out.add(exemplar);
    }
    return out;
  }

  Future<List<MemoryEntityClaimSnapshot>> listClaims(
    String entityId, {
    bool activeOnly = true,
    int limit = 12,
  }) async {
    final Database db = await _db.database;
    final List<String> whereClauses = <String>['entity_id = ?'];
    final List<Object?> whereArgs = <Object?>[entityId.trim()];
    if (activeOnly) {
      whereClauses.add('active = 1');
    }
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_claims',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'active DESC, confidence DESC, updated_at DESC',
      limit: limit.clamp(1, 50),
    );
    return rows
        .map(
          (row) =>
              MemoryEntityClaimSnapshot.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<MemoryEntityDossier> buildDossier(
    MemoryEntitySearchCandidate candidate, {
    int exemplarLimit = 3,
    int claimLimit = 12,
    int eventLimit = 8,
  }) async {
    final List<MemoryEntityExemplar> exemplars = await listExemplars(
      candidate.entityId,
      limit: exemplarLimit,
    );
    final List<MemoryEntityClaimSnapshot> claims = await listClaims(
      candidate.entityId,
      limit: claimLimit,
    );
    final List<MemoryEntityEventSnapshot> events = await listEvents(
      candidate.entityId,
      limit: eventLimit,
    );
    return MemoryEntityDossier(
      candidate: candidate,
      claims: claims,
      exemplars: exemplars,
      events: events,
    );
  }

  Future<List<MemoryEntityEventSnapshot>> listEvents(
    String entityId, {
    int limit = 12,
  }) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_events',
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId.trim()],
      orderBy: 'updated_at DESC, created_at DESC, id DESC',
      limit: limit.clamp(1, 50),
    );
    return rows
        .map(
          (row) =>
              MemoryEntityEventSnapshot.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<MemoryEntityReviewQueueItem>> listReviewQueueItems({
    MemoryEntityReviewStatus status = MemoryEntityReviewStatus.pending,
    int limit = 200,
  }) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_review_queue',
      where: 'status = ?',
      whereArgs: <Object?>[status.wireName],
      orderBy: 'created_at DESC',
      limit: limit.clamp(1, 500),
    );
    return rows
        .map(
          (row) => MemoryEntityReviewQueueItem.fromMap(
            Map<String, Object?>.from(row),
          ),
        )
        .toList(growable: false);
  }

  Future<MemoryEntityReviewQueueItem?> getReviewQueueItem(int id) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_review_queue',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityReviewQueueItem.fromMap(rows.first);
  }

  Future<MemoryEntityApplyResult> approveReviewQueueItem({
    required int reviewId,
    String? targetEntityId,
    bool forceCreateNew = false,
  }) async {
    final MemoryEntityReviewQueueItem item =
        await getReviewQueueItem(reviewId) ??
        (throw StateError('review item not found: $reviewId'));
    if (item.status != MemoryEntityReviewStatus.pending) {
      throw StateError('review item is not pending: $reviewId');
    }

    final MemoryVisualCandidate candidate = MemoryVisualCandidate.fromJson(
      _decodeJsonMap(item.candidateJson, field: 'candidate_json'),
    );
    final MemoryEntityResolutionDecision originalResolution =
        MemoryEntityResolutionDecision.fromJson(
          _decodeJsonMap(item.resolutionJson, field: 'resolution_json'),
        );
    final MemoryEntityMergePlan mergePlan = MemoryEntityMergePlan.fromJson(
      _decodeJsonMap(item.mergePlanJson, field: 'merge_plan_json'),
    );
    final MemoryEntityRootPolicy policy =
        MemoryEntityPolicies.forRootKey(candidate.rootKey) ??
        (throw StateError('未知的 root_key: ${candidate.rootKey}'));

    final String approvedTargetEntityId = await _resolveApprovedTargetEntityId(
      policy: policy,
      explicitTargetEntityId: targetEntityId,
      reviewItem: item,
      originalResolution: originalResolution,
      forceCreateNew: forceCreateNew,
    );
    final MemoryEntityResolutionDecision approvedResolution =
        _buildApprovedResolution(
          original: originalResolution,
          approvedTargetEntityId: approvedTargetEntityId,
          forceCreateNew: forceCreateNew,
        );
    final MemoryEntityAuditDecision approvedAudit = MemoryEntityAuditDecision(
      action: MemoryEntityAuditAction.approve,
      confidence: 1.0,
      suggestedEntityId: approvedTargetEntityId.isEmpty
          ? null
          : approvedTargetEntityId,
      reasons: <String>[
        if (item.reviewReason.trim().isNotEmpty) item.reviewReason.trim(),
        forceCreateNew ? '人工复核后批准新建实体' : '人工复核后批准写入',
      ],
      notes: 'review_queue_id=$reviewId',
    );
    final String preferredName = _pickNonEmpty(
      mergePlan.preferredName,
      approvedResolution.suggestedPreferredName,
      candidate.preferredName,
      policy.rootKey,
    );
    final String canonicalKey = deriveCanonicalKey(
      policy: policy,
      preferredName: preferredName,
    );
    final String slugPath = deriveSlugPath(
      policy: policy,
      preferredName: preferredName,
      canonicalKey: canonicalKey,
    );
    final String desiredDisplayUri = buildDisplayUri(
      rootUri: policy.rootUri,
      slugPath: slugPath,
      canonicalKey: canonicalKey,
    );
    final String summaryRewrite = _normalizeContent(
      mergePlan.summaryRewrite.isNotEmpty
          ? mergePlan.summaryRewrite
          : candidate.preferredName,
    );
    final bool strongSignal = _isStrongSignal(
      policy: policy,
      displayUri: desiredDisplayUri,
      content: summaryRewrite,
      aliases: candidate.aliases,
    );
    final List<MemoryEntityExemplar> exemplars =
        await _loadReviewQueueExemplars(
          item: item,
          candidate: candidate,
          mergePlan: mergePlan,
        );
    final String approvedResolutionJson = encodeJsonPretty(
      approvedResolution.toJson(),
    );
    final String approvedAuditJson = encodeJsonPretty(approvedAudit.toJson());

    final MemoryEntityApplyResult result = await _upsertEntityObservation(
      policy: policy,
      explicitEntityId: approvedTargetEntityId.isEmpty
          ? null
          : approvedTargetEntityId,
      desiredDisplayUri: desiredDisplayUri,
      preferredName: preferredName,
      canonicalKey: canonicalKey,
      latestContent: summaryRewrite,
      currentSummary: _summarizeContent(summaryRewrite),
      visualSignatureSummary: _pickNonEmpty(
        mergePlan.visualSignatureSummary,
        candidate.visualSignatureSummary,
        '',
        '',
      ),
      aliases: <String>[
        ...candidate.aliases,
        ...approvedResolution.aliasesToAdd,
        ...mergePlan.aliasesToAdd,
      ],
      claims: mergePlan.claimsToUpsert,
      events: mergePlan.eventsToAppend,
      candidateId: candidate.candidateId,
      resolutionStagePayloads:
          <
            ({
              String stage,
              String action,
              double confidence,
              String? modelName,
              String inputJson,
              String outputJson,
              String payloadJson,
            })
          >[
            (
              stage: 'review_resolution',
              action: approvedResolution.action.wireName,
              confidence: 1.0,
              modelName: 'human_review',
              inputJson: item.resolutionJson,
              outputJson: approvedResolutionJson,
              payloadJson: approvedResolutionJson,
            ),
            (
              stage: 'review_merge_plan',
              action: 'MERGE_PLAN_REUSED',
              confidence: 1.0,
              modelName: 'human_review',
              inputJson: item.mergePlanJson,
              outputJson: item.mergePlanJson,
              payloadJson: item.mergePlanJson,
            ),
            (
              stage: 'review_audit',
              action: approvedAudit.action.wireName,
              confidence: approvedAudit.confidence,
              modelName: 'human_review',
              inputJson: item.auditJson,
              outputJson: approvedAuditJson,
              payloadJson: approvedAuditJson,
            ),
          ],
      segmentId: item.segmentId,
      batchIndex: item.batchIndex,
      segmentStartMs: null,
      segmentEndMs: null,
      evidenceSummary: item.evidenceSummary ?? '',
      appNames: item.appNames,
      actionKind: 'review_approved',
      strongSignal: strongSignal,
      score: _scoreEpisode(
        policy: policy,
        displayUri: desiredDisplayUri,
        actionKind: 'review_approved',
        content: summaryRewrite,
        strongSignal: strongSignal,
      ),
      exemplars: exemplars,
      needsReview: false,
      reviewReason: '',
      matchMode: _EntityObservationMatchMode.explicitOnly,
      deriveDisplayUriFromCanonicalKey: true,
    );
    await _setReviewQueueStatus(
      reviewId: reviewId,
      status: MemoryEntityReviewStatus.approved,
    );
    return result;
  }

  Future<void> dismissReviewQueueItem(int reviewId) {
    return _setReviewQueueStatus(
      reviewId: reviewId,
      status: MemoryEntityReviewStatus.dismissed,
    );
  }

  String canonicalizeUri(String uri) {
    final String value = uri.trim();
    if (value.isEmpty) return '';
    final NocturneUri parsed = _mem.parseUri(value);
    return _mem.makeUri(parsed.domain, parsed.path);
  }

  String normalizeForSearch(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(
            r"""[!"#\$%&'()*+,./:;<=>?@\[\]\\^`{|}~_，。！？、；：（）【】《》“”‘’]+""",
          ),
          '',
        );
  }

  String normalizeCanonicalKey(String value) {
    return normalizeForSearch(value).replaceAll(' ', '');
  }

  String slugify(String value) {
    String out = value.trim().toLowerCase();
    out = out.replaceAll(RegExp(r'[^\u0000-\u007F]+'), '');
    out = out.replaceAll(RegExp(r'[^a-z0-9/_-]+'), '_');
    out = out.replaceAll(RegExp(r'_+'), '_');
    out = out.replaceAll(RegExp(r'/+'), '/');
    out = out.replaceAll(RegExp(r'^[_/]+|[_/]+$'), '');
    return out;
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final List<Map<String, Object?>> rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  String _humanizeLeafFromUri(String uri) {
    final String leaf = _mem.parseUri(uri).path.split('/').last;
    return leaf.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  Object? _nullIfBlank(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  List<String> _decodeStringListJson(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return const <String>[];
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is! List) return const <String>[];
      return decoded
          .map((item) => (item as String? ?? '').trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<MemoryEntitySearchCandidate>> shortlistCandidates({
    required String rootUri,
    required String entityType,
    required String preferredName,
    List<String> aliases = const <String>[],
    String? canonicalKey,
    String? visualSignatureSummary,
    int limit = 8,
  }) async {
    final String normalizedRoot = canonicalizeUri(rootUri);
    final String normalizedType = entityType.trim().toLowerCase();
    final String normalizedName = normalizeForSearch(preferredName);
    final LinkedHashSet<String> aliasNorms = LinkedHashSet<String>();
    for (final String alias in aliases) {
      final String normalized = normalizeForSearch(alias);
      if (normalized.isNotEmpty) aliasNorms.add(normalized);
    }
    final LinkedHashSet<String> aliasLookupNorms = LinkedHashSet<String>.from(
      aliasNorms,
    );
    if (normalizedName.isNotEmpty) {
      aliasLookupNorms.add(normalizedName);
    }
    final String canonicalNorm = normalizeCanonicalKey(
      canonicalKey ?? preferredName,
    );
    final String visualNorm = normalizeForSearch(visualSignatureSummary ?? '');
    await _ensureSearchIndexSynced();
    final Database db = await _db.database;

    final LinkedHashSet<String> candidateIds = LinkedHashSet<String>();
    final Map<String, double> sourceBonuses = <String, double>{};

    void addCandidate(String entityId, double bonus) {
      final String normalized = entityId.trim();
      if (normalized.isEmpty) return;
      candidateIds.add(normalized);
      final double current =
          sourceBonuses[normalized] ?? double.negativeInfinity;
      if (bonus > current) {
        sourceBonuses[normalized] = bonus;
      }
    }

    Future<void> addDirectMatches(
      String sql,
      List<Object?> args,
      double baseBonus,
    ) async {
      final List<Map<String, Object?>> rows = await db.rawQuery(sql, args);
      for (final Map<String, Object?> row in rows) {
        addCandidate((row['entity_id'] ?? '').toString(), baseBonus);
      }
    }

    if (canonicalNorm.isNotEmpty) {
      await addDirectMatches(
        '''
        SELECT entity_id
        FROM memory_entities
        WHERE root_uri = ? AND entity_type = ? AND canonical_key = ?
        LIMIT 24
        ''',
        <Object?>[normalizedRoot, normalizedType, canonicalNorm],
        12,
      );
    }

    if (normalizedName.isNotEmpty) {
      await addDirectMatches(
        '''
        SELECT entity_id
        FROM memory_entities
        WHERE root_uri = ? AND entity_type = ? AND preferred_name_norm = ?
        LIMIT 24
        ''',
        <Object?>[normalizedRoot, normalizedType, normalizedName],
        10,
      );
    }

    if (aliasLookupNorms.isNotEmpty) {
      final String placeholders = List<String>.filled(
        aliasLookupNorms.length,
        '?',
      ).join(', ');
      final List<Map<String, Object?>> aliasRows = await db.rawQuery(
        '''
        SELECT DISTINCT e.entity_id
        FROM memory_entity_aliases a
        INNER JOIN memory_entities e ON e.entity_id = a.entity_id
        WHERE e.root_uri = ?
          AND e.entity_type = ?
          AND a.alias_norm IN ($placeholders)
        LIMIT 32
        ''',
        <Object?>[normalizedRoot, normalizedType, ...aliasLookupNorms],
      );
      for (final Map<String, Object?> row in aliasRows) {
        addCandidate((row['entity_id'] ?? '').toString(), 8.5);
      }
    }

    final String ftsQuery = _buildFtsQuery(
      preferredNameNorm: normalizedName,
      aliasNorms: aliasNorms,
      canonicalNorm: canonicalNorm,
      visualSignatureNorm: visualNorm,
    );
    if (ftsQuery.isNotEmpty) {
      final List<Map<String, Object?>> ftsRows = await db.rawQuery(
        '''
        SELECT f.entity_id, bm25(memory_entity_search_fts) AS rank
        FROM memory_entity_search_fts f
        INNER JOIN memory_entities e ON e.entity_id = f.entity_id
        WHERE e.root_uri = ?
          AND e.entity_type = ?
          AND memory_entity_search_fts MATCH ?
        ORDER BY rank ASC
        LIMIT 32
        ''',
        <Object?>[normalizedRoot, normalizedType, ftsQuery],
      );
      for (int index = 0; index < ftsRows.length; index += 1) {
        final double bonus = math.max(1.2, 4.6 - (index * 0.12));
        addCandidate((ftsRows[index]['entity_id'] ?? '').toString(), bonus);
      }
    }

    final List<Map<String, Object?>> recentRows = await db.query(
      'memory_entities',
      columns: const <String>['entity_id'],
      where: 'root_uri = ? AND entity_type = ?',
      whereArgs: <Object?>[normalizedRoot, normalizedType],
      orderBy:
          "CASE status WHEN 'active' THEN 0 WHEN 'candidate' THEN 1 ELSE 2 END ASC, last_seen_at DESC, decayed_score DESC, raw_score DESC",
      limit: 24,
    );
    for (int index = 0; index < recentRows.length; index += 1) {
      final double bonus = math.max(0.2, 1.4 - (index * 0.05));
      addCandidate((recentRows[index]['entity_id'] ?? '').toString(), bonus);
    }

    if (candidateIds.isEmpty) {
      return const <MemoryEntitySearchCandidate>[];
    }

    final List<MemoryEntityRecord> records = await _loadEntityRecordsByIds(
      db,
      candidateIds.toList(growable: false),
    );
    final Map<String, List<String>> aliasMap = await _loadAliasMap(
      db,
      records.map((item) => item.entityId).toList(growable: false),
    );

    final List<({MemoryEntityRecord record, double score})> scored =
        <({MemoryEntityRecord record, double score})>[];
    for (final MemoryEntityRecord record in records) {
      final List<String> candidateAliases =
          aliasMap[record.entityId] ?? const <String>[];
      final double score =
          (sourceBonuses[record.entityId] ?? 0) +
          _candidateScore(
            record: record,
            preferredNameNorm: normalizedName,
            aliasNorms: aliasNorms,
            canonicalNorm: canonicalNorm,
            candidateAliases: candidateAliases,
            visualSignatureNorm: visualNorm,
          );
      if (score <= 0 && !sourceBonuses.containsKey(record.entityId)) continue;
      scored.add((record: record, score: score));
    }
    scored.sort((a, b) {
      final int primary = b.score.compareTo(a.score);
      if (primary != 0) return primary;
      final int secondary = b.record.decayedScore.compareTo(
        a.record.decayedScore,
      );
      if (secondary != 0) return secondary;
      return b.record.lastSeenAt.compareTo(a.record.lastSeenAt);
    });

    final List<MemoryEntitySearchCandidate> out =
        <MemoryEntitySearchCandidate>[];
    for (final ({MemoryEntityRecord record, double score}) item in scored.take(
      limit.clamp(1, 20),
    )) {
      out.add(
        await _buildSearchCandidate(
          item.record,
          aliases: aliasMap[item.record.entityId] ?? const <String>[],
        ),
      );
    }
    return out;
  }

  Future<List<MemoryEntityRecord>> _loadEntityRecordsByIds(
    DatabaseExecutor db,
    List<String> entityIds,
  ) async {
    final List<String> filtered = entityIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (filtered.isEmpty) return const <MemoryEntityRecord>[];
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (int start = 0; start < filtered.length; start += 400) {
      final List<String> batch = filtered.sublist(
        start,
        math.min(start + 400, filtered.length),
      );
      final String placeholders = List<String>.filled(
        batch.length,
        '?',
      ).join(', ');
      rows.addAll(
        await db.rawQuery('''
          SELECT *
          FROM memory_entities
          WHERE entity_id IN ($placeholders)
          ''', batch),
      );
    }
    return rows.map(MemoryEntityRecord.fromMap).toList(growable: false);
  }

  Future<MemoryEntitySearchCandidate> _buildSearchCandidate(
    MemoryEntityRecord record, {
    required List<String> aliases,
  }) async {
    return MemoryEntitySearchCandidate(
      entityId: record.entityId,
      rootUri: record.rootUri,
      entityType: record.entityType,
      preferredName: record.preferredName,
      canonicalKey: record.canonicalKey,
      displayUri: record.displayUri,
      currentSummary: record.currentSummary,
      visualSignatureSummary: record.visualSignatureSummary,
      status: record.status,
      rawScore: record.rawScore,
      decayedScore: record.decayedScore,
      distinctSegmentCount: record.distinctSegmentCount,
      distinctDayCount: record.distinctDayCount,
      strongSignalCount: record.strongSignalCount,
      exemplarSampleIds: await listExemplarSampleIds(record.entityId),
      aliases: aliases,
      lastEvidenceSummary: record.lastEvidenceSummary,
    );
  }

  Future<Map<String, List<String>>> _loadAliasMap(
    DatabaseExecutor db,
    List<String> entityIds,
  ) async {
    final List<String> filtered = entityIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (filtered.isEmpty) return const <String, List<String>>{};
    final Map<String, List<String>> out = <String, List<String>>{};
    for (int start = 0; start < filtered.length; start += 400) {
      final List<String> batch = filtered.sublist(
        start,
        math.min(start + 400, filtered.length),
      );
      final String placeholders = List<String>.filled(
        batch.length,
        '?',
      ).join(', ');
      final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT entity_id, alias, alias_text, source
        FROM memory_entity_aliases
        WHERE entity_id IN ($placeholders)
        ORDER BY alias_norm ASC
        ''', batch);
      for (final Map<String, Object?> row in rows) {
        final String entityId = (row['entity_id'] ?? '').toString().trim();
        final String source = (row['source'] ?? '').toString().trim();
        if (entityId.isEmpty || source == managedUriAliasSource) continue;
        final String alias = (row['alias_text'] ?? row['alias'] ?? '')
            .toString()
            .trim();
        if (alias.isEmpty) continue;
        out.putIfAbsent(entityId, () => <String>[]).add(alias);
      }
    }
    return out;
  }

  Future<void> _refreshEntitySearchIndex(String entityId) async {
    final String normalized = entityId.trim();
    if (normalized.isEmpty) return;
    final Database db = await _db.database;
    await _refreshEntitySearchIndexOn(db, normalized);
  }

  Future<void> _ensureSearchIndexSynced({bool force = false}) async {
    final Database db = await _db.database;
    final int entityCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM memory_entities'),
        ) ??
        0;
    final int searchCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) AS c FROM memory_entity_search_fts',
          ),
        ) ??
        0;

    if (entityCount <= 0) {
      if (searchCount > 0) {
        await db.delete('memory_entity_search_fts');
      }
      return;
    }

    if (!force && entityCount == searchCount) {
      final int missingCount =
          Sqflite.firstIntValue(
            await db.rawQuery('''
              SELECT COUNT(*) AS c
              FROM memory_entities e
              LEFT JOIN memory_entity_search_fts f
                ON f.entity_id = e.entity_id
              WHERE f.entity_id IS NULL
              '''),
          ) ??
          0;
      if (missingCount <= 0) {
        return;
      }
    }

    await db.transaction((txn) async {
      if (force) {
        await txn.delete('memory_entity_search_fts');
      }
      final List<Map<String, Object?>> rows = await txn.query(
        'memory_entities',
        columns: const <String>['entity_id'],
        orderBy: 'updated_at ASC, created_at ASC',
      );
      for (final Map<String, Object?> row in rows) {
        final String entityId = (row['entity_id'] ?? '').toString().trim();
        if (entityId.isEmpty) continue;
        await _refreshEntitySearchIndexOn(txn, entityId);
      }
    });
  }

  Future<void> _refreshEntitySearchIndexOn(
    DatabaseExecutor db,
    String entityId,
  ) async {
    final String normalized = entityId.trim();
    if (normalized.isEmpty) return;
    await db.delete(
      'memory_entity_search_fts',
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
    );
    final MemoryEntityRecord? record = await _findRecordById(db, normalized);
    if (record == null) return;

    final List<Map<String, Object?>> aliasRows = await db.query(
      'memory_entity_aliases',
      columns: const <String>['alias', 'alias_text', 'source'],
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
      orderBy: 'alias_norm ASC',
    );
    final List<String> aliases = aliasRows
        .where(
          (row) =>
              (row['source'] ?? '').toString().trim() != managedUriAliasSource,
        )
        .map(
          (row) => (row['alias_text'] ?? row['alias'] ?? '').toString().trim(),
        )
        .where((alias) => alias.isNotEmpty)
        .toList(growable: false);
    final List<Map<String, Object?>> claimRows = await db.query(
      'memory_entity_claims',
      columns: const <String>['fact_type', 'slot_key', 'value_text', 'value'],
      where: 'entity_id = ? AND active = 1',
      whereArgs: <Object?>[normalized],
      orderBy: 'confidence DESC, updated_at DESC',
      limit: 12,
    );
    final List<Map<String, Object?>> evidenceRows = await db.query(
      'memory_entity_evidence',
      columns: const <String>['evidence_summary'],
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
      orderBy: 'created_at DESC',
      limit: 4,
    );

    final String searchText = _buildSearchText(
      record: record,
      aliases: aliases,
      claimRows: claimRows,
      evidenceRows: evidenceRows,
    );
    if (searchText.isEmpty) return;
    await db.insert('memory_entity_search_fts', <String, Object?>{
      'entity_id': normalized,
      'search_text': searchText,
    });
  }

  String _buildSearchText({
    required MemoryEntityRecord record,
    required Iterable<String> aliases,
    required Iterable<Map<String, Object?>> claimRows,
    required Iterable<Map<String, Object?>> evidenceRows,
  }) {
    final LinkedHashSet<String> parts = LinkedHashSet<String>();

    void addText(String? raw) {
      final String normalized = normalizeForSearch(raw ?? '');
      if (normalized.isNotEmpty) {
        parts.add(normalized);
      }
    }

    addText(record.preferredName);
    addText(record.canonicalKey);
    addText(record.currentSummary);
    addText(record.visualSignatureSummary);
    addText(record.rootUri);
    addText(record.entityType);
    addText(record.status.wireName);
    for (final String alias in aliases) {
      addText(alias);
    }
    for (final Map<String, Object?> claim in claimRows) {
      addText((claim['fact_type'] ?? '').toString());
      addText((claim['slot_key'] ?? '').toString());
      addText((claim['value_text'] ?? claim['value'] ?? '').toString());
    }
    for (final Map<String, Object?> evidence in evidenceRows) {
      addText((evidence['evidence_summary'] ?? '').toString());
    }

    return parts.join('\n');
  }

  String _buildFtsQuery({
    required String preferredNameNorm,
    required Set<String> aliasNorms,
    required String canonicalNorm,
    required String visualSignatureNorm,
  }) {
    final LinkedHashSet<String> terms = LinkedHashSet<String>();

    void addTerm(String value) {
      final String normalized = value.trim();
      if (normalized.length >= 2) {
        terms.add('"${normalized.replaceAll('"', '""')}"');
      }
    }

    if (preferredNameNorm.isNotEmpty) {
      addTerm(preferredNameNorm);
      for (final String token in preferredNameNorm.split(' ')) {
        addTerm(token);
      }
    }
    for (final String alias in aliasNorms) {
      addTerm(alias);
      for (final String token in alias.split(' ')) {
        addTerm(token);
      }
    }
    if (canonicalNorm.isNotEmpty) {
      addTerm(canonicalNorm);
    }
    for (final String token in visualSignatureNorm.split(' ')) {
      if (token.length >= 3) {
        addTerm(token);
      }
      if (terms.length >= 10) break;
    }
    return terms.join(' OR ');
  }

  String deriveCanonicalKey({
    required MemoryEntityRootPolicy policy,
    required String preferredName,
    String? displayUri,
    String? explicitCanonicalKey,
  }) {
    final String normalizedDisplay = displayUri == null
        ? ''
        : canonicalizeUri(displayUri);
    if (normalizedDisplay == policy.rootUri) {
      return rootAggregateCanonicalKey;
    }
    final String explicit = normalizeCanonicalKey(explicitCanonicalKey ?? '');
    if (explicit.isNotEmpty) return explicit;
    final String nameKey = normalizeCanonicalKey(preferredName);
    if (nameKey.isNotEmpty) return nameKey;
    if (normalizedDisplay.isNotEmpty) {
      final String leaf = _mem
          .parseUri(normalizedDisplay)
          .path
          .split('/')
          .last
          .trim();
      final String leafKey = normalizeCanonicalKey(leaf);
      if (leafKey.isNotEmpty) return leafKey;
    }
    return 'entity_${_stableHashBase36(preferredName)}';
  }

  String deriveSlugPath({
    required MemoryEntityRootPolicy policy,
    required String preferredName,
    required String canonicalKey,
  }) {
    if (canonicalKey == rootAggregateCanonicalKey &&
        policy.allowRootMaterialization) {
      return '';
    }
    final String fromCanonical = _normalizeSlugPath(slugify(canonicalKey));
    if (fromCanonical.isNotEmpty) return fromCanonical;
    final String fromName = _normalizeSlugPath(slugify(preferredName));
    if (fromName.isNotEmpty) return fromName;
    return 'entity_${_stableHashBase36(canonicalKey)}';
  }

  String buildDisplayUri({
    required String rootUri,
    required String slugPath,
    required String canonicalKey,
  }) {
    final String normalizedRoot = canonicalizeUri(rootUri);
    if (canonicalKey == rootAggregateCanonicalKey || slugPath.trim().isEmpty) {
      return normalizedRoot;
    }
    final NocturneUri parsed = _mem.parseUri(normalizedRoot);
    final String nextPath = parsed.path.isEmpty
        ? slugPath.trim()
        : '${parsed.path}/${slugPath.trim()}';
    return _mem.makeUri(parsed.domain, nextPath);
  }

  Future<MemoryEntityApplyResult> recordCompatObservation({
    required String rootUri,
    required String displayUri,
    required String preferredName,
    required String latestContent,
    required String evidenceSummary,
    required List<String> appNames,
    required int segmentId,
    required int batchIndex,
    required int? segmentStartMs,
    required int? segmentEndMs,
    required String actionKind,
    required List<String> aliases,
    List<MemoryEntityFactCandidate> claims =
        const <MemoryEntityFactCandidate>[],
    List<MemoryEntityExemplar> exemplars = const <MemoryEntityExemplar>[],
  }) async {
    throw UnsupportedError(
      'uri-first compatibility ingestion has been removed; use applyAIPipelineResult() with entity_id-first resolution instead.',
    );
  }

  Future<MemoryEntityApplyResult> applyAIPipelineResult({
    required MemoryVisualCandidate visualCandidate,
    required MemoryEntityResolutionWorkflowResult resolutionWorkflow,
    required MemoryStructuredDecisionResult<MemoryEntityMergePlan>
    mergePlanResult,
    required MemoryStructuredDecisionResult<MemoryEntityAuditDecision>
    auditResult,
    required List<MemoryEntityDossier> shortlist,
    required int segmentId,
    required int batchIndex,
    required int? segmentStartMs,
    required int? segmentEndMs,
    required String evidenceSummary,
    required List<String> appNames,
    required List<MemoryEntityExemplar> exemplars,
  }) async {
    final MemoryEntityRootPolicy policy =
        MemoryEntityPolicies.forRootKey(visualCandidate.rootKey) ??
        (throw StateError('未知的 root_key: ${visualCandidate.rootKey}'));
    final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    resolutionResult = resolutionWorkflow.finalResult;
    final MemoryEntityResolutionDecision resolution = resolutionResult.value;
    final MemoryEntityMergePlan mergePlan = mergePlanResult.value;
    final MemoryEntityAuditDecision audit = auditResult.value;

    final String preferredName = _pickNonEmpty(
      mergePlan.preferredName,
      resolution.suggestedPreferredName,
      visualCandidate.preferredName,
      policy.rootKey,
    );
    final String canonicalKey = deriveCanonicalKey(
      policy: policy,
      preferredName: preferredName,
    );
    final String slugPath = deriveSlugPath(
      policy: policy,
      preferredName: preferredName,
      canonicalKey: canonicalKey,
    );
    final String desiredDisplayUri = buildDisplayUri(
      rootUri: policy.rootUri,
      slugPath: slugPath,
      canonicalKey: canonicalKey,
    );
    final bool strongSignal = _isStrongSignal(
      policy: policy,
      displayUri: desiredDisplayUri,
      content: mergePlan.summaryRewrite,
      aliases: visualCandidate.aliases,
    );
    final bool needsReview =
        resolution.needsReview ||
        resolution.action == MemoryEntityResolutionAction.reviewRequired ||
        audit.action != MemoryEntityAuditAction.approve;
    final String reviewReason = needsReview
        ? <String>[
            ...resolution.conflicts,
            ...audit.reasons,
            ...resolution.reasons,
          ].where((part) => part.trim().isNotEmpty).join('；')
        : '';

    final List<
      ({
        String stage,
        String action,
        double confidence,
        String? modelName,
        String inputJson,
        String outputJson,
        String payloadJson,
      })
    >
    resolutionStagePayloads =
        <
          ({
            String stage,
            String action,
            double confidence,
            String? modelName,
            String inputJson,
            String outputJson,
            String payloadJson,
          })
        >[
          for (final MemoryPipelineAuditEntry entry
              in resolutionWorkflow.auditTrail)
            (
              stage: entry.stage,
              action: entry.action,
              confidence: entry.confidence,
              modelName: entry.modelUsed,
              inputJson: entry.inputJson,
              outputJson: entry.outputJson,
              payloadJson: entry.payloadJson,
            ),
          (
            stage: 'merge_plan',
            action: 'MERGE_PLAN',
            confidence: resolution.confidence,
            modelName: mergePlanResult.modelUsed,
            inputJson: mergePlanResult.inputJson,
            outputJson: mergePlanResult.outputJson,
            payloadJson: mergePlanResult.outputJson,
          ),
          (
            stage: 'audit',
            action: audit.action.wireName,
            confidence: audit.confidence,
            modelName: auditResult.modelUsed,
            inputJson: auditResult.inputJson,
            outputJson: auditResult.outputJson,
            payloadJson: auditResult.outputJson,
          ),
        ];

    if (needsReview) {
      await _enqueueReviewQueueItem(
        candidateId: visualCandidate.candidateId,
        rootUri: policy.rootUri,
        entityType: policy.entityType,
        preferredName: preferredName,
        segmentId: segmentId,
        batchIndex: batchIndex,
        reviewStage: audit.action != MemoryEntityAuditAction.approve
            ? 'audit'
            : 'resolution',
        reviewReason: reviewReason.isEmpty ? '需要人工复核' : reviewReason,
        suggestedEntityId:
            audit.suggestedEntityId ?? resolution.matchedEntityId,
        evidenceSummary: evidenceSummary,
        appNames: appNames,
        candidateJson: encodeJsonPretty(visualCandidate.toJson()),
        shortlistJson: encodeJsonPretty(<String, dynamic>{
          'shortlist': shortlist
              .map((item) => item.toJson(includeFilePaths: false))
              .toList(growable: false),
        }),
        resolutionJson: encodeJsonPretty(resolution.toJson()),
        mergePlanJson: encodeJsonPretty(mergePlan.toJson()),
        auditJson: encodeJsonPretty(audit.toJson()),
        resolutionStagePayloads: resolutionStagePayloads,
      );
      return MemoryEntityApplyResult(
        record: null,
        created: false,
        needsReview: true,
        queuedForReview: true,
        reviewReason: reviewReason.isEmpty ? '需要人工复核' : reviewReason,
      );
    }

    final String? explicitEntityId = resolution.matchedEntityId?.trim();

    return _upsertEntityObservation(
      policy: policy,
      explicitEntityId: explicitEntityId,
      desiredDisplayUri: desiredDisplayUri,
      preferredName: preferredName,
      canonicalKey: canonicalKey,
      latestContent: _normalizeContent(
        mergePlan.summaryRewrite.isNotEmpty
            ? mergePlan.summaryRewrite
            : visualCandidate.preferredName,
      ),
      currentSummary: _summarizeContent(mergePlan.summaryRewrite),
      visualSignatureSummary: _pickNonEmpty(
        mergePlan.visualSignatureSummary,
        visualCandidate.visualSignatureSummary,
        '',
        '',
      ),
      aliases: <String>[
        ...visualCandidate.aliases,
        ...resolution.aliasesToAdd,
        ...mergePlan.aliasesToAdd,
      ],
      claims: mergePlan.claimsToUpsert,
      events: mergePlan.eventsToAppend,
      candidateId: visualCandidate.candidateId,
      resolutionStagePayloads: resolutionStagePayloads,
      segmentId: segmentId,
      batchIndex: batchIndex,
      segmentStartMs: segmentStartMs,
      segmentEndMs: segmentEndMs,
      evidenceSummary: evidenceSummary,
      appNames: appNames,
      actionKind: 'ai_rebuild',
      strongSignal: strongSignal,
      score: _scoreEpisode(
        policy: policy,
        displayUri: desiredDisplayUri,
        actionKind: 'ai_rebuild',
        content: mergePlan.summaryRewrite,
        strongSignal: strongSignal,
      ),
      exemplars: exemplars,
      needsReview: false,
      reviewReason: '',
      matchMode: _EntityObservationMatchMode.explicitOnly,
      deriveDisplayUriFromCanonicalKey: true,
    );
  }

  Future<void> rewriteEntityContent({
    required String entityId,
    required String content,
  }) async {
    final String normalized = _normalizeContent(content);
    if (normalized.isEmpty) {
      throw ArgumentError('content must not be empty');
    }
    final Database db = await _db.database;
    await db.update(
      'memory_entities',
      <String, Object?>{
        'latest_content': normalized,
        'current_summary': _summarizeContent(normalized),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId.trim()],
    );
    await _syncSignalReadModelsForEntity(entityId.trim());
    await _refreshEntitySearchIndex(entityId.trim());
  }

  Future<void> moveEntityLeaf({
    required String entityId,
    required String targetUri,
  }) async {
    final MemoryEntityRecord record =
        await getRecordById(entityId) ??
        (throw StateError('entity not found: $entityId'));
    final String normalizedTarget = canonicalizeUri(targetUri);
    final MemoryEntityRootPolicy targetPolicy =
        MemoryEntityPolicies.forRootUri(normalizedTarget) ??
        (throw StateError('target uri is not managed: $normalizedTarget'));
    final String canonicalKey = deriveCanonicalKey(
      policy: targetPolicy,
      preferredName: record.preferredName,
      displayUri: normalizedTarget,
      explicitCanonicalKey: record.canonicalKey,
    );
    final Database db = await _db.database;
    await db.transaction((txn) async {
      final String finalUri = await _ensureUniqueDisplayUri(
        txn,
        desiredUri: normalizedTarget,
        entityId: record.entityId,
      );
      await txn.update(
        'memory_entities',
        <String, Object?>{
          'root_uri': targetPolicy.rootUri,
          'entity_type': targetPolicy.entityType,
          'display_uri': finalUri,
          'canonical_key': canonicalKey,
          'activation_score': targetPolicy.activationScore,
          'min_distinct_days': targetPolicy.minDistinctDays,
          'allow_single_strong_activation':
              targetPolicy.allowSingleStrongActivation ? 1 : 0,
          'allow_root_materialization': targetPolicy.allowRootMaterialization
              ? 1
              : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'entity_id = ?',
        whereArgs: <Object?>[record.entityId],
      );
      await txn.delete(
        'memory_entity_aliases',
        where: 'entity_id = ? AND source = ? AND alias = ?',
        whereArgs: <Object?>[
          record.entityId,
          managedUriAliasSource,
          normalizedTarget,
        ],
      );
    });
    await _recalculateEntitySignals(record.entityId);
    await _refreshEntitySearchIndex(record.entityId);
  }

  Future<void> archiveEntity(String entityId) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Database db = await _db.database;
    await db.update(
      'memory_entities',
      <String, Object?>{
        'status': MemoryEntityStatus.archived.wireName,
        'archived_at': now,
        'updated_at': now,
      },
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId.trim()],
    );
    await _syncSignalReadModelsForEntity(entityId.trim());
    await _refreshEntitySearchIndex(entityId.trim());
  }

  Future<void> _restoreLegacyStatus({
    required String entityId,
    required MemoryEntityStatus status,
    required int activatedAt,
    required int archivedAt,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, Object?> values = <String, Object?>{
      'status': status.wireName,
      'updated_at': now,
    };
    if (status == MemoryEntityStatus.active) {
      values['activated_at'] = activatedAt > 0 ? activatedAt : now;
      values['archived_at'] = null;
    } else if (status == MemoryEntityStatus.archived) {
      values['archived_at'] = archivedAt > 0 ? archivedAt : now;
      if (activatedAt > 0) {
        values['activated_at'] = activatedAt;
      }
    }
    await (await _db.database).update(
      'memory_entities',
      values,
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId.trim()],
    );
    await _syncSignalReadModelsForEntity(entityId.trim());
  }

  Future<void> deleteEntity(String entityId) async {
    final String normalized = entityId.trim();
    final Database db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'memory_signal_episodes',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_signal_profiles',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_resolution_audits',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_events',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_exemplars',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_evidence',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_episodes',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_claims',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_aliases',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entities',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      await txn.delete(
        'memory_entity_search_fts',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
    });
  }

  Future<void> addManagedUriAlias({
    required String entityId,
    required String uri,
  }) async {
    final String normalizedUri = canonicalizeUri(uri);
    final Database db = await _db.database;
    await db.insert('memory_entity_aliases', <String, Object?>{
      'entity_id': entityId.trim(),
      'alias': normalizedUri,
      'alias_text': normalizedUri,
      'alias_norm': normalizedUri.toLowerCase(),
      'alias_type': 'display_uri',
      'source': managedUriAliasSource,
      'confidence': 1.0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _refreshEntitySearchIndex(entityId.trim());
  }

  Future<void> markMaterialized(String entityId) async {
    await (await _db.database).update(
      'memory_entities',
      <String, Object?>{
        'last_materialized_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId.trim()],
    );
    await _syncSignalReadModelsForEntity(entityId.trim());
  }

  Future<MemoryEntityApplyResult> _upsertEntityObservation({
    required MemoryEntityRootPolicy policy,
    required String? explicitEntityId,
    required String desiredDisplayUri,
    required String preferredName,
    required String canonicalKey,
    required String latestContent,
    required String currentSummary,
    required String visualSignatureSummary,
    required List<String> aliases,
    required List<MemoryEntityFactCandidate> claims,
    required List<MemoryEntityEventCandidate> events,
    required String candidateId,
    required List<
      ({
        String stage,
        String action,
        double confidence,
        String? modelName,
        String inputJson,
        String outputJson,
        String payloadJson,
      })
    >
    resolutionStagePayloads,
    required int segmentId,
    required int batchIndex,
    required int? segmentStartMs,
    required int? segmentEndMs,
    required String evidenceSummary,
    required List<String> appNames,
    required String actionKind,
    required bool strongSignal,
    required double score,
    required List<MemoryEntityExemplar> exemplars,
    required bool needsReview,
    required String reviewReason,
    required _EntityObservationMatchMode matchMode,
    required bool deriveDisplayUriFromCanonicalKey,
  }) async {
    final Database db = await _db.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    String resolvedEntityId = '';
    bool created = false;

    await db.transaction((txn) async {
      MemoryEntityRecord? existing;
      if ((explicitEntityId ?? '').trim().isNotEmpty) {
        existing = await _findRecordById(txn, explicitEntityId!.trim());
      }
      if (existing == null) {
        switch (matchMode) {
          case _EntityObservationMatchMode.explicitOnly:
            break;
          case _EntityObservationMatchMode.explicitOrDisplayUri:
            existing = await _findRecordByDisplayUri(txn, desiredDisplayUri);
            break;
        }
      }

      final String resolvedCanonicalKey =
          existing?.canonicalKey ??
          await _ensureUniqueCanonicalKey(
            txn,
            rootUri: policy.rootUri,
            entityType: policy.entityType,
            desiredCanonicalKey: canonicalKey,
            entityId: null,
          );
      final String derivedDisplayUri = deriveDisplayUriFromCanonicalKey
          ? buildDisplayUri(
              rootUri: policy.rootUri,
              slugPath: deriveSlugPath(
                policy: policy,
                preferredName: preferredName,
                canonicalKey: resolvedCanonicalKey,
              ),
              canonicalKey: resolvedCanonicalKey,
            )
          : desiredDisplayUri;
      final String finalDisplayUri = existing == null
          ? await _ensureUniqueDisplayUri(
              txn,
              desiredUri: derivedDisplayUri,
              entityId: null,
            )
          : existing.displayUri;
      final String mergedContent = existing == null
          ? _normalizeContent(latestContent)
          : _mergeDraftContent(
              existing: existing.latestContent,
              incoming: latestContent,
            );

      final String entityId = existing?.entityId ?? _uuidV4();
      final String sourceBatchId = '$segmentId:$batchIndex';
      resolvedEntityId = entityId;
      created = existing == null;

      final Map<String, Object?> values = <String, Object?>{
        'entity_id': entityId,
        'root_uri': policy.rootUri,
        'entity_type': policy.entityType,
        'preferred_name': preferredName.trim(),
        'preferred_name_norm': normalizeForSearch(preferredName),
        'canonical_key': resolvedCanonicalKey,
        'display_uri': finalDisplayUri,
        'status':
            existing?.status.wireName ?? MemoryEntityStatus.candidate.wireName,
        'current_summary': currentSummary.trim().isNotEmpty
            ? currentSummary.trim()
            : _summarizeContent(mergedContent),
        'latest_content': mergedContent,
        'visual_signature_summary': visualSignatureSummary.trim(),
        'activation_score': policy.activationScore,
        'min_distinct_days': policy.minDistinctDays,
        'allow_single_strong_activation': policy.allowSingleStrongActivation
            ? 1
            : 0,
        'allow_root_materialization': policy.allowRootMaterialization ? 1 : 0,
        'needs_review': needsReview ? 1 : 0,
        'review_reason': reviewReason.trim().isEmpty
            ? null
            : reviewReason.trim(),
        'last_evidence_summary': evidenceSummary.trim().isEmpty
            ? null
            : evidenceSummary.trim(),
        'updated_at': now,
      };
      if (existing == null) {
        values['created_at'] = now;
      }
      if (segmentStartMs != null && segmentStartMs > 0) {
        values['first_seen_at'] = existing == null || existing.firstSeenAt <= 0
            ? segmentStartMs
            : math.min(existing.firstSeenAt, segmentStartMs);
        values['last_seen_at'] = existing == null
            ? segmentStartMs
            : math.max(existing.lastSeenAt, segmentStartMs);
      }

      if (existing == null) {
        await txn.insert('memory_entities', values);
      } else {
        await txn.update(
          'memory_entities',
          values,
          where: 'entity_id = ?',
          whereArgs: <Object?>[entityId],
        );
      }

      final LinkedHashSet<String> aliasValues = LinkedHashSet<String>();
      for (final String alias in aliases) {
        final String normalized = alias.trim();
        if (normalized.isEmpty || normalized == preferredName.trim()) {
          continue;
        }
        aliasValues.add(normalized);
      }
      for (final String alias in aliasValues) {
        final String norm = normalizeForSearch(alias);
        if (norm.isEmpty) continue;
        await txn.insert('memory_entity_aliases', <String, Object?>{
          'entity_id': entityId,
          'alias': alias,
          'alias_text': alias,
          'alias_norm': norm,
          'alias_type': 'semantic',
          'source': 'semantic',
          'confidence': 1.0,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final MemoryEntityFactCandidate claim in claims) {
        final String normalizedValue = normalizeForSearch(claim.value);
        if (normalizedValue.isEmpty) continue;
        final String? slotKey = (claim.slotKey ?? '').trim().isEmpty
            ? null
            : claim.slotKey!.trim();
        if (claim.cardinality == MemoryEntityCardinality.singleton &&
            slotKey != null) {
          await txn.update(
            'memory_entity_claims',
            <String, Object?>{
              'active': 0,
              'status': 'inactive',
              'valid_to': now,
              'updated_at': now,
            },
            where:
                'entity_id = ? AND fact_type = ? AND slot_key = ? AND value_norm <> ?',
            whereArgs: <Object?>[
              entityId,
              claim.factType,
              slotKey,
              normalizedValue,
            ],
          );
        }
        final Map<String, Object?> claimInsertValues = <String, Object?>{
          'claim_id': _uuidV4(),
          'entity_id': entityId,
          'fact_type': claim.factType.trim(),
          'slot_key': slotKey,
          'value': claim.value.trim(),
          'value_text': claim.value.trim(),
          'value_norm': normalizedValue,
          'cardinality': claim.cardinality.wireName,
          'status': 'active',
          'confidence': claim.confidence,
          'active': 1,
          'valid_from': segmentStartMs ?? segmentEndMs ?? now,
          'valid_to': null,
          'evidence_frames_json': claim.evidenceFrames.isEmpty
              ? null
              : jsonEncode(claim.evidenceFrames),
          'source_batch_id': sourceBatchId,
          'source': actionKind,
          'updated_at': now,
        };
        final Map<String, Object?> claimUpdateValues = <String, Object?>{
          'value': claim.value.trim(),
          'value_text': claim.value.trim(),
          'cardinality': claim.cardinality.wireName,
          'status': 'active',
          'confidence': claim.confidence,
          'active': 1,
          'valid_from': segmentStartMs ?? segmentEndMs ?? now,
          'valid_to': null,
          'evidence_frames_json': claim.evidenceFrames.isEmpty
              ? null
              : jsonEncode(claim.evidenceFrames),
          'source_batch_id': sourceBatchId,
          'source': actionKind,
          'updated_at': now,
        };
        await txn.insert(
          'memory_entity_claims',
          claimInsertValues,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.update(
          'memory_entity_claims',
          claimUpdateValues,
          where:
              'entity_id = ? AND fact_type = ? AND ${slotKey == null ? "slot_key IS NULL" : "slot_key = ?"} AND value_norm = ?',
          whereArgs: <Object?>[
            entityId,
            claim.factType.trim(),
            if (slotKey != null) slotKey,
            normalizedValue,
          ],
        );
      }

      for (final MemoryEntityEventCandidate event in events) {
        final String normalizedNote = event.note.trim();
        if (normalizedNote.isEmpty) continue;
        await txn.insert('memory_entity_events', <String, Object?>{
          'entity_id': entityId,
          'event_note': normalizedNote,
          'evidence_frames_json': event.evidenceFrames.isEmpty
              ? null
              : jsonEncode(event.evidenceFrames),
          'source_batch_id': sourceBatchId,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      final int firstSeenAt = segmentStartMs != null && segmentStartMs > 0
          ? segmentStartMs
          : (segmentEndMs ?? now);
      final int lastSeenAt = segmentEndMs != null && segmentEndMs > 0
          ? segmentEndMs
          : firstSeenAt;
      await txn.insert('memory_entity_episodes', <String, Object?>{
        'entity_id': entityId,
        'root_uri': policy.rootUri,
        'display_uri': finalDisplayUri,
        'segment_id': segmentId,
        'batch_index': batchIndex,
        'day_key': _dayKey(firstSeenAt),
        'first_seen_at': firstSeenAt,
        'last_seen_at': lastSeenAt,
        'score': score,
        'strong_signal': strongSignal ? 1 : 0,
        'action_kind': actionKind,
        'evidence_summary': evidenceSummary,
        'app_names_json': jsonEncode(appNames.toSet().toList()..sort()),
        'content_snapshot': _normalizeContent(latestContent),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('memory_entity_evidence', <String, Object?>{
        'entity_id': entityId,
        'segment_id': segmentId,
        'batch_index': batchIndex,
        'evidence_summary': evidenceSummary,
        'apps_json': jsonEncode(appNames.toSet().toList()..sort()),
        'app_names_json': jsonEncode(appNames.toSet().toList()..sort()),
        'sample_ids_json': jsonEncode(
          exemplars
              .map((item) => item.sampleId)
              .whereType<int>()
              .toSet()
              .toList()
            ..sort(),
        ),
        'frame_count': exemplars.length,
        'start_at': segmentStartMs,
        'end_at': segmentEndMs,
      });
      int rankCounter = 0;
      for (final MemoryEntityExemplar exemplar in exemplars) {
        await txn.insert('memory_entity_exemplars', <String, Object?>{
          'entity_id': entityId,
          'segment_id': segmentId,
          'batch_index': batchIndex,
          'sample_id': exemplar.sampleId,
          'capture_time': exemplar.captureTime,
          'app_name': exemplar.appName,
          'file_path': exemplar.filePath,
          'position_index': exemplar.positionIndex ?? 0,
          'rank': exemplar.rank ?? rankCounter,
          'reason': exemplar.reason ?? 'evidence_frame',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        rankCounter += 1;
      }
      await _insertPipelineAuditRows(
        txn,
        entityId: entityId,
        candidateId: candidateId,
        segmentId: segmentId,
        batchIndex: batchIndex,
        resolutionStagePayloads: resolutionStagePayloads,
      );
      final String? commitAuditAction = _inferCommitAuditAction(
        created: created,
        resolutionStagePayloads: resolutionStagePayloads,
      );
      if (commitAuditAction != null) {
        await _insertCommitAuditRow(
          txn,
          entityId: entityId,
          candidateId: candidateId,
          segmentId: segmentId,
          batchIndex: batchIndex,
          action: commitAuditAction,
          payload: <String, Object?>{
            'entity_id': entityId,
            'created': created,
            'action_kind': actionKind,
            'display_uri': finalDisplayUri,
          },
        );
      }
    });

    await _recalculateEntitySignals(resolvedEntityId);
    await _refreshEntitySearchIndex(resolvedEntityId);
    final MemoryEntityRecord record =
        await getRecordById(resolvedEntityId) ??
        (throw StateError('entity write succeeded but row was not found'));
    return MemoryEntityApplyResult(
      record: record,
      created: created,
      needsReview: record.needsReview,
      queuedForReview: false,
      reviewReason: record.reviewReason,
    );
  }

  Future<void> _enqueueReviewQueueItem({
    required String candidateId,
    required String rootUri,
    required String entityType,
    required String preferredName,
    required int segmentId,
    required int batchIndex,
    required String reviewStage,
    required String reviewReason,
    required String? suggestedEntityId,
    required String evidenceSummary,
    required List<String> appNames,
    required String candidateJson,
    required String shortlistJson,
    required String resolutionJson,
    required String mergePlanJson,
    required String auditJson,
    required List<
      ({
        String stage,
        String action,
        double confidence,
        String? modelName,
        String inputJson,
        String outputJson,
        String payloadJson,
      })
    >
    resolutionStagePayloads,
  }) async {
    final Database db = await _db.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert('memory_entity_review_queue', <String, Object?>{
        'candidate_id': candidateId.trim(),
        'root_uri': canonicalizeUri(rootUri),
        'entity_type': entityType.trim().toLowerCase(),
        'preferred_name': preferredName.trim(),
        'segment_id': segmentId,
        'batch_index': batchIndex,
        'review_stage': reviewStage.trim(),
        'review_reason': reviewReason.trim(),
        'suggested_entity_id': suggestedEntityId?.trim(),
        'status': MemoryEntityReviewStatus.pending.wireName,
        'evidence_summary': evidenceSummary.trim().isEmpty
            ? null
            : evidenceSummary.trim(),
        'app_names_json': jsonEncode(appNames.toSet().toList()..sort()),
        'candidate_json': candidateJson,
        'shortlist_json': shortlistJson,
        'resolution_json': resolutionJson,
        'merge_plan_json': mergePlanJson,
        'audit_json': auditJson,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _insertPipelineAuditRows(
        txn,
        entityId: null,
        candidateId: candidateId,
        segmentId: segmentId,
        batchIndex: batchIndex,
        resolutionStagePayloads: resolutionStagePayloads,
      );
      await _insertCommitAuditRow(
        txn,
        entityId: suggestedEntityId?.trim().isEmpty == true
            ? null
            : suggestedEntityId?.trim(),
        candidateId: candidateId,
        segmentId: segmentId,
        batchIndex: batchIndex,
        action: 'QUEUE_REVIEW',
        payload: <String, Object?>{
          'review_stage': reviewStage.trim(),
          'review_reason': reviewReason.trim(),
          'suggested_entity_id': suggestedEntityId?.trim(),
        },
      );
    });
  }

  Future<void> _insertPipelineAuditRows(
    DatabaseExecutor txn, {
    required String? entityId,
    required String candidateId,
    required int segmentId,
    required int batchIndex,
    required List<
      ({
        String stage,
        String action,
        double confidence,
        String? modelName,
        String inputJson,
        String outputJson,
        String payloadJson,
      })
    >
    resolutionStagePayloads,
  }) async {
    for (final ({
          String stage,
          String action,
          double confidence,
          String? modelName,
          String inputJson,
          String outputJson,
          String payloadJson,
        })
        payload
        in resolutionStagePayloads) {
      await txn.insert('memory_entity_resolution_audits', <String, Object?>{
        'entity_id': entityId,
        'segment_id': segmentId,
        'batch_index': batchIndex,
        'candidate_id': candidateId,
        'stage': payload.stage,
        'action': payload.action,
        'confidence': payload.confidence,
        'model_name': payload.modelName?.trim(),
        'input_json': payload.inputJson,
        'output_json': payload.outputJson,
        'payload_json': payload.payloadJson,
      });
    }
  }

  String? _inferCommitAuditAction({
    required bool created,
    required List<
      ({
        String stage,
        String action,
        double confidence,
        String? modelName,
        String inputJson,
        String outputJson,
        String payloadJson,
      })
    >
    resolutionStagePayloads,
  }) {
    if (resolutionStagePayloads.isEmpty) return null;
    if (created) return 'CREATE_NEW_ENTITY';
    final String resolutionAction = resolutionStagePayloads
        .where((payload) => payload.stage.contains('resolution'))
        .map((payload) => payload.action.trim())
        .firstWhere((action) => action.isNotEmpty, orElse: () => '');
    if (resolutionAction ==
        MemoryEntityResolutionAction.addAliasToExisting.wireName) {
      return 'MERGE_EXISTING_ALIAS';
    }
    return 'MERGE_EXISTING_ENTITY';
  }

  Future<void> _insertCommitAuditRow(
    DatabaseExecutor txn, {
    required String? entityId,
    required String candidateId,
    required int segmentId,
    required int batchIndex,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    final String payloadJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(payload);
    await txn.insert('memory_entity_resolution_audits', <String, Object?>{
      'entity_id': entityId?.trim().isEmpty == true ? null : entityId?.trim(),
      'segment_id': segmentId,
      'batch_index': batchIndex,
      'candidate_id': candidateId.trim(),
      'stage': 'apply_commit',
      'action': action.trim(),
      'confidence': 1.0,
      'model_name': 'system',
      'input_json': null,
      'output_json': payloadJson,
      'payload_json': payloadJson,
    });
  }

  Future<void> _recalculateEntitySignals(String entityId) async {
    final String normalizedEntityId = entityId.trim();
    if (normalizedEntityId.isEmpty) return;
    final Database db = await _db.database;
    final MemoryEntityRecord existing =
        await getRecordById(normalizedEntityId) ??
        (throw StateError('entity not found: $normalizedEntityId'));
    final MemoryEntityRootPolicy policy =
        MemoryEntityPolicies.forRootUri(existing.rootUri) ??
        (throw StateError('missing root policy: ${existing.rootUri}'));
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entity_episodes',
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalizedEntityId],
      orderBy: 'last_seen_at ASC',
    );

    if (rows.isEmpty) return;

    final LinkedHashSet<int> segments = LinkedHashSet<int>();
    final LinkedHashSet<String> dayKeys = LinkedHashSet<String>();
    int strongCount = 0;
    int firstSeenAt = 0;
    int lastSeenAt = 0;
    double rawScore = 0;
    double decayedScore = 0;
    final int now = DateTime.now().millisecondsSinceEpoch;

    for (final Map<String, Object?> row in rows) {
      final int segmentId = _toInt(row['segment_id']);
      final String dayKey = (row['day_key'] ?? '').toString();
      final int rowFirst = _toInt(row['first_seen_at']);
      final int rowLast = _toInt(row['last_seen_at']);
      final double score = _toDouble(row['score']);
      final bool strong = _toInt(row['strong_signal']) > 0;

      if (segmentId > 0) segments.add(segmentId);
      if (dayKey.isNotEmpty) dayKeys.add(dayKey);
      if (strong) strongCount += 1;
      if (firstSeenAt <= 0 || (rowFirst > 0 && rowFirst < firstSeenAt)) {
        firstSeenAt = rowFirst;
      }
      if (rowLast > lastSeenAt) {
        lastSeenAt = rowLast;
      }
      rawScore += score;
      final double ageDays =
          math.max(0, now - rowLast) / Duration.millisecondsPerDay;
      decayedScore +=
          score * math.exp(-ageDays / policy.decayTauDays.toDouble());
    }

    final bool rootOnly = existing.displayUri == policy.rootUri;
    final bool evidenceSatisfied =
        dayKeys.length >= policy.minDistinctDays ||
        (strongCount > 0 && policy.allowSingleStrongActivation);
    final bool rootBlocked = rootOnly && !policy.allowRootMaterialization;
    final bool reviewBlocked = existing.needsReview;
    final bool readyToActivate =
        decayedScore >= policy.activationScore &&
        evidenceSatisfied &&
        !rootBlocked &&
        !reviewBlocked;

    MemoryEntityStatus status = existing.status;
    int? activatedAt = existing.activatedAt > 0 ? existing.activatedAt : null;
    int? archivedAt = existing.archivedAt > 0 ? existing.archivedAt : null;

    if (readyToActivate) {
      status = MemoryEntityStatus.active;
      activatedAt ??= now;
      archivedAt = null;
    } else if (reviewBlocked) {
      status = MemoryEntityStatus.candidate;
      archivedAt = null;
    } else {
      final double daysSinceLast =
          math.max(0, now - lastSeenAt) / Duration.millisecondsPerDay;
      if (rawScore >= 1.2 && daysSinceLast >= policy.archiveAfterDays) {
        status = MemoryEntityStatus.archived;
        archivedAt ??= now;
      } else if (existing.status == MemoryEntityStatus.active &&
          existing.activatedAt > 0) {
        status = MemoryEntityStatus.active;
        activatedAt = existing.activatedAt;
        archivedAt = null;
      } else if (status != MemoryEntityStatus.archived) {
        status = MemoryEntityStatus.candidate;
      }
    }

    await db.update(
      'memory_entities',
      <String, Object?>{
        'status': status.wireName,
        'raw_score': rawScore,
        'decayed_score': decayedScore,
        'activation_score': policy.activationScore,
        'evidence_count': rows.length,
        'distinct_segment_count': segments.length,
        'distinct_day_count': dayKeys.length,
        'strong_signal_count': strongCount,
        'min_distinct_days': policy.minDistinctDays,
        'allow_single_strong_activation': policy.allowSingleStrongActivation
            ? 1
            : 0,
        'allow_root_materialization': policy.allowRootMaterialization ? 1 : 0,
        'evidence_satisfied': evidenceSatisfied ? 1 : 0,
        'ready_to_activate': readyToActivate ? 1 : 0,
        'root_materialization_blocked': rootBlocked ? 1 : 0,
        'missing_activation_score': math.max(
          0,
          policy.activationScore - decayedScore,
        ),
        'missing_distinct_days': math.max(
          0,
          policy.minDistinctDays - dayKeys.length,
        ),
        'first_seen_at': firstSeenAt > 0 ? firstSeenAt : null,
        'last_seen_at': lastSeenAt > 0 ? lastSeenAt : null,
        'activated_at': activatedAt,
        'archived_at': archivedAt,
        'updated_at': now,
      },
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalizedEntityId],
    );
    await _syncSignalReadModelsForEntityTxn(db, normalizedEntityId);
  }

  Future<void> _syncSignalReadModelsForEntity(String entityId) async {
    final String normalized = entityId.trim();
    if (normalized.isEmpty) return;
    final Database db = await _db.database;
    await db.transaction((txn) async {
      await _syncSignalReadModelsForEntityTxn(txn, normalized);
    });
  }

  Future<void> _syncSignalReadModelsForEntityTxn(
    DatabaseExecutor db,
    String entityId,
  ) async {
    final String normalized = entityId.trim();
    if (normalized.isEmpty) return;
    final List<Map<String, Object?>> entityRows = await db.query(
      'memory_entities',
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    await db.delete(
      'memory_signal_episodes',
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
    );
    if (entityRows.isEmpty) {
      await db.delete(
        'memory_signal_profiles',
        where: 'entity_id = ?',
        whereArgs: <Object?>[normalized],
      );
      return;
    }

    final Map<String, Object?> entity = entityRows.first;
    final String signalSummary = _normalizeContent(
      (entity['current_summary'] ?? '').toString().trim().isNotEmpty
          ? (entity['current_summary'] ?? '').toString()
          : (entity['latest_content'] ?? '').toString(),
    );
    await db.insert('memory_signal_profiles', <String, Object?>{
      'entity_id': entity['entity_id'],
      'root_uri': entity['root_uri'],
      'entity_type': entity['entity_type'],
      'preferred_name': entity['preferred_name'],
      'preferred_name_norm': entity['preferred_name_norm'],
      'canonical_key': entity['canonical_key'],
      'uri': entity['display_uri'],
      'status': entity['status'],
      'current_summary': entity['current_summary'] ?? '',
      'latest_content': signalSummary,
      'visual_signature_summary': entity['visual_signature_summary'] ?? '',
      'raw_score': entity['raw_score'] ?? 0,
      'decayed_score': entity['decayed_score'] ?? 0,
      'activation_score': entity['activation_score'] ?? 0,
      'evidence_count': entity['evidence_count'] ?? 0,
      'distinct_segment_count': entity['distinct_segment_count'] ?? 0,
      'distinct_day_count': entity['distinct_day_count'] ?? 0,
      'strong_signal_count': entity['strong_signal_count'] ?? 0,
      'min_distinct_days': entity['min_distinct_days'] ?? 0,
      'allow_single_strong_activation':
          entity['allow_single_strong_activation'] ?? 0,
      'allow_root_materialization': entity['allow_root_materialization'] ?? 0,
      'evidence_satisfied': entity['evidence_satisfied'] ?? 0,
      'ready_to_activate': entity['ready_to_activate'] ?? 0,
      'root_materialization_blocked':
          entity['root_materialization_blocked'] ?? 0,
      'missing_activation_score': entity['missing_activation_score'] ?? 0,
      'missing_distinct_days': entity['missing_distinct_days'] ?? 0,
      'needs_review': entity['needs_review'] ?? 0,
      'review_reason': entity['review_reason'],
      'lifecycle_status': entity['lifecycle_status'],
      'first_seen_at': entity['first_seen_at'],
      'last_seen_at': entity['last_seen_at'],
      'activated_at': entity['activated_at'],
      'archived_at': entity['archived_at'],
      'last_materialized_at': entity['last_materialized_at'],
      'last_evidence_summary': entity['last_evidence_summary'],
      'created_at': entity['created_at'],
      'updated_at': entity['updated_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final List<Map<String, Object?>> episodeRows = await db.query(
      'memory_entity_episodes',
      where: 'entity_id = ?',
      whereArgs: <Object?>[normalized],
      orderBy: 'last_seen_at ASC, batch_index ASC, id ASC',
    );
    for (final Map<String, Object?> row in episodeRows) {
      await db.insert('memory_signal_episodes', <String, Object?>{
        'entity_id': normalized,
        'root_uri': entity['root_uri'],
        'uri': entity['display_uri'],
        'segment_id': row['segment_id'],
        'batch_index': row['batch_index'] ?? 0,
        'first_seen_at': row['first_seen_at'],
        'last_seen_at': row['last_seen_at'],
        'score': row['score'] ?? 0,
        'strong_signal': row['strong_signal'] ?? 0,
        'action_kind': row['action_kind'] ?? '',
        'evidence_summary': row['evidence_summary'],
        'app_names_json': row['app_names_json'],
        'content_snapshot': (row['content_snapshot'] ?? '').toString().trim(),
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<MemoryEntityRecord?> _findRecordById(
    DatabaseExecutor db,
    String entityId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      where: 'entity_id = ?',
      whereArgs: <Object?>[entityId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityRecord.fromMap(rows.first);
  }

  Future<MemoryEntityRecord?> _findRecordByCanonicalKey(
    DatabaseExecutor db, {
    required String rootUri,
    required String entityType,
    required String canonicalKey,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      where: 'root_uri = ? AND entity_type = ? AND canonical_key = ?',
      whereArgs: <Object?>[rootUri, entityType, canonicalKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityRecord.fromMap(rows.first);
  }

  Future<MemoryEntityRecord?> _findRecordByDisplayUri(
    DatabaseExecutor db,
    String displayUri,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'memory_entities',
      where: 'display_uri = ?',
      whereArgs: <Object?>[displayUri],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemoryEntityRecord.fromMap(rows.first);
  }

  Future<String> _ensureUniqueCanonicalKey(
    DatabaseExecutor db, {
    required String rootUri,
    required String entityType,
    required String desiredCanonicalKey,
    required String? entityId,
  }) async {
    String base = normalizeCanonicalKey(desiredCanonicalKey);
    if (base.isEmpty) {
      base = 'entity_${_stableHashBase36(_uuidV4())}';
    }
    if (base == rootAggregateCanonicalKey) {
      final MemoryEntityRecord? rootConflict = await _findRecordByCanonicalKey(
        db,
        rootUri: rootUri,
        entityType: entityType,
        canonicalKey: base,
      );
      if (rootConflict == null || rootConflict.entityId == entityId) {
        return base;
      }
      base = 'entity_${_stableHashBase36(_uuidV4())}';
    }

    Future<bool> isAvailable(String key) async {
      final MemoryEntityRecord? conflict = await _findRecordByCanonicalKey(
        db,
        rootUri: rootUri,
        entityType: entityType,
        canonicalKey: key,
      );
      return conflict == null || conflict.entityId == entityId;
    }

    if (await isAvailable(base)) {
      return base;
    }

    for (int suffix = 2; suffix < 1000; suffix += 1) {
      final String candidate = '${base}_$suffix';
      if (await isAvailable(candidate)) {
        return candidate;
      }
    }

    return '${base}_${_stableHashBase36(_uuidV4())}';
  }

  Future<String> _ensureUniqueDisplayUri(
    DatabaseExecutor db, {
    required String desiredUri,
    required String? entityId,
  }) async {
    final String normalized = canonicalizeUri(desiredUri);
    final MemoryEntityRecord? conflict = await _findRecordByDisplayUri(
      db,
      normalized,
    );
    if (conflict == null || conflict.entityId == entityId) {
      return normalized;
    }
    final NocturneUri parsed = _mem.parseUri(normalized);
    final int cut = parsed.path.lastIndexOf('/');
    final String prefix = cut >= 0 ? parsed.path.substring(0, cut) : '';
    final String leaf = cut >= 0 ? parsed.path.substring(cut + 1) : parsed.path;
    int suffix = 2;
    while (suffix < 1000) {
      final String nextLeaf = '${leaf}_$suffix';
      final String nextUri = _mem.makeUri(
        parsed.domain,
        prefix.isEmpty ? nextLeaf : '$prefix/$nextLeaf',
      );
      final MemoryEntityRecord? row = await _findRecordByDisplayUri(
        db,
        nextUri,
      );
      if (row == null || row.entityId == entityId) {
        return nextUri;
      }
      suffix += 1;
    }
    return normalized;
  }

  double _candidateScore({
    required MemoryEntityRecord record,
    required String preferredNameNorm,
    required Set<String> aliasNorms,
    required String canonicalNorm,
    required List<String> candidateAliases,
    required String visualSignatureNorm,
  }) {
    double score = 0;
    if (preferredNameNorm.isEmpty &&
        canonicalNorm.isEmpty &&
        aliasNorms.isEmpty &&
        visualSignatureNorm.isEmpty) {
      return 0;
    }
    if (canonicalNorm.isNotEmpty && record.canonicalKey == canonicalNorm) {
      score += 10;
    }
    if (preferredNameNorm.isNotEmpty &&
        record.preferredNameNorm == preferredNameNorm) {
      score += 8;
    }
    if (preferredNameNorm.isNotEmpty &&
        record.preferredNameNorm.contains(preferredNameNorm)) {
      score += 2.5;
    }
    if (preferredNameNorm.isNotEmpty &&
        preferredNameNorm.contains(record.preferredNameNorm)) {
      score += 2;
    }
    final double nameSimilarity = _normalizedStringSimilarity(
      record.preferredNameNorm,
      preferredNameNorm,
    );
    final double trigramNameSimilarity = _trigramSimilarity(
      record.preferredNameNorm,
      preferredNameNorm,
    );
    if (nameSimilarity >= 0.92) {
      score += 5;
    } else if (nameSimilarity >= 0.82) {
      score += 3;
    } else if (nameSimilarity >= 0.7) {
      score += 1.2;
    }
    if (trigramNameSimilarity >= 0.9) {
      score += 4.2;
    } else if (trigramNameSimilarity >= 0.78) {
      score += 2.1;
    } else if (trigramNameSimilarity >= 0.65) {
      score += 0.8;
    }

    final Set<String> candidateAliasNorms = candidateAliases
        .map(normalizeForSearch)
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final String aliasNorm in aliasNorms) {
      if (candidateAliasNorms.contains(aliasNorm)) {
        score += 6;
      } else if (candidateAliasNorms.any(
        (value) => value.contains(aliasNorm),
      )) {
        score += 1.5;
      } else {
        final double aliasSimilarity = candidateAliasNorms
            .map(
              (value) => math.max(
                _normalizedStringSimilarity(value, aliasNorm),
                _trigramSimilarity(value, aliasNorm),
              ),
            )
            .fold<double>(0, math.max);
        if (aliasSimilarity >= 0.88) {
          score += 2.4;
        } else if (aliasSimilarity >= 0.76) {
          score += 1.1;
        }
      }
    }

    final String leaf = _mem.parseUri(record.displayUri).path.split('/').last;
    final String leafNorm = normalizeForSearch(leaf);
    if (canonicalNorm.isNotEmpty && leafNorm == canonicalNorm) {
      score += 3;
    }
    final String recordVisualNorm = normalizeForSearch(
      record.visualSignatureSummary,
    );
    final double visualSimilarity = _tokenOverlapRatio(
      recordVisualNorm,
      visualSignatureNorm,
    );
    final double visualTrigramSimilarity = _trigramSimilarity(
      recordVisualNorm,
      visualSignatureNorm,
    );
    if (visualSignatureNorm.isNotEmpty && recordVisualNorm.isNotEmpty) {
      if (recordVisualNorm == visualSignatureNorm) {
        score += 4;
      } else if (recordVisualNorm.contains(visualSignatureNorm) ||
          visualSignatureNorm.contains(recordVisualNorm)) {
        score += 1.8;
      } else {
        final Set<String> visualTokens = visualSignatureNorm
            .split(' ')
            .where((token) => token.isNotEmpty)
            .toSet();
        final Set<String> recordTokens = recordVisualNorm
            .split(' ')
            .where((token) => token.isNotEmpty)
            .toSet();
        final int overlap = visualTokens.intersection(recordTokens).length;
        if (overlap > 0) {
          score += overlap * 0.6;
        }
      }
      score += visualSimilarity * 2.2;
      score += visualTrigramSimilarity * 1.3;
    }
    if (record.status == MemoryEntityStatus.active) {
      score += 0.8;
    }
    if (record.lastSeenAt > 0) {
      final double ageDays =
          math.max(
            0,
            DateTime.now().millisecondsSinceEpoch - record.lastSeenAt,
          ) /
          Duration.millisecondsPerDay;
      if (ageDays <= 7) {
        score += 0.9;
      } else if (ageDays <= 30) {
        score += 0.5;
      }
    }
    if (record.needsReview) {
      score -= 0.8;
    }
    return score;
  }

  double _trigramSimilarity(String a, String b) {
    final String left = a.trim();
    final String right = b.trim();
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;

    Set<String> trigrams(String value) {
      final String padded = '  $value  ';
      final Set<String> out = <String>{};
      for (int index = 0; index <= padded.length - 3; index += 1) {
        out.add(padded.substring(index, index + 3));
      }
      return out;
    }

    final Set<String> leftSet = trigrams(left);
    final Set<String> rightSet = trigrams(right);
    if (leftSet.isEmpty || rightSet.isEmpty) return 0;
    final int overlap = leftSet.intersection(rightSet).length;
    final int union = leftSet.union(rightSet).length;
    if (union <= 0) return 0;
    return overlap / union;
  }

  double _normalizedStringSimilarity(String a, String b) {
    final String left = a.trim();
    final String right = b.trim();
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;
    final int distance = _levenshteinDistance(left, right);
    final int base = math.max(left.length, right.length);
    if (base <= 0) return 0;
    return 1 - (distance / base);
  }

  double _tokenOverlapRatio(String a, String b) {
    final Set<String> left = a
        .split(' ')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final Set<String> right = b
        .split(' ')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (left.isEmpty || right.isEmpty) return 0;
    final int overlap = left.intersection(right).length;
    final int union = left.union(right).length;
    if (union <= 0) return 0;
    return overlap / union;
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final List<int> previous = List<int>.generate(
      b.length + 1,
      (int index) => index,
    );
    final List<int> current = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i < a.length; i += 1) {
      current[0] = i + 1;
      for (int j = 0; j < b.length; j += 1) {
        final int cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = math.min(
          math.min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + cost,
        );
      }
      for (int j = 0; j < current.length; j += 1) {
        previous[j] = current[j];
      }
    }
    return previous.last;
  }

  bool _isStrongSignal({
    required MemoryEntityRootPolicy policy,
    required String displayUri,
    required String content,
    required List<String> aliases,
  }) {
    final String combined = <String>[
      content,
      ...aliases,
    ].join('\n').toLowerCase();
    final bool keywordHit = policy.strongKeywords.any(
      (keyword) => combined.contains(keyword.toLowerCase()),
    );
    final bool specificNode = canonicalizeUri(displayUri) != policy.rootUri;
    return keywordHit || (specificNode && aliases.isNotEmpty);
  }

  double _scoreEpisode({
    required MemoryEntityRootPolicy policy,
    required String displayUri,
    required String actionKind,
    required String content,
    required bool strongSignal,
  }) {
    double score = 1.0;
    if (canonicalizeUri(displayUri) != policy.rootUri) {
      score += 0.4;
    }
    if (actionKind == 'create_memory' ||
        actionKind == 'ai_rebuild' ||
        actionKind == 'review_approved') {
      score += 0.4;
    }
    if (content.trim().length >= 40) {
      score += 0.2;
    }
    if (strongSignal) {
      score += 1.0;
    }
    return score;
  }

  String _normalizeSlugPath(String value) {
    final List<String> parts = value
        .trim()
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '';
    final List<String> out = <String>[];
    for (final String part in parts.take(6)) {
      final String normalized = part
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      if (normalized.isEmpty) continue;
      out.add(normalized);
    }
    return out.join('/');
  }

  Future<void> _setReviewQueueStatus({
    required int reviewId,
    required MemoryEntityReviewStatus status,
  }) async {
    await (await _db.database).update(
      'memory_entity_review_queue',
      <String, Object?>{
        'status': status.wireName,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[reviewId],
    );
  }

  Map<String, dynamic> _decodeJsonMap(String raw, {required String field}) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    throw FormatException('invalid $field');
  }

  Future<String> _resolveApprovedTargetEntityId({
    required MemoryEntityRootPolicy policy,
    required String? explicitTargetEntityId,
    required MemoryEntityReviewQueueItem reviewItem,
    required MemoryEntityResolutionDecision originalResolution,
    required bool forceCreateNew,
  }) async {
    if (forceCreateNew) return '';
    final String preferredTarget = _pickNonEmpty(
      explicitTargetEntityId,
      reviewItem.suggestedEntityId,
      originalResolution.matchedEntityId ?? '',
      '',
    );
    final String normalized = preferredTarget.trim();
    if (normalized.isEmpty) return '';
    final MemoryEntityRecord target =
        await getRecordById(normalized) ??
        (throw StateError('suggested entity not found: $normalized'));
    if (target.rootUri != policy.rootUri ||
        target.entityType != policy.entityType) {
      throw StateError(
        'review target is outside expected root/type: $normalized',
      );
    }
    return target.entityId;
  }

  MemoryEntityResolutionDecision _buildApprovedResolution({
    required MemoryEntityResolutionDecision original,
    required String approvedTargetEntityId,
    required bool forceCreateNew,
  }) {
    if (forceCreateNew || approvedTargetEntityId.isEmpty) {
      return MemoryEntityResolutionDecision(
        action: MemoryEntityResolutionAction.createNew,
        confidence: math.max(original.confidence, 0.99),
        matchedEntityId: null,
        suggestedPreferredName: original.suggestedPreferredName,
        aliasesToAdd: original.aliasesToAdd,
        reasons: <String>[...original.reasons, '人工复核后批准新建实体'],
        conflicts: const <String>[],
        needsReview: false,
      );
    }
    final MemoryEntityResolutionAction action =
        original.action == MemoryEntityResolutionAction.addAliasToExisting
        ? MemoryEntityResolutionAction.addAliasToExisting
        : MemoryEntityResolutionAction.matchExisting;
    return MemoryEntityResolutionDecision(
      action: action,
      confidence: math.max(original.confidence, 0.99),
      matchedEntityId: approvedTargetEntityId,
      suggestedPreferredName: original.suggestedPreferredName,
      aliasesToAdd: original.aliasesToAdd,
      reasons: <String>[...original.reasons, '人工复核后批准合并到现有实体'],
      conflicts: const <String>[],
      needsReview: false,
    );
  }

  Future<List<MemoryEntityExemplar>> _loadReviewQueueExemplars({
    required MemoryEntityReviewQueueItem item,
    required MemoryVisualCandidate candidate,
    required MemoryEntityMergePlan mergePlan,
  }) async {
    final List<Map<String, dynamic>> samples = await _db.listSegmentSamples(
      item.segmentId,
    );
    final List<Map<String, dynamic>> ordered =
        List<Map<String, dynamic>>.from(samples)..sort((
          Map<String, dynamic> a,
          Map<String, dynamic> b,
        ) {
          final int ai = _toInt(a['position_index']);
          final int bi = _toInt(b['position_index']);
          final int byPos = ai.compareTo(bi);
          if (byPos != 0) return byPos;
          return _toInt(a['capture_time']).compareTo(_toInt(b['capture_time']));
        });
    final List<MemoryEntityExemplar> all = <MemoryEntityExemplar>[
      for (int index = 0; index < ordered.length; index += 1)
        MemoryEntityExemplar.fromMap(<String, dynamic>{
          ...ordered[index],
          'position_index': index,
        }),
    ].where((item) => item.filePath.isNotEmpty).toList(growable: false);
    final LinkedHashSet<int> evidenceFrames = LinkedHashSet<int>.from(
      candidate.evidenceFrames,
    );
    for (final MemoryEntityFactCandidate claim in mergePlan.claimsToUpsert) {
      evidenceFrames.addAll(claim.evidenceFrames);
    }
    for (final MemoryEntityEventCandidate event in mergePlan.eventsToAppend) {
      evidenceFrames.addAll(event.evidenceFrames);
    }
    final List<MemoryEntityExemplar> filtered = <MemoryEntityExemplar>[
      for (final int frame in evidenceFrames)
        if (frame >= 0 && frame < all.length) all[frame],
    ];
    return filtered.isEmpty ? all.take(3).toList(growable: false) : filtered;
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _dayKey(int ms) {
    if (ms <= 0) return '';
    final DateTime value = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final String mm = value.month.toString().padLeft(2, '0');
    final String dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }

  static String _pickNonEmpty(String? a, String? b, String c, String d) {
    for (final String? value in <String?>[a, b, c, d]) {
      final String text = value?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _summarizeContent(String content) {
    final String normalized = _normalizeContent(content);
    if (normalized.isEmpty) return '';
    final List<String> lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return '';
    final String first = lines.first;
    return first.length <= 220 ? first : '${first.substring(0, 220)}...';
  }

  static String _normalizeContent(String content) {
    return content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }

  static String _normLine(String line) =>
      line.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _mergeDraftContent({
    required String existing,
    required String incoming,
  }) {
    final List<String> currentLines = _splitLines(existing);
    final List<String> incomingLines = _splitLines(incoming);
    final Set<String> seen = currentLines
        .map(_normLine)
        .where((line) => line.isNotEmpty)
        .toSet();

    for (final String line in incomingLines) {
      final String norm = _normLine(line);
      if (norm.isEmpty) continue;
      final _FieldValue? field = _parseFieldLine(line);
      if (field == null) {
        if (!seen.contains(norm)) {
          currentLines.add(line);
          seen.add(norm);
        }
        continue;
      }

      final int existingIndex = currentLines.indexWhere(
        (candidate) => _parseFieldLine(candidate)?.fieldKey == field.fieldKey,
      );
      final int historyIndex = currentLines.indexWhere(
        (candidate) => _parseHistoryLine(candidate)?.fieldKey == field.fieldKey,
      );
      if (existingIndex < 0) {
        currentLines.add(line);
        seen.add(norm);
        continue;
      }

      final _FieldValue? existingField = _parseFieldLine(
        currentLines[existingIndex],
      );
      if (existingField == null ||
          _normLine(existingField.value) == _normLine(field.value)) {
        continue;
      }

      final LinkedHashSet<String> history = LinkedHashSet<String>();
      if (historyIndex >= 0) {
        history.addAll(
          _parseHistoryLine(currentLines[historyIndex])?.historyValues ??
              const <String>[],
        );
      }
      history.add(existingField.value);
      currentLines[existingIndex] = line;
      if (historyIndex >= 0) {
        currentLines[historyIndex] = _buildHistoryLine(
          field.displayKey,
          history,
        );
      } else {
        currentLines.insert(
          existingIndex + 1,
          _buildHistoryLine(field.displayKey, history),
        );
      }
    }

    return _normalizeContent(currentLines.join('\n'));
  }

  static List<String> _splitLines(String content) {
    final String normalized = _normalizeContent(content);
    if (normalized.isEmpty) return <String>[];
    return normalized
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
  }

  static final RegExp _fieldLineRe = RegExp(
    r'^-\s*([^:：]{1,24})\s*[:：]\s*(.+)$',
  );
  static final RegExp _historyLineRe = RegExp(
    r'^-\s*历史记录\(([^)]+)\)\s*[:：]\s*(.+)$',
  );

  static _FieldValue? _parseFieldLine(String line) {
    final RegExpMatch? match = _fieldLineRe.firstMatch(line.trim());
    if (match == null) return null;
    final String displayKey = (match.group(1) ?? '').trim();
    final String value = (match.group(2) ?? '').trim();
    if (displayKey.isEmpty || value.isEmpty) return null;
    return _FieldValue(
      fieldKey: displayKey.toLowerCase().replaceAll(RegExp(r'\s+'), ''),
      displayKey: displayKey,
      value: value,
    );
  }

  static _HistoryValue? _parseHistoryLine(String line) {
    final RegExpMatch? match = _historyLineRe.firstMatch(line.trim());
    if (match == null) return null;
    final String displayKey = (match.group(1) ?? '').trim();
    final String value = (match.group(2) ?? '').trim();
    if (displayKey.isEmpty || value.isEmpty) return null;
    return _HistoryValue(
      fieldKey: displayKey.toLowerCase().replaceAll(RegExp(r'\s+'), ''),
      historyValues: value
          .split(RegExp(r'\s*[；;]\s*'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }

  static String _buildHistoryLine(String displayKey, Iterable<String> values) {
    return '- 历史记录($displayKey)：${values.join('；')}';
  }

  String _stableHashBase36(String value) {
    int hash = 2166136261;
    for (final int code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash.toRadixString(36);
  }

  String _uuidV4() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    final String seed = '$now-${_stableHashBase36(now.toString())}';
    final String hex = seed.codeUnits
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join()
        .padRight(32, '0')
        .substring(0, 32);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}

enum _EntityObservationMatchMode { explicitOnly, explicitOrDisplayUri }

class _FieldValue {
  const _FieldValue({
    required this.fieldKey,
    required this.displayKey,
    required this.value,
  });

  final String fieldKey;
  final String displayKey;
  final String value;
}

class _HistoryValue {
  const _HistoryValue({required this.fieldKey, required this.historyValues});

  final String fieldKey;
  final List<String> historyValues;
}
