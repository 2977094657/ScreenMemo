import 'dart:async';

import 'package:flutter/services.dart';

import '../models/memory_models.dart';
import 'ai_providers_service.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'screenshot_database.dart';

class MemoryBridgeService {
  MemoryBridgeService._();

  static final MemoryBridgeService instance = MemoryBridgeService._();

  static const MethodChannel _methodChannel = MethodChannel('com.fqyw.screen_memo/memory');
  static const EventChannel _snapshotChannel =
      EventChannel('com.fqyw.screen_memo/memory/snapshot');
  static const EventChannel _progressChannel =
      EventChannel('com.fqyw.screen_memo/memory/progress');
  static const EventChannel _tagUpdateChannel =
      EventChannel('com.fqyw.screen_memo/memory/tag_updates');

  final StreamController<MemorySnapshot> _snapshotController =
      StreamController<MemorySnapshot>.broadcast();
  final StreamController<MemoryProgressState> _progressController =
      StreamController<MemoryProgressState>.broadcast();
  final StreamController<MemoryTagUpdate> _tagUpdateController =
      StreamController<MemoryTagUpdate>.broadcast();

  MemorySnapshot? _latestSnapshot;
  String _cachedPersonaSummary = '';
  MemoryProgressState _latestProgress = const MemoryProgressIdle();
  bool _waitingForInitialProgress = false;
  String? _pendingStageLabel;

  StreamSubscription<dynamic>? _snapshotSubscription;
  StreamSubscription<dynamic>? _progressSubscription;
  StreamSubscription<dynamic>? _tagUpdateSubscription;

  bool _initialized = false;

  MemorySnapshot? get latestSnapshot => _latestSnapshot;
  MemoryProgressState get latestProgress => _latestProgress;
  bool get waitingForInitialProgress => _waitingForInitialProgress;
  String? get pendingStageLabel => _pendingStageLabel;
  String get latestPersonaSummary {
    final String snapshotSummary = _latestSnapshot?.personaSummary.trim() ?? '';
    if (snapshotSummary.isNotEmpty) {
      return snapshotSummary;
    }
    final PersonaProfile? profile = _latestSnapshot?.personaProfile;
    final String derived = profile?.toMarkdown().trim() ?? '';
    if (derived.isNotEmpty) {
      return derived;
    }
    return _cachedPersonaSummary;
  }

  PersonaProfile get latestPersonaProfile =>
      _latestSnapshot?.personaProfile ?? PersonaProfile.empty();

  void primeProgressState(
    MemoryProgressState progress, {
    bool waitingForInitialProgress = false,
    String? stageLabel,
  }) {
    _latestProgress = progress;
    _waitingForInitialProgress = waitingForInitialProgress;
    _pendingStageLabel = stageLabel;
  }

  void updatePreparationStage(String? stageLabel) {
    _pendingStageLabel = stageLabel;
  }

  void clearPreparationState() {
    _waitingForInitialProgress = false;
    _pendingStageLabel = null;
  }
  
  Future<bool> deleteTag(int tagId) async {
    await ensureInitialized();
    _logInfo('删除标签调用 tagId=$tagId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#deleteTag', <String, dynamic>{'tagId': tagId});
    return result == true;
  }

  Stream<MemorySnapshot> get snapshotStream => _snapshotController.stream;
  Stream<MemoryProgressState> get progressStream => _progressController.stream;
  Stream<MemoryTagUpdate> get tagUpdateStream => _tagUpdateController.stream;

  Future<void> ensureInitialized() async {
    _logInfo('ensureInitialized 调用；initialized=$_initialized');
    if (_initialized) return;
    _initialized = true;
    await _startBackendService();
    _snapshotSubscription ??=
        _snapshotChannel.receiveBroadcastStream().listen(_onSnapshotEvent, onError: _logError);
    _progressSubscription ??=
        _progressChannel.receiveBroadcastStream().listen(_onProgressEvent, onError: _logError);
    _tagUpdateSubscription ??=
        _tagUpdateChannel.receiveBroadcastStream().listen(_onTagUpdateEvent, onError: _logError);
    _logInfo('ensureInitialized 完成；订阅已激活=${_snapshotSubscription != null}');
  }

  Future<void> setExtractionContext({
    AIProvider? provider,
    String? model,
  }) async {
    await ensureInitialized();
    if (provider == null || provider.id == null || model == null || model.trim().isEmpty) {
      _logInfo('setExtractionContext 清空上下文（provider/model 缺失）');
    }
    if (provider == null || provider.id == null || model == null || model.trim().isEmpty) {
      await _methodChannel.invokeMethod('memory#setExtractionContext', <String, dynamic>{
        'context': null,
      });
      return;
    }

    final apiKey = await AIProvidersService.instance.getApiKey(provider.id!);
    if (apiKey == null || apiKey.trim().isEmpty) {
      await _methodChannel.invokeMethod('memory#setExtractionContext', <String, dynamic>{
        'context': null,
      });
      return;
    }

    String? base;
    if (provider.baseUrl != null && provider.baseUrl!.trim().isNotEmpty) {
      base = provider.baseUrl!.trim();
    } else {
      switch (provider.type) {
        case AIProviderTypes.openai:
          base = 'https://api.openai.com';
          break;
        case AIProviderTypes.gemini:
          base = 'https://generativelanguage.googleapis.com';
          break;
        default:
          base = null;
      }
    }

    final context = <String, dynamic>{
      'providerId': provider.id,
      'providerName': provider.name,
      'providerType': provider.type,
      'baseUrl': base,
      'chatPath': provider.chatPath,
      'useResponseApi': provider.useResponseApi,
      'model': model.trim(),
      'apiKey': apiKey.trim(),
      'extra': provider.extra,
    };

    await _methodChannel.invokeMethod('memory#setExtractionContext', <String, dynamic>{
      'context': context,
    });
    _logInfo(
      'setExtractionContext applied providerId=${provider.id} type=${provider.type} model=${model.trim()} baseUrl=${base ?? 'default'}',
    );
  }

  Future<void> ingestEvent({
    required String type,
    required String source,
    required String content,
    String? externalId,
    DateTime? occurredAt,
    Map<String, String>? metadata,
    bool ensureInit = true,
  }) async {
    if (content.trim().isEmpty) {
      _logInfo('导入事件跳过：内容为空 type=$type source=$source externalId=$externalId');
      return;
    }
    if (ensureInit) {
      await ensureInitialized();
    }
    final Map<String, dynamic> event = <String, dynamic>{
      'occurredAt': (occurredAt ?? DateTime.now()).millisecondsSinceEpoch,
      'type': type,
      'source': source,
      'content': content,
      'metadata': (metadata ?? const <String, String>{}),
    };
    if (externalId != null && externalId.trim().isNotEmpty) {
      event['externalId'] = externalId.trim();
    }
    try {
      await _methodChannel.invokeMethod('memory#ingestEvent', <String, dynamic>{'event': event});
    } catch (err) {
      _logWarn('导入事件失败 type=$type source=$source externalId=$externalId error=$err');
    }
  }

  Future<int> syncAllConversationsToMemory() async {
    await ensureInitialized();
    final ScreenshotDatabase db = ScreenshotDatabase.instance;
    final List<Map<String, dynamic>> convRows = await db.listAiConversations();
    final Set<String> cids = <String>{
      ...convRows.map((e) => (e['cid'] as String?)?.trim() ?? '').where((cid) => cid.isNotEmpty),
    };
    if (cids.isEmpty) {
      final String fallback = await AISettingsService.instance.getActiveConversationCid();
      if (fallback.trim().isNotEmpty) {
        cids.add(fallback.trim());
      }
    }
    if (cids.isEmpty) {
      _logInfo('同步所有会话到记忆：跳过（无会话）');
      return 0;
    }
    int totalIngested = 0;
    for (final String cid in cids) {
      final List<Map<String, dynamic>> rows = await db.getAiMessages(cid);
      final int ingested = await _ingestChatRows(cid, rows);
      totalIngested += ingested;
      _logInfo('同步会话到记忆 cid=$cid 消息数=${rows.length} 已导入=$ingested');
    }
    _logInfo('同步所有会话到记忆完成 总导入=$totalIngested 会话数=${cids.length}');
    return totalIngested;
  }

  Future<void> ingestChatMessage({
    required String conversationId,
    required String role,
    required String content,
    required DateTime createdAt,
    int? messageId,
    String? reasoning,
    int? reasoningDurationMs,
  }) async {
    final Map<String, String> metadata = <String, String>{
      'conversation_cid': conversationId,
      'role': role,
      if (messageId != null) 'message_id': messageId.toString(),
      'source': 'ai_chat',
    };
    if (reasoning != null && reasoning.trim().isNotEmpty) {
      metadata['reasoning'] = _truncate(reasoning.trim(), 800);
    }
    if (reasoningDurationMs != null) {
      metadata['reasoning_duration_ms'] = reasoningDurationMs.toString();
    }
    final String externalId = _buildChatExternalId(
      conversationId: conversationId,
      messageId: messageId,
      createdAt: createdAt.millisecondsSinceEpoch,
      role: role,
      content: content,
    );
    await ingestEvent(
      type: 'chat_message',
      source: role,
      content: content,
      externalId: externalId,
      occurredAt: createdAt,
      metadata: metadata,
    );
  }

  Future<Map<String, dynamic>> searchMemoryGraph({
    required String query,
    int depth = 2,
    int limit = 80,
    bool includeHistory = true,
  }) async {
    await ensureInitialized();
    final dynamic result = await _methodChannel.invokeMethod(
      'memory#graphSearch',
      <String, dynamic>{
        'query': query,
        'depth': depth,
        'limit': limit,
        'includeHistory': includeHistory,
      },
    );
    if (result is Map) {
      return _toStringMap(result);
    }
    return <String, dynamic>{
      'error': 'invalid_payload',
      'query': query,
      'raw_type': result.runtimeType.toString(),
    };
  }

  Future<MemorySnapshot?> fetchSnapshot() async {
    await ensureInitialized();
    _logInfo('fetchSnapshot 调用 memory#getSnapshot');
    final dynamic result = await _methodChannel.invokeMethod('memory#getSnapshot');
    final MemorySnapshot? snapshot = _parseSnapshot(result);
    if (snapshot != null) {
      _emitSnapshot(snapshot);
      _logInfo(
        'fetchSnapshot received pending=${snapshot.pendingTags.length} confirmed=${snapshot.confirmedTags.length} events=${snapshot.recentEvents.length}',
      );
    } else {
      _logInfo('fetchSnapshot 返回 null snapshot');
    }
    return snapshot;
  }

  Future<int> syncSegmentsToMemory() async {
    await ensureInitialized();
    final int? count = await _methodChannel.invokeMethod<int>('memory#syncSegments');
    return count ?? 0;
  }

  Future<int> processSampleEvents({int limit = 30}) async {
    await ensureInitialized();
    try {
      final int? processed = await _methodChannel.invokeMethod<int>(
        'memory#processSampleEvents',
        <String, dynamic>{'limit': limit},
      );
      return processed ?? 0;
    } catch (err) {
      _logWarn('处理样本事件失败 错误=$err');
      rethrow;
    }
  }

  Future<void> cancelInitialization() async {
    await ensureInitialized();
    try {
      await _methodChannel.invokeMethod('memory#cancelInitialization');
    } catch (err) {
      _logWarn('取消初始化失败 错误=$err');
      rethrow;
    }
  }

  Future<void> clearMemoryData() async {
    await ensureInitialized();
    try {
      await _methodChannel.invokeMethod('memory#clearMemoryData');
      _cachedPersonaSummary = '';
    } catch (err) {
      _logWarn('清理记忆数据失败 错误=$err');
      rethrow;
    }
  }

  Future<MemoryTag?> fetchTagById(int tagId) async {
    await ensureInitialized();
    _logInfo('fetchTagById 调用 tagId=$tagId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#getTag', <String, dynamic>{'tagId': tagId});
    final MemoryTag? tag = _parseTag(result);
    if (tag == null) {
      _logWarn('fetchTagById 返回 null tagId=$tagId');
    }
    return tag;
  }

  Future<MemoryEventSummary?> fetchEventById(int eventId) async {
    await ensureInitialized();
    _logInfo('fetchEventById 调用 eventId=$eventId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#getEvent', <String, dynamic>{'eventId': eventId});
    final MemoryEventSummary? summary = _parseEvent(result);
    if (summary == null) {
      _logWarn('fetchEventById 返回 null eventId=$eventId');
    }
    return summary;
  }

  Future<List<MemoryTag>> loadTags({
    required String status,
    required int offset,
    required int limit,
  }) async {
    await ensureInitialized();
    final dynamic result =
        await _methodChannel.invokeMethod('memory#loadTags', <String, dynamic>{
      'status': status,
      'offset': offset,
      'limit': limit,
    });
    final List<dynamic> raw = (result as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => MemoryTag.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<List<MemoryEventSummary>> loadRecentEvents({
    required int offset,
    required int limit,
  }) async {
    await ensureInitialized();
    final dynamic result = await _methodChannel.invokeMethod(
      'memory#loadRecentEvents',
      <String, dynamic>{
        'offset': offset,
        'limit': limit,
      },
    );
    final List<dynamic> raw = (result as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => MemoryEventSummary.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<MemoryTag?> confirmTag(int tagId) async {
    await ensureInitialized();
    _logInfo('confirmTag 调用 tagId=$tagId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#confirmTag', <String, dynamic>{'tagId': tagId});
    if (result == null) {
      _logInfo('confirmTag 返回 null tagId=$tagId');
      return null;
    }
    final MemoryTag? tag = _parseTag(result);
    if (tag != null) {
      _logInfo('confirmTag 响应 status=${tag.status} occurrences=${tag.occurrences}');
      _handleTagUpdate(MemoryTagUpdate(tag: tag, isNewTag: false, statusChanged: true));
    }
    return tag;
  }

  Future<void> startHistoricalProcessing({bool forceReprocess = false}) async {
    await ensureInitialized();
    _logInfo('startHistoricalProcessing 调用 force=$forceReprocess');
    await _methodChannel.invokeMethod('memory#initialize', <String, dynamic>{
      'forceReprocess': forceReprocess,
    });
    _logInfo('startHistoricalProcessing 调用完成 force=$forceReprocess');
  }

  void dispose() {
    _snapshotSubscription?.cancel();
    _progressSubscription?.cancel();
    _tagUpdateSubscription?.cancel();
    _snapshotController.close();
    _progressController.close();
    _tagUpdateController.close();
    _initialized = false;
  }

  Future<void> _startBackendService() async {
    _logInfo('startBackendService 调用');
    try {
      await _methodChannel.invokeMethod('memory#startService');
      _logInfo('startBackendService 请求已发送');
    } catch (err) {
      _logWarn('启动服务失败：$err');
    }
  }

  void _onSnapshotEvent(dynamic event) {
    final MemorySnapshot? snapshot = _parseSnapshot(event);
    if (snapshot != null) {
      _emitSnapshot(snapshot);
    }
  }

  void _onProgressEvent(dynamic event) {
    _logInfo('收到进度事件 type=${event.runtimeType}');
    final MemoryProgressState progress = _parseProgress(event);
    _latestProgress = progress;
    clearPreparationState();
    _progressController.add(progress);
    _logInfo('进度更新 runtime=${progress.runtimeType}');
  }

  void _onTagUpdateEvent(dynamic event) {
    _logInfo('收到标签更新事件 type=${event.runtimeType}');
    final MemoryTagUpdate? update = _parseTagUpdate(event);
    if (update != null) {
      _logInfo(
        'tag update parsed tagId=${update.tag.id} isNew=${update.isNewTag} statusChanged=${update.statusChanged}',
      );
      _handleTagUpdate(update);
    }
  }

  void _emitSnapshot(MemorySnapshot snapshot) {
    final String incomingPersona = snapshot.personaSummary.trim();
    final String derivedPersona = incomingPersona.isNotEmpty
        ? incomingPersona
        : snapshot.personaProfile.toMarkdown().trim();
    final bool hasDerivedPersona = derivedPersona.isNotEmpty;

    if (hasDerivedPersona) {
      _cachedPersonaSummary = derivedPersona;
    }

    final bool shouldPreservePersona =
        !hasDerivedPersona && _cachedPersonaSummary.isNotEmpty;

    final MemorySnapshot effectiveSnapshot = shouldPreservePersona
        ? snapshot.copyWith(personaSummary: _cachedPersonaSummary)
        : snapshot.copyWith(personaSummary: hasDerivedPersona ? derivedPersona : snapshot.personaSummary);

    _latestSnapshot = effectiveSnapshot;
    _snapshotController.add(effectiveSnapshot);
  }

  void _handleTagUpdate(MemoryTagUpdate update) {
    _logInfo('处理标签更新 tagId=${update.tag.id} status=${update.tag.status}');
    final MemorySnapshot? snapshot = _latestSnapshot;
    if (snapshot == null) {
      unawaited(fetchSnapshot());
    } else {
      _emitSnapshot(snapshot.mergeTag(update.tag));
    }
    _tagUpdateController.add(update);
  }

  MemorySnapshot? _parseSnapshot(dynamic data) {
    if (data is! Map) return null;
    return MemorySnapshot.fromMap(_toStringMap(data));
  }

  MemoryTag? _parseTag(dynamic data) {
    if (data is! Map) return null;
    return MemoryTag.fromMap(_toStringMap(data));
  }

  MemoryEventSummary? _parseEvent(dynamic data) {
    if (data is! Map) return null;
    return MemoryEventSummary.fromMap(_toStringMap(data));
  }

  MemoryProgressState _parseProgress(dynamic data) {
    if (data is! Map) {
      _logInfo('parseProgress 收到非 Map 的 payload');
      return const MemoryProgressIdle();
    }
    final Map<String, dynamic> map = _toStringMap(data);
    final String state = (map['state'] as String?) ?? 'idle';
    _logInfo(
      'parseProgress 状态=$state 已处理=${map['processedCount']} 总数=${map['totalCount']} 进度=${map['progress']} 耗时=${map['durationMillis']} 错误=${map['errorMessage']}',
    );
    switch (state) {
      case 'running':
        final List<String> tags = ((map['newlyDiscoveredTags'] as List?) ?? const [])
            .whereType<String>()
            .toList(growable: false);
        return MemoryProgressRunning(
          processedCount: _toInt(map['processedCount']) ?? 0,
          totalCount: _toInt(map['totalCount']) ?? 0,
          progress: _toDouble(map['progress']) ?? 0,
          currentEventId: _toInt(map['currentEventId']),
          currentEventExternalId: map['currentEventExternalId'] as String?,
          currentEventType: map['currentEventType'] as String?,
          newlyDiscoveredTags: List<String>.unmodifiable(tags),
        );
      case 'completed':
        final Duration duration =
            Duration(milliseconds: _toInt(map['durationMillis']) ?? 0);
        _logInfo(
          'parseProgress 已完成 总数=${map['totalCount']} 耗时Ms=${duration.inMilliseconds}',
        );
        return MemoryProgressCompleted(
          totalCount: _toInt(map['totalCount']) ?? 0,
          duration: duration,
        );
      case 'failed':
        _logWarn(
          'parseProgress 失败 已处理=${map['processedCount']} 总数=${map['totalCount']} 错误=${map['errorMessage']}',
        );
        return MemoryProgressFailed(
          processedCount: _toInt(map['processedCount']) ?? 0,
          totalCount: _toInt(map['totalCount']) ?? 0,
          errorMessage: (map['errorMessage'] as String?) ?? 'unknown',
          rawResponse: map['rawResponse'] as String?,
          failureCode: map['failureCode'] as String?,
          failedEventExternalId: map['failedEventExternalId'] as String?,
        );
      case 'idle':
      default:
        return const MemoryProgressIdle();
    }
  }

  MemoryTagUpdate? _parseTagUpdate(dynamic data) {
    if (data is! Map) return null;
    final Map<String, dynamic> map = _toStringMap(data);
    final dynamic tagRaw = map['tag'];
    if (tagRaw is! Map) return null;
    final MemoryTag tag = MemoryTag.fromMap(_toStringMap(tagRaw));
    final bool isNewTag = map['isNewTag'] == true;
    final bool statusChanged = map['statusChanged'] == true;
    return MemoryTagUpdate(tag: tag, isNewTag: isNewTag, statusChanged: statusChanged);
  }

  Map<String, dynamic> _toStringMap(Map<dynamic, dynamic> input) {
    final Map<String, dynamic> result = <String, dynamic>{};
    input.forEach((key, value) {
      if (key != null) {
        result[key.toString()] = value;
      }
    });
    return result;
  }

  void _logInfo(String message) {
    try {
      FlutterLogger.nativeInfo('MemoryBridgeService', message);
    } catch (_) {}
  }

  void _logWarn(String message) {
    try {
      FlutterLogger.nativeWarn('MemoryBridgeService', message);
    } catch (_) {}
  }

  void _logError(Object error) {
    try {
      FlutterLogger.nativeError('MemoryBridgeService', error.toString());
    } catch (_) {}
  }

  Future<int> _ingestChatRows(String cid, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;
    int ingested = 0;
    int index = 0;
    for (final Map<String, dynamic> row in rows) {
      final String role = ((row['role'] as String?) ?? 'user').trim();
      if (role != 'user' && role != 'assistant') {
        index++;
        continue;
      }
      final String content = (row['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) {
        index++;
        continue;
      }
      final int createdAt = (row['created_at'] as int?) ??
          DateTime.now().millisecondsSinceEpoch;
      final int? messageId = row['id'] is int ? row['id'] as int : null;
      final String? reasoning = row['reasoning_content'] as String?;
      final int? reasoningDurationMs = row['reasoning_duration_ms'] as int?;

      final Map<String, String> metadata = <String, String>{
        'conversation_cid': cid,
        'role': role,
        'source': 'ai_chat',
        'created_at_ms': createdAt.toString(),
      };
      if (messageId != null) {
        metadata['message_id'] = messageId.toString();
      } else {
        metadata['message_index'] = index.toString();
      }
      if (reasoning != null && reasoning.trim().isNotEmpty) {
        metadata['reasoning'] = _truncate(reasoning.trim(), 800);
      }
      if (reasoningDurationMs != null) {
        metadata['reasoning_duration_ms'] = reasoningDurationMs.toString();
      }

      final String externalId = _buildChatExternalId(
        conversationId: cid,
        messageId: messageId ?? index,
        createdAt: createdAt,
        role: role,
        content: content,
      );
      await ingestEvent(
        type: 'chat_message',
        source: role,
        content: content,
        externalId: externalId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
        metadata: metadata,
        ensureInit: false,
      );
      ingested++;
      index++;
    }
    return ingested;
  }

  String _buildChatExternalId({
    required String conversationId,
    int? messageId,
    required int createdAt,
    required String role,
    required String content,
  }) {
    final String normalizedRole = role.trim().toLowerCase();
    final int resolvedMessageId =
        messageId ?? _stableHash('$conversationId|$createdAt|$normalizedRole');
    final int hash =
        _stableHash('$conversationId|$resolvedMessageId|$createdAt|$normalizedRole|$content');
    return 'chat:$conversationId:$resolvedMessageId:$createdAt:$normalizedRole:$hash';
  }

  int _stableHash(String input) {
    const int seed = 1125899907;
    int result = seed;
    for (int i = 0; i < input.length; i++) {
      final int codeUnit = input.codeUnitAt(i);
      result = (result * 16777619) ^ codeUnit;
    }
    return result & 0x7fffffff;
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    final int cutoff = maxLength > 3 ? maxLength - 3 : 0;
    return '${text.substring(0, cutoff)}...';
  }
}

double? _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
