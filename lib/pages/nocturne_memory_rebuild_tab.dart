import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/user_settings_keys.dart';
import '../services/ai_request_gateway.dart';
import '../services/ai_settings_service.dart';
import '../services/flutter_logger.dart';
import '../services/nocturne_memory_service.dart';
import '../services/nocturne_memory_prompts.dart';
import '../services/screenshot_database.dart';
import '../services/user_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_dialog.dart';

class NocturneMemoryRebuildTab extends StatefulWidget {
  const NocturneMemoryRebuildTab({super.key});

  @override
  State<NocturneMemoryRebuildTab> createState() =>
      _NocturneMemoryRebuildTabState();
}

class _NocturneMemoryRebuildTabState extends State<NocturneMemoryRebuildTab>
    with AutomaticKeepAliveClientMixin {
  static const int _maxImagesPerCall = 10;

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final NocturneMemoryService _mem = NocturneMemoryService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;

  final UserSettingsService _settings = UserSettingsService.instance;

  bool _running = false;
  bool _stopRequested = false;
  bool _paused = false;

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
  final ScrollController _logScroll = ScrollController();
  Timer? _persistDebounce;
  bool _persistInFlight = false;

  // Cache current memory contents for de-duplication + snapshot to the LLM.
  final Map<String, String> _memoryContentCache = <String, String>{};
  bool _allowedUriIndexLoaded = false;
  final Set<String> _knownAllowedUris = <String>{};

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _restorePersistedState();
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    if (_running) {
      _paused = true;
      _pauseReason = 'page_left';
    }
    _running = false;
    _stopRequested = false;
    // ignore: discarded_futures
    _persistState(force: true);
    _logScroll.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void _appendLog(String line) {
    final String ts = DateFormat('HH:mm:ss').format(DateTime.now());
    final String msg = '[$ts] $line';
    if (!mounted) return;
    setState(() {
      _logs.add(msg);
      if (_logs.length > 600) {
        _logs.removeRange(0, _logs.length - 600);
      }
    });
    _schedulePersist();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      try {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } catch (_) {}
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 600), () {
      // ignore: discarded_futures
      _persistState();
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
        'v': 1,
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
    } catch (_) {} finally {
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
      final Map<String, dynamic> m = Map<String, dynamic>.from(decoded as Map);

      final bool wasRunning = m['running'] == true;
      final bool paused = m['paused'] == true;
      final int cursor = _toInt(m['cursor']) ?? 0;
      final int? cursorSegId = _toInt(m['cursor_segment_id']);
      final String pauseReason = (m['pause_reason'] ?? '').toString().trim();
      final int segSampleCursor = _toInt(m['segment_sample_cursor']) ?? 0;
      final int segSampleTotal = _toInt(m['segment_sample_total']) ?? 0;
      final int? segSampleCursorSegId = _toInt(m['segment_sample_cursor_segment_id']);

      final List<String> logs = <String>[];
      final dynamic logsRaw = m['logs'];
      if (logsRaw is List) {
        for (final v in logsRaw) {
          final String s = v?.toString() ?? '';
          if (s.trim().isEmpty) continue;
          logs.add(s);
          if (logs.length >= 200) break;
        }
      }

      if (mounted) {
        setState(() {
          _running = false; // never auto-resume on restore
          _stopRequested = false;
          _paused = paused || wasRunning;
          _pauseReason =
              wasRunning ? 'restored_running' : (pauseReason.isEmpty ? null : pauseReason);
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
            ..addAll(logs);
        });
      }

      // Reload segments and align cursor by segment id (more stable than index).
      final List<Map<String, dynamic>> segs = await _loadAllSegments();
      if (!mounted) return;
      int idx = -1;
      if (cursorSegId != null) {
        idx = segs.indexWhere((e) => _toInt(e['id']) == cursorSegId);
      }
      int effectiveCursor = idx >= 0 ? idx : cursor;
      effectiveCursor = effectiveCursor.clamp(0, segs.length);
      final int? effectiveCursorSegId = effectiveCursor >= 0 && effectiveCursor < segs.length
          ? _toInt(segs[effectiveCursor]['id'])
          : null;
      final bool keepSegCursor = segSampleCursorSegId != null &&
          effectiveCursorSegId != null &&
          segSampleCursorSegId == effectiveCursorSegId;

      setState(() {
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
      });

      if (wasRunning) {
        _appendLog('已恢复上次状态（此前正在运行，已自动暂停）');
      }
    } catch (_) {}
  }

  Future<void> _start() async {
    if (_running) return;

    final bool ok = await UIDialogs.showConfirm(
      context,
      title: '一键重建记忆',
      message:
          '将清空当前 Nocturne 记忆库，并仅用“动态”里的截图图片重新构建。\n\n继续？',
      confirmText: '开始重建',
    );
    if (!ok) return;

    setState(() {
      _running = true;
      _stopRequested = false;
      _paused = false;
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
    });

    _appendLog('开始：重建记忆（纯图片语料，每次<=${_maxImagesPerCall}张）');

    try {
      await _mem.resetAll();
      _appendLog('已清空记忆库');
      await _bootstrapAnchors();
      _appendLog('已创建基础节点（core://agent, core://my_user, ...）');
    } catch (e) {
      _appendLog('清空/初始化失败：$e');
      if (mounted) {
        setState(() {
          _running = false;
          _failed += 1;
          _paused = true;
          _pauseReason = 'init_failed';
          _lastError = e.toString();
        });
      }
      return;
    }

    // 加载需要处理的 segments（只取轻量字段），避免 CursorWindow 读取大文本。
    try {
      final List<Map<String, dynamic>> segs = await _loadAllSegments();
      _appendLog('待处理段落数：${segs.length}');
      if (!mounted) return;
      setState(() {
        _segments = segs;
      });
    } catch (e) {
      _appendLog('加载段落失败：$e');
      if (mounted) {
        setState(() {
          _running = false;
          _failed += 1;
          _paused = true;
          _pauseReason = 'load_segments_failed';
          _lastError = e.toString();
        });
      }
      return;
    }

    // ignore: discarded_futures
    _runLoop();
  }

  Future<List<Map<String, dynamic>>> _loadAllSegments() async {
    const int pageSize = 200;
    int offset = 0;
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    while (true) {
      final List<Map<String, dynamic>> page = await _db.listSegmentsForMemoryRebuild(
        limit: pageSize,
        offset: offset,
        // 没有样本图片的段落直接跳过（等价于“无图继续向前推进”）。
        requireSamples: true,
      );
      if (page.isEmpty) break;
      out.addAll(page);
      offset += page.length;
      if (page.length < pageSize) break;
      // 让 UI 有机会刷新
      await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  Future<void> _bootstrapAnchors() async {
    // core://agent
    await _mem.createMemory(
      parentUri: 'core://',
      title: 'agent',
      priority: 0,
      content:
          '你是 ScreenMemo 内置的助手。\n'
          '- 目标：帮助用户回忆、检索、总结。\n'
          '- 记忆：使用 Nocturne 风格的 URI 图结构。',
    );
    // core://my_user
    await _mem.createMemory(
      parentUri: 'core://',
      title: 'my_user',
      priority: 0,
      content:
          '这里存放“用户长期记忆”（由动态截图自动构建）。\n'
          '- 写入规则：仅记录稳定、可复用的信息；不确定就不写。',
    );
    // core://agent/my_user
    await _mem.createMemory(
      parentUri: 'core://agent',
      title: 'my_user',
      priority: 0,
      content:
          '与用户交互时：\n'
          '- 优先尊重用户的偏好与约束。\n'
          '- 需要时可引用长期记忆，但避免臆测。',
    );

    // 分类节点
    const List<String> cats = <String>[
      'identity',
      'preferences',
      'projects',
      'people',
      'habits',
      'other',
    ];
    for (final c in cats) {
      await _mem.createMemory(
        parentUri: 'core://my_user',
        title: c,
        priority: 1,
        content: '（自动构建中）',
      );
    }
  }

  void _stop() {
    if (!_running) return;
    _appendLog('收到停止请求…');
    setState(() {
      _stopRequested = true;
      _paused = false;
      _pauseReason = null;
      _lastRawResponse = null;
      _lastError = null;
      _lastSegmentId = null;
      _segmentSampleCursor = 0;
      _segmentSampleTotal = 0;
      _segmentSampleCursorSegmentId = null;
    });
  }

  void _continueAfterPause() {
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
    setState(() {
      _paused = false;
      _pauseReason = null;
      _lastRawResponse = null;
      _lastError = null;
      _lastSegmentId = null;
      if (skipSegment) {
        // 将 cursor 向前推进一格（跳过当前失败的段落）
        if (_cursor < _segments.length) {
          _cursor = (_cursor + 1).clamp(0, _segments.length);
        }
        _segmentSampleCursor = 0;
        _segmentSampleTotal = 0;
        _segmentSampleCursorSegmentId = null;
      }
      _running = true;
    });
    _schedulePersist();
    // ignore: discarded_futures
    _runLoop();
  }

  Future<void> _runLoop() async {
    while (mounted && _running && !_stopRequested && !_paused) {
      if (_cursor >= _segments.length) {
        _appendLog('完成：所有段落已处理');
        setState(() {
          _running = false;
          _stopRequested = false;
          _paused = false;
          _pauseReason = null;
        });
        return;
      }

      final Map<String, dynamic> seg = _segments[_cursor];
      final int sid = (seg['id'] is num) ? (seg['id'] as num).toInt() : 0;
      _lastSegmentId = sid;
      _appendLog('处理段落 #$sid (${_cursor + 1}/${_segments.length})');

      try {
        final _SegmentOutcome outcome = await _processSegment(seg);
        if (!mounted) return;
        if (outcome == _SegmentOutcome.paused) return;
        if (_paused || !_running || _stopRequested) return;
      } catch (e) {
        _appendLog('段落 #$sid 处理失败：$e');
        if (!mounted) return;
        setState(() {
          _failed += 1;
          _paused = true;
          _running = false;
          _pauseReason = 'segment_failed';
          _lastError = e.toString();
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _processed += 1;
        _cursor += 1;
        _segmentSampleCursor = 0;
        _segmentSampleTotal = 0;
        _segmentSampleCursorSegmentId = null;
      });

      // Yield
      await Future<void>.delayed(Duration.zero);
    }

    if (!mounted) return;
    if (_stopRequested) {
      _appendLog('已停止');
      setState(() {
        _running = false;
        _stopRequested = false;
        _paused = true;
        _pauseReason = 'stopped';
      });
      _schedulePersist();
    }
  }

  Future<_SegmentOutcome> _processSegment(Map<String, dynamic> seg) async {
    final int sid = (seg['id'] is num) ? (seg['id'] as num).toInt() : 0;
    if (sid <= 0) return _SegmentOutcome.ok;

    final List<Map<String, dynamic>> samplesRaw = await _db.listSegmentSamples(sid);
    final List<Map<String, dynamic>> samples = List<Map<String, dynamic>>.from(samplesRaw)
      ..sort((a, b) {
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
      return _SegmentOutcome.skipped;
    }

    final List<AIEndpoint> endpoints =
        await AISettingsService.instance.getEndpointCandidates(context: 'memory');
    if (endpoints.isEmpty) {
      throw StateError('未配置可用的 AI Endpoint（memory 上下文）');
    }

    final String sysPrompt = _systemPrompt();

    final int total = filtered.length;
    int cursor = (_segmentSampleCursorSegmentId == sid) ? _segmentSampleCursor : 0;
    cursor = cursor.clamp(0, total);
    if (mounted) {
      setState(() {
        _segmentSampleCursorSegmentId = sid;
        _segmentSampleTotal = total;
        _segmentSampleCursor = cursor;
      });
    }
    _appendLog('段落 #$sid 图片数=$total，将按 ${_maxImagesPerCall} 张/批全部处理');

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
              '以下是同一段时间窗口内的截图（本批次最多 $_maxImagesPerCall 张）。你可能会在同一段落收到多个批次，请逐批输出 JSON actions。',
        },
      ];
      try {
        final String snapshot = await _buildUserMemorySnapshot();
        if (snapshot.trim().isNotEmpty) {
          parts.add(<String, Object?>{'type': 'text', 'text': snapshot});
        }
      } catch (_) {}

      int attached = 0;
      while (attached < _maxImagesPerCall && cursor < total) {
        final Map<String, dynamic> m = filtered[cursor];
        cursor += 1;
        final String path = (m['file_path'] as String?) ?? '';
        if (path.trim().isEmpty) continue;

        final int ts = (m['capture_time'] as int?) ?? 0;
        final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
        final String app = ((m['app_name'] as String?) ?? '').trim();
        final String label =
            '截图：${DateFormat('yyyy-MM-dd HH:mm:ss').format(dt)} ${app.isEmpty ? '' : ('· ' + app)}';

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

      if (mounted) {
        setState(() {
          _segmentSampleCursorSegmentId = sid;
          _segmentSampleTotal = total;
          _segmentSampleCursor = cursor;
        });
      }
      _schedulePersist();

      if (attached <= 0) {
        if (!anyAttachedOverall) {
          _skippedNoImages += 1;
          _appendLog('段落 #$sid 图片读取失败，跳过');
          return _SegmentOutcome.skipped;
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

      final List<_MemoryAction> actions;
      try {
        actions = _parseActions(raw);
      } catch (e) {
        _appendLog('解析失败（批次 #$batchIndex），暂停：$e');
        if (!mounted) return _SegmentOutcome.paused;
        setState(() {
          _failed += 1;
          _paused = true;
          _running = false;
          _pauseReason = 'parse_failed';
          _lastRawResponse = raw;
          _lastError = e.toString();
        });
        return _SegmentOutcome.paused;
      }

      if (actions.isEmpty) {
        _appendLog('段落 #$sid 批次 #$batchIndex 无可写入记忆（actions=0）');
        await Future<void>.delayed(Duration.zero);
        continue;
      }

      final List<_MemoryAction> ordered = <_MemoryAction>[
        ...actions.where((a) => a.tool == 'create_memory'),
        ...actions.where((a) => a.tool == 'update_memory'),
        ...actions.where(
          (a) => a.tool != 'create_memory' && a.tool != 'update_memory',
        ),
      ];

      // 应用 actions。任何一条失败都暂停（允许继续跳过）。
      for (int i = 0; i < ordered.length; i++) {
        final a = ordered[i];
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
          if (!mounted) return _SegmentOutcome.paused;
          setState(() {
            _failed += 1;
            _paused = true;
            _running = false;
            _pauseReason = 'apply_failed';
            _lastRawResponse = raw;
            _lastError = e.toString();
          });
          return _SegmentOutcome.paused;
        }
      }

      _appendLog('段落 #$sid 批次 #$batchIndex 写入完成（actions=${ordered.length}）');
      await Future<void>.delayed(Duration.zero);
    }

    return _SegmentOutcome.ok;
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

  static const List<_SnapshotTarget> _snapshotTargets = <_SnapshotTarget>[
    _SnapshotTarget(name: 'identity', uri: 'core://my_user/identity'),
    _SnapshotTarget(name: 'preferences', uri: 'core://my_user/preferences'),
    _SnapshotTarget(name: 'projects', uri: 'core://my_user/projects'),
    _SnapshotTarget(name: 'people', uri: 'core://my_user/people'),
    _SnapshotTarget(name: 'habits', uri: 'core://my_user/habits'),
    _SnapshotTarget(name: 'other', uri: 'core://my_user/other'),
  ];

  bool _isAllowedUpdateTarget(String uri) {
    final String u = uri.trim();
    if (u.isEmpty) return false;
    try {
      final NocturneUri parsed = _mem.parseUri(u);
      if (parsed.domain != 'core') return false;
      final String canon = _mem.makeUri(parsed.domain, parsed.path);
      return _snapshotTargets.any((t) =>
          canon == t.uri || canon.startsWith('${t.uri}/'));
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
      return _snapshotTargets.any((t) =>
          canon == t.uri || canon.startsWith('${t.uri}/'));
    } catch (_) {
      return false;
    }
  }

  Future<String> _readMemoryContentCached(String uri) async {
    final String u = uri.trim();
    final String? cached = _memoryContentCache[u];
    if (cached != null) return cached;
    final Map<String, dynamic> node = await _mem.readMemory(u);
    final String content = (node['content'] is String) ? (node['content'] as String) : '';
    _memoryContentCache[u] = content;
    return content;
  }

  static String _normLine(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ');

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
        line = '- ' + line.substring(1).trimLeft();
      } else if (line.startsWith('•') || line.startsWith('*')) {
        line = '- ' + line.substring(1).trimLeft();
      } else {
        line = '- ' + line;
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

    String append = '\n' + newLines.join('\n');
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
    for (final _SnapshotTarget t in _snapshotTargets) {
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
    final List<String> parts =
        rel.split('/').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return;
    if (parts.length > 10) {
      throw StateError('create_memory parent path too deep (>10): $parentUri');
    }

    String cur = root;
    for (final part in parts) {
      if (!_slugRe.hasMatch(part) || _digitsOnlyRe.hasMatch(part)) {
        throw StateError('create_memory invalid slug in parent path: $part');
      }
      final String next = '$cur/$part';
      if (_knownAllowedUris.contains(next)) {
        cur = next;
        continue;
      }

      final String dirContent = '（自动创建的目录节点，用于组织子记忆）';
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
    if ((parentUriArg == null && uriArg == null) || content.trim().isEmpty) return;

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
        throw StateError('create_memory title must match uri leaf: title=$titleRaw uri=$targetUri');
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

  String _tailContent(String content, {required int maxLines, required int maxChars}) {
    final String t = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (t.isEmpty) return '';
    final List<String> lines =
        t.split('\n').map((e) => e.trimRight()).where((e) => e.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '';
    final List<String> tail =
        (lines.length <= maxLines) ? lines : lines.sublist(lines.length - maxLines);
    String joined = tail.join('\n');
    if (joined.length > maxChars) {
      joined = joined.substring(joined.length - maxChars);
    }
    return joined.trim();
  }

  bool _isUnderAllowedRootsUri(String uri) {
    final String u = uri.trim();
    if (u.isEmpty) return false;
    return _snapshotTargets.any(
      (t) => u == t.uri || u.startsWith('${t.uri}/'),
    );
  }

  Future<void> _ensureAllowedUriIndexLoaded() async {
    if (_allowedUriIndexLoaded) return;
    _allowedUriIndexLoaded = true;
    try {
      final List<Map<String, dynamic>> paths = await _mem.getAllPaths(domain: 'core');
      for (final p in paths) {
        final String uri = (p['uri'] ?? '').toString().trim();
        if (uri.isEmpty) continue;
        if (_isUnderAllowedRootsUri(uri)) {
          _knownAllowedUris.add(uri);
        }
      }
      for (final _SnapshotTarget t in _snapshotTargets) {
        _knownAllowedUris.add(t.uri);
      }
    } catch (_) {
      // Allow retry next time.
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
      final List<String> parts = rel.split('/').where((e) => e.trim().isNotEmpty).toList();
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
        final String indent =
            depth <= 0 ? '' : List<String>.filled(depth, '  ').join();
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
    for (final _SnapshotTarget t in _snapshotTargets) {
      String content = '';
      try {
        content = await _readMemoryContentCached(t.uri);
      } catch (_) {
        content = '';
      }
      final String tail = _tailContent(content, maxLines: 12, maxChars: 900);
      out.add('');
      out.add('[' + t.name + '] ' + t.uri);
      out.add('目录索引（深度<=3，最多18行；用于避免重复建节点）：');
      out.addAll(
        _buildSubtreeIndexLines(
          t.uri,
          maxDepth: 3,
          maxLines: 18,
        ),
      );
      out.add('内容尾部：');
      out.add(tail.isEmpty ? '（空）' : tail);
    }
    return out.join('\n');
  }

  String _systemPrompt() {
    return NocturneMemoryPrompts.rebuildSystemPrompt(maxImages: _maxImagesPerCall);
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

  List<_EvidenceImage> _pickKeyImages(
    List<Map<String, dynamic>> samples, {
    required int limit,
  }) {
    if (samples.isEmpty) return const <_EvidenceImage>[];
    final List<Map<String, dynamic>> sorted = List<Map<String, dynamic>>.from(
      samples,
    )..sort(
        (a, b) => ((a['position_index'] as int?) ?? 0).compareTo(
          (b['position_index'] as int?) ?? 0,
        ),
      );

    int effectiveLimit = limit.clamp(1, 50);
    final int n = sorted.length;
    if (effectiveLimit >= n) effectiveLimit = n;

    final List<int> indices = <int>[];
    if (effectiveLimit == 1) {
      indices.add(n ~/ 2);
    } else {
      final double step = (n - 1) / (effectiveLimit - 1);
      final Set<int> used = <int>{};
      for (int k = 0; k < effectiveLimit; k++) {
        int idx = (k * step).round();
        if (idx < 0) idx = 0;
        if (idx >= n) idx = n - 1;
        if (used.add(idx)) indices.add(idx);
      }
    }

    final List<_EvidenceImage> out = <_EvidenceImage>[];
    for (final idx in indices) {
      if (idx < 0 || idx >= n) continue;
      final Map<String, dynamic> m = sorted[idx];
      final String path = (m['file_path'] as String?) ?? '';
      if (path.trim().isEmpty) continue;
      // 不在这里检查文件存在；统一在读取时统计 missing
      final int ts = (m['capture_time'] as int?) ?? 0;
      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      final String app = ((m['app_name'] as String?) ?? '').trim();
      final String label =
          '截图：${DateFormat('yyyy-MM-dd HH:mm:ss').format(dt)} ${app.isEmpty ? '' : ('· ' + app)}';
      out.add(_EvidenceImage(path: path, label: label.trim()));
    }
    return out;
  }

  List<_MemoryAction> _parseActions(String raw) {
    final dynamic decoded = _decodeJsonLenient(raw);
    final List<dynamic> actionsRaw;
    if (decoded is Map) {
      final dynamic a = decoded['actions'] ?? decoded['tool_calls'];
      if (a is List) {
        actionsRaw = a;
      } else if (a == null) {
        actionsRaw = const <dynamic>[];
      } else {
        throw FormatException('actions must be a list');
      }
    } else if (decoded is List) {
      actionsRaw = decoded;
    } else {
      throw FormatException('invalid JSON root');
    }

    final List<_MemoryAction> out = <_MemoryAction>[];
    for (final item in actionsRaw) {
      if (item is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(item as Map);
      final String tool =
          (m['tool'] ?? m['name'] ?? '').toString().trim().toLowerCase();
      final dynamic argsRaw = m['args'] ?? m['arguments'] ?? m['arguments_json'];
      Map<String, dynamic> args = <String, dynamic>{};
      if (argsRaw is Map) {
        args = Map<String, dynamic>.from(argsRaw as Map);
      } else if (argsRaw is String) {
        try {
          final dynamic a2 = jsonDecode(argsRaw);
          if (a2 is Map) args = Map<String, dynamic>.from(a2);
        } catch (_) {}
      }
      if (tool.isEmpty) continue;
      out.add(_MemoryAction(tool: tool, args: args));
      if (out.length >= 20) break; // hard cap
    }
    return out;
  }

  dynamic _decodeJsonLenient(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) throw const FormatException('empty response');
    try {
      return jsonDecode(t);
    } catch (_) {}

    // ```json ... ```
    final RegExp fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true);
    final Match? m = fence.firstMatch(t);
    if (m != null) {
      final String inside = (m.group(1) ?? '').trim();
      if (inside.isNotEmpty) {
        try {
          return jsonDecode(inside);
        } catch (_) {}
      }
    }

    // First {...} or [...]
    final int objStart = t.indexOf('{');
    final int arrStart = t.indexOf('[');
    int start = -1;
    if (objStart >= 0 && arrStart >= 0) {
      start = objStart < arrStart ? objStart : arrStart;
    } else if (objStart >= 0) {
      start = objStart;
    } else if (arrStart >= 0) {
      start = arrStart;
    }
    if (start >= 0) {
      final int objEnd = t.lastIndexOf('}');
      final int arrEnd = t.lastIndexOf(']');
      int end = -1;
      if (t[start] == '{') end = objEnd;
      if (t[start] == '[') end = arrEnd;
      if (end > start) {
        final String slice = t.substring(start, end + 1);
        return jsonDecode(slice);
      }
    }
    throw const FormatException('JSON parse failed');
  }

  Widget _buildStatsRow(BuildContext context) {
    final int total = _segments.length;
    final int cur = _cursor.clamp(0, total);
    final String pos = total <= 0 ? '-' : '$cur/$total';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '进度：$pos  已处理=$_processed  跳过(无图)=$_skippedNoImages  跳过(文件缺失)=$_skippedMissingFiles  失败=$_failed',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_lastSegmentId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '当前段落：#${_lastSegmentId}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        if (_segmentSampleCursorSegmentId != null && _segmentSampleTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '段内图片：$_segmentSampleCursor/$_segmentSampleTotal',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildPausePanel(BuildContext context) {
    if (!_paused) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String reason = (_pauseReason ?? '').trim();
    final String header = reason == 'parse_failed'
        ? '解析失败，已暂停'
        : reason == 'apply_failed'
            ? '写入失败，已暂停'
            : '已暂停';
    final String detail = (_lastError ?? '').trim();
    final String raw = (_lastRawResponse ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.error.withOpacity(0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onErrorContainer,
                ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onErrorContainer,
                  ),
            ),
          ],
          if (raw.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '原始响应：',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onErrorContainer.withOpacity(0.95),
                  ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.65),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: cs.outline.withOpacity(0.18), width: 1),
              ),
              child: SelectableText(
                raw,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: _continueAfterPause,
                child: const Text('继续'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: (detail.isEmpty && raw.isEmpty)
                    ? null
                    : () async {
                        try {
                          final StringBuffer sb = StringBuffer();
                          if (_lastSegmentId != null) sb.writeln('segment: #${_lastSegmentId}');
                          if (reason.isNotEmpty) sb.writeln('reason: $reason');
                          if (detail.isNotEmpty) sb.writeln(detail);
                          if (raw.isNotEmpty) {
                            sb.writeln();
                            sb.writeln('raw:');
                            sb.writeln(raw);
                          }
                          await Clipboard.setData(
                            ClipboardData(text: sb.toString().trimRight()),
                          );
                          if (mounted) _toast('已复制');
                        } catch (_) {
                          if (mounted) _toast('复制失败');
                        }
                      },
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('复制错误'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () async {
                  await UIDialogs.showInfo(
                    context,
                    title: '提示',
                    message:
                        '“继续”会跳过当前失败批次（本批最多10张图），继续处理本段剩余图片；若该段落已无剩余则进入下一段。\n\n若属于段落级异常，则会直接跳过该段落。',
                  );
                },
                child: const Text('说明'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(BuildContext context) {
    if (_logs.isEmpty) {
      return Center(
        child: Text(
          '日志会显示在这里',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView.builder(
      controller: _logScroll,
      itemCount: _logs.length,
      itemBuilder: (ctx, i) {
        final s = _logs[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            s,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('一键重建'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _running ? _stop : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('停止'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withOpacity(0.22),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.18),
                width: 1,
              ),
            ),
            child: _buildStatsRow(context),
          ),
          const SizedBox(height: 10),
          _buildPausePanel(context),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.0),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.18),
                  width: 1,
                ),
              ),
              child: _buildLogList(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceImage {
  final String path;
  final String label;
  const _EvidenceImage({required this.path, required this.label});
}

class _SnapshotTarget {
  final String name;
  final String uri;
  const _SnapshotTarget({required this.name, required this.uri});
}

class _IndexTreeNode {
  final Map<String, _IndexTreeNode> children = <String, _IndexTreeNode>{};
}

class _MemoryAction {
  final String tool;
  final Map<String, dynamic> args;
  const _MemoryAction({required this.tool, required this.args});
}

enum _SegmentOutcome { ok, skipped, paused }
