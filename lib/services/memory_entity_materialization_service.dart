import 'memory_entity_models.dart';
import 'memory_entity_policy.dart';
import 'memory_entity_store.dart';
import 'nocturne_memory_service.dart';

class MemoryEntityMaterializationService {
  MemoryEntityMaterializationService._internal();

  static final MemoryEntityMaterializationService instance =
      MemoryEntityMaterializationService._internal();

  final MemoryEntityStore _store = MemoryEntityStore.instance;
  final NocturneMemoryService _mem = NocturneMemoryService.instance;

  Future<void> materializeAll({bool Function()? shouldStop}) async {
    await _mem.runEntityMaterializationWrite(() async {
      await _store.refreshSignals();
      final List<MemoryEntityRecord> records = await _store.listRecords();
      for (final MemoryEntityRecord record in records) {
        if (shouldStop?.call() == true) return;
        if (record.status == MemoryEntityStatus.candidate ||
            record.needsReview) {
          continue;
        }
        await rematerializeEntity(record.entityId);
      }
    });
  }

  Future<void> rematerializeEntity(String entityId) async {
    await _mem.runEntityMaterializationWrite(() async {
      final MemoryEntityRecord record =
          await _store.getRecordById(entityId) ??
          (throw StateError('entity not found: $entityId'));
      if (record.status == MemoryEntityStatus.candidate || record.needsReview) {
        return;
      }
      final String canonicalTarget = materializedUriFor(
        displayUri: record.displayUri,
        status: record.status,
      );
      final String activeCanonicalTarget = materializedUriFor(
        displayUri: record.displayUri,
        status: MemoryEntityStatus.active,
      );
      final String archivedCanonicalTarget = materializedUriFor(
        displayUri: record.displayUri,
        status: MemoryEntityStatus.archived,
      );
      final String content = await _buildMaterializedContent(record);
      if (content.trim().isEmpty) return;

      await _writeManagedPath(
        targetUri: canonicalTarget,
        content: content,
        rootUri: record.rootUri,
        priority: record.status == MemoryEntityStatus.active ? 2 : 6,
      );

      if (record.status == MemoryEntityStatus.archived) {
        if (activeCanonicalTarget != canonicalTarget) {
          await _deleteIfExists(activeCanonicalTarget);
        }
      } else if (archivedCanonicalTarget != canonicalTarget) {
        await _deleteIfExists(archivedCanonicalTarget);
      }

      final List<String> aliasPaths = await _store.listManagedUriAliases(
        record.entityId,
      );
      for (final String aliasUri in aliasPaths) {
        final String currentAlias = materializedUriFor(
          displayUri: aliasUri,
          status: record.status,
        );
        final String activeAlias = materializedUriFor(
          displayUri: aliasUri,
          status: MemoryEntityStatus.active,
        );
        final String archivedAlias = materializedUriFor(
          displayUri: aliasUri,
          status: MemoryEntityStatus.archived,
        );
        await _writeAlias(currentAlias, canonicalTarget, record.rootUri);
        if (record.status == MemoryEntityStatus.archived) {
          if (activeAlias != currentAlias) {
            await _deleteIfExists(activeAlias);
          }
        } else if (archivedAlias != currentAlias) {
          await _deleteIfExists(archivedAlias);
        }
      }

      await _store.markMaterialized(record.entityId);
    });
  }

  Future<void> removeEntityMaterialization(
    String entityId, {
    MemoryEntityRecord? snapshot,
  }) async {
    final MemoryEntityRecord record =
        snapshot ??
        await _store.getRecordById(entityId) ??
        (throw StateError('entity not found: $entityId'));
    final List<String> aliasPaths = await _store.listManagedUriAliases(
      record.entityId,
    );
    await removeDisplayUriVariants(<String>[record.displayUri, ...aliasPaths]);
  }

  Future<void> removeDisplayUriVariants(Iterable<String> displayUris) async {
    await _mem.runEntityMaterializationWrite(() async {
      final Set<String> uris = <String>{};
      for (final String displayUri in displayUris) {
        final String trimmed = displayUri.trim();
        if (trimmed.isEmpty) continue;
        uris.add(
          materializedUriFor(
            displayUri: trimmed,
            status: MemoryEntityStatus.active,
          ),
        );
        uris.add(
          materializedUriFor(
            displayUri: trimmed,
            status: MemoryEntityStatus.archived,
          ),
        );
      }
      for (final String uri in uris) {
        await _deleteIfExists(uri);
      }
    });
  }

  String materializedUriFor({
    required String displayUri,
    required MemoryEntityStatus status,
  }) {
    final String normalized = _store.canonicalizeUri(displayUri);
    if (status != MemoryEntityStatus.archived) {
      return normalized;
    }
    final MemoryEntityRootPolicy? policy = MemoryEntityPolicies.forRootUri(
      normalized,
    );
    final String rootUri =
        policy?.rootUri ??
        MemoryEntityPolicies.forRootUri(normalized)?.rootUri ??
        normalized;
    return _buildArchivedUri(normalized, rootUri);
  }

  Future<String> _buildMaterializedContent(MemoryEntityRecord record) async {
    final List<String> body = record.latestContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final List<MemoryEntityEventSnapshot> recentEvents = await _store
        .listEvents(record.entityId, limit: 3);
    final Set<String> bodyNorms = body.map((line) => line.trim()).toSet();
    final List<String> eventLines = <String>[];
    for (final MemoryEntityEventSnapshot event in recentEvents) {
      final String line = '- 近期事件：${event.note.trim()}';
      if (event.note.trim().isEmpty || bodyNorms.contains(line.trim())) {
        continue;
      }
      eventLines.add(line);
    }
    final List<String> meta = <String>[
      '- 记忆信号状态：${record.status == MemoryEntityStatus.active ? '活跃' : '已封存'}',
      '- 证据段数：${record.distinctSegmentCount}',
      '- 跨天出现：${record.distinctDayCount}',
      '- 首次出现：${_formatDate(record.firstSeenAt)}',
      '- 最近出现：${_formatDate(record.lastSeenAt)}',
      '- 当前信号分：${record.decayedScore.toStringAsFixed(2)}',
      '- 累计信号分：${record.rawScore.toStringAsFixed(2)}',
    ];
    if ((record.lastEvidenceSummary ?? '').trim().isNotEmpty) {
      meta.add('- 最近证据：${record.lastEvidenceSummary!.trim()}');
    }
    if (record.status == MemoryEntityStatus.archived) {
      meta.add('- 生命周期状态：已封存（${_formatDate(record.lastSeenAt)}，原因：长期未再次出现）');
    }
    return <String>[
      ...body,
      if (eventLines.isNotEmpty && body.isNotEmpty) '',
      ...eventLines,
      if (body.isNotEmpty || eventLines.isNotEmpty) '',
      ...meta,
    ].join('\n').trim();
  }

  Future<void> _writeManagedPath({
    required String targetUri,
    required String content,
    required String rootUri,
    required int priority,
  }) async {
    final NocturneUri parsed = _mem.parseUri(targetUri);
    final NocturneUri root = _mem.parseUri(rootUri);
    if (parsed.path == root.path) {
      final String existing = await _readContentSafe(targetUri);
      if (existing.trim() == content.trim()) return;
      await _mem.updateMemory(
        uri: targetUri,
        oldString: existing,
        newString: content,
      );
      return;
    }

    final int cut = parsed.path.lastIndexOf('/');
    final String parentPath = cut >= 0 ? parsed.path.substring(0, cut) : '';
    final String leaf = cut >= 0 ? parsed.path.substring(cut + 1) : parsed.path;
    final String parentUri = _mem.makeUri(parsed.domain, parentPath);
    await _ensureParentChainExists(parentUri, rootUri: rootUri);
    try {
      await _mem.createMemory(
        parentUri: parentUri,
        title: leaf,
        content: content,
        priority: priority,
      );
    } catch (error) {
      if (!error.toString().contains('path already exists')) rethrow;
      final String existing = await _readContentSafe(targetUri);
      if (existing.trim() == content.trim()) return;
      await _mem.updateMemory(
        uri: targetUri,
        oldString: existing,
        newString: content,
      );
    }
  }

  Future<void> _writeAlias(
    String aliasUri,
    String targetUri,
    String rootUri,
  ) async {
    if (aliasUri == targetUri) return;
    final NocturneUri parsed = _mem.parseUri(aliasUri);
    final int cut = parsed.path.lastIndexOf('/');
    final String parentPath = cut >= 0 ? parsed.path.substring(0, cut) : '';
    final String parentUri = _mem.makeUri(parsed.domain, parentPath);
    await _ensureParentChainExists(parentUri, rootUri: rootUri);
    try {
      await _mem.addAlias(newUri: aliasUri, targetUri: targetUri, priority: 6);
    } catch (error) {
      if (!error.toString().contains('path already exists')) rethrow;
    }
  }

  Future<void> _ensureParentChainExists(
    String parentUri, {
    required String rootUri,
  }) async {
    final String normalizedParent = _store.canonicalizeUri(parentUri);
    final String normalizedRoot = _store.canonicalizeUri(rootUri);
    if (normalizedParent == normalizedRoot) return;
    final NocturneUri parent = _mem.parseUri(normalizedParent);
    final NocturneUri root = _mem.parseUri(normalizedRoot);
    final String rel = parent.path.substring(root.path.length + 1);
    final List<String> parts = rel
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    String current = normalizedRoot;
    for (final String part in parts) {
      final String next = '$current/$part';
      try {
        await _mem.createMemory(
          parentUri: current,
          title: part,
          content: '（自动创建的目录节点，用于组织实体记忆）',
          priority: 5,
        );
      } catch (error) {
        if (!error.toString().contains('path already exists')) rethrow;
      }
      current = next;
    }
  }

  String _buildArchivedUri(String uri, String rootUri) {
    if (!uri.startsWith('$rootUri/')) return uri;
    final String relative = uri.substring(rootUri.length + 1);
    return '$rootUri/archive/$relative';
  }

  Future<void> _deleteIfExists(String uri) async {
    try {
      await _mem.readMemory(uri);
    } catch (_) {
      return;
    }
    try {
      await _mem.deleteMemory(uri: uri);
    } catch (_) {}
  }

  Future<String> _readContentSafe(String uri) async {
    try {
      final Map<String, dynamic> row = await _mem.readMemory(uri);
      return (row['content'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  String _formatDate(int ms) {
    if (ms <= 0) return '未知';
    final DateTime value = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final String mm = value.month.toString().padLeft(2, '0');
    final String dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }
}
