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

  StreamSubscription<dynamic>? _snapshotSubscription;
  StreamSubscription<dynamic>? _progressSubscription;
  StreamSubscription<dynamic>? _tagUpdateSubscription;

  bool _initialized = false;

  MemorySnapshot? get latestSnapshot => _latestSnapshot;
  MemoryProgressState get latestProgress => _latestProgress;
  String get latestPersonaSummary {
    final String snapshotSummary = _latestSnapshot?.personaSummary.trim() ?? '';
    if (snapshotSummary.isNotEmpty) {
      return snapshotSummary;
    }
    return _cachedPersonaSummary;
  }
  
  Future<bool> deleteTag(int tagId) async {
    await ensureInitialized();
    _logInfo('deleteTag invoke tagId=$tagId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#deleteTag', <String, dynamic>{'tagId': tagId});
    return result == true;
  }

  Stream<MemorySnapshot> get snapshotStream => _snapshotController.stream;
  Stream<MemoryProgressState> get progressStream => _progressController.stream;
  Stream<MemoryTagUpdate> get tagUpdateStream => _tagUpdateController.stream;

  Future<void> ensureInitialized() async {
    _logInfo('ensureInitialized invoked; initialized=$_initialized');
    if (_initialized) return;
    _initialized = true;
    await _startBackendService();
    _snapshotSubscription ??=
        _snapshotChannel.receiveBroadcastStream().listen(_onSnapshotEvent, onError: _logError);
    _progressSubscription ??=
        _progressChannel.receiveBroadcastStream().listen(_onProgressEvent, onError: _logError);
    _tagUpdateSubscription ??=
        _tagUpdateChannel.receiveBroadcastStream().listen(_onTagUpdateEvent, onError: _logError);
    _logInfo('ensureInitialized completed; subscriptions active=${_snapshotSubscription != null}');
  }

  Future<void> setExtractionContext({
    AIProvider? provider,
    String? model,
  }) async {
    await ensureInitialized();
    if (provider == null || provider.id == null || model == null || model.trim().isEmpty) {
      _logInfo('setExtractionContext clearing context (provider/model missing)');
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
      _logInfo('ingestEvent skipped empty content type=$type source=$source externalId=$externalId');
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
      _logWarn('ingestEvent failed type=$type source=$source externalId=$externalId error=$err');
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
      _logInfo('syncAllConversationsToMemory skipped (no conversations)');
      return 0;
    }
    int totalIngested = 0;
    for (final String cid in cids) {
      final List<Map<String, dynamic>> rows = await db.getAiMessages(cid);
      final int ingested = await _ingestChatRows(cid, rows);
      totalIngested += ingested;
      _logInfo('syncAllConversationsToMemory conversation=$cid messages=${rows.length} ingested=$ingested');
    }
    _logInfo('syncAllConversationsToMemory completed totalIngested=$totalIngested conversations=${cids.length}');
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

  Future<MemorySnapshot?> fetchSnapshot() async {
    await ensureInitialized();
    _logInfo('fetchSnapshot invokeMethod memory#getSnapshot');
    final dynamic result = await _methodChannel.invokeMethod('memory#getSnapshot');
    final MemorySnapshot? snapshot = _parseSnapshot(result);
    if (snapshot != null) {
      _emitSnapshot(snapshot);
      _logInfo(
        'fetchSnapshot received pending=${snapshot.pendingTags.length} confirmed=${snapshot.confirmedTags.length} events=${snapshot.recentEvents.length}',
      );
    } else {
      _logInfo('fetchSnapshot received null snapshot');
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
      _logWarn('processSampleEvents failed error=$err');
      rethrow;
    }
  }

  Future<void> cancelInitialization() async {
    await ensureInitialized();
    try {
      await _methodChannel.invokeMethod('memory#cancelInitialization');
    } catch (err) {
      _logWarn('cancelInitialization failed error=$err');
      rethrow;
    }
  }

  Future<void> clearMemoryData() async {
    await ensureInitialized();
    try {
      await _methodChannel.invokeMethod('memory#clearMemoryData');
      _cachedPersonaSummary = '';
    } catch (err) {
      _logWarn('clearMemoryData failed error=$err');
      rethrow;
    }
  }

  Future<MemoryTag?> fetchTagById(int tagId) async {
    await ensureInitialized();
    _logInfo('fetchTagById invoke tagId=$tagId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#getTag', <String, dynamic>{'tagId': tagId});
    final MemoryTag? tag = _parseTag(result);
    if (tag == null) {
      _logWarn('fetchTagById received null tagId=$tagId');
    }
    return tag;
  }

  Future<MemoryEventSummary?> fetchEventById(int eventId) async {
    await ensureInitialized();
    _logInfo('fetchEventById invoke eventId=$eventId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#getEvent', <String, dynamic>{'eventId': eventId});
    final MemoryEventSummary? summary = _parseEvent(result);
    if (summary == null) {
      _logWarn('fetchEventById received null eventId=$eventId');
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
    _logInfo('confirmTag invoke tagId=$tagId');
    final dynamic result =
        await _methodChannel.invokeMethod('memory#confirmTag', <String, dynamic>{'tagId': tagId});
    if (result == null) {
      _logInfo('confirmTag response null tagId=$tagId');
      return null;
    }
    final MemoryTag? tag = _parseTag(result);
    if (tag != null) {
      _logInfo('confirmTag received status=${tag.status} occurrences=${tag.occurrences}');
      _handleTagUpdate(MemoryTagUpdate(tag: tag, isNewTag: false, statusChanged: true));
    }
    return tag;
  }

  Future<void> startHistoricalProcessing({bool forceReprocess = false}) async {
    await ensureInitialized();
    _logInfo('startHistoricalProcessing invoke force=$forceReprocess');
    await _methodChannel.invokeMethod('memory#initialize', <String, dynamic>{
      'forceReprocess': forceReprocess,
    });
    _logInfo('startHistoricalProcessing invoke completed force=$forceReprocess');
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
    _logInfo('startBackendService invoked');
    try {
      await _methodChannel.invokeMethod('memory#startService');
      _logInfo('startBackendService request sent');
    } catch (err) {
      _logWarn('startService failed: $err');
    }
  }

  void _onSnapshotEvent(dynamic event) {
    _logInfo('snapshot event received type=${event.runtimeType}');
    final MemorySnapshot? snapshot = _parseSnapshot(event);
    if (snapshot != null) {
      _logInfo(
        'snapshot parsed pending=${snapshot.pendingTags.length} confirmed=${snapshot.confirmedTags.length}',
      );
      _emitSnapshot(snapshot);
    }
  }

  void _onProgressEvent(dynamic event) {
    _logInfo('progress event received type=${event.runtimeType}');
    final MemoryProgressState progress = _parseProgress(event);
    _latestProgress = progress;
    _progressController.add(progress);
    _logInfo('progress updated runtime=${progress.runtimeType}');
  }

  void _onTagUpdateEvent(dynamic event) {
    _logInfo('tag update event received type=${event.runtimeType}');
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
    final bool hasIncomingPersona = incomingPersona.isNotEmpty;

    if (hasIncomingPersona) {
      _cachedPersonaSummary = incomingPersona;
    }

    final bool shouldPreservePersona =
        !hasIncomingPersona && _cachedPersonaSummary.isNotEmpty;

    final MemorySnapshot effectiveSnapshot = shouldPreservePersona
        ? snapshot.copyWith(personaSummary: _cachedPersonaSummary)
        : snapshot;

    _latestSnapshot = effectiveSnapshot;
    _snapshotController.add(effectiveSnapshot);
    _logInfo(
      'emit snapshot pending=${effectiveSnapshot.pendingTags.length} confirmed=${effectiveSnapshot.confirmedTags.length} personaPreserved=$shouldPreservePersona cacheLength=${_cachedPersonaSummary.length}',
    );
  }

  void _handleTagUpdate(MemoryTagUpdate update) {
    _logInfo('handleTagUpdate tagId=${update.tag.id} status=${update.tag.status}');
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
      _logInfo('parseProgress received non-map payload');
      return const MemoryProgressIdle();
    }
    final Map<String, dynamic> map = _toStringMap(data);
    final String state = (map['state'] as String?) ?? 'idle';
    _logInfo(
      'parseProgress state=$state processed=${map['processedCount']} total=${map['totalCount']} progress=${map['progress']} duration=${map['durationMillis']} error=${map['errorMessage']}',
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
          'parseProgress completed total=${map['totalCount']} durationMs=${duration.inMilliseconds}',
        );
        return MemoryProgressCompleted(
          totalCount: _toInt(map['totalCount']) ?? 0,
          duration: duration,
        );
      case 'failed':
        _logWarn(
          'parseProgress failed processed=${map['processedCount']} total=${map['totalCount']} error=${map['errorMessage']}',
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
    return text.substring(0, cutoff) + '...';
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