import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/user_settings_keys.dart';
import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'nocturne_memory_prompts.dart';
import 'nocturne_memory_service.dart';
import 'screenshot_database.dart';
import 'user_settings_service.dart';

class NocturneMemoryRebuildService extends ChangeNotifier {
  NocturneMemoryRebuildService._internal();

  static final NocturneMemoryRebuildService instance =
      NocturneMemoryRebuildService._internal();

  static const int maxImagesPerCall = 10;
  static const MethodChannel _platform = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  static const List<String> _rootCategories = <String>[
    'identity',
    'people',
    'places',
    'organizations',
    'preferences',
    'interests',
    'projects',
    'goals',
    'habits',
    'other',
  ];

  static const List<NocturneMemorySnapshotTarget>
  snapshotTargets = <NocturneMemorySnapshotTarget>[
    NocturneMemorySnapshotTarget(
      name: 'identity',
      uri: 'core://my_user/identity',
    ),
    NocturneMemorySnapshotTarget(name: 'people', uri: 'core://my_user/people'),
    NocturneMemorySnapshotTarget(name: 'places', uri: 'core://my_user/places'),
    NocturneMemorySnapshotTarget(
      name: 'organizations',
      uri: 'core://my_user/organizations',
    ),
    NocturneMemorySnapshotTarget(
      name: 'preferences',
      uri: 'core://my_user/preferences',
    ),
    NocturneMemorySnapshotTarget(
      name: 'interests',
      uri: 'core://my_user/interests',
    ),
    NocturneMemorySnapshotTarget(
      name: 'projects',
      uri: 'core://my_user/projects',
    ),
    NocturneMemorySnapshotTarget(name: 'goals', uri: 'core://my_user/goals'),
    NocturneMemorySnapshotTarget(name: 'habits', uri: 'core://my_user/habits'),
    NocturneMemorySnapshotTarget(name: 'other', uri: 'core://my_user/other'),
  ];

  static const Set<String> _actionToolNames = <String>{
    'update_memory',
    'create_memory',
  };

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final NocturneMemoryService _mem = NocturneMemoryService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;
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

  final Map<String, String> _memoryContentCache = <String, String>{};
  bool _allowedUriIndexLoaded = false;
  final Set<String> _knownAllowedUris = <String>{};

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
    _memoryContentCache.clear();
    _allowedUriIndexLoaded = false;
    _knownAllowedUris.clear();
    _publish(forceNotification: true);

    _appendLog('开始：重建记忆（纯图片语料，每次<=$maxImagesPerCall张）');

    try {
      await _mem.resetAll();
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

    for (final String c in _rootCategories) {
      await _mem.createMemory(
        parentUri: 'core://my_user',
        title: c,
        priority: 1,
        content: '（自动构建中）',
      );
    }
  }

  Future<void> _runLoop() async {
    if (_runLoopInFlight) return;
    _runLoopInFlight = true;
    try {
      while (_running && !_stopRequested && !_paused) {
        if (_cursor >= _segments.length) {
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
          if (_paused || !_running || _stopRequested) return;
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
        _appendLog('已停止');
        _running = false;
        _stopRequested = false;
        _paused = true;
        _phase = 'stopped';
        _pauseReason = 'stopped';
        await _persistState(force: true);
        _publish(forceNotification: true);
      }
    } finally {
      _runLoopInFlight = false;
    }
  }

  Future<NocturneMemorySegmentOutcome> _processSegment(
    Map<String, dynamic> seg,
  ) async {
    final int sid = (seg['id'] is num) ? (seg['id'] as num).toInt() : 0;
    if (sid <= 0) return NocturneMemorySegmentOutcome.ok;

    final List<Map<String, dynamic>> samplesRaw = await _db.listSegmentSamples(
      sid,
    );
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

    final List<AIEndpoint> endpoints = await AISettingsService.instance
        .getEndpointCandidates(context: 'memory');
    if (endpoints.isEmpty) {
      throw StateError('未配置可用的 AI Endpoint（memory 上下文）');
    }

    final String sysPrompt = _systemPrompt();

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

      final List<Map<String, Object?>> parts = <Map<String, Object?>>[
        <String, Object?>{
          'type': 'text',
          'text':
              '以下是同一段时间窗口内的截图（本批次最多 $maxImagesPerCall 张）。你可能会在同一段落收到多个批次，请逐批输出紧凑格式动作列表。',
        },
      ];
      try {
        final String snapshot = await _buildUserMemorySnapshot();
        if (snapshot.trim().isNotEmpty) {
          parts.add(<String, Object?>{'type': 'text', 'text': snapshot});
        }
      } catch (_) {}

      int attached = 0;
      while (attached < maxImagesPerCall && cursor < total) {
        final Map<String, dynamic> m = filtered[cursor];
        cursor += 1;
        final String path = (m['file_path'] as String?) ?? '';
        if (path.trim().isEmpty) continue;

        final int ts = (m['capture_time'] as int?) ?? 0;
        final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
        final String app = ((m['app_name'] as String?) ?? '').trim();
        final String label =
            '截图：${DateFormat('yyyy-MM-dd HH:mm:ss').format(dt)} ${app.isEmpty ? '' : '· $app'}';

        final String dataUrl;
        try {
          dataUrl = await _readAsDataUrl(path);
        } catch (_) {
          _skippedMissingFiles += 1;
          continue;
        }
        parts.add(<String, Object?>{'type': 'text', 'text': label.trim()});
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': dataUrl},
        });
        attached += 1;
      }

      _segmentSampleCursorSegmentId = sid;
      _segmentSampleTotal = total;
      _segmentSampleCursor = cursor;
      _publish();

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
      _appendLog(
        '段落 #$sid 批次 #$batchIndex：样本 ${batchStart + 1}-$batchEnd/$total，实际附上=$attached',
      );

      final List<AIMessage> messages = <AIMessage>[
        AIMessage(role: 'system', content: sysPrompt),
        AIMessage(role: 'user', content: '', apiContent: parts),
      ];

      AIGatewayResult result;
      try {
        result = await _gateway.complete(
          endpoints: endpoints,
          messages: messages,
          responseStartMarker: '',
          timeout: const Duration(minutes: 2),
          logContext: 'memory_rebuild_segment_${sid}_batch_$batchIndex',
        );
      } catch (e) {
        try {
          await FlutterLogger.nativeWarn('Memory', 'AI 调用失败 sid=$sid err=$e');
        } catch (_) {}
        rethrow;
      }

      final String raw = (result.content).trim();
      if (raw.isEmpty) {
        throw StateError('AI 返回为空');
      }

      final List<NocturneMemoryAction> actions;
      try {
        actions = parseModelOutput(content: raw);
      } catch (e) {
        _appendLog('解析失败（批次 #$batchIndex），暂停：$e');
        _failed += 1;
        _paused = true;
        _running = false;
        _phase = 'paused';
        _pauseReason = 'parse_failed';
        _lastRawResponse = raw;
        _lastError = e.toString();
        await _persistState(force: true);
        _publish(forceNotification: true);
        return NocturneMemorySegmentOutcome.paused;
      }

      if (actions.isEmpty) {
        _appendLog('段落 #$sid 批次 #$batchIndex 无可写入记忆（actions=0）');
        await Future<void>.delayed(Duration.zero);
        continue;
      }

      final List<NocturneMemoryAction> ordered = <NocturneMemoryAction>[
        ...actions.where((a) => a.tool == 'create_memory'),
        ...actions.where((a) => a.tool == 'update_memory'),
        ...actions.where(
          (a) => a.tool != 'create_memory' && a.tool != 'update_memory',
        ),
      ];

      for (int i = 0; i < ordered.length; i++) {
        final NocturneMemoryAction a = ordered[i];
        try {
          if (a.tool == 'update_memory') {
            await _applyUpdateMemoryAction(a.args);
          } else if (a.tool == 'create_memory') {
            await _applyCreateMemoryAction(a.args);
          } else {
            _appendLog('忽略不支持的 tool=${a.tool}');
          }
        } catch (e) {
          _appendLog(
            '应用失败（批次 #$batchIndex 第${i + 1}/${ordered.length}条），暂停：$e',
          );
          _failed += 1;
          _paused = true;
          _running = false;
          _phase = 'paused';
          _pauseReason = 'apply_failed';
          _lastRawResponse = raw;
          _lastError = e.toString();
          await _persistState(force: true);
          _publish(forceNotification: true);
          return NocturneMemorySegmentOutcome.paused;
        }
      }

      _appendLog('段落 #$sid 批次 #$batchIndex 写入完成（actions=${ordered.length}）');
      await Future<void>.delayed(Duration.zero);
    }

    return NocturneMemorySegmentOutcome.ok;
  }

  static int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static final RegExp _slugRe = RegExp(r'^[a-z0-9_-]+$');
  static final RegExp _digitsOnlyRe = RegExp(r'^[0-9]+$');

  static String? _toTrimmedOrNull(Object? v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool _isAllowedUpdateTarget(String uri) {
    final String u = uri.trim();
    if (u.isEmpty) return false;
    try {
      final NocturneUri parsed = _mem.parseUri(u);
      if (parsed.domain != 'core') return false;
      final String canon = _mem.makeUri(parsed.domain, parsed.path);
      return snapshotTargets.any(
        (t) => canon == t.uri || canon.startsWith('${t.uri}/'),
      );
    } catch (_) {
      return false;
    }
  }

  bool _isAllowedCreateParent(String parentUri) {
    final String u = parentUri.trim();
    if (u.isEmpty) return false;
    try {
      final NocturneUri parsed = _mem.parseUri(u);
      if (parsed.domain != 'core') return false;
      final String canon = _mem.makeUri(parsed.domain, parsed.path);
      return snapshotTargets.any(
        (t) => canon == t.uri || canon.startsWith('${t.uri}/'),
      );
    } catch (_) {
      return false;
    }
  }

  Future<String> _readMemoryContentCached(String uri) async {
    final String u = uri.trim();
    final String? cached = _memoryContentCache[u];
    if (cached != null) return cached;
    final Map<String, dynamic> node = await _mem.readMemory(u);
    final String content = (node['content'] is String)
        ? (node['content'] as String)
        : '';
    _memoryContentCache[u] = content;
    return content;
  }

  static String _normLine(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  List<String> _extractBulletLines(String append) {
    final String t = append
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (t.isEmpty) return const <String>[];
    final List<String> out = <String>[];
    final Set<String> used = <String>{};
    for (final String raw in t.split('\n')) {
      String line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('-')) {
        line = '- ${line.substring(1).trimLeft()}';
      } else if (line.startsWith('•') || line.startsWith('*')) {
        line = '- ${line.substring(1).trimLeft()}';
      } else {
        line = '- $line';
      }
      if (line == '-' || line == '- ' || line.trim() == '-') continue;
      final String key = _normLine(line);
      if (!used.add(key)) continue;
      out.add(line);
      if (out.length >= 60) break;
    }
    return out;
  }

  Future<void> _applyUpdateMemoryAction(Map<String, dynamic> args) async {
    final String uriRaw = (args['uri'] ?? '').toString().trim();
    if (uriRaw.isEmpty) return;
    final NocturneUri parsed = _mem.parseUri(uriRaw);
    final String uri = _mem.makeUri(parsed.domain, parsed.path);
    if (!_isAllowedUpdateTarget(uri)) {
      throw StateError('illegal update target uri: $uri');
    }
    _knownAllowedUris.add(uri);

    final String appendRaw = (args['append'] ?? '').toString();
    final List<String> bulletLines = _extractBulletLines(appendRaw);
    if (bulletLines.isEmpty) return;

    final String existing = await _readMemoryContentCached(uri);
    final Set<String> existingSet = existing
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(_normLine)
        .where((e) => e.isNotEmpty)
        .toSet();

    final List<String> newLines = <String>[];
    for (final String line in bulletLines) {
      final String k = _normLine(line);
      if (k.isEmpty) continue;
      if (existingSet.contains(k)) continue;
      existingSet.add(k);
      newLines.add(line);
      if (newLines.length >= 20) break;
    }
    if (newLines.isEmpty) {
      _appendLog('去重：$uri 没有新增要点，跳过');
      return;
    }

    String append = '\n${newLines.join('\n')}';
    if (append.length > 6000) {
      append = append.substring(0, 6000);
    }
    await _mem.updateMemory(uri: uri, append: append);
    _memoryContentCache[uri] = existing + append;
    _appendLog('产出记忆：${_formatMemoryPathForLog(uri)}（追加 ${newLines.length} 条）');
  }

  String _formatMemoryPathForLog(String uri) {
    final String u = uri.trim();
    if (u.isEmpty) return u;
    try {
      final NocturneUri parsed = _mem.parseUri(u);
      final String path = parsed.path.trim();
      return path.isEmpty ? parsed.uri : path;
    } catch (_) {
      return u;
    }
  }

  String? _allowedRootForUri(String uri) {
    final String u = uri.trim();
    if (u.isEmpty) return null;
    for (final NocturneMemorySnapshotTarget t in snapshotTargets) {
      if (u == t.uri) return t.uri;
      final String prefix = '${t.uri}/';
      if (u.startsWith(prefix)) return t.uri;
    }
    return null;
  }

  Future<void> _ensureParentChainExists(String parentUri) async {
    final String p = parentUri.trim();
    if (p.isEmpty) return;
    await _ensureAllowedUriIndexLoaded();

    final String? root = _allowedRootForUri(p);
    if (root == null) {
      throw StateError('illegal parent_uri: $parentUri');
    }
    if (p == root) return;

    final String rel = p.substring(root.length + 1);
    final List<String> parts = rel
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    if (parts.length > 10) {
      throw StateError('create_memory parent path too deep (>10): $parentUri');
    }

    String cur = root;
    for (final String part in parts) {
      if (!_slugRe.hasMatch(part) || _digitsOnlyRe.hasMatch(part)) {
        throw StateError('create_memory invalid slug in parent path: $part');
      }
      final String next = '$cur/$part';
      if (_knownAllowedUris.contains(next)) {
        cur = next;
        continue;
      }

      const String dirContent = '（自动创建的目录节点，用于组织子记忆）';
      try {
        final Map<String, dynamic> created = await _mem.createMemory(
          parentUri: cur,
          title: part,
          priority: 5,
          content: dirContent,
        );
        final String createdUri = (created['uri'] ?? '').toString().trim();
        final String u = createdUri.isNotEmpty ? createdUri : next;
        _knownAllowedUris.add(u);
        _memoryContentCache[u] = dirContent;
        _appendLog('产出记忆：${_formatMemoryPathForLog(u)}（新建目录）');
      } catch (e) {
        final String msg = e.toString();
        if (!msg.contains('path already exists')) rethrow;
        _knownAllowedUris.add(next);
        _memoryContentCache[next] = dirContent;
      }
      cur = next;
    }
  }

  Future<void> _applyCreateMemoryAction(Map<String, dynamic> args) async {
    final String? parentUriArg = _toTrimmedOrNull(args['parent_uri']);
    final String? uriArg = _toTrimmedOrNull(args['uri']);
    String content = (args['content'] ?? '').toString();
    if ((parentUriArg == null && uriArg == null) || content.trim().isEmpty) {
      return;
    }

    String parentUri;
    String? titleRaw = _toTrimmedOrNull(args['title']);

    if (parentUriArg != null) {
      final NocturneUri parsedParent = _mem.parseUri(parentUriArg);
      parentUri = _mem.makeUri(parsedParent.domain, parsedParent.path);
    } else {
      final NocturneUri parsed = _mem.parseUri(uriArg!);
      final String targetUri = _mem.makeUri(parsed.domain, parsed.path);
      if (!_isUnderAllowedRootsUri(targetUri)) {
        throw StateError('illegal uri for create_memory: $targetUri');
      }
      final String path = parsed.path.trim();
      if (path.isEmpty) {
        throw StateError('create_memory invalid uri (empty path): $targetUri');
      }
      final int cut = path.lastIndexOf('/');
      final String parentPath = cut >= 0 ? path.substring(0, cut) : '';
      final String leaf = cut >= 0 ? path.substring(cut + 1) : path;
      parentUri = _mem.makeUri(parsed.domain, parentPath);
      if (titleRaw == null) {
        titleRaw = leaf;
      } else if (titleRaw != leaf) {
        throw StateError(
          'create_memory title must match uri leaf: title=$titleRaw uri=$targetUri',
        );
      }
    }

    if (!_isAllowedCreateParent(parentUri)) {
      throw StateError('illegal parent_uri for create_memory: $parentUri');
    }

    final int priority = ((_toInt(args['priority']) ?? 2).clamp(0, 9)).toInt();
    if (titleRaw == null) {
      throw StateError('create_memory missing required title (slug)');
    }
    final String title = titleRaw;
    if (!_slugRe.hasMatch(title) || _digitsOnlyRe.hasMatch(title)) {
      throw StateError('create_memory invalid title slug: $title');
    }
    if (title.length > 64) {
      throw StateError('create_memory title too long (max 64): $title');
    }
    final String? disclosure = _toTrimmedOrNull(args['disclosure']);
    content = content.trimRight();
    if (content.length > 6000) {
      content = content.substring(0, 6000);
    }
    try {
      await _ensureParentChainExists(parentUri);
      final Map<String, dynamic> created = await _mem.createMemory(
        parentUri: parentUri,
        content: content,
        priority: priority,
        title: title,
        disclosure: disclosure,
      );
      final String createdUri = (created['uri'] ?? '').toString().trim();
      if (createdUri.isNotEmpty) {
        _knownAllowedUris.add(createdUri);
        _memoryContentCache[createdUri] = content;
        _appendLog('产出记忆：${_formatMemoryPathForLog(createdUri)}（新建）');
      }
    } catch (e) {
      final String msg = e.toString();
      if (msg.contains('path already exists')) {
        _appendLog('create_memory 已存在，跳过：$parentUri/$title');
        return;
      }
      rethrow;
    }
  }

  String _tailContent(
    String content, {
    required int maxLines,
    required int maxChars,
  }) {
    final String t = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (t.isEmpty) return '';
    final List<String> lines = t
        .split('\n')
        .map((e) => e.trimRight())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';
    final List<String> tail = (lines.length <= maxLines)
        ? lines
        : lines.sublist(lines.length - maxLines);
    String joined = tail.join('\n');
    if (joined.length > maxChars) {
      joined = joined.substring(joined.length - maxChars);
    }
    return joined.trim();
  }

  bool _isUnderAllowedRootsUri(String uri) {
    final String u = uri.trim();
    if (u.isEmpty) return false;
    return snapshotTargets.any((t) => u == t.uri || u.startsWith('${t.uri}/'));
  }

  Future<void> _ensureAllowedUriIndexLoaded() async {
    if (_allowedUriIndexLoaded) return;
    _allowedUriIndexLoaded = true;
    try {
      final List<Map<String, dynamic>> paths = await _mem.getAllPaths(
        domain: 'core',
      );
      for (final Map<String, dynamic> p in paths) {
        final String uri = (p['uri'] ?? '').toString().trim();
        if (uri.isEmpty) continue;
        if (_isUnderAllowedRootsUri(uri)) {
          _knownAllowedUris.add(uri);
        }
      }
      for (final NocturneMemorySnapshotTarget t in snapshotTargets) {
        _knownAllowedUris.add(t.uri);
      }
    } catch (_) {
      _allowedUriIndexLoaded = false;
    }
  }

  List<String> _buildSubtreeIndexLines(
    String rootUri, {
    required int maxDepth,
    required int maxLines,
  }) {
    final String root = rootUri.trim();
    if (root.isEmpty) return const <String>[];
    final String prefix = '$root/';

    final _IndexTreeNode tree = _IndexTreeNode();
    for (final String u in _knownAllowedUris) {
      if (!u.startsWith(prefix)) continue;
      final String rel = u.substring(prefix.length).trim();
      if (rel.isEmpty) continue;
      final List<String> parts = rel
          .split('/')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;
      _IndexTreeNode cur = tree;
      for (int i = 0; i < parts.length && i < maxDepth; i++) {
        cur = cur.children.putIfAbsent(parts[i], () => _IndexTreeNode());
      }
    }

    if (tree.children.isEmpty) {
      return const <String>['（无子节点）'];
    }

    final List<String> out = <String>[];
    bool clipped = false;

    void walk(_IndexTreeNode node, int depth) {
      if (out.length >= maxLines) {
        clipped = true;
        return;
      }
      final List<String> keys = node.children.keys.toList()..sort();
      for (final String k in keys) {
        if (out.length >= maxLines) {
          clipped = true;
          return;
        }
        final String indent = depth <= 0
            ? ''
            : List<String>.filled(depth, '  ').join();
        out.add('$indent- $k');
        walk(node.children[k]!, depth + 1);
        if (out.length >= maxLines) {
          clipped = true;
          return;
        }
      }
    }

    walk(tree, 0);
    if (clipped) out.add('...');
    return out;
  }

  Future<String> _buildUserMemorySnapshot() async {
    await _ensureAllowedUriIndexLoaded();
    final List<String> out = <String>[
      '【当前长期记忆快照（用于去重）】',
      '如果你准备写入的要点已经出现在快照里（含同义表达），必须跳过，不要重复写入。',
    ];
    for (final NocturneMemorySnapshotTarget t in snapshotTargets) {
      String content = '';
      try {
        content = await _readMemoryContentCached(t.uri);
      } catch (_) {
        content = '';
      }
      final String tail = _tailContent(content, maxLines: 12, maxChars: 900);
      out.add('');
      out.add('[${t.name}] ${t.uri}');
      out.add('目录索引（深度<=3，最多18行；用于避免重复建节点）：');
      out.addAll(_buildSubtreeIndexLines(t.uri, maxDepth: 3, maxLines: 18));
      out.add('内容尾部：');
      out.add(tail.isEmpty ? '（空）' : tail);
    }
    return out.join('\n');
  }

  String _systemPrompt() {
    return NocturneMemoryPrompts.rebuildSystemPrompt(
      maxImages: maxImagesPerCall,
    );
  }

  static String _detectImageMimeByExt(String path) {
    final String p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  Future<String> _readAsDataUrl(String path) async {
    final File f = File(path);
    if (!await f.exists()) {
      throw StateError('file not found');
    }
    final String mime = _detectImageMimeByExt(path);
    final List<int> bytes = await f.readAsBytes();
    final String b64 = base64Encode(bytes);
    return 'data:$mime;base64,$b64';
  }

  @visibleForTesting
  static List<NocturneMemoryAction> parseModelOutput({
    required String content,
  }) {
    final String raw = content.trim();
    if (raw.isEmpty) throw const FormatException('empty response');
    if (raw == '[]') return const <NocturneMemoryAction>[];

    final ({bool matched, List<NocturneMemoryAction> actions}) compactParsed =
        _tryParseCompactActions(raw);
    if (compactParsed.matched) return compactParsed.actions;
    throw const FormatException('compact action parse failed');
  }

  static ({bool matched, List<NocturneMemoryAction> actions})
  _tryParseCompactActions(String raw) {
    final String t = raw.trim();
    if (!t.startsWith('[') || !t.endsWith(']')) {
      return (matched: false, actions: const <NocturneMemoryAction>[]);
    }
    final String body = t.substring(1, t.length - 1).trim();
    if (body.isEmpty) {
      return (matched: true, actions: const <NocturneMemoryAction>[]);
    }

    final List<String> blocks = <String>[];
    int depth = 0;
    int blockStart = -1;
    int consumed = 0;
    for (int i = 0; i < body.length; i++) {
      final String ch = body[i];
      if (ch == '{') {
        if (depth == 0) {
          if (!_onlyCompactSeparators(body.substring(consumed, i))) {
            return (matched: false, actions: const <NocturneMemoryAction>[]);
          }
          blockStart = i;
        }
        depth += 1;
      } else if (ch == '}') {
        if (depth <= 0) {
          return (matched: false, actions: const <NocturneMemoryAction>[]);
        }
        depth -= 1;
        if (depth == 0 && blockStart >= 0) {
          blocks.add(body.substring(blockStart, i + 1));
          blockStart = -1;
          consumed = i + 1;
        }
      }
    }
    if (depth != 0) {
      return (matched: false, actions: const <NocturneMemoryAction>[]);
    }
    if (!_onlyCompactSeparators(body.substring(consumed))) {
      return (matched: false, actions: const <NocturneMemoryAction>[]);
    }
    if (blocks.isEmpty) {
      return (matched: false, actions: const <NocturneMemoryAction>[]);
    }

    final List<NocturneMemoryAction> out = <NocturneMemoryAction>[];
    for (final String block in blocks) {
      final String inner = block.substring(1, block.length - 1).trim();
      if (inner.isEmpty) {
        return (matched: false, actions: const <NocturneMemoryAction>[]);
      }

      final String tool;
      final String rest;
      final int firstComma = inner.indexOf(',');
      if (firstComma < 0) {
        return (matched: false, actions: const <NocturneMemoryAction>[]);
      } else {
        tool = inner.substring(0, firstComma).trim().toLowerCase();
        rest = inner.substring(firstComma + 1).trim();
      }
      if (!_actionToolNames.contains(tool)) {
        return (matched: false, actions: const <NocturneMemoryAction>[]);
      }

      if (tool == 'update_memory') {
        final List<String> parts = _splitN(rest, ',', 2);
        if (parts.length != 2) {
          return (matched: false, actions: const <NocturneMemoryAction>[]);
        }
        final String uri = parts[0].trim();
        final String append = parts[1].trim();
        if (uri.isEmpty || append.isEmpty) {
          return (matched: false, actions: const <NocturneMemoryAction>[]);
        }
        out.add(
          NocturneMemoryAction(
            tool: tool,
            args: <String, dynamic>{'uri': uri, 'append': append},
          ),
        );
      } else if (tool == 'create_memory') {
        final List<String> parts = _splitN(rest, ',', 3);
        if (parts.length != 3) {
          return (matched: false, actions: const <NocturneMemoryAction>[]);
        }
        final String parentUri = parts[0].trim();
        final String title = parts[1].trim();
        final String content = parts[2].trim();
        if (parentUri.isEmpty || title.isEmpty || content.isEmpty) {
          return (matched: false, actions: const <NocturneMemoryAction>[]);
        }
        out.add(
          NocturneMemoryAction(
            tool: tool,
            args: <String, dynamic>{
              'parent_uri': parentUri,
              'title': title,
              'content': content,
            },
          ),
        );
      }
      if (out.length >= 20) break;
    }
    return (matched: true, actions: out);
  }

  static bool _onlyCompactSeparators(String value) {
    for (int i = 0; i < value.length; i++) {
      final String ch = value[i];
      if (ch == ',' || ch.trim().isEmpty) continue;
      return false;
    }
    return true;
  }

  static List<String> _splitN(String input, String delimiter, int maxSplits) {
    if (maxSplits <= 0) return <String>[input];
    final List<String> out = <String>[];
    int start = 0;
    int splits = 0;
    while (splits < maxSplits) {
      final int idx = input.indexOf(delimiter, start);
      if (idx < 0) break;
      out.add(input.substring(start, idx));
      start = idx + delimiter.length;
      splits += 1;
    }
    out.add(input.substring(start));
    return out;
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

class NocturneMemorySnapshotTarget {
  final String name;
  final String uri;
  const NocturneMemorySnapshotTarget({required this.name, required this.uri});
}

class _IndexTreeNode {
  final Map<String, _IndexTreeNode> children = <String, _IndexTreeNode>{};
}

class NocturneMemoryAction {
  final String tool;
  final Map<String, dynamic> args;
  const NocturneMemoryAction({required this.tool, required this.args});
}

enum NocturneMemorySegmentOutcome { ok, skipped, paused }
