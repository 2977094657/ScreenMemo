import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_audit_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_merge_planner_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_models.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_policy.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_resolution_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_retrieval_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_store.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_visual_extraction_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_roots.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_signal_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/data/settings/user_settings_service.dart';

class NocturneMemoryRebuildService extends ChangeNotifier {
  NocturneMemoryRebuildService._internal();

  static final NocturneMemoryRebuildService instance =
      NocturneMemoryRebuildService._internal();

  static const int maxImagesPerCall = 10;
  static const MethodChannel _platform = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  static const List<NocturneMemoryRootSpec> snapshotTargets =
      NocturneMemoryRoots.all;

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final NocturneMemoryService _mem = NocturneMemoryService.instance;
  final NocturneMemorySignalService _signals =
      NocturneMemorySignalService.instance;
  final MemoryEntityStore _entityStore = MemoryEntityStore.instance;
  final MemoryEntityRetrievalService _entityRetrieval =
      MemoryEntityRetrievalService.instance;
  final MemoryVisualExtractionService _visualExtractor =
      MemoryVisualExtractionService.instance;
  final MemoryEntityResolutionService _entityResolver =
      MemoryEntityResolutionService.instance;
  final MemoryEntityMergePlannerService _mergePlanner =
      MemoryEntityMergePlannerService.instance;
  final MemoryEntityAuditService _entityAudit =
      MemoryEntityAuditService.instance;
  final UserSettingsService _settings = UserSettingsService.instance;

  bool _initialized = false;
  Future<void>? _ensureFuture;
  bool _resumeNeeded = false;

  bool _running = false;
  bool _stopRequested = false;
  bool _paused = false;
  String _phase = 'idle';

  int _cursor = 0;
  List<Map<String, dynamic>> _segments = const <Map<String, dynamic>>[];

  int _processed = 0;
  int _skippedNoImages = 0;
  int _skippedMissingFiles = 0;
  int _failed = 0;

  int _segmentSampleCursor = 0;
  int _segmentSampleTotal = 0;
  int? _segmentSampleCursorSegmentId;

  String? _pauseReason;
  String? _lastRawResponse;
  String? _lastError;
  int? _lastSegmentId;

  final List<String> _logs = <String>[];
  Timer? _persistDebounce;
  bool _persistInFlight = false;
  bool _notificationSyncInFlight = false;
  bool _notificationSyncPending = false;
  bool _runLoopInFlight = false;

  bool get initialized => _initialized;
  bool get running => _running;
  bool get paused => _paused;
  bool get stopRequested => _stopRequested;
  String get phase => _phase;
  int get cursor => _cursor;
  int get totalSegments => _segments.length;
  int get processed => _processed;
  int get skippedNoImages => _skippedNoImages;
  int get skippedMissingFiles => _skippedMissingFiles;
  int get failed => _failed;
  int get segmentSampleCursor => _segmentSampleCursor;
  int get segmentSampleTotal => _segmentSampleTotal;
  int? get segmentSampleCursorSegmentId => _segmentSampleCursorSegmentId;
  String? get pauseReason => _pauseReason;
  String? get lastRawResponse => _lastRawResponse;
  String? get lastError => _lastError;
  int? get lastSegmentId => _lastSegmentId;
  UnmodifiableListView<String> get logs => UnmodifiableListView<String>(_logs);

  Future<void> ensureInitialized({bool autoResume = false}) async {
    _ensureFuture ??= _restorePersistedState().then((_) {
      _initialized = true;
      notifyListeners();
    });
    await _ensureFuture;
    if (autoResume) {
      await _maybeAutoResume();
    }
  }

  Future<void> startFresh() async {
    await ensureInitialized();
    if (_running) return;

    _running = true;
    _stopRequested = false;
    _paused = false;
    _phase = 'preparing';
    _resumeNeeded = false;
    _cursor = 0;
    _segments = const <Map<String, dynamic>>[];
    _processed = 0;
    _skippedNoImages = 0;
    _skippedMissingFiles = 0;
    _failed = 0;
    _segmentSampleCursor = 0;
    _segmentSampleTotal = 0;
    _segmentSampleCursorSegmentId = null;
    _pauseReason = null;
    _lastRawResponse = null;
    _lastError = null;
    _lastSegmentId = null;
    _logs.clear();
    _publish(forceNotification: true);

    _appendLog('开始：重建记忆（纯图片语料，每次<=$maxImagesPerCall张）');

    try {
      await _mem.resetAll();
      await _signals.resetAll();
      _appendLog('已清空记忆库');
      await _bootstrapAnchors();
      _appendLog('已创建基础节点（core://agent, core://my_user, ...）');
    } catch (e) {
      _appendLog('清空/初始化失败：$e');
      _running = false;
      _failed += 1;
      _paused = true;
      _phase = 'paused';
      _pauseReason = 'init_failed';
      _lastError = e.toString();
      _publish(forceNotification: true);
      return;
    }

    try {
      final List<Map<String, dynamic>> segs = await _loadAllSegments();
      _segments = segs;
      _appendLog('待处理段落数：${segs.length}');
      _phase = 'running';
      _publish(forceNotification: true);
    } catch (e) {
      _appendLog('加载段落失败：$e');
      _running = false;
      _failed += 1;
      _paused = true;
      _phase = 'paused';
      _pauseReason = 'load_segments_failed';
      _lastError = e.toString();
      _publish(forceNotification: true);
      return;
    }

    _scheduleRunLoop();
  }

  void requestStop() {
    if (!_running) return;
    _appendLog('收到停止请求…');
    _stopRequested = true;
    _paused = false;
    _phase = 'running';
    _pauseReason = null;
    _lastRawResponse = null;
    _lastError = null;
    _lastSegmentId = null;
    _segmentSampleCursor = 0;
    _segmentSampleTotal = 0;
    _segmentSampleCursorSegmentId = null;
    _publish(forceNotification: true);
  }

  void continueAfterPause() {
    if (!_paused) return;
    final String r = (_pauseReason ?? '').trim();
    final bool skipBatch = r == 'parse_failed' || r == 'apply_failed';
    final bool skipSegment = r == 'segment_failed';
    _appendLog(
      skipSegment
          ? '继续：跳过失败段落并向前推进'
          : skipBatch
          ? '继续：跳过失败批次并继续处理本段剩余图片'
          : '继续：从当前位置继续',
    );
    _paused = false;
    _pauseReason = null;
    _lastRawResponse = null;
    _lastError = null;
    _lastSegmentId = null;
    if (skipSegment) {
      if (_cursor < _segments.length) {
        _cursor = (_cursor + 1).clamp(0, _segments.length);
      }
      _segmentSampleCursor = 0;
      _segmentSampleTotal = 0;
      _segmentSampleCursorSegmentId = null;
    }
    _running = true;
    _phase = _segments.isEmpty ? 'preparing' : 'running';
    _publish(forceNotification: true);
    _scheduleRunLoop();
  }

  void _scheduleRunLoop() {
    if (_runLoopInFlight) return;
    unawaited(_runLoop());
  }

  void _appendLog(String line) {
    final String ts = DateFormat('HH:mm:ss').format(DateTime.now());
    final String msg = '[$ts] $line';
    _logs.add(msg);
    if (_logs.length > 600) {
      _logs.removeRange(0, _logs.length - 600);
    }
    _publish(syncNotification: false);
  }

  void _publish({
    bool schedulePersist = true,
    bool syncNotification = true,
    bool forceNotification = false,
  }) {
    if (schedulePersist) {
      _schedulePersist();
    }
    if (syncNotification) {
      unawaited(_syncNotification(force: forceNotification));
    }
    notifyListeners();
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persistState());
    });
  }

  int? _currentCursorSegmentId() {
    if (_cursor < 0 || _cursor >= _segments.length) return null;
    final Map<String, dynamic> seg = _segments[_cursor];
    final dynamic raw = seg['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static String? _capString(String? s, int maxLen) {
    if (s == null) return null;
    final String t = s.trim();
    if (t.isEmpty) return null;
    if (t.length <= maxLen) return t;
    return t.substring(0, maxLen);
  }

  Future<void> _persistState({bool force = false}) async {
    if (_persistInFlight && !force) return;
    _persistInFlight = true;
    try {
      final List<String> logTail = _logs.length <= 200
          ? List<String>.from(_logs)
          : _logs.sublist(_logs.length - 200);
      final Map<String, dynamic> m = <String, dynamic>{
        'v': 2,
        'phase': _phase,
        'running': _running,
        'paused': _paused,
        'pause_reason': (_pauseReason ?? '').trim(),
        'cursor': _cursor,
        'cursor_segment_id': _currentCursorSegmentId(),
        'segments_total': _segments.length,
        'processed': _processed,
        'skipped_no_images': _skippedNoImages,
        'skipped_missing_files': _skippedMissingFiles,
        'failed': _failed,
        'segment_sample_cursor': _segmentSampleCursor,
        'segment_sample_total': _segmentSampleTotal,
        'segment_sample_cursor_segment_id': _segmentSampleCursorSegmentId,
        'last_segment_id': _lastSegmentId,
        'last_error': _capString(_lastError, 8000),
        'last_raw_response': _capString(_lastRawResponse, 60000),
        'logs': logTail,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      await _settings.setString(
        UserSettingKeys.nocturneMemoryRebuildState,
        jsonEncode(m),
      );
    } catch (_) {
    } finally {
      _persistInFlight = false;
    }
  }

  Future<void> _restorePersistedState() async {
    try {
      final String? raw = await _settings.getString(
        UserSettingKeys.nocturneMemoryRebuildState,
      );
      final String t = (raw ?? '').trim();
      if (t.isEmpty) return;

      dynamic decoded;
      try {
        decoded = jsonDecode(t);
      } catch (_) {
        return;
      }
      if (decoded is! Map) return;
      final Map<String, dynamic> m = Map<String, dynamic>.from(decoded);

      final bool wasRunning = m['running'] == true;
      final bool paused = m['paused'] == true;
      final int cursor = _toInt(m['cursor']) ?? 0;
      final int? cursorSegId = _toInt(m['cursor_segment_id']);
      final String pauseReason = (m['pause_reason'] ?? '').toString().trim();
      final int segSampleCursor = _toInt(m['segment_sample_cursor']) ?? 0;
      final int segSampleTotal = _toInt(m['segment_sample_total']) ?? 0;
      final int? segSampleCursorSegId = _toInt(
        m['segment_sample_cursor_segment_id'],
      );

      final List<String> restoredLogs = <String>[];
      final dynamic logsRaw = m['logs'];
      if (logsRaw is List) {
        for (final v in logsRaw) {
          final String s = v?.toString() ?? '';
          if (s.trim().isEmpty) continue;
          restoredLogs.add(s);
          if (restoredLogs.length >= 200) break;
        }
      }

      _running = false;
      _stopRequested = false;
      _paused = wasRunning ? false : paused;
      _phase = wasRunning
          ? 'paused'
          : ((m['phase'] ?? '').toString().trim().isNotEmpty
                ? (m['phase'] ?? '').toString().trim()
                : (_paused ? 'paused' : 'idle'));
      _pauseReason = wasRunning
          ? 'restored_running'
          : (pauseReason.isEmpty ? null : pauseReason);
      _cursor = cursor;
      _processed = _toInt(m['processed']) ?? 0;
      _skippedNoImages = _toInt(m['skipped_no_images']) ?? 0;
      _skippedMissingFiles = _toInt(m['skipped_missing_files']) ?? 0;
      _failed = _toInt(m['failed']) ?? 0;
      _segmentSampleCursor = segSampleCursor;
      _segmentSampleTotal = segSampleTotal;
      _segmentSampleCursorSegmentId = segSampleCursorSegId;
      _lastSegmentId = _toInt(m['last_segment_id']);
      _lastError = m['last_error']?.toString();
      _lastRawResponse = m['last_raw_response']?.toString();
      _logs
        ..clear()
        ..addAll(restoredLogs);
      _resumeNeeded = wasRunning;

      final List<Map<String, dynamic>> segs = await _loadAllSegments();
      int idx = -1;
      if (cursorSegId != null) {
        idx = segs.indexWhere((e) => _toInt(e['id']) == cursorSegId);
      }
      int effectiveCursor = idx >= 0 ? idx : cursor;
      effectiveCursor = effectiveCursor.clamp(0, segs.length);
      final int? effectiveCursorSegId =
          effectiveCursor >= 0 && effectiveCursor < segs.length
          ? _toInt(segs[effectiveCursor]['id'])
          : null;
      final bool keepSegCursor =
          segSampleCursorSegId != null &&
          effectiveCursorSegId != null &&
          segSampleCursorSegId == effectiveCursorSegId;

      _segments = segs;
      _cursor = effectiveCursor;
      if (keepSegCursor) {
        _segmentSampleCursorSegmentId = effectiveCursorSegId;
        _segmentSampleTotal = segSampleTotal;
        _segmentSampleCursor = segSampleCursor.clamp(0, segSampleTotal);
      } else {
        _segmentSampleCursor = 0;
        _segmentSampleTotal = 0;
        _segmentSampleCursorSegmentId = null;
      }

      if (wasRunning) {
        _appendLog('已恢复上次状态（检测到未完成任务，等待自动继续）');
      }
    } catch (_) {}
  }

  Future<void> _maybeAutoResume() async {
    if (!_resumeNeeded || _running) return;
    _resumeNeeded = false;
    _appendLog('检测到未完成的记忆重建，已在后台自动恢复');
    _paused = false;
    _pauseReason = null;
    _running = true;
    _stopRequested = false;
    _phase = _segments.isEmpty ? 'preparing' : 'running';
    _publish(forceNotification: true);
    _scheduleRunLoop();
  }

  Future<List<Map<String, dynamic>>> _loadAllSegments() async {
    const int pageSize = 200;
    int offset = 0;
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    while (true) {
      final List<Map<String, dynamic>> page = await _db
          .listSegmentsForMemoryRebuild(
            limit: pageSize,
            offset: offset,
            requireSamples: true,
          );
      if (page.isEmpty) break;
      out.addAll(page);
      offset += page.length;
      if (page.length < pageSize) break;
      await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  Future<void> _bootstrapAnchors() async {
    await _mem.runBootstrapWrite(() async {
      await _mem.createMemory(
        parentUri: 'core://',
        title: 'agent',
        priority: 0,
        content:
            '你是 ScreenMemo 内置的助手。\n'
            '- 目标：帮助用户回忆、检索、总结。\n'
            '- 记忆：使用 Nocturne 风格的 URI 图结构。',
      );
      await _mem.createMemory(
        parentUri: 'core://',
        title: 'my_user',
        priority: 0,
        content:
            '这里存放“用户长期记忆”（由动态截图自动构建）。\n'
            '- 写入规则：仅记录稳定、可复用的信息；不确定就不写。',
      );
      await _mem.createMemory(
        parentUri: 'core://agent',
        title: 'my_user',
        priority: 0,
        content:
            '与用户交互时：\n'
            '- 优先尊重用户的偏好与约束。\n'
            '- 需要时可引用长期记忆，但避免臆测。',
      );

      for (final NocturneMemoryRootSpec root in snapshotTargets) {
        await _mem.createMemory(
          parentUri: 'core://my_user',
          title: root.name,
          priority: 1,
          content: '（自动构建中）',
        );
      }
    });
  }

  Future<void> _runLoop() async {
    if (_runLoopInFlight) return;
    _runLoopInFlight = true;
    try {
      while (_running && !_stopRequested && !_paused) {
        if (_cursor >= _segments.length) {
          _phase = 'finalizing';
          _appendLog('收尾：根据信号物化长期记忆');
          _publish();
          try {
            await _signals.materializeProfiles(
              shouldStop: () => _stopRequested,
            );
            if (_stopRequested) {
              break;
            }
            _appendLog('已完成信号物化与封存整理');
          } catch (e) {
            _appendLog('信号物化失败：$e');
            _failed += 1;
            _paused = true;
            _running = false;
            _phase = 'paused';
            _pauseReason = 'finalize_failed';
            _lastError = e.toString();
            await _persistState(force: true);
            _publish(forceNotification: true);
            return;
          }
          _appendLog('完成：所有段落已处理');
          _running = false;
          _stopRequested = false;
          _paused = false;
          _phase = 'completed';
          _pauseReason = null;
          await _persistState(force: true);
          _publish(forceNotification: true);
          return;
        }

        final Map<String, dynamic> seg = _segments[_cursor];
        final int sid = (seg['id'] is num) ? (seg['id'] as num).toInt() : 0;
        _lastSegmentId = sid;
        _appendLog('处理段落 #$sid (${_cursor + 1}/${_segments.length})');
        _publish();

        try {
          final NocturneMemorySegmentOutcome outcome = await _processSegment(
            seg,
          );
          if (outcome == NocturneMemorySegmentOutcome.paused) return;
          if (_paused || !_running) return;
          if (_stopRequested) break;
        } catch (e) {
          _appendLog('段落 #$sid 处理失败：$e');
          _failed += 1;
          _paused = true;
          _running = false;
          _phase = 'paused';
          _pauseReason = 'segment_failed';
          _lastError = e.toString();
          await _persistState(force: true);
          _publish(forceNotification: true);
          return;
        }

        _processed += 1;
        _cursor += 1;
        _segmentSampleCursor = 0;
        _segmentSampleTotal = 0;
        _segmentSampleCursorSegmentId = null;
        _publish();
        await Future<void>.delayed(Duration.zero);
      }

      if (_stopRequested) {
        await _finalizeStopped();
      }
    } finally {
      _runLoopInFlight = false;
    }
  }

  Future<void> _finalizeStopped() async {
    _appendLog('已停止');
    _running = false;
    _stopRequested = false;
    _paused = true;
    _phase = 'stopped';
    _pauseReason = 'stopped';
    await _persistState(force: true);
    _publish(forceNotification: true);
  }

  Future<NocturneMemorySegmentOutcome> _processSegment(
    Map<String, dynamic> seg,
  ) async {
    final int sid = (seg['id'] is num) ? (seg['id'] as num).toInt() : 0;
    if (sid <= 0) return NocturneMemorySegmentOutcome.ok;

    final List<Map<String, dynamic>> samplesRaw = await _db.listSegmentSamples(
      sid,
    );
    if (_stopRequested) return NocturneMemorySegmentOutcome.ok;
    final List<Map<String, dynamic>> samples =
        List<Map<String, dynamic>>.from(samplesRaw)..sort((a, b) {
          final int ai = (a['position_index'] as int?) ?? 0;
          final int bi = (b['position_index'] as int?) ?? 0;
          final int c = ai.compareTo(bi);
          if (c != 0) return c;
          final int at = (a['capture_time'] as int?) ?? 0;
          final int bt = (b['capture_time'] as int?) ?? 0;
          return at.compareTo(bt);
        });

    final List<Map<String, dynamic>> filtered = <Map<String, dynamic>>[];
    for (final m in samples) {
      final String path = (m['file_path'] as String?) ?? '';
      if (path.trim().isEmpty) continue;
      filtered.add(m);
    }

    if (filtered.isEmpty) {
      _skippedNoImages += 1;
      _appendLog('段落 #$sid 无可用图片，跳过');
      _publish();
      return NocturneMemorySegmentOutcome.skipped;
    }

    final int total = filtered.length;
    int cursor = (_segmentSampleCursorSegmentId == sid)
        ? _segmentSampleCursor
        : 0;
    cursor = cursor.clamp(0, total);
    _segmentSampleCursorSegmentId = sid;
    _segmentSampleTotal = total;
    _segmentSampleCursor = cursor;
    _publish();
    _appendLog('段落 #$sid 图片数=$total，将按 $maxImagesPerCall 张/批全部处理');

    int batchIndex = 0;
    bool anyAttachedOverall = false;
    while (cursor < total) {
      if (_stopRequested) break;
      batchIndex += 1;
      final int batchStart = cursor;
      final List<Map<String, dynamic>> attachedSamples =
          <Map<String, dynamic>>[];
      int attached = 0;
      while (attached < maxImagesPerCall && cursor < total) {
        if (_stopRequested) break;
        final Map<String, dynamic> m = filtered[cursor];
        cursor += 1;
        final String path = (m['file_path'] as String?) ?? '';
        if (path.trim().isEmpty) continue;
        try {
          final File file = File(path);
          if (!await file.exists()) {
            _skippedMissingFiles += 1;
            continue;
          }
        } catch (_) {
          _skippedMissingFiles += 1;
          continue;
        }
        attachedSamples.add(m);
        attached += 1;
      }

      _segmentSampleCursorSegmentId = sid;
      _segmentSampleTotal = total;
      _segmentSampleCursor = cursor;
      _publish();
      if (_stopRequested) return NocturneMemorySegmentOutcome.ok;

      if (attached <= 0) {
        if (!anyAttachedOverall) {
          _skippedNoImages += 1;
          _appendLog('段落 #$sid 图片读取失败，跳过');
          _publish();
          return NocturneMemorySegmentOutcome.skipped;
        }
        _appendLog('段落 #$sid 剩余图片均无法读取，结束本段');
        break;
      }
      anyAttachedOverall = true;

      final int batchEnd = cursor;
      final String batchEvidenceSummary = _buildBatchEvidenceSummary(
        sid: sid,
        batchIndex: batchIndex,
        batchStart: batchStart,
        batchEnd: batchEnd,
        total: total,
        attachedSamples: attachedSamples,
      );
      final NocturneMemorySignalContext signalContext =
          NocturneMemorySignalContext(
            segmentId: sid,
            batchIndex: batchIndex,
            segmentStartMs: _toInt(seg['start_time']),
            segmentEndMs: _resolveSignalSegmentEndMs(
              seg: seg,
              attachedSamples: attachedSamples,
            ),
            evidenceSummary: batchEvidenceSummary,
            appNames:
                attachedSamples
                    .map(
                      (sample) =>
                          ((sample['app_name'] as String?) ?? '').trim(),
                    )
                    .where((app) => app.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort(),
          );
      _appendLog(
        '段落 #$sid 批次 #$batchIndex：样本 ${batchStart + 1}-$batchEnd/$total，实际附上=$attached',
      );
      final MemoryBatchExtractionResult extraction;
      try {
        extraction = await _visualExtractor.extractBatch(
          segmentId: sid,
          batchIndex: batchIndex,
          samples: attachedSamples,
        );
      } catch (e) {
        await _recordBatchRunSafe(
          segmentId: sid,
          batchIndex: batchIndex,
          status: 'extract_failed',
          sampleCount: attachedSamples.length,
          candidateCount: 0,
          appliedCount: 0,
          reviewCount: 0,
          skippedCount: 0,
        );
        _appendLog('AI 视觉提取失败（批次 #$batchIndex），暂停：$e');
        _failed += 1;
        _paused = true;
        _running = false;
        _phase = 'paused';
        _pauseReason = 'extract_failed';
        _lastError = e.toString();
        await _persistState(force: true);
        _publish(forceNotification: true);
        return NocturneMemorySegmentOutcome.paused;
      }
      _lastRawResponse = extraction.rawPayload;

      if (_stopRequested) {
        _appendLog('停止：已跳过段落 #$sid 批次 #$batchIndex 的实体写入');
        return NocturneMemorySegmentOutcome.ok;
      }

      if (extraction.entities.isEmpty) {
        _appendLog('段落 #$sid 批次 #$batchIndex 未提取到可进入候选层的实体');
        await _recordBatchRunSafe(
          segmentId: sid,
          batchIndex: batchIndex,
          status: 'empty',
          sampleCount: attachedSamples.length,
          candidateCount: 0,
          appliedCount: 0,
          reviewCount: 0,
          skippedCount: 0,
          modelName: extraction.modelUsed,
        );
        await Future<void>.delayed(Duration.zero);
        continue;
      }

      int appliedCount = 0;
      int reviewCount = 0;
      int skippedCount = 0;
      for (final MemoryVisualCandidate candidate in extraction.entities) {
        if (_stopRequested) {
          _appendLog('停止：段落 #$sid 批次 #$batchIndex 在实体处理前终止');
          return NocturneMemorySegmentOutcome.ok;
        }
        try {
          final _EntityCandidateApplyOutcome outcome =
              await _applyEntityCandidate(
                sid: sid,
                batchIndex: batchIndex,
                candidate: candidate,
                signalContext: signalContext,
                attachedSamples: attachedSamples,
              );
          if (outcome.applied) {
            appliedCount += 1;
          }
          if (outcome.queuedForReview) {
            reviewCount += 1;
          }
          if (outcome.skipped) {
            skippedCount += 1;
          }
        } catch (e) {
          await _recordBatchRunSafe(
            segmentId: sid,
            batchIndex: batchIndex,
            status: 'entity_apply_failed',
            sampleCount: attachedSamples.length,
            candidateCount: extraction.entities.length,
            appliedCount: appliedCount,
            reviewCount: reviewCount,
            skippedCount: skippedCount,
            modelName: extraction.modelUsed,
          );
          _appendLog(
            '实体应用失败（批次 #$batchIndex，${candidate.preferredName}），暂停：$e',
          );
          _failed += 1;
          _paused = true;
          _running = false;
          _phase = 'paused';
          _pauseReason = 'entity_apply_failed';
          _lastError = e.toString();
          await _persistState(force: true);
          _publish(forceNotification: true);
          return NocturneMemorySegmentOutcome.paused;
        }
      }

      await _recordBatchRunSafe(
        segmentId: sid,
        batchIndex: batchIndex,
        status: 'completed',
        sampleCount: attachedSamples.length,
        candidateCount: extraction.entities.length,
        appliedCount: appliedCount,
        reviewCount: reviewCount,
        skippedCount: skippedCount,
        modelName: extraction.modelUsed,
      );
      _appendLog(
        '段落 #$sid 批次 #$batchIndex 写入完成（applied=$appliedCount, review=$reviewCount, skipped=$skippedCount）',
      );
      await Future<void>.delayed(Duration.zero);
    }

    return NocturneMemorySegmentOutcome.ok;
  }

  Future<_EntityCandidateApplyOutcome> _applyEntityCandidate({
    required int sid,
    required int batchIndex,
    required MemoryVisualCandidate candidate,
    required NocturneMemorySignalContext signalContext,
    required List<Map<String, dynamic>> attachedSamples,
  }) async {
    if (candidate.shouldSkip) {
      final String reason = (candidate.skipReason ?? '').trim();
      _appendLog(
        '段落 #$sid 批次 #$batchIndex 跳过候选 ${candidate.preferredName}：${reason.isEmpty ? 'AI 判定不值得进入候选层' : reason}',
      );
      return const _EntityCandidateApplyOutcome.skipped();
    }

    final MemoryEntityRootPolicy? policy = MemoryEntityPolicies.forRootKey(
      candidate.rootKey,
    );
    if (policy == null) {
      _appendLog('段落 #$sid 批次 #$batchIndex 忽略未知 root_key=${candidate.rootKey}');
      return const _EntityCandidateApplyOutcome.skipped();
    }

    final List<MemoryEntityExemplar> allExemplars = <MemoryEntityExemplar>[
      for (int index = 0; index < attachedSamples.length; index += 1)
        MemoryEntityExemplar.fromMap(<String, dynamic>{
          ...attachedSamples[index],
          'position_index': index,
        }),
    ].where((item) => item.filePath.isNotEmpty).toList(growable: false);
    final List<MemoryEntityExemplar> evidenceExemplars =
        candidate.evidenceFrames.isEmpty
        ? allExemplars
        : <MemoryEntityExemplar>[
            for (final int frame in candidate.evidenceFrames)
              if (frame >= 0 && frame < allExemplars.length)
                allExemplars[frame],
          ];
    final List<MemoryEntityExemplar> candidateExemplars =
        evidenceExemplars.isEmpty ? allExemplars : evidenceExemplars;

    final List<MemoryEntityDossier> shortlist = await _entityRetrieval
        .retrieveShortlist(policy: policy, candidate: candidate);
    final MemoryEntityResolutionWorkflowResult resolutionWorkflow =
        await _entityResolver.resolve(
          candidate: candidate,
          shortlist: shortlist,
          currentExemplars: candidateExemplars,
        );
    final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    resolutionResult = resolutionWorkflow.finalResult;
    final MemoryEntityResolutionDecision resolution = resolutionResult.value;
    final MemoryEntityDossier? matched = resolution.matchedEntityId == null
        ? null
        : shortlist.cast<MemoryEntityDossier?>().firstWhere(
            (item) => item?.entityId == resolution.matchedEntityId,
            orElse: () => null,
          );
    final MemoryStructuredDecisionResult<MemoryEntityMergePlan>
    mergePlanResult = await _mergePlanner.plan(
      candidate: candidate,
      resolution: resolution,
      matched: matched,
      currentExemplars: candidateExemplars,
    );
    final MemoryEntityMergePlan mergePlan = mergePlanResult.value;
    final MemoryStructuredDecisionResult<MemoryEntityAuditDecision>
    auditResult = await _entityAudit.audit(
      candidate: candidate,
      resolution: resolution,
      mergePlan: mergePlan,
      shortlist: shortlist,
      currentExemplars: candidateExemplars,
    );
    final MemoryEntityApplyResult applied = await _entityStore
        .applyAIPipelineResult(
          visualCandidate: candidate,
          resolutionWorkflow: resolutionWorkflow,
          mergePlanResult: mergePlanResult,
          auditResult: auditResult,
          shortlist: shortlist,
          segmentId: signalContext.segmentId,
          batchIndex: signalContext.batchIndex,
          segmentStartMs: signalContext.segmentStartMs,
          segmentEndMs: signalContext.segmentEndMs,
          evidenceSummary: signalContext.evidenceSummary,
          appNames: signalContext.appNames,
          exemplars: candidateExemplars,
        );
    if (applied.queuedForReview || applied.record == null) {
      _appendLog(
        '实体候选 ${candidate.preferredName} 已进入 review 队列'
        '${(applied.reviewReason ?? '').trim().isEmpty ? '' : '：${applied.reviewReason!.trim()}'}',
      );
      return const _EntityCandidateApplyOutcome.queuedReview();
    }
    final MemoryEntityRecord record = applied.record!;
    final String state = record.status == MemoryEntityStatus.active
        ? 'active'
        : record.status == MemoryEntityStatus.archived
        ? 'archived'
        : 'candidate';
    _appendLog(
      '实体 ${record.preferredName} -> ${record.displayUri} '
      '(${applied.created ? 'new' : 'merge'}, $state${applied.needsReview ? ', review' : ''})',
    );
    return const _EntityCandidateApplyOutcome.applied();
  }

  Future<void> _recordBatchRunSafe({
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
    try {
      await _entityStore.recordBatchRun(
        segmentId: segmentId,
        batchIndex: batchIndex,
        status: status,
        sampleCount: sampleCount,
        candidateCount: candidateCount,
        appliedCount: appliedCount,
        reviewCount: reviewCount,
        skippedCount: skippedCount,
        modelName: modelName,
      );
    } catch (e) {
      _appendLog('批次指标写入失败（段落 #$segmentId 批次 #$batchIndex）：$e');
    }
  }

  static int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String _buildBatchEvidenceSummary({
    required int sid,
    required int batchIndex,
    required int batchStart,
    required int batchEnd,
    required int total,
    required List<Map<String, dynamic>> attachedSamples,
  }) {
    final List<DateTime> captureTimes =
        attachedSamples
            .map((sample) => _toInt(sample['capture_time']))
            .whereType<int>()
            .where((ts) => ts > 0)
            .map((ts) => DateTime.fromMillisecondsSinceEpoch(ts).toLocal())
            .toList()
          ..sort();
    final LinkedHashSet<String> appNames = LinkedHashSet<String>.from(
      attachedSamples
          .map((sample) => ((sample['app_name'] as String?) ?? '').trim())
          .where((app) => app.isNotEmpty),
    );

    final StringBuffer summary = StringBuffer(
      '来自动态段 #$sid 批次 #$batchIndex 的截图',
    );
    summary.write('（样本 ${batchStart + 1}-$batchEnd/$total');
    if (captureTimes.isNotEmpty) {
      final DateFormat fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
      final String first = fmt.format(captureTimes.first);
      final String last = fmt.format(captureTimes.last);
      if (captureTimes.length == 1) {
        summary.write('，时间：$first');
      } else {
        summary.write('，时间：$first 至 $last');
      }
    }
    summary.write('，共${attachedSamples.length}张');
    if (appNames.isNotEmpty) {
      summary.write('；应用：${appNames.join('、')}');
    }
    summary.write('）');
    return summary.toString();
  }

  int? _resolveSignalSegmentEndMs({
    required Map<String, dynamic> seg,
    required List<Map<String, dynamic>> attachedSamples,
  }) {
    final int? segmentEnd = _toInt(seg['end_time']);
    if (segmentEnd != null && segmentEnd > 0) return segmentEnd;
    int latest = 0;
    for (final Map<String, dynamic> sample in attachedSamples) {
      final int ts = _toInt(sample['capture_time']) ?? 0;
      if (ts > latest) latest = ts;
    }
    return latest > 0 ? latest : null;
  }

  String _notificationStatus() {
    if (_running && _phase == 'preparing') return 'preparing';
    if (_running) return 'running';
    if (_phase == 'completed') return 'completed';
    if (_phase == 'stopped') return 'stopped';
    if (_paused || _phase == 'paused') return 'paused';
    return 'idle';
  }

  int _notificationCurrentPosition() {
    if (_segments.isEmpty) return 0;
    if (_cursor >= _segments.length) return _segments.length;
    return (_cursor + 1).clamp(1, _segments.length);
  }

  Future<void> _syncNotification({bool force = false}) async {
    if (_notificationSyncInFlight) {
      _notificationSyncPending = true;
      return;
    }
    _notificationSyncInFlight = true;
    try {
      do {
        _notificationSyncPending = false;
        final String status = _notificationStatus();
        if (status == 'idle') {
          try {
            await _platform.invokeMethod('cancelMemoryRebuildNotification');
          } catch (_) {}
          continue;
        }
        final Map<String, dynamic> payload = <String, dynamic>{
          'status': status,
          'processed': _processed,
          'failed': _failed,
          'total': _segments.length,
          'currentPosition': _notificationCurrentPosition(),
          'currentSegmentId': _lastSegmentId ?? 0,
          'segmentSampleCursor': _segmentSampleCursor,
          'segmentSampleTotal': _segmentSampleTotal,
          'pauseReason': _pauseReason ?? '',
          'lastError': _lastError ?? '',
        };
        try {
          await _platform.invokeMethod(
            'showMemoryRebuildNotification',
            payload,
          );
        } catch (_) {}
      } while (_notificationSyncPending);
    } finally {
      _notificationSyncInFlight = false;
    }
  }
}

enum NocturneMemorySegmentOutcome { ok, skipped, paused }

class _EntityCandidateApplyOutcome {
  const _EntityCandidateApplyOutcome({
    required this.applied,
    required this.queuedForReview,
    required this.skipped,
  });

  const _EntityCandidateApplyOutcome.applied()
    : applied = true,
      queuedForReview = false,
      skipped = false;

  const _EntityCandidateApplyOutcome.queuedReview()
    : applied = false,
      queuedForReview = true,
      skipped = false;

  const _EntityCandidateApplyOutcome.skipped()
    : applied = false,
      queuedForReview = false,
      skipped = true;

  final bool applied;
  final bool queuedForReview;
  final bool skipped;
}
