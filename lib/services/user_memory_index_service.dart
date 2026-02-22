import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'screenshot_database.dart';
import 'user_memory_service.dart';

class _LoadedImages {
  const _LoadedImages({required this.parts, required this.basenames});

  final List<Map<String, Object?>> parts;
  final List<String> basenames;
}

class UserMemoryIndexState {
  const UserMemoryIndexState({
    required this.source,
    required this.status,
    required this.cursor,
    required this.stats,
    required this.startedAtMs,
    required this.finishedAtMs,
    required this.updatedAtMs,
    required this.error,
  });

  final String source;
  final String status; // idle | running | paused | error | done
  final Map<String, dynamic> cursor;
  final Map<String, dynamic> stats;
  final int? startedAtMs;
  final int? finishedAtMs;
  final int? updatedAtMs;
  final String? error;

  static Map<String, dynamic> _decodeJsonObj(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return const <String, dynamic>{};
    try {
      final dynamic v = jsonDecode(t);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  factory UserMemoryIndexState.fromRow(Map<String, dynamic> row) {
    final String source = (row['source'] as String?)?.trim() ?? '';
    return UserMemoryIndexState(
      source: source,
      status: (row['status'] as String?)?.trim() ?? 'idle',
      cursor: _decodeJsonObj((row['cursor_json'] as String?) ?? ''),
      stats: _decodeJsonObj((row['stats_json'] as String?) ?? ''),
      startedAtMs: row['started_at'] as int?,
      finishedAtMs: row['finished_at'] as int?,
      updatedAtMs: row['updated_at'] as int?,
      error: (row['error'] as String?)?.trim(),
    );
  }
}

class UserMemoryIndexService {
  UserMemoryIndexService._internal();

  static final UserMemoryIndexService instance =
      UserMemoryIndexService._internal();

  static const String kSourceSegmentsVisionV1 = 'segments_vision_v1';

  static bool isAfterCursor({
    required int segmentEndTime,
    required int segmentId,
    required int cursorEndTime,
    required int cursorSegmentId,
  }) {
    return segmentEndTime > cursorEndTime ||
        (segmentEndTime == cursorEndTime && segmentId > cursorSegmentId);
  }

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final AISettingsService _settings = AISettingsService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;

  final StreamController<UserMemoryIndexState> _stateController =
      StreamController<UserMemoryIndexState>.broadcast();
  Stream<UserMemoryIndexState> get onStateChanged => _stateController.stream;

  Future<UserMemoryIndexState?> getState({
    String source = kSourceSegmentsVisionV1,
  }) async {
    final String src = source.trim().isEmpty
        ? kSourceSegmentsVisionV1
        : source.trim();
    try {
      final db = await _db.database;
      final rows = await db.query(
        'user_memory_index_state',
        where: 'source = ?',
        whereArgs: <Object?>[src],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return UserMemoryIndexState.fromRow(
        Map<String, dynamic>.from(rows.first),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> startFullReindex({
    String source = kSourceSegmentsVisionV1,
  }) async {
    final String src = source.trim().isEmpty
        ? kSourceSegmentsVisionV1
        : source.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;

    // Full rebuild should start from a clean slate for index-generated data,
    // otherwise stale items can survive indefinitely.
    if (src == kSourceSegmentsVisionV1) {
      try {
        await UserMemoryService.instance.clearIndexGeneratedData(
          preserveUserEditsAndPins: false,
        );
      } catch (_) {}
    }

    try {
      final db = await _db.database;
      await db.execute(
        '''
        INSERT INTO user_memory_index_state(source, status, cursor_json, stats_json, started_at, finished_at, updated_at, error)
        VALUES(?, ?, ?, ?, ?, NULL, ?, NULL)
        ON CONFLICT(source) DO UPDATE SET
          status = excluded.status,
          cursor_json = excluded.cursor_json,
          stats_json = excluded.stats_json,
          started_at = excluded.started_at,
          finished_at = NULL,
          updated_at = excluded.updated_at,
          error = NULL
        ''',
        <Object?>[
          src,
          'running',
          jsonEncode(<String, dynamic>{}),
          jsonEncode(<String, dynamic>{
            'processed_segments': 0,
            'processed_images': 0,
            'inserted': 0,
            'updated': 0,
            'touched': 0,
            'errors': 0,
          }),
          now,
          now,
        ],
      );
    } catch (_) {}
    await _emitState(src);
    _ensureLoop(src);
  }

  Future<void> pause({String source = kSourceSegmentsVisionV1}) async {
    final String src = source.trim().isEmpty
        ? kSourceSegmentsVisionV1
        : source.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final db = await _db.database;
      await db.rawUpdate(
        'UPDATE user_memory_index_state SET status = ?, updated_at = ? WHERE source = ?',
        <Object?>['paused', now, src],
      );
    } catch (_) {}
    await _emitState(src);
  }

  Future<void> resume({String source = kSourceSegmentsVisionV1}) async {
    final String src = source.trim().isEmpty
        ? kSourceSegmentsVisionV1
        : source.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final db = await _db.database;
      await db.rawUpdate(
        'UPDATE user_memory_index_state SET status = ?, updated_at = ? WHERE source = ?',
        <Object?>['running', now, src],
      );
    } catch (_) {}
    await _emitState(src);
    _ensureLoop(src);
  }

  Future<void> cancel({String source = kSourceSegmentsVisionV1}) async {
    final String src = source.trim().isEmpty
        ? kSourceSegmentsVisionV1
        : source.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    try {
      final db = await _db.database;
      await db.rawUpdate(
        '''
        UPDATE user_memory_index_state
        SET status = ?, cursor_json = NULL, finished_at = NULL, updated_at = ?, error = NULL
        WHERE source = ?
        ''',
        <Object?>['idle', now, src],
      );
    } catch (_) {}
    await _emitState(src);
  }

  Future<void> _emitState(String source) async {
    try {
      final UserMemoryIndexState? st = await getState(source: source);
      if (st == null) return;
      _stateController.add(st);
    } catch (_) {}
  }

  final Set<String> _runningSources = <String>{};

  void _ensureLoop(String source) {
    final String src = source.trim();
    if (src.isEmpty) return;
    if (_runningSources.contains(src)) return;
    _runningSources.add(src);
    unawaited(
      _runLoop(src).whenComplete(() {
        _runningSources.remove(src);
      }),
    );
  }

  String _detectImageMimeByExt(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  int _estimateDataUrlBytes(int rawBytes, String mime) {
    final int b64Len = ((rawBytes + 2) ~/ 3) * 4;
    final int prefixLen = ('data:$mime;base64,').length;
    return prefixLen + b64Len;
  }

  List<int> _evenlySampleIndices(int length, int count) {
    if (length <= 0 || count <= 0) return const <int>[];
    if (count >= length) {
      return List<int>.generate(length, (i) => i, growable: false);
    }
    if (count == 1) return <int>[(length - 1) ~/ 2];
    final List<int> out = <int>[];
    for (int i = 0; i < count; i++) {
      final double t = i / (count - 1);
      final int idx = (t * (length - 1)).round().clamp(0, length - 1);
      if (!out.contains(idx)) out.add(idx);
    }
    out.sort();
    return out;
  }

  Future<String> _getIndexStatus(DatabaseExecutor db, String source) async {
    try {
      final rows = await db.query(
        'user_memory_index_state',
        columns: const <String>['status'],
        where: 'source = ?',
        whereArgs: <Object?>[source],
        limit: 1,
      );
      if (rows.isEmpty) return 'idle';
      return (rows.first['status'] as String?)?.trim() ?? 'idle';
    } catch (_) {
      return 'idle';
    }
  }

  Future<void> _updateIndexState(
    DatabaseExecutor db,
    String source, {
    String? status,
    Map<String, dynamic>? cursor,
    Map<String, dynamic>? stats,
    int? startedAtMs,
    int? finishedAtMs,
    String? error,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<String> sets = <String>[];
    final List<Object?> args = <Object?>[];

    if (status != null) {
      sets.add('status = ?');
      args.add(status);
    }
    if (cursor != null) {
      sets.add('cursor_json = ?');
      args.add(jsonEncode(cursor));
    }
    if (stats != null) {
      sets.add('stats_json = ?');
      args.add(jsonEncode(stats));
    }
    if (startedAtMs != null) {
      sets.add('started_at = ?');
      args.add(startedAtMs);
    }
    if (finishedAtMs != null) {
      sets.add('finished_at = ?');
      args.add(finishedAtMs);
    }
    if (error != null) {
      sets.add('error = ?');
      args.add(error);
    }

    sets.add('updated_at = ?');
    args.add(now);
    args.add(source);

    final String sql =
        'UPDATE user_memory_index_state SET ${sets.join(', ')} WHERE source = ?';
    try {
      await db.execute(sql, args);
    } catch (_) {}
  }

  Future<int> _countTotalSegments(DatabaseExecutor db) async {
    try {
      final rows = await db.rawQuery('''
        SELECT COUNT(*) AS c
        FROM segments s
        WHERE s.end_time > 0
          AND EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)
        ''');
      if (rows.isEmpty) return 0;
      return (rows.first['c'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNextSegments(
    DatabaseExecutor db,
    int lastEndTime,
    int lastId, {
    int limit = 20,
  }) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT s.id, s.start_time, s.end_time
        FROM segments s
        WHERE s.end_time > 0
          AND EXISTS (SELECT 1 FROM segment_samples ss WHERE ss.segment_id = s.id)
          AND (s.end_time > ? OR (s.end_time = ? AND s.id > ?))
        ORDER BY s.end_time ASC, s.id ASC
        LIMIT ?
        ''',
        <Object?>[lastEndTime, lastEndTime, lastId, limit.clamp(1, 100)],
      );
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSegmentSamples(
    DatabaseExecutor db,
    int segmentId,
  ) async {
    try {
      final rows = await db.query(
        'segment_samples',
        columns: const <String>['file_path', 'position_index', 'is_keyframe'],
        where: 'segment_id = ?',
        whereArgs: <Object?>[segmentId],
        orderBy: 'position_index ASC',
      );
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _pickSampleImages(
    List<Map<String, dynamic>> samples, {
    int maxImages = 12,
  }) {
    final int max = maxImages.clamp(1, 15);
    if (samples.isEmpty) return const <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> keyframes = samples
        .where((e) => ((e['is_keyframe'] as int?) ?? 0) != 0)
        .toList(growable: false);
    final List<Map<String, dynamic>> nonKeyframes = samples
        .where((e) => ((e['is_keyframe'] as int?) ?? 0) == 0)
        .toList(growable: false);

    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    final Set<String> seen = <String>{};

    void add(Map<String, dynamic> s) {
      final String fp = (s['file_path'] as String?)?.trim() ?? '';
      if (fp.isEmpty) return;
      if (seen.add(fp)) out.add(s);
    }

    for (final s in keyframes) {
      if (out.length >= max) break;
      add(s);
    }
    if (out.length >= max) return out;

    final int need = max - out.length;
    final List<int> idxs = _evenlySampleIndices(nonKeyframes.length, need);
    for (final int idx in idxs) {
      if (out.length >= max) break;
      if (idx < 0 || idx >= nonKeyframes.length) continue;
      add(nonKeyframes[idx]);
    }
    return out;
  }

  Future<_LoadedImages> _loadImagesAsParts(
    List<Map<String, dynamic>> pickedSamples, {
    int maxTotalPayloadBytes = 10 * 1024 * 1024,
    int maxImages = 12,
  }) async {
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
    final List<String> basenames = <String>[];
    int totalPayloadBytes = 0;
    int count = 0;

    for (final s in pickedSamples) {
      if (count >= maxImages) break;
      final String filePath = (s['file_path'] as String?)?.trim() ?? '';
      if (filePath.isEmpty) continue;
      try {
        final File f = File(filePath);
        if (!await f.exists()) continue;
        final String mime = _detectImageMimeByExt(filePath);
        final int rawLen = await f.length();
        final int estimated = _estimateDataUrlBytes(rawLen, mime);
        if (totalPayloadBytes + estimated > maxTotalPayloadBytes) {
          continue;
        }
        final List<int> bytes = await f.readAsBytes();
        final String b64 = base64Encode(bytes);
        final String dataUrl = 'data:$mime;base64,$b64';
        final int actual = dataUrl.length;
        if (totalPayloadBytes + actual > maxTotalPayloadBytes) {
          continue;
        }
        totalPayloadBytes += actual;
        count += 1;
        final String name = p.basename(filePath);
        basenames.add(name);
        parts.add(<String, Object?>{'type': 'text', 'text': 'Filename: $name'});
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': dataUrl},
        });
      } catch (_) {}
    }
    return _LoadedImages(parts: parts, basenames: basenames);
  }

  String _sanitizeModelText(String text) {
    String t = text.trim();
    if (!t.startsWith('```')) return t;
    t = t.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*```$'), '');
    return t.trim();
  }

  ExtractedUserMemoryItem _canonicalizeItem(
    ExtractedUserMemoryItem original,
    Map<String, dynamic>? canonical,
  ) {
    String kind = (canonical?['kind'] as String?)?.trim() ?? original.kind;
    kind = (() {
      final String k = kind.trim().toLowerCase();
      if (k == 'rule' || k == 'fact' || k == 'habit') return k;
      return 'fact';
    })();

    final String? keyRaw = (canonical?['key'] as String?)?.trim();
    final String? key = (keyRaw == null || keyRaw.isEmpty)
        ? original.key
        : keyRaw;

    final String content =
        ((canonical?['content'] as String?)?.trim() ?? original.content).trim();

    List<String> keywords = original.keywords;
    final dynamic kw = canonical?['keywords'];
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

    double? confidence = original.confidence;
    final dynamic c = canonical?['confidence'];
    if (c is num) {
      confidence = c.toDouble().clamp(0.0, 1.0);
    } else if (c is String) {
      final double? parsed = double.tryParse(c.trim());
      if (parsed != null) confidence = parsed.clamp(0.0, 1.0);
    }

    return ExtractedUserMemoryItem(
      kind: kind,
      key: (key == null || key.trim().isEmpty) ? null : key.trim(),
      content: content,
      keywords: keywords,
      confidence: confidence,
      // Keep evidence from the original extraction; the merge model does not need to edit it.
      evidenceFilenames: original.evidenceFilenames,
    );
  }

  Future<List<UserMemoryResolvedWrite>> _resolveWritesWithMergeModel({
    required List<AIEndpoint> endpoints,
    required List<ExtractedUserMemoryItem> extracted,
    required int segmentId,
    required String model,
  }) async {
    if (extracted.isEmpty) {
      return const <UserMemoryResolvedWrite>[];
    }

    List<UserMemoryResolvedWrite> fallbackUpserts() => extracted
        .map((it) => UserMemoryResolvedWrite.upsert(it))
        .toList(growable: false);

    final bool allHaveKeys = extracted.every(
      (e) => (e.key ?? '').trim().isNotEmpty,
    );
    if (allHaveKeys) {
      return fallbackUpserts();
    }

    // Lightweight candidate retrieval (local FTS) to keep the merge prompt small.
    final Map<int, UserMemoryItem> candidatesById = <int, UserMemoryItem>{};
    final Map<int, List<int>> candidateIdsByIndex = <int, List<int>>{};
    for (int i = 0; i < extracted.length; i += 1) {
      final ExtractedUserMemoryItem it = extracted[i];
      final List<String> qParts = <String>[
        (it.key ?? '').trim(),
        it.content.trim(),
        it.keywords.join(' ').trim(),
      ].where((e) => e.isNotEmpty).toList(growable: false);
      final String q = qParts.join(' ');
      if (q.isEmpty) continue;
      try {
        final hits = await UserMemoryService.instance.searchItems(
          q,
          limit: 6,
          offset: 0,
          allowAdvanced: false,
        );
        final List<int> ids = <int>[];
        for (final h in hits) {
          if (h.id <= 0) continue;
          candidatesById[h.id] = h;
          if (ids.length < 6) ids.add(h.id);
        }
        if (ids.isNotEmpty) candidateIdsByIndex[i] = ids;
      } catch (_) {}
    }

    final Set<int> allCandidateIds = candidatesById.keys.toSet();
    final bool shouldCallMerge =
        extracted.length > 1 || allCandidateIds.isNotEmpty;
    if (!shouldCallMerge) {
      return fallbackUpserts();
    }

    final List<Map<String, Object?>> newItems = <Map<String, Object?>>[];
    for (int i = 0; i < extracted.length; i += 1) {
      final it = extracted[i];
      newItems.add(<String, Object?>{
        'index': i,
        'kind': it.kind,
        'key': (it.key ?? '').trim(),
        'content': it.content,
        'keywords': it.keywords,
        'confidence': it.confidence,
        'candidate_ids': candidateIdsByIndex[i] ?? const <int>[],
      });
    }

    final List<Map<String, Object?>> candidates = candidatesById.values
        .map(
          (c) => <String, Object?>{
            'id': c.id,
            'kind': c.kind,
            'key': (c.memoryKey ?? '').trim(),
            'content': c.content,
            'pinned': c.pinned,
            'user_edited': c.userEdited,
            'updated_at': c.updatedAtMs,
          },
        )
        .toList(growable: false);

    final String sys = [
      '你是一个“用户长期记忆去重/合并器”。',
      '输入包含：new_items（本次抽取结果）与 candidates（已有记忆候选）。',
      '',
      '任务：为每条 new_items 生成一个 decision：',
      '- action="merge": 语义等价/同一条记忆；选择 target_id（必须来自 candidates.id）；canonical 给出规范化字段。',
      '- action="upsert": 新的长期记忆；canonical 给出规范化字段。',
      '- action="discard": 与其它 new_items 重复且已被 merge/upsert 覆盖，或不够长期/太弱。',
      '',
      'key 规则（用于去重）：尽量输出稳定 key（lowercase，使用 . 分层，不含日期/segment id）。',
      '如果 merge 的目标 candidate 已有 key，请复用它；不要随意更换已有 key。',
      '',
      '约束：canonical.content 只能做等价改写/归一化，不要引入新事实。',
      '如果不确定是否重复，优先 upsert。',
    ].join('\n');

    const String toolName = 'user_memory_merge';
    final List<Map<String, dynamic>> tools = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': toolName,
          'description':
              'Resolve merge/upsert/discard decisions for extracted user memories.',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'decisions': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{
                    'index': <String, dynamic>{'type': 'integer', 'minimum': 0},
                    'action': <String, dynamic>{
                      'type': 'string',
                      'enum': <String>['upsert', 'merge', 'discard'],
                    },
                    'target_id': <String, dynamic>{
                      'type': 'integer',
                      'minimum': 1,
                    },
                    'canonical': <String, dynamic>{
                      'type': 'object',
                      'properties': <String, dynamic>{
                        'kind': <String, dynamic>{
                          'type': 'string',
                          'enum': <String>['rule', 'fact', 'habit'],
                        },
                        'key': <String, dynamic>{'type': 'string'},
                        'content': <String, dynamic>{'type': 'string'},
                        'keywords': <String, dynamic>{
                          'type': 'array',
                          'items': <String, dynamic>{'type': 'string'},
                        },
                        'confidence': <String, dynamic>{
                          'type': 'number',
                          'minimum': 0,
                          'maximum': 1,
                        },
                      },
                      'required': <String>[
                        'kind',
                        'content',
                        'keywords',
                        'confidence',
                      ],
                    },
                  },
                  'required': <String>['index', 'action'],
                },
              },
            },
            'required': <String>['decisions'],
          },
        },
      },
    ];
    final Map<String, dynamic> toolChoice = <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{'name': toolName},
    };

    try {
      final String userPayload = jsonEncode(<String, Object?>{
        'segment_id': segmentId,
        'model': model,
        'new_items': newItems,
        'candidates': candidates,
      });

      final AIGatewayResult result = await _gateway.complete(
        endpoints: endpoints,
        messages: <AIMessage>[
          AIMessage(role: 'system', content: sys),
          AIMessage(role: 'user', content: userPayload),
        ],
        responseStartMarker: '',
        timeout: const Duration(seconds: 45),
        preferStreaming: false,
        logContext: 'user_memory_merge_segment_$segmentId',
        tools: tools,
        toolChoice: toolChoice,
      );

      String mergeText = result.content;
      if (result.toolCalls.isNotEmpty) {
        for (final AIToolCall tc in result.toolCalls) {
          if (tc.name == toolName) {
            mergeText = tc.argumentsJson;
            break;
          }
        }
      }

      dynamic data;
      final String t = _sanitizeModelText(mergeText);
      try {
        data = jsonDecode(t);
      } catch (_) {
        final int s = t.indexOf('{');
        final int e = t.lastIndexOf('}');
        if (s >= 0 && e > s) {
          data = jsonDecode(t.substring(s, e + 1));
        } else {
          return fallbackUpserts();
        }
      }
      if (data is! Map) return fallbackUpserts();
      final dynamic decisionsRaw = data['decisions'];
      if (decisionsRaw is! List) return fallbackUpserts();

      final Map<int, Map<String, dynamic>> byIndex =
          <int, Map<String, dynamic>>{};
      for (final d in decisionsRaw) {
        if (d is! Map) continue;
        final int idx = (d['index'] is int)
            ? (d['index'] as int)
            : int.tryParse('${d['index']}'.trim()) ?? -1;
        if (idx < 0) continue;
        byIndex[idx] = Map<String, dynamic>.from(d);
      }

      final List<UserMemoryResolvedWrite> out = <UserMemoryResolvedWrite>[];
      for (int i = 0; i < extracted.length; i += 1) {
        final ExtractedUserMemoryItem original = extracted[i];
        final Map<String, dynamic>? d = byIndex[i];
        if (d == null) {
          out.add(UserMemoryResolvedWrite.upsert(original));
          continue;
        }
        final String action = (d['action'] as String? ?? '')
            .trim()
            .toLowerCase();
        final Map<String, dynamic>? canonical = (d['canonical'] is Map)
            ? Map<String, dynamic>.from(d['canonical'] as Map)
            : null;
        final ExtractedUserMemoryItem canon = _canonicalizeItem(
          original,
          canonical,
        );

        if (action == 'discard') {
          out.add(UserMemoryResolvedWrite.discard(original));
          continue;
        }
        if (action == 'merge') {
          final int targetId = (d['target_id'] is int)
              ? (d['target_id'] as int)
              : int.tryParse('${d['target_id']}'.trim()) ?? 0;
          if (targetId > 0 && allCandidateIds.contains(targetId)) {
            out.add(
              UserMemoryResolvedWrite.merge(targetId: targetId, item: canon),
            );
            continue;
          }
          // Invalid target -> fallback to upsert.
          out.add(UserMemoryResolvedWrite.upsert(canon));
          continue;
        }
        // Default: upsert.
        out.add(UserMemoryResolvedWrite.upsert(canon));
      }

      return out;
    } catch (_) {
      return fallbackUpserts();
    }
  }

  Future<void> _runLoop(String source) async {
    final String src = source.trim();
    if (src.isEmpty) return;
    final db = await _db.database;
    try {
      // Ensure the row exists.
      await db.execute(
        '''
        INSERT OR IGNORE INTO user_memory_index_state(source, status, updated_at)
        VALUES(?, 'idle', ?)
        ''',
        <Object?>[src, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (_) {}

    // Only run when status is running.
    final String initialStatus = await _getIndexStatus(db, src);
    if (initialStatus != 'running') return;

    final UserMemoryIndexState? st0 = await getState(source: src);
    Map<String, dynamic> cursor = st0?.cursor ?? <String, dynamic>{};
    Map<String, dynamic> stats = st0?.stats ?? <String, dynamic>{};

    int lastEndTime = (cursor['last_segment_end_time'] as int?) ?? 0;
    int lastId = (cursor['last_segment_id'] as int?) ?? 0;

    // Populate total on first run.
    if (stats['total_segments'] == null) {
      final int total = await _countTotalSegments(db);
      stats = <String, dynamic>{...stats, 'total_segments': total};
      await _updateIndexState(db, src, stats: stats);
      await _emitState(src);
    }

    // Resolve memory endpoints once per run.
    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: 'memory',
    );
    if (endpoints.isEmpty) {
      await _updateIndexState(
        db,
        src,
        status: 'error',
        error: 'No AI endpoints configured for context=memory',
      );
      await _emitState(src);
      return;
    }
    final String model = endpoints.first.model;

    while (true) {
      final String status = await _getIndexStatus(db, src);
      if (status != 'running') break;

      final List<Map<String, dynamic>> batch = await _fetchNextSegments(
        db,
        lastEndTime,
        lastId,
        limit: 20,
      );
      if (batch.isEmpty) {
        await _updateIndexState(
          db,
          src,
          status: 'done',
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _emitState(src);
        // Refresh auto profile once at the end.
        try {
          await UserMemoryService.instance.refreshAutoProfile();
        } catch (_) {}
        return;
      }

      for (final seg in batch) {
        final String status2 = await _getIndexStatus(db, src);
        if (status2 != 'running') break;

        final int sid = (seg['id'] as int?) ?? 0;
        final int st = (seg['start_time'] as int?) ?? 0;
        final int et = (seg['end_time'] as int?) ?? 0;
        if (sid <= 0 || st <= 0 || et <= 0) {
          stats = <String, dynamic>{
            ...stats,
            'processed_segments':
                ((stats['processed_segments'] as int?) ?? 0) + 1,
            'errors': ((stats['errors'] as int?) ?? 0) + 1,
            'last_error': 'invalid_segment_row sid=$sid st=$st et=$et',
          };
          lastEndTime = et > 0 ? et : lastEndTime;
          lastId = sid > 0 ? sid : lastId;
          cursor = <String, dynamic>{
            ...cursor,
            'last_segment_end_time': lastEndTime,
            'last_segment_id': lastId,
            'model': model,
          };
          await _updateIndexState(db, src, cursor: cursor, stats: stats);
          await _emitState(src);
          continue;
        }

        try {
          final List<Map<String, dynamic>> samples = await _fetchSegmentSamples(
            db,
            sid,
          );
          final List<Map<String, dynamic>> picked = _pickSampleImages(
            samples,
            maxImages: 12,
          );

          final List<Map<String, Object?>> parts = <Map<String, Object?>>[
            <String, Object?>{
              'type': 'text',
              'text': '以下图片来自用户设备，同一段时间窗口的截图。每张图片前有 Filename: ...',
            },
          ];
          final _LoadedImages loaded = await _loadImagesAsParts(
            picked,
            maxImages: 12,
          );
          parts.addAll(loaded.parts);

          final int imagesProvided = loaded.basenames.length;
          final Set<String> allowedNames = loaded.basenames.toSet();

          if (imagesProvided <= 0) {
            throw Exception('no_images_available_for_segment');
          }

          final DateTime nowLocal = DateTime.now().toLocal();
          final String today = nowLocal.toIso8601String().substring(0, 10);
          final DateTime startLocal = DateTime.fromMillisecondsSinceEpoch(
            st,
          ).toLocal();
          final DateTime endLocal = DateTime.fromMillisecondsSinceEpoch(
            et,
          ).toLocal();
          String two(int v) => v.toString().padLeft(2, '0');
          String fmt(DateTime d) =>
              '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';

          final String sys = [
            '你是一个“用户长期记忆抽取器”。你将看到用户设备上的截图（同一段 segment 的多张截图）。',
            '请只根据图片与提供的 segment 元信息抽取可长期保存的用户记忆。',
            '',
            'segment_id: $sid',
            'segment_time_local: ${fmt(startLocal)} – ${fmt(endLocal)}',
            'today_local: $today',
            '',
            '约束：',
            '- 只输出与“用户本人”有关、可长期复用的偏好/习惯/规则/事实；不要输出临时任务或一次性事件。',
            '- 不确定就不要写；不要根据常识推断；不要编造。',
            '- evidence 必须来自你看到的图片 Filename 列表（最多 5 个）。无法给出证据则不要输出该条。',
            '- key 可选，但强烈建议提供稳定 key（lowercase，用 . 分层，不含日期/segment id；同一语义尽量复用同一 key）。',
            '- 输出必须是 JSON only（不要代码块/不要解释）。',
            '- 如无可提取内容，输出 {"items":[]}。',
            '',
            '输出 schema：',
            '{ "items": [',
            '  { "kind":"rule|fact|habit", "key":"optional", "content":"string", "keywords":["..."], "confidence":0.0, "evidence":["..."] }',
            '] }',
          ].join('\n');

          const String toolName = 'user_memory_extract';
          final List<Map<String, dynamic>> tools = <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'function',
              'function': <String, dynamic>{
                'name': toolName,
                'description':
                    'Extract long-term user memory items from the provided screenshots. '
                    'Return ONLY the structured arguments matching the schema.',
                'parameters': <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{
                    'items': <String, dynamic>{
                      'type': 'array',
                      'items': <String, dynamic>{
                        'type': 'object',
                        'properties': <String, dynamic>{
                          'kind': <String, dynamic>{
                            'type': 'string',
                            'enum': <String>['rule', 'fact', 'habit'],
                          },
                          'key': <String, dynamic>{'type': 'string'},
                          'content': <String, dynamic>{'type': 'string'},
                          'keywords': <String, dynamic>{
                            'type': 'array',
                            'items': <String, dynamic>{'type': 'string'},
                          },
                          'confidence': <String, dynamic>{
                            'type': 'number',
                            'minimum': 0,
                            'maximum': 1,
                          },
                          'evidence': <String, dynamic>{
                            'type': 'array',
                            'items': <String, dynamic>{'type': 'string'},
                            'maxItems': 5,
                          },
                        },
                        'required': <String>[
                          'kind',
                          'content',
                          'keywords',
                          'confidence',
                          'evidence',
                        ],
                      },
                    },
                  },
                  'required': <String>['items'],
                },
              },
            },
          ];
          final Map<String, dynamic> toolChoice = <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{'name': toolName},
          };

          AIGatewayResult result;
          int attempt = 0;
          while (true) {
            attempt += 1;
            try {
              result = await _gateway.complete(
                endpoints: endpoints,
                messages: <AIMessage>[
                  AIMessage(role: 'system', content: sys),
                  AIMessage(role: 'user', content: '', apiContent: parts),
                ],
                responseStartMarker: '',
                timeout: const Duration(seconds: 60),
                preferStreaming: false,
                logContext: 'user_memory_index_segment_$sid',
                tools: tools,
                toolChoice: toolChoice,
              );
              break;
            } catch (e) {
              if (attempt >= 3) rethrow;
              final String msg = e.toString().toLowerCase();
              final bool retryable =
                  msg.contains('429') ||
                  msg.contains('rate') ||
                  msg.contains('timeout') ||
                  msg.contains('timed out');
              if (!retryable) rethrow;
              final int backoffMs = attempt == 1 ? 1500 : 3500;
              await Future<void>.delayed(Duration(milliseconds: backoffMs));
            }
          }

          // Prefer structured tool-call output; fall back to plain text JSON.
          String extractionText = result.content;
          if (result.toolCalls.isNotEmpty) {
            for (final AIToolCall tc in result.toolCalls) {
              if (tc.name == toolName) {
                extractionText = tc.argumentsJson;
                break;
              }
            }
          }
          final List<ExtractedUserMemoryItem> extracted =
              UserMemoryService.parseExtractionFromModelText(
                extractionText,
                allowedEvidenceFilenames: allowedNames,
              );

          final UserMemoryUpsertEvidenceParams ev =
              UserMemoryUpsertEvidenceParams(
                sourceType: 'segment',
                sourceId: 'segment:$sid',
                startTime: st,
                endTime: et,
              );

          // Optional: model-assisted merge to reduce semantic duplicates at write-time
          // (mobile-friendly; avoids heavy dedupe during UI search/render).
          final List<UserMemoryResolvedWrite> resolvedWrites =
              await _resolveWritesWithMergeModel(
                endpoints: endpoints,
                extracted: extracted,
                segmentId: sid,
                model: model,
              );

          final UserMemoryUpsertStats upsertStats = await UserMemoryService
              .instance
              .applyResolvedWrites(writes: resolvedWrites, evidence: ev);

          stats = <String, dynamic>{
            ...stats,
            'processed_segments':
                ((stats['processed_segments'] as int?) ?? 0) + 1,
            'processed_images':
                ((stats['processed_images'] as int?) ?? 0) + imagesProvided,
            'inserted':
                ((stats['inserted'] as int?) ?? 0) + upsertStats.inserted,
            'updated': ((stats['updated'] as int?) ?? 0) + upsertStats.updated,
            'touched': ((stats['touched'] as int?) ?? 0) + upsertStats.touched,
          };
        } catch (e) {
          stats = <String, dynamic>{
            ...stats,
            'processed_segments':
                ((stats['processed_segments'] as int?) ?? 0) + 1,
            'errors': ((stats['errors'] as int?) ?? 0) + 1,
            'last_error': e.toString(),
          };
          try {
            await FlutterLogger.nativeWarn(
              'Memory',
              'index segment $sid failed: $e',
            );
          } catch (_) {}
        }

        // Advance cursor regardless of success/failure to avoid being stuck.
        lastEndTime = et;
        lastId = sid;
        cursor = <String, dynamic>{
          ...cursor,
          'last_segment_end_time': lastEndTime,
          'last_segment_id': lastId,
          'model': model,
        };
        await _updateIndexState(
          db,
          src,
          cursor: cursor,
          stats: stats,
          error: null,
        );
        await _emitState(src);
      }
    }
  }

  void dispose() {
    try {
      _stateController.close();
    } catch (_) {}
  }
}
