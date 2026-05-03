import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_models.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_roots.dart';
import 'package:path/path.dart' as p;
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_signal_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Directory> _prepareDesktopDbRoot() async {
  final Directory tmp = await Directory.systemTemp.createTemp(
    'screen_memo_signal_memory_',
  );
  final Directory root = Directory(p.join(tmp.path, 'root'));
  await root.create(recursive: true);
  await ScreenshotDatabase.instance.initializeForDesktop(root.path);
  return tmp;
}

Future<void> _bootstrapRoots() async {
  final NocturneMemoryService mem = NocturneMemoryService.instance;
  final NocturneMemorySignalService signals =
      NocturneMemorySignalService.instance;
  await mem.resetAll();
  await signals.resetAll();
  await mem.createMemory(
    parentUri: 'core://',
    title: 'agent',
    content: '你是 ScreenMemo 内置的助手。',
    priority: 0,
  );
  await mem.createMemory(
    parentUri: 'core://',
    title: 'my_user',
    content: '这里存放用户长期记忆。',
    priority: 0,
  );
  await mem.createMemory(
    parentUri: 'core://agent',
    title: 'my_user',
    content: '与用户交互时优先尊重用户偏好。',
    priority: 0,
  );
  for (final NocturneMemoryRootSpec root in NocturneMemoryRoots.all) {
    await mem.createMemory(
      parentUri: 'core://my_user',
      title: root.name,
      content: '（自动构建中）',
      priority: 1,
    );
  }
}

NocturneMemorySignalContext _ctx(
  int segmentId,
  DateTime when, {
  int batchIndex = 1,
  List<String> apps = const <String>['哔哩哔哩'],
}) {
  final int ms = when.millisecondsSinceEpoch;
  return NocturneMemorySignalContext(
    segmentId: segmentId,
    batchIndex: batchIndex,
    segmentStartMs: ms,
    segmentEndMs: ms,
    evidenceSummary: '来自动态段 #$segmentId 的截图证据（${when.toIso8601String()}）',
    appNames: apps,
  );
}

String _dayKey(DateTime when) {
  final String mm = when.month.toString().padLeft(2, '0');
  final String dd = when.day.toString().padLeft(2, '0');
  return '${when.year}-$mm-$dd';
}

Future<void> _createLegacySignalTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS memory_signal_profiles (
      uri TEXT PRIMARY KEY,
      root_uri TEXT NOT NULL,
      parent_uri TEXT NOT NULL,
      title TEXT,
      latest_content TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'candidate',
      raw_score REAL NOT NULL DEFAULT 0,
      decayed_score REAL NOT NULL DEFAULT 0,
      evidence_count INTEGER NOT NULL DEFAULT 0,
      distinct_segment_count INTEGER NOT NULL DEFAULT 0,
      distinct_day_count INTEGER NOT NULL DEFAULT 0,
      strong_signal_count INTEGER NOT NULL DEFAULT 0,
      first_seen_at INTEGER,
      last_seen_at INTEGER,
      activated_at INTEGER,
      archived_at INTEGER,
      last_materialized_at INTEGER,
      last_evidence_summary TEXT,
      created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
      updated_at INTEGER DEFAULT (strftime('%s','now') * 1000)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS memory_signal_episodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uri TEXT NOT NULL,
      root_uri TEXT NOT NULL,
      segment_id INTEGER NOT NULL,
      batch_index INTEGER NOT NULL DEFAULT 0,
      day_key TEXT NOT NULL,
      first_seen_at INTEGER NOT NULL,
      last_seen_at INTEGER NOT NULL,
      score REAL NOT NULL DEFAULT 0,
      strong_signal INTEGER NOT NULL DEFAULT 0,
      app_names_json TEXT,
      evidence_summary TEXT,
      action_kind TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      created_at INTEGER DEFAULT (strftime('%s','now') * 1000),
      updated_at INTEGER DEFAULT (strftime('%s','now') * 1000),
      UNIQUE(uri, segment_id)
    )
  ''');
}

Future<void> _retimeEntityEpisodes(
  Database db,
  String displayUri,
  List<DateTime> seenTimes,
) async {
  final List<Map<String, Object?>> entities = await db.query(
    'memory_entities',
    columns: const <String>['entity_id'],
    where: 'display_uri = ?',
    whereArgs: <Object?>[displayUri],
    limit: 1,
  );
  if (entities.isEmpty) {
    throw StateError('entity not found: $displayUri');
  }
  final String entityId = (entities.first['entity_id'] ?? '').toString();
  final List<Map<String, Object?>> episodes = await db.query(
    'memory_entity_episodes',
    columns: const <String>['id'],
    where: 'entity_id = ?',
    whereArgs: <Object?>[entityId],
    orderBy: 'id ASC',
  );
  if (episodes.isEmpty) {
    throw StateError('entity has no episodes: $displayUri');
  }
  for (int index = 0; index < episodes.length; index += 1) {
    final int episodeId = (episodes[index]['id'] as num).toInt();
    final DateTime when =
        seenTimes[index < seenTimes.length ? index : seenTimes.length - 1];
    await db.update(
      'memory_entity_episodes',
      <String, Object?>{
        'day_key': _dayKey(when),
        'first_seen_at': when.millisecondsSinceEpoch,
        'last_seen_at': when.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[episodeId],
    );
  }
}

Future<int> _insertReviewQueueItem(
  Database db, {
  required String preferredName,
  required String rootUri,
  required String entityType,
  required int segmentId,
  String? suggestedEntityId,
}) {
  final MemoryVisualCandidate candidate = MemoryVisualCandidate(
    candidateId: 'review_candidate_$segmentId',
    rootKey: 'preferences',
    entityType: entityType,
    preferredName: preferredName,
    aliases: const <String>['vim style'],
    visualSignatureSummary: '稳定出现的主题偏好界面与编辑器配色',
    stableVisualCues: const <String>['高对比配色', '编辑器主题切换界面'],
    facts: const <MemoryEntityFactCandidate>[
      MemoryEntityFactCandidate(
        factType: 'preference',
        slotKey: 'theme',
        value: '偏好 Vim 风格主题',
        cardinality: MemoryEntityCardinality.singleton,
        confidence: 0.93,
        evidenceFrames: <int>[0],
      ),
    ],
    confidence: 0.91,
    evidenceFrames: const <int>[0],
  );
  final MemoryEntityResolutionDecision resolution =
      MemoryEntityResolutionDecision(
        action: MemoryEntityResolutionAction.reviewRequired,
        confidence: 0.44,
        matchedEntityId: suggestedEntityId,
        suggestedPreferredName: preferredName,
        reasons: const <String>['存在同类偏好项，需人工确认'],
        conflicts: const <String>['命名接近但需要人工决定'],
        needsReview: true,
      );
  final MemoryEntityMergePlan mergePlan = MemoryEntityMergePlan(
    preferredName: preferredName,
    aliasesToAdd: const <String>['Vim Theme'],
    summaryRewrite: '用户长期偏好使用 Vim 风格主题。',
    visualSignatureSummary: '高对比、深色、编辑器主题偏好界面持续出现',
    claimsToUpsert: const <MemoryEntityFactCandidate>[
      MemoryEntityFactCandidate(
        factType: 'preference',
        slotKey: 'theme',
        value: '长期偏好 Vim 风格主题',
        cardinality: MemoryEntityCardinality.singleton,
        confidence: 0.96,
        evidenceFrames: <int>[0],
      ),
    ],
    eventsToAppend: const <MemoryEntityEventCandidate>[
      MemoryEntityEventCandidate(
        note: '在多个设置界面中反复出现 Vim 风格主题偏好',
        evidenceFrames: <int>[0],
      ),
    ],
  );
  final MemoryEntityAuditDecision audit = MemoryEntityAuditDecision(
    action: MemoryEntityAuditAction.blockAmbiguous,
    confidence: 0.42,
    suggestedEntityId: suggestedEntityId,
    reasons: const <String>['等待人工复核后再写入'],
  );
  return db.insert('memory_entity_review_queue', <String, Object?>{
    'candidate_id': candidate.candidateId,
    'root_uri': rootUri,
    'entity_type': entityType,
    'preferred_name': preferredName,
    'segment_id': segmentId,
    'batch_index': 1,
    'review_stage': 'audit',
    'review_reason': '需要人工复核',
    'suggested_entity_id': suggestedEntityId,
    'status': MemoryEntityReviewStatus.pending.wireName,
    'evidence_summary': '来自复核测试的截图证据',
    'app_names_json': jsonEncode(const <String>['Code Editor']),
    'candidate_json': const JsonEncoder.withIndent(
      '  ',
    ).convert(candidate.toJson()),
    'shortlist_json': const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'shortlist': const <Object>[]}),
    'resolution_json': const JsonEncoder.withIndent(
      '  ',
    ).convert(resolution.toJson()),
    'merge_plan_json': const JsonEncoder.withIndent(
      '  ',
    ).convert(mergePlan.toJson()),
    'audit_json': const JsonEncoder.withIndent('  ').convert(audit.toJson()),
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'interest stays candidate after one strong episode and is not materialized',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryService mem = NocturneMemoryService.instance;

        await signals.seedCreateActionForTest(
          parentUri: 'core://my_user/interests',
          title: 'dyson_sphere_program',
          content: '用户持续关注《戴森球计划》相关内容。',
          context: _ctx(1, DateTime.now()),
        );

        final Map<String, List<String>> sections = await signals
            .buildSnapshotSections();
        expect(
          sections['core://my_user/interests']!.join('\n'),
          contains('[candidate] core://my_user/interests/dyson_sphere_program'),
        );

        await signals.materializeProfiles();

        expect(
          () => mem.readMemory('core://my_user/interests/dyson_sphere_program'),
          throwsA(isA<StateError>()),
        );
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test('dashboard exposes candidate activation gap', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'single_topic',
        content: '用户持续关注某个具体主题。',
        context: _ctx(1, DateTime.now()),
      );

      final NocturneMemorySignalDashboard dashboard = await signals
          .loadDashboard(limitPerStatus: 5);
      final NocturneMemorySignalDiagnosticItem item = dashboard.topCandidates
          .firstWhere((candidate) => candidate.uri.endsWith('/single_topic'));

      expect(dashboard.candidateCount, greaterThanOrEqualTo(1));
      expect(item.status, NocturneMemorySignalStatus.candidate);
      expect(item.missingDistinctDays, greaterThan(0));
      expect(item.missingActivationScore, greaterThanOrEqualTo(0));
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('legacy uri-based signal rows migrate once into entity storage', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final Database db = await ScreenshotDatabase.instance.database;
      final DateTime first = DateTime(2026, 4, 1, 9);
      final DateTime second = DateTime(2026, 4, 3, 10);

      await _createLegacySignalTables(db);
      await db.insert('memory_signal_profiles', <String, Object?>{
        'uri': 'core://my_user/interests/legacy_topic',
        'root_uri': 'core://my_user/interests',
        'parent_uri': 'core://my_user/interests',
        'title': 'legacy_topic',
        'latest_content': '旧版信号层保留下来的长期主题。',
        'status': 'active',
        'raw_score': 3.2,
        'decayed_score': 2.8,
        'evidence_count': 2,
        'distinct_segment_count': 2,
        'distinct_day_count': 2,
        'strong_signal_count': 1,
        'first_seen_at': first.millisecondsSinceEpoch,
        'last_seen_at': second.millisecondsSinceEpoch,
        'activated_at': second.millisecondsSinceEpoch,
        'last_evidence_summary': '旧版 signal profile',
      });
      await db.insert('memory_signal_episodes', <String, Object?>{
        'uri': 'core://my_user/interests/legacy_topic',
        'root_uri': 'core://my_user/interests',
        'segment_id': 101,
        'batch_index': 1,
        'day_key': _dayKey(first),
        'first_seen_at': first.millisecondsSinceEpoch,
        'last_seen_at': first.millisecondsSinceEpoch,
        'score': 1.4,
        'strong_signal': 0,
        'app_names_json': '["Flutter"]',
        'evidence_summary': '第一天看到旧主题',
        'action_kind': 'create_memory',
        'content': '旧版信号层保留下来的长期主题。',
      });
      await db.insert('memory_signal_episodes', <String, Object?>{
        'uri': 'core://my_user/interests/legacy_topic',
        'root_uri': 'core://my_user/interests',
        'segment_id': 102,
        'batch_index': 1,
        'day_key': _dayKey(second),
        'first_seen_at': second.millisecondsSinceEpoch,
        'last_seen_at': second.millisecondsSinceEpoch,
        'score': 1.8,
        'strong_signal': 1,
        'app_names_json': '["Flutter"]',
        'evidence_summary': '第三天再次出现',
        'action_kind': 'update_memory',
        'content': '- 经常回到这个主题',
      });

      final NocturneMemorySignalDashboard dashboard = await signals
          .loadDashboard(limitPerStatus: 10);
      expect(
        dashboard.topActive.any(
          (item) => item.uri == 'core://my_user/interests/legacy_topic',
        ),
        isTrue,
      );

      final List<Map<String, Object?>> entities = await db.query(
        'memory_entities',
        where: 'display_uri = ?',
        whereArgs: <Object?>['core://my_user/interests/legacy_topic'],
      );
      expect(entities.length, 1);

      final List<Map<String, Object?>> episodes = await db.query(
        'memory_entity_episodes',
        where: 'entity_id = ?',
        whereArgs: <Object?>[(entities.first['entity_id'] ?? '').toString()],
      );
      expect(episodes.length, 2);

      await signals.loadDashboard(limitPerStatus: 10);

      final List<Map<String, Object?>> migratedRows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM memory_entities WHERE display_uri = 'core://my_user/interests/legacy_topic'",
      );
      final int migratedCount = ((migratedRows.first['c'] as num?) ?? 0)
          .toInt();
      expect(migratedCount, 1);
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test(
    'listSegmentSamples exposes appearance and distinct-day counts',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        final Database db = await ScreenshotDatabase.instance.database;
        final DateTime first = DateTime(2026, 4, 1, 9);
        final DateTime second = DateTime(2026, 4, 2, 10);
        final int segmentId = await db.insert('segments', <String, Object?>{
          'start_time': first.millisecondsSinceEpoch,
          'end_time': second.millisecondsSinceEpoch,
          'duration_sec': 60,
          'sample_interval_sec': 5,
          'status': 'done',
          'segment_kind': 'global',
        });

        await db.insert('segment_samples', <String, Object?>{
          'segment_id': segmentId,
          'capture_time': first.millisecondsSinceEpoch,
          'file_path': '/tmp/a.png',
          'app_package_name': 'dev.sample.app',
          'app_name': 'Sample',
          'position_index': 0,
        });
        await db.insert('segment_samples', <String, Object?>{
          'segment_id': segmentId,
          'capture_time': first
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          'file_path': '/tmp/b.png',
          'app_package_name': 'dev.sample.app',
          'app_name': 'Sample',
          'position_index': 1,
        });
        await db.insert('segment_samples', <String, Object?>{
          'segment_id': segmentId,
          'capture_time': second.millisecondsSinceEpoch,
          'file_path': '/tmp/c.png',
          'app_package_name': 'dev.sample.app',
          'app_name': 'Sample',
          'position_index': 2,
        });

        final List<Map<String, dynamic>> rows = await ScreenshotDatabase
            .instance
            .listSegmentSamples(segmentId);

        expect(rows, hasLength(3));
        expect(rows.first['appearance_count'], 3);
        expect(rows.first['segment_occurrence_count'], 3);
        expect(rows.first['distinct_day_count'], 2);
        expect(rows.first['cross_day_count'], 2);
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test('loadItemsByStatus returns full candidate list', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'topic_a',
        content: '用户持续关注主题 A。',
        context: _ctx(1, DateTime.now()),
      );
      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'topic_b',
        content: '用户持续关注主题 B。',
        context: _ctx(2, DateTime.now()),
      );
      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'topic_c',
        content: '用户持续关注主题 C。',
        context: _ctx(3, DateTime.now()),
      );

      final List<NocturneMemorySignalDiagnosticItem> candidates = await signals
          .loadItemsByStatus(NocturneMemorySignalStatus.candidate);

      final Set<String> uris = candidates.map((item) => item.uri).toSet();
      expect(uris, contains('core://my_user/interests/topic_a'));
      expect(uris, contains('core://my_user/interests/topic_b'));
      expect(uris, contains('core://my_user/interests/topic_c'));
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('interest becomes active after cross-day repeated evidence', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final DateTime now = DateTime.now();

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'dyson_sphere_program',
        content: '用户持续关注《戴森球计划》相关内容。',
        context: _ctx(1, now.subtract(const Duration(days: 3))),
      );
      await signals.seedUpdateActionForTest(
        uri: 'core://my_user/interests/dyson_sphere_program',
        bulletLines: const <String>['- 经常搜索《戴森球计划》攻略与玩法讨论'],
        context: _ctx(2, now),
      );

      await signals.materializeProfiles();

      final Map<String, dynamic> node = await mem.readMemory(
        'core://my_user/interests/dyson_sphere_program',
      );
      final String content = (node['content'] as String?) ?? '';
      expect(content, contains('记忆信号状态：活跃'));
      expect(content, contains('戴森球计划'));
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('active interest stays active before archive threshold', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final Database db = await ScreenshotDatabase.instance.database;
      final DateTime now = DateTime.now();

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'steady_topic',
        content: '用户持续关注某个长期话题。',
        context: _ctx(1, now.subtract(const Duration(days: 3))),
      );
      await signals.seedUpdateActionForTest(
        uri: 'core://my_user/interests/steady_topic',
        bulletLines: const <String>['- 经常搜索这个主题的相关资料'],
        context: _ctx(2, now),
      );
      await signals.materializeProfiles();

      await _retimeEntityEpisodes(
        db,
        'core://my_user/interests/steady_topic',
        <DateTime>[
          now.subtract(const Duration(days: 21)),
          now.subtract(const Duration(days: 20)),
        ],
      );

      await signals.materializeProfiles();

      final NocturneMemorySignalDiagnosticItem item = (await signals
          .loadDiagnosticItem('core://my_user/interests/steady_topic'))!;
      expect(item.status, NocturneMemorySignalStatus.active);
      final Map<String, dynamic> node = await mem.readMemory(
        'core://my_user/interests/steady_topic',
      );
      expect((node['content'] as String?) ?? '', contains('记忆信号状态：活跃'));
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('stale interest is archived under archive subtree', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final DateTime old = DateTime.now().subtract(const Duration(days: 90));

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'flash_topic',
        content: '用户持续关注某个短期热点话题。',
        context: _ctx(1, old),
      );

      await signals.materializeProfiles();

      final Map<String, dynamic> archived = await mem.readMemory(
        'core://my_user/interests/archive/flash_topic',
      );
      final String content = (archived['content'] as String?) ?? '';
      expect(content, contains('记忆信号状态：已封存'));
      expect(content, contains('生命周期状态：已封存'));
      expect(
        () => mem.readMemory('core://my_user/interests/flash_topic'),
        throwsA(isA<StateError>()),
      );
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('single strong preference can materialize on root node', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;

      await signals.seedUpdateActionForTest(
        uri: 'core://my_user/preferences',
        bulletLines: const <String>['- 喜欢深色主题'],
        context: _ctx(1, DateTime.now(), apps: const <String>['设置']),
      );

      await signals.materializeProfiles();

      final Map<String, dynamic> root = await mem.readMemory(
        'core://my_user/preferences',
      );
      final String content = (root['content'] as String?) ?? '';
      expect(content, contains('喜欢深色主题'));
      expect(content, contains('记忆信号状态：活跃'));
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test('materializeProfiles honors stop callback', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final DateTime now = DateTime.now();

      await signals.seedCreateActionForTest(
        parentUri: 'core://my_user/interests',
        title: 'stop_test_topic',
        content: '用户持续关注一个会被物化的话题。',
        context: _ctx(1, now.subtract(const Duration(days: 3))),
      );
      await signals.seedUpdateActionForTest(
        uri: 'core://my_user/interests/stop_test_topic',
        bulletLines: const <String>['- 经常搜索这个话题的相关资料'],
        context: _ctx(2, now),
      );

      await signals.materializeProfiles(shouldStop: () => true);

      expect(
        () => mem.readMemory('core://my_user/interests/stop_test_topic'),
        throwsA(isA<StateError>()),
      );
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });

  test(
    'people root-only update stays candidate and is not materialized',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryService mem = NocturneMemoryService.instance;

        await signals.seedUpdateActionForTest(
          uri: 'core://my_user/people',
          bulletLines: const <String>['- 联系人：张三'],
          context: _ctx(1, DateTime.now(), apps: const <String>['微信']),
        );

        await signals.materializeProfiles();

        final Map<String, dynamic> root = await mem.readMemory(
          'core://my_user/people',
        );
        final String content = (root['content'] as String?) ?? '';
        expect(content, isNot(contains('联系人：张三')));

        final Map<String, List<String>> sections = await signals
            .buildSnapshotSections();
        expect(
          sections['core://my_user/people']!.join('\n'),
          contains('[candidate] core://my_user/people'),
        );
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'archived profile moves existing active node into archive subtree',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryService mem = NocturneMemoryService.instance;
        final Database db = await ScreenshotDatabase.instance.database;
        final DateTime now = DateTime.now();

        await signals.seedCreateActionForTest(
          parentUri: 'core://my_user/interests',
          title: 'lasting_topic',
          content: '用户持续关注某个长期话题。',
          context: _ctx(1, now.subtract(const Duration(days: 2))),
        );
        await signals.seedUpdateActionForTest(
          uri: 'core://my_user/interests/lasting_topic',
          bulletLines: const <String>['- 经常搜索这个主题的资料'],
          context: _ctx(2, now),
        );
        await signals.materializeProfiles();

        final Map<String, dynamic> active = await mem.readMemory(
          'core://my_user/interests/lasting_topic',
        );
        expect((active['content'] as String?) ?? '', contains('记忆信号状态：活跃'));

        await _retimeEntityEpisodes(
          db,
          'core://my_user/interests/lasting_topic',
          <DateTime>[
            now.subtract(const Duration(days: 122)),
            now.subtract(const Duration(days: 120)),
          ],
        );

        await signals.materializeProfiles();

        final Map<String, dynamic> archived = await mem.readMemory(
          'core://my_user/interests/archive/lasting_topic',
        );
        final String archivedContent = (archived['content'] as String?) ?? '';
        expect(archivedContent, contains('记忆信号状态：已封存'));
        expect(
          () => mem.readMemory('core://my_user/interests/lasting_topic'),
          throwsA(isA<StateError>()),
        );
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'archiving also moves managed alias path into archive subtree',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryService mem = NocturneMemoryService.instance;
        final Database db = await ScreenshotDatabase.instance.database;
        final DateTime now = DateTime.now();

        await signals.seedCreateActionForTest(
          parentUri: 'core://my_user/interests',
          title: 'alias_topic',
          content: '用户持续关注某个长期话题。',
          context: _ctx(1, now.subtract(const Duration(days: 3))),
        );
        await signals.seedUpdateActionForTest(
          uri: 'core://my_user/interests/alias_topic',
          bulletLines: const <String>['- 经常搜索这个主题的资料'],
          context: _ctx(2, now),
        );
        await signals.materializeProfiles();
        await signals.addAliasToProfile(
          targetUri: 'core://my_user/interests/alias_topic',
          newUri: 'core://my_user/interests/alias_topic_shortcut',
        );

        final Map<String, dynamic> activeAlias = await mem.readMemory(
          'core://my_user/interests/alias_topic_shortcut',
        );
        final String activeNodeUuid = (activeAlias['node_uuid'] ?? '')
            .toString();
        expect(activeNodeUuid, isNotEmpty);

        await _retimeEntityEpisodes(
          db,
          'core://my_user/interests/alias_topic',
          <DateTime>[
            now.subtract(const Duration(days: 122)),
            now.subtract(const Duration(days: 120)),
          ],
        );

        await signals.materializeProfiles();

        final Map<String, dynamic> archivedAlias = await mem.readMemory(
          'core://my_user/interests/archive/alias_topic_shortcut',
        );
        expect((archivedAlias['node_uuid'] ?? '').toString(), activeNodeUuid);
        expect(
          () => mem.readMemory('core://my_user/interests/alias_topic_shortcut'),
          throwsA(isA<StateError>()),
        );
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'review queue approval creates and materializes managed entity',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryService mem = NocturneMemoryService.instance;
        final Database db = await ScreenshotDatabase.instance.database;
        final int reviewId = await _insertReviewQueueItem(
          db,
          preferredName: 'Vim Theme',
          rootUri: 'core://my_user/preferences',
          entityType: 'preferences',
          segmentId: 301,
        );

        final MemoryEntityApplyResult result = await signals
            .approveReviewQueueItem(reviewId: reviewId, forceCreateNew: true);

        expect(result.record, isNotNull);
        expect(
          result.record!.displayUri,
          'core://my_user/preferences/vim_theme',
        );
        expect(result.record!.status, MemoryEntityStatus.active);
        final Map<String, dynamic> memory = await mem.readMemory(
          'core://my_user/preferences/vim_theme',
        );
        expect((memory['content'] ?? '').toString(), contains('Vim 风格主题'));

        final List<MemoryEntityReviewQueueItem> pending = await signals
            .loadReviewQueueItems();
        expect(pending.where((item) => item.id == reviewId), isEmpty);
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test(
    'review queue approval can merge into existing entity and persist evidence frames',
    () async {
      final Directory tmp = await _prepareDesktopDbRoot();
      try {
        await _bootstrapRoots();
        final NocturneMemorySignalService signals =
            NocturneMemorySignalService.instance;
        final NocturneMemoryService mem = NocturneMemoryService.instance;
        final Database db = await ScreenshotDatabase.instance.database;
        final DateTime now = DateTime(2026, 4, 8, 10, 0);

        await signals.seedCreateActionForTest(
          parentUri: 'core://my_user/preferences',
          title: 'vim_theme',
          content: '用户长期偏好使用 Vim 风格主题。',
          context: _ctx(401, now, apps: const <String>['Code Editor']),
        );
        await signals.materializeProfiles();

        final List<Map<String, Object?>> existingRows = await db.query(
          'memory_entities',
          columns: const <String>['entity_id'],
          where: 'display_uri = ?',
          whereArgs: const <Object?>['core://my_user/preferences/vim_theme'],
          limit: 1,
        );
        expect(existingRows, isNotEmpty);
        final String existingEntityId = (existingRows.first['entity_id'] ?? '')
            .toString();

        final int reviewId = await _insertReviewQueueItem(
          db,
          preferredName: 'Vim Theme',
          rootUri: 'core://my_user/preferences',
          entityType: 'preferences',
          segmentId: 402,
          suggestedEntityId: existingEntityId,
        );

        final MemoryEntityApplyResult result = await signals
            .approveReviewQueueItem(reviewId: reviewId);

        expect(result.record, isNotNull);
        expect(result.record!.entityId, existingEntityId);

        final List<Map<String, Object?>> entityRows = await db.query(
          'memory_entities',
          columns: const <String>['entity_id'],
          where: 'display_uri = ?',
          whereArgs: const <Object?>['core://my_user/preferences/vim_theme'],
        );
        expect(entityRows, hasLength(1));

        final List<Map<String, Object?>> aliasRows = await db.query(
          'memory_entity_aliases',
          columns: const <String>['alias'],
          where: 'entity_id = ?',
          whereArgs: <Object?>[existingEntityId],
        );
        final Set<String> aliases = aliasRows
            .map((row) => (row['alias'] ?? '').toString())
            .where((value) => value.trim().isNotEmpty)
            .toSet();
        expect(aliases, contains('vim style'));
        expect(aliases, contains('Vim Theme'));

        final List<Map<String, Object?>> claimRows = await db.query(
          'memory_entity_claims',
          columns: const <String>['value', 'evidence_frames_json'],
          where: 'entity_id = ?',
          whereArgs: <Object?>[existingEntityId],
        );
        final Map<String, Object?> claim = claimRows.firstWhere(
          (row) => (row['value'] ?? '').toString().contains('Vim 风格主题'),
        );
        expect(
          jsonDecode((claim['evidence_frames_json'] ?? '[]').toString()),
          <dynamic>[0],
        );

        final List<Map<String, Object?>> eventRows = await db.query(
          'memory_entity_events',
          columns: const <String>['event_note', 'evidence_frames_json'],
          where: 'entity_id = ?',
          whereArgs: <Object?>[existingEntityId],
        );
        final Map<String, Object?> event = eventRows.firstWhere(
          (row) => (row['event_note'] ?? '').toString().contains('Vim 风格主题偏好'),
        );
        expect(
          jsonDecode((event['evidence_frames_json'] ?? '[]').toString()),
          <dynamic>[0],
        );

        final Map<String, dynamic> memory = await mem.readMemory(
          'core://my_user/preferences/vim_theme',
        );
        expect((memory['content'] ?? '').toString(), contains('Vim 风格主题'));
      } finally {
        try {
          await ScreenshotDatabase.instance.disposeDesktop();
        } catch (_) {}
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    },
  );

  test('review queue item can be dismissed', () async {
    final Directory tmp = await _prepareDesktopDbRoot();
    try {
      await _bootstrapRoots();
      final NocturneMemorySignalService signals =
          NocturneMemorySignalService.instance;
      final Database db = await ScreenshotDatabase.instance.database;
      final int reviewId = await _insertReviewQueueItem(
        db,
        preferredName: 'Vim Theme',
        rootUri: 'core://my_user/preferences',
        entityType: 'preferences',
        segmentId: 302,
      );

      await signals.dismissReviewQueueItem(reviewId);

      final List<Map<String, Object?>> rows = await db.query(
        'memory_entity_review_queue',
        columns: const <String>['status'],
        where: 'id = ?',
        whereArgs: <Object?>[reviewId],
        limit: 1,
      );
      expect(rows, isNotEmpty);
      expect(rows.first['status'], MemoryEntityReviewStatus.dismissed.wireName);
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    }
  });
}
