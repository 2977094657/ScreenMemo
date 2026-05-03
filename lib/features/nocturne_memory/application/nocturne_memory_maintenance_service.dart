import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/features/ai/application/ai_request_gateway.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/core/lifecycle/app_lifecycle_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_prompts.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_signal_service.dart';
import 'package:screen_memo/data/settings/user_settings_service.dart';

enum NocturneMemoryMaintenanceAction {
  rewriteMemory('rewrite_memory', '重写节点'),
  addAlias('add_alias', '新增别名'),
  moveMemory('move_memory', '移动节点'),
  archiveMemory('archive_memory', '强制封存'),
  deleteMemory('delete_memory', '删除节点'),
  dropCandidate('drop_candidate', '丢弃候选');

  const NocturneMemoryMaintenanceAction(this.wireName, this.label);

  final String wireName;
  final String label;

  static NocturneMemoryMaintenanceAction? fromWire(String value) {
    final String normalized = value.trim().toLowerCase();
    for (final NocturneMemoryMaintenanceAction action
        in NocturneMemoryMaintenanceAction.values) {
      if (action.wireName == normalized) return action;
    }
    return null;
  }
}

class NocturneMemoryMaintenanceSuggestion {
  const NocturneMemoryMaintenanceSuggestion({
    required this.action,
    required this.targetUri,
    required this.reason,
    required this.evidence,
    this.targetEntityId,
    this.newUri,
    this.content,
  });

  final NocturneMemoryMaintenanceAction action;
  final String targetUri;
  final String reason;
  final String evidence;
  final String? targetEntityId;
  final String? newUri;
  final String? content;

  String get fingerprint => jsonEncode(toJson());

  String get summaryLine {
    switch (action) {
      case NocturneMemoryMaintenanceAction.rewriteMemory:
        return '${action.label}: $targetUri';
      case NocturneMemoryMaintenanceAction.addAlias:
        return '${action.label}: ${newUri ?? "（缺失 new_uri）"} -> $targetUri';
      case NocturneMemoryMaintenanceAction.moveMemory:
        return '${action.label}: $targetUri -> ${newUri ?? "（缺失 new_uri）"}';
      case NocturneMemoryMaintenanceAction.archiveMemory:
        return '${action.label}: $targetUri';
      case NocturneMemoryMaintenanceAction.deleteMemory:
        return '${action.label}: $targetUri';
      case NocturneMemoryMaintenanceAction.dropCandidate:
        return '${action.label}: $targetUri';
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'action': action.wireName,
    'target_uri': targetUri,
    'target_entity_id': targetEntityId,
    'new_uri': newUri,
    'content': content,
    'reason': reason,
    'evidence': evidence,
  };
}

class NocturneMemoryMaintenancePlan {
  const NocturneMemoryMaintenancePlan({
    required this.summary,
    required this.suggestions,
  });

  final String summary;
  final List<NocturneMemoryMaintenanceSuggestion> suggestions;
}

class NocturneMemoryMaintenanceService extends ChangeNotifier {
  NocturneMemoryMaintenanceService._internal();

  static final NocturneMemoryMaintenanceService instance =
      NocturneMemoryMaintenanceService._internal();

  static const Duration _autoRunInterval = Duration(hours: 12);

  final UserSettingsService _settings = UserSettingsService.instance;
  final AISettingsService _aiSettings = AISettingsService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;
  final NocturneMemoryService _mem = NocturneMemoryService.instance;
  final NocturneMemorySignalService _signals =
      NocturneMemorySignalService.instance;

  StreamSubscription<AppLifecycleEvent>? _lifecycleSub;
  bool _initialized = false;
  bool _running = false;
  bool _applying = false;
  int _lastRunAtMs = 0;
  String _lastSummary = '';
  String _lastRaw = '';
  String _lastError = '';
  String _lastStatus = 'idle';
  List<NocturneMemoryMaintenanceSuggestion> _suggestions =
      const <NocturneMemoryMaintenanceSuggestion>[];
  int _lastApplyAtMs = 0;
  String _lastApplyStatus = 'idle';
  String _lastApplyResult = '';

  bool get initialized => _initialized;
  bool get running => _running;
  bool get applying => _applying;
  int get lastRunAtMs => _lastRunAtMs;
  String get lastSummary => _lastSummary;
  String get lastRaw => _lastRaw;
  String get lastError => _lastError;
  String get lastStatus => _lastStatus;
  List<NocturneMemoryMaintenanceSuggestion> get suggestions =>
      List<NocturneMemoryMaintenanceSuggestion>.unmodifiable(_suggestions);
  int get lastApplyAtMs => _lastApplyAtMs;
  String get lastApplyStatus => _lastApplyStatus;
  String get lastApplyResult => _lastApplyResult;

  Future<void> ensureInitialized({bool autoResume = false}) async {
    if (_initialized) {
      if (autoResume) unawaited(_maybeAutoRun());
      return;
    }
    _lastRunAtMs = await _settings.getInt(
      UserSettingKeys.nocturneMemoryMaintenanceLastRunMs,
    );
    _lastSummary =
        (await _settings.getString(
          UserSettingKeys.nocturneMemoryMaintenanceLastReport,
        )) ??
        '';
    _lastRaw =
        (await _settings.getString(
          UserSettingKeys.nocturneMemoryMaintenanceLastRaw,
        )) ??
        '';
    _lastError =
        (await _settings.getString(
          UserSettingKeys.nocturneMemoryMaintenanceLastError,
        )) ??
        '';
    _lastStatus =
        (await _settings.getString(
          UserSettingKeys.nocturneMemoryMaintenanceLastStatus,
          defaultValue: 'idle',
        )) ??
        'idle';
    _suggestions = _decodeStoredSuggestions(
      (await _settings.getString(
            UserSettingKeys.nocturneMemoryMaintenanceLastSuggestionsJson,
          )) ??
          '',
    );
    _lastApplyAtMs = await _settings.getInt(
      UserSettingKeys.nocturneMemoryMaintenanceLastApplyAtMs,
    );
    _lastApplyStatus =
        (await _settings.getString(
          UserSettingKeys.nocturneMemoryMaintenanceLastApplyStatus,
          defaultValue: 'idle',
        )) ??
        'idle';
    _lastApplyResult =
        (await _settings.getString(
          UserSettingKeys.nocturneMemoryMaintenanceLastApplyResult,
        )) ??
        '';
    _lifecycleSub ??= AppLifecycleService.instance.events.listen((event) {
      if (event == AppLifecycleEvent.firstUiResumed ||
          event == AppLifecycleEvent.resumed) {
        unawaited(_maybeAutoRun());
      }
    });
    _initialized = true;
    if (autoResume) unawaited(_maybeAutoRun());
  }

  Future<void> runNow({bool force = false}) async {
    await ensureInitialized();
    if (_running || _applying) return;
    if (!force) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (_lastRunAtMs > 0 &&
          now - _lastRunAtMs < _autoRunInterval.inMilliseconds) {
        return;
      }
    }

    _running = true;
    _lastStatus = 'running';
    _lastError = '';
    notifyListeners();
    await _persistState();

    String raw = '';
    try {
      final NocturneMemorySignalDashboard dashboard = await _signals
          .loadDashboard(limitPerStatus: 12);
      if (dashboard.totalCount <= 0) {
        _lastSummary = '当前没有候选、正式或封存信号，暂无可整理内容。';
        _lastRaw = '';
        _suggestions = const <NocturneMemoryMaintenanceSuggestion>[];
        _lastStatus = 'completed';
        _lastRunAtMs = DateTime.now().millisecondsSinceEpoch;
        notifyListeners();
        await _persistState();
        return;
      }

      final List<AIEndpoint> endpoints = await _aiSettings
          .getEndpointCandidates(context: 'memory');
      if (endpoints.isEmpty) {
        throw StateError('未配置可用的 AI Endpoint（memory 上下文）');
      }

      final String prompt = _buildMaintenancePrompt(dashboard);
      final AIGatewayResult result = await _gateway.complete(
        endpoints: endpoints,
        messages: <AIMessage>[
          AIMessage(
            role: 'system',
            content: NocturneMemoryPrompts.maintenanceSystemPrompt(),
          ),
          AIMessage(role: 'user', content: prompt),
        ],
        responseStartMarker: '',
        timeout: const Duration(seconds: 90),
        logContext: 'memory_maintenance_suggestions',
      );
      raw = result.content.trim();
      final NocturneMemoryMaintenancePlan plan = parseModelOutput(raw);
      _lastRaw = raw;
      _lastSummary = plan.summary;
      _suggestions = plan.suggestions;
      _lastStatus = 'completed';
      _lastRunAtMs = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
      await _persistState();
    } catch (e) {
      if (raw.trim().isNotEmpty) {
        _lastRaw = raw;
      }
      _lastStatus = 'failed';
      _lastError = e.toString();
      await FlutterLogger.nativeWarn('MemoryMaintenance', '整理建议生成失败：$e');
      notifyListeners();
      await _persistState();
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> applySuggestions({
    List<NocturneMemoryMaintenanceSuggestion>? suggestions,
  }) async {
    await ensureInitialized();
    if (_running || _applying) return;
    final List<NocturneMemoryMaintenanceSuggestion> plan =
        List<NocturneMemoryMaintenanceSuggestion>.from(
          suggestions ?? _suggestions,
        );
    if (plan.isEmpty) {
      _lastApplyStatus = 'idle';
      _lastApplyResult = '当前没有可应用的整理建议。';
      notifyListeners();
      await _persistState();
      return;
    }

    _applying = true;
    _lastApplyStatus = 'running';
    _lastApplyResult = '';
    notifyListeners();
    await _persistState();

    final List<String> lines = <String>[];
    final List<NocturneMemoryMaintenanceSuggestion> applied =
        <NocturneMemoryMaintenanceSuggestion>[];
    int successCount = 0;
    int failureCount = 0;
    try {
      for (final NocturneMemoryMaintenanceSuggestion suggestion in plan) {
        try {
          await _applySuggestion(suggestion);
          applied.add(suggestion);
          successCount += 1;
          lines.add('[ok] ${suggestion.summaryLine}');
        } catch (e) {
          failureCount += 1;
          lines.add('[failed] ${suggestion.summaryLine} -> $e');
        }
      }

      if (applied.isNotEmpty) {
        _removePendingSuggestions(applied);
      }
      _lastApplyAtMs = DateTime.now().millisecondsSinceEpoch;
      if (failureCount == 0) {
        _lastApplyStatus = 'completed';
        _lastApplyResult =
            '已应用 $successCount 条整理建议。${lines.isEmpty ? "" : "\n${lines.join("\n")}"}';
        if (_suggestions.isEmpty) {
          _lastSummary = '上一批整理建议已应用完成。请重新生成以查看最新状态。';
          _lastRaw = '';
        }
      } else {
        _lastApplyStatus = 'failed';
        _lastApplyResult =
            '整理建议应用完成：成功 $successCount 条，失败 $failureCount 条。\n${lines.join("\n")}';
      }
      notifyListeners();
      await _persistState();
    } finally {
      _applying = false;
      notifyListeners();
    }
  }

  Future<void> applyPendingSuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    await applySuggestions(
      suggestions: <NocturneMemoryMaintenanceSuggestion>[suggestion],
    );
  }

  Future<void> dismissSuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    await ensureInitialized();
    if (_running || _applying) return;
    final int before = _suggestions.length;
    _removePendingSuggestions(<NocturneMemoryMaintenanceSuggestion>[
      suggestion,
    ]);
    if (_suggestions.length == before) return;
    _lastApplyAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastApplyStatus = 'dismissed';
    _lastApplyResult = '已忽略 1 条整理建议。\n[dismissed] ${suggestion.summaryLine}';
    if (_suggestions.isEmpty) {
      _lastSummary = '当前没有待处理的整理建议。请重新生成以查看最新状态。';
    }
    notifyListeners();
    await _persistState();
  }

  Future<void> _applySuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    switch (suggestion.action) {
      case NocturneMemoryMaintenanceAction.rewriteMemory:
        await _applyRewriteMemorySuggestion(suggestion);
        return;
      case NocturneMemoryMaintenanceAction.addAlias:
        await _applyAddAliasSuggestion(suggestion);
        return;
      case NocturneMemoryMaintenanceAction.moveMemory:
        await _applyMoveMemorySuggestion(suggestion);
        return;
      case NocturneMemoryMaintenanceAction.archiveMemory:
        await _applyArchiveMemorySuggestion(suggestion);
        return;
      case NocturneMemoryMaintenanceAction.deleteMemory:
        await _applyDeleteMemorySuggestion(suggestion);
        return;
      case NocturneMemoryMaintenanceAction.dropCandidate:
        final NocturneMemorySignalDiagnosticItem? item =
            await _loadManagedSuggestionItem(suggestion);
        if (item != null) {
          await _signals.dropCandidateByEntityId(item.entityId);
          return;
        }
        await _signals.dropCandidate(suggestion.targetUri);
        return;
    }
  }

  Future<NocturneMemorySignalDiagnosticItem?> _loadManagedSuggestionItem(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    final String entityId = (suggestion.targetEntityId ?? '').trim();
    if (entityId.isNotEmpty) {
      final NocturneMemorySignalDiagnosticItem? item = await _signals
          .loadDiagnosticItemByEntityId(entityId);
      if (item != null) return item;
    }
    return _signals.loadDiagnosticItem(suggestion.targetUri);
  }

  Future<void> _applyRewriteMemorySuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    final String content = _normalizeContent(suggestion.content ?? '');
    if (content.isEmpty) {
      throw StateError('rewrite_memory 缺少 content');
    }

    final NocturneMemorySignalDiagnosticItem item =
        await _loadManagedSuggestionItem(suggestion) ??
        (throw StateError('rewrite_memory 找不到受管实体：${suggestion.targetUri}'));
    await _signals.rewriteProfileContentByEntityId(
      entityId: item.entityId,
      content: content,
    );
  }

  Future<void> _applyAddAliasSuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    final String? newUri = suggestion.newUri;
    if (newUri == null || newUri.trim().isEmpty) {
      throw StateError('add_alias 缺少 new_uri');
    }

    final NocturneMemorySignalDiagnosticItem item =
        await _loadManagedSuggestionItem(suggestion) ??
        (throw StateError('add_alias 找不到受管实体：${suggestion.targetUri}'));
    await _signals.addAliasToProfileByEntityId(
      entityId: item.entityId,
      newUri: newUri,
    );
  }

  Future<void> _applyMoveMemorySuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    final String? newUri = suggestion.newUri;
    if (newUri == null || newUri.trim().isEmpty) {
      throw StateError('move_memory 缺少 new_uri');
    }

    final NocturneMemorySignalDiagnosticItem item =
        await _loadManagedSuggestionItem(suggestion) ??
        (throw StateError('move_memory 找不到受管实体：${suggestion.targetUri}'));
    if (item.isRootNode) {
      throw StateError('不允许移动根节点：${suggestion.targetUri}');
    }
    if (await _signals.hasProfileDescendants(suggestion.targetUri)) {
      throw StateError('当前仅支持移动叶子节点：${suggestion.targetUri}');
    }
    await _signals.moveProfileLeafByEntityId(
      entityId: item.entityId,
      targetUri: newUri,
    );
  }

  Future<void> _applyArchiveMemorySuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    final NocturneMemorySignalDiagnosticItem? item =
        await _loadManagedSuggestionItem(suggestion);
    if (item == null) {
      throw StateError('archive_memory 只能用于受管的记忆信号节点');
    }
    if (item.isRootNode) {
      throw StateError('不允许封存根节点：${suggestion.targetUri}');
    }
    if (await _signals.hasProfileDescendants(suggestion.targetUri)) {
      throw StateError('当前仅支持封存叶子节点：${suggestion.targetUri}');
    }
    final String materializedUri = _signals.materializedUriFor(
      suggestion.targetUri,
      item.status,
    );
    if (item.status != NocturneMemorySignalStatus.candidate &&
        await _memoryExists(materializedUri)) {
      await _assertLeafMemoryPath(materializedUri);
    }
    await _signals.forceArchiveProfileByEntityId(item.entityId);
  }

  Future<void> _applyDeleteMemorySuggestion(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) async {
    final NocturneMemorySignalDiagnosticItem item =
        await _loadManagedSuggestionItem(suggestion) ??
        (throw StateError('delete_memory 找不到受管实体：${suggestion.targetUri}'));
    if (item.isRootNode) {
      throw StateError('不允许删除根节点：${suggestion.targetUri}');
    }
    if (await _signals.hasProfileDescendants(suggestion.targetUri)) {
      throw StateError('当前仅支持删除叶子节点：${suggestion.targetUri}');
    }
    if (item.status == NocturneMemorySignalStatus.candidate) {
      await _signals.dropCandidateByEntityId(item.entityId);
      return;
    }
    await _signals.deleteProfileByEntityId(item.entityId);
  }

  Future<void> _maybeAutoRun() async {
    if (_running || _applying) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (_lastRunAtMs > 0 &&
        now - _lastRunAtMs < _autoRunInterval.inMilliseconds) {
      return;
    }
    await runNow(force: true);
  }

  String _buildMaintenancePrompt(NocturneMemorySignalDashboard dashboard) {
    String statusLine(NocturneMemorySignalDiagnosticItem item) {
      final List<String> notes = <String>[
        'entity_id=${item.entityId}',
        'uri=${item.uri}',
        'status=${item.status.name}',
        'score=${item.decayedScore.toStringAsFixed(2)}/${item.activationScore.toStringAsFixed(2)}',
        'days=${item.distinctDayCount}/${item.minDistinctDays}',
        'segments=${item.distinctSegmentCount}',
      ];
      if (item.strongSignalCount > 0) {
        notes.add('strong=${item.strongSignalCount}');
      }
      if (item.rootMaterializationBlocked) {
        notes.add('root_blocked=true');
      }
      if (item.status == NocturneMemorySignalStatus.candidate &&
          !item.readyToActivate) {
        if (item.missingActivationScore > 0) {
          notes.add(
            'missing_score=${item.missingActivationScore.toStringAsFixed(2)}',
          );
        }
        if (item.missingDistinctDays > 0) {
          notes.add('missing_days=${item.missingDistinctDays}');
        }
      }
      return '${notes.join(' | ')}\nlatest_content:\n${_block(item.latestContent)}';
    }

    final StringBuffer sb = StringBuffer();
    sb.writeln('信号总览');
    sb.writeln(
      'total=${dashboard.totalCount} candidate=${dashboard.candidateCount} active=${dashboard.activeCount} archived=${dashboard.archivedCount}',
    );
    sb.writeln('根路径分布');
    for (final NocturneMemorySignalRootSummary root in dashboard.roots) {
      if (root.candidateCount <= 0 &&
          root.activeCount <= 0 &&
          root.archivedCount <= 0) {
        continue;
      }
      sb.writeln(
        '- ${root.rootUri}: candidate=${root.candidateCount}, active=${root.activeCount}, archived=${root.archivedCount}',
      );
    }

    void writeSection(
      String title,
      List<NocturneMemorySignalDiagnosticItem> items,
    ) {
      sb.writeln();
      sb.writeln(title);
      if (items.isEmpty) {
        sb.writeln('- 无');
        return;
      }
      for (final NocturneMemorySignalDiagnosticItem item in items) {
        sb.writeln('- - -');
        sb.writeln(statusLine(item));
      }
    }

    writeSection('候选节点', dashboard.topCandidates);
    writeSection('活跃节点', dashboard.topActive);
    writeSection('封存节点', dashboard.topArchived);
    return sb.toString().trimRight();
  }

  Future<void> _persistState() async {
    await _settings.setInt(
      UserSettingKeys.nocturneMemoryMaintenanceLastRunMs,
      _lastRunAtMs,
    );
    await _settings.setString(
      UserSettingKeys.nocturneMemoryMaintenanceLastReport,
      _lastSummary,
    );
    await _settings.setString(
      UserSettingKeys.nocturneMemoryMaintenanceLastRaw,
      _lastRaw,
    );
    await _settings.setString(
      UserSettingKeys.nocturneMemoryMaintenanceLastError,
      _lastError,
    );
    await _settings.setString(
      UserSettingKeys.nocturneMemoryMaintenanceLastStatus,
      _lastStatus,
    );
    await _settings.setString(
      UserSettingKeys.nocturneMemoryMaintenanceLastSuggestionsJson,
      jsonEncode(
        _suggestions.map((item) => item.toJson()).toList(growable: false),
      ),
    );
    await _settings.setInt(
      UserSettingKeys.nocturneMemoryMaintenanceLastApplyAtMs,
      _lastApplyAtMs,
    );
    await _settings.setString(
      UserSettingKeys.nocturneMemoryMaintenanceLastApplyStatus,
      _lastApplyStatus,
    );
    await _settings.setString(
      UserSettingKeys.nocturneMemoryMaintenanceLastApplyResult,
      _lastApplyResult,
    );
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    _initialized = false;
    _running = false;
    _applying = false;
    _lastRunAtMs = 0;
    _lastSummary = '';
    _lastRaw = '';
    _lastError = '';
    _lastStatus = 'idle';
    _suggestions = const <NocturneMemoryMaintenanceSuggestion>[];
    _lastApplyAtMs = 0;
    _lastApplyStatus = 'idle';
    _lastApplyResult = '';
  }

  @visibleForTesting
  void setSuggestionsForTest(
    List<NocturneMemoryMaintenanceSuggestion> suggestions, {
    String summary = '测试建议',
  }) {
    _suggestions = List<NocturneMemoryMaintenanceSuggestion>.from(suggestions);
    _lastSummary = summary;
  }

  static NocturneMemoryMaintenancePlan parseModelOutput(String raw) {
    final String payload = _extractJsonPayload(raw);
    if (payload.trim().isEmpty) {
      throw const FormatException('AI 未返回可解析内容');
    }
    final dynamic decoded = jsonDecode(payload);

    String summary = '';
    List<dynamic> suggestionItems = const <dynamic>[];
    if (decoded is Map) {
      summary = _cleanText(decoded['summary']);
      final dynamic rawSuggestions = decoded['suggestions'];
      if (rawSuggestions == null) {
        suggestionItems = const <dynamic>[];
      } else if (rawSuggestions is List) {
        suggestionItems = rawSuggestions;
      } else {
        throw const FormatException('suggestions 必须是数组');
      }
    } else if (decoded is List) {
      suggestionItems = decoded;
    } else {
      throw const FormatException('整理建议必须是 JSON 对象或数组');
    }

    final Set<String> fingerprints = <String>{};
    final List<NocturneMemoryMaintenanceSuggestion> suggestions =
        <NocturneMemoryMaintenanceSuggestion>[];
    for (final dynamic item in suggestionItems) {
      if (item is! Map) continue;
      final NocturneMemoryMaintenanceSuggestion? suggestion = _parseSuggestion(
        Map<String, dynamic>.from(item),
      );
      if (suggestion == null) continue;
      final String fingerprint = jsonEncode(suggestion.toJson());
      if (!fingerprints.add(fingerprint)) continue;
      suggestions.add(suggestion);
    }

    if (summary.isEmpty) {
      summary = suggestions.isEmpty
          ? 'AI 判断当前暂无需要人工应用的整理动作。'
          : 'AI 生成了 ${suggestions.length} 条可人工应用的整理建议。';
    }
    return NocturneMemoryMaintenancePlan(
      summary: summary,
      suggestions: suggestions,
    );
  }

  static List<NocturneMemoryMaintenanceSuggestion> _decodeStoredSuggestions(
    String raw,
  ) {
    if (raw.trim().isEmpty) {
      return const <NocturneMemoryMaintenanceSuggestion>[];
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <NocturneMemoryMaintenanceSuggestion>[];
      }
      final List<NocturneMemoryMaintenanceSuggestion> out =
          <NocturneMemoryMaintenanceSuggestion>[];
      for (final dynamic item in decoded) {
        if (item is! Map) continue;
        final NocturneMemoryMaintenanceSuggestion? suggestion =
            _parseSuggestion(Map<String, dynamic>.from(item));
        if (suggestion != null) out.add(suggestion);
      }
      return out;
    } catch (_) {
      return const <NocturneMemoryMaintenanceSuggestion>[];
    }
  }

  static NocturneMemoryMaintenanceSuggestion? _parseSuggestion(
    Map<String, dynamic> raw,
  ) {
    final NocturneMemoryMaintenanceAction? action =
        NocturneMemoryMaintenanceAction.fromWire(
          _cleanText(raw['action'].toString()),
        );
    if (action == null) return null;

    final String targetUri = _canonicalizeManagedUri(
      raw['target_uri'] ?? raw['uri'],
    );
    final String targetEntityId = _cleanText(raw['target_entity_id']);
    final String reason = _cleanText(raw['reason']);
    final String evidence = _cleanText(raw['evidence']);
    if (targetUri.isEmpty || reason.isEmpty || evidence.isEmpty) {
      return null;
    }

    switch (action) {
      case NocturneMemoryMaintenanceAction.rewriteMemory:
        final String content = _normalizeContent(
          (raw['content'] ?? '').toString(),
        );
        if (content.isEmpty || _looksLikeSystemMeta(content)) {
          return null;
        }
        return NocturneMemoryMaintenanceSuggestion(
          action: action,
          targetUri: targetUri,
          targetEntityId: targetEntityId.isEmpty ? null : targetEntityId,
          content: content,
          reason: reason,
          evidence: evidence,
        );
      case NocturneMemoryMaintenanceAction.addAlias:
      case NocturneMemoryMaintenanceAction.moveMemory:
        final String newUri = _canonicalizeManagedUri(raw['new_uri']);
        if (newUri.isEmpty || newUri == targetUri) {
          return null;
        }
        return NocturneMemoryMaintenanceSuggestion(
          action: action,
          targetUri: targetUri,
          targetEntityId: targetEntityId.isEmpty ? null : targetEntityId,
          newUri: newUri,
          reason: reason,
          evidence: evidence,
        );
      case NocturneMemoryMaintenanceAction.archiveMemory:
      case NocturneMemoryMaintenanceAction.deleteMemory:
      case NocturneMemoryMaintenanceAction.dropCandidate:
        return NocturneMemoryMaintenanceSuggestion(
          action: action,
          targetUri: targetUri,
          targetEntityId: targetEntityId.isEmpty ? null : targetEntityId,
          reason: reason,
          evidence: evidence,
        );
    }
  }

  static String _extractJsonPayload(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final RegExp fenceRe = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    );
    final RegExpMatch? fenced = fenceRe.firstMatch(trimmed);
    final String unfenced = fenced == null
        ? trimmed
        : (fenced.group(1) ?? '').trim();
    if (unfenced.startsWith('{') || unfenced.startsWith('[')) {
      return unfenced;
    }

    final int objectStart = unfenced.indexOf('{');
    final int objectEnd = unfenced.lastIndexOf('}');
    if (objectStart >= 0 && objectEnd > objectStart) {
      return unfenced.substring(objectStart, objectEnd + 1);
    }
    final int arrayStart = unfenced.indexOf('[');
    final int arrayEnd = unfenced.lastIndexOf(']');
    if (arrayStart >= 0 && arrayEnd > arrayStart) {
      return unfenced.substring(arrayStart, arrayEnd + 1);
    }
    return unfenced;
  }

  static String _canonicalizeManagedUri(Object? raw) {
    final String value = _cleanText(raw);
    if (value.isEmpty) return '';
    try {
      final NocturneMemoryService mem = NocturneMemoryService.instance;
      final NocturneUri parsed = mem.parseUri(value);
      final String normalized = mem.makeUri(parsed.domain, parsed.path);
      if (!NocturneMemorySignalService.instance.isManagedUri(normalized)) {
        return '';
      }
      return normalized;
    } catch (_) {
      return '';
    }
  }

  static bool _looksLikeSystemMeta(String content) {
    const List<String> banned = <String>[
      '记忆信号状态：',
      '证据段数：',
      '跨天出现：',
      '首次出现：',
      '最近出现：',
      '当前信号分：',
      '累计信号分：',
      '生命周期状态：已封存',
    ];
    return banned.any(content.contains);
  }

  void _removePendingSuggestions(
    Iterable<NocturneMemoryMaintenanceSuggestion> suggestions,
  ) {
    final Set<String> fingerprints = suggestions
        .map((item) => item.fingerprint)
        .toSet();
    if (fingerprints.isEmpty) return;
    _suggestions = _suggestions
        .where((item) => !fingerprints.contains(item.fingerprint))
        .toList(growable: false);
  }

  Future<void> _assertLeafMemoryPath(String uri) async {
    final Map<String, dynamic> row = await _mem.readMemory(uri);
    final List<dynamic> children =
        (row['children'] as List?) ?? const <dynamic>[];
    if (children.isNotEmpty) {
      throw StateError('当前仅支持叶子节点操作：$uri');
    }
  }

  Future<bool> _memoryExists(String uri) async {
    try {
      await _mem.readMemory(uri);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _block(String value) {
    final String normalized = _normalizeContent(value);
    if (normalized.isEmpty) return '（空）';
    if (normalized.length <= 320) return normalized;
    return '${normalized.substring(0, 320)}…';
  }

  static String _cleanText(Object? value) {
    return value?.toString().trim() ?? '';
  }

  static String _normalizeContent(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }
}
