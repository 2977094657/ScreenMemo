import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

import 'memory_entity_materialization_service.dart';
import 'memory_entity_models.dart';
import 'memory_entity_policy.dart';
import 'memory_entity_store.dart';
import 'nocturne_memory_roots.dart';
import 'nocturne_memory_service.dart';

class NocturneMemorySignalContext {
  final int segmentId;
  final int batchIndex;
  final int? segmentStartMs;
  final int? segmentEndMs;
  final String evidenceSummary;
  final List<String> appNames;

  const NocturneMemorySignalContext({
    required this.segmentId,
    required this.batchIndex,
    required this.segmentStartMs,
    required this.segmentEndMs,
    required this.evidenceSummary,
    required this.appNames,
  });
}

enum NocturneMemorySignalStatus { candidate, active, archived }

class NocturneMemorySignalPolicy {
  final String rootUri;
  final double activationScore;
  final int minDistinctDays;
  final bool allowSingleStrongActivation;
  final int archiveAfterDays;
  final int decayTauDays;
  final bool allowRootMaterialization;
  final bool preferSpecificChildNodes;
  final List<String> strongKeywords;

  const NocturneMemorySignalPolicy({
    required this.rootUri,
    required this.activationScore,
    required this.minDistinctDays,
    required this.allowSingleStrongActivation,
    required this.archiveAfterDays,
    required this.decayTauDays,
    required this.allowRootMaterialization,
    required this.preferSpecificChildNodes,
    required this.strongKeywords,
  });
}

class NocturneMemorySignalDiagnosticItem {
  final String entityId;
  final String uri;
  final String rootUri;
  final String title;
  final NocturneMemorySignalStatus status;
  final double rawScore;
  final double decayedScore;
  final double activationScore;
  final int distinctSegmentCount;
  final int distinctDayCount;
  final int minDistinctDays;
  final int strongSignalCount;
  final int firstSeenAt;
  final int lastSeenAt;
  final bool isRootNode;
  final bool allowRootMaterialization;
  final bool allowSingleStrongActivation;
  final bool evidenceSatisfied;
  final bool readyToActivate;
  final bool rootMaterializationBlocked;
  final double missingActivationScore;
  final int missingDistinctDays;
  final String latestContent;
  final bool needsReview;
  final String? reviewReason;

  const NocturneMemorySignalDiagnosticItem({
    required this.entityId,
    required this.uri,
    required this.rootUri,
    required this.title,
    required this.status,
    required this.rawScore,
    required this.decayedScore,
    required this.activationScore,
    required this.distinctSegmentCount,
    required this.distinctDayCount,
    required this.minDistinctDays,
    required this.strongSignalCount,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.isRootNode,
    required this.allowRootMaterialization,
    required this.allowSingleStrongActivation,
    required this.evidenceSatisfied,
    required this.readyToActivate,
    required this.rootMaterializationBlocked,
    required this.missingActivationScore,
    required this.missingDistinctDays,
    required this.latestContent,
    required this.needsReview,
    this.reviewReason,
  });
}

class NocturneMemorySignalRootSummary {
  final String rootUri;
  final int candidateCount;
  final int activeCount;
  final int archivedCount;

  const NocturneMemorySignalRootSummary({
    required this.rootUri,
    required this.candidateCount,
    required this.activeCount,
    required this.archivedCount,
  });
}

class NocturneMemorySignalDashboard {
  final int totalCount;
  final int candidateCount;
  final int activeCount;
  final int archivedCount;
  final int reviewQueueCount;
  final MemoryEntityQualityMetrics qualityMetrics;
  final List<NocturneMemorySignalRootSummary> roots;
  final List<NocturneMemorySignalDiagnosticItem> topCandidates;
  final List<NocturneMemorySignalDiagnosticItem> topActive;
  final List<NocturneMemorySignalDiagnosticItem> topArchived;

  const NocturneMemorySignalDashboard({
    required this.totalCount,
    required this.candidateCount,
    required this.activeCount,
    required this.archivedCount,
    required this.reviewQueueCount,
    required this.qualityMetrics,
    required this.roots,
    required this.topCandidates,
    required this.topActive,
    required this.topArchived,
  });
}

class NocturneMemorySignalService {
  NocturneMemorySignalService._internal();

  static final NocturneMemorySignalService instance =
      NocturneMemorySignalService._internal();

  final MemoryEntityStore _store = MemoryEntityStore.instance;
  final MemoryEntityMaterializationService _materializer =
      MemoryEntityMaterializationService.instance;
  final NocturneMemoryService _mem = NocturneMemoryService.instance;

  bool isManagedUri(String uri) => MemoryEntityPolicies.forRootUri(uri) != null;

  Future<void> resetAll() => _store.resetAll();

  Future<void> _ensureLegacyEntitiesReady() async {
    await _store.migrateLegacySignalTablesIfNeeded();
    await _store.ensureSignalReadModelsReady();
  }

  Future<void> recordUpdateAction({
    required String uri,
    required List<String> bulletLines,
    required NocturneMemorySignalContext context,
  }) async {
    throw UnsupportedError(
      'uri-first signal ingestion has been removed; use the AI entity pipeline instead.',
    );
  }

  Future<void> recordCreateAction({
    required String parentUri,
    required String title,
    required String content,
    required NocturneMemorySignalContext context,
  }) async {
    throw UnsupportedError(
      'uri-first signal ingestion has been removed; use the AI entity pipeline instead.',
    );
  }

  @visibleForTesting
  Future<MemoryEntityApplyResult> seedCreateActionForTest({
    required String parentUri,
    required String title,
    required String content,
    required NocturneMemorySignalContext context,
  }) async {
    final String normalizedParent = _store.canonicalizeUri(parentUri);
    final NocturneUri parent = _mem.parseUri(normalizedParent);
    final String displayUri = _mem.makeUri(
      parent.domain,
      parent.path.isEmpty ? title : '${parent.path}/$title',
    );
    return seedResolvedEntityObservationForTest(
      displayUri: displayUri,
      content: content,
      context: context,
    );
  }

  @visibleForTesting
  Future<MemoryEntityApplyResult> seedUpdateActionForTest({
    required String uri,
    required List<String> bulletLines,
    required NocturneMemorySignalContext context,
  }) {
    return seedResolvedEntityObservationForTest(
      displayUri: uri,
      content: bulletLines.join('\n'),
      context: context,
    );
  }

  @visibleForTesting
  Future<MemoryEntityApplyResult> seedResolvedEntityObservationForTest({
    required String displayUri,
    required String content,
    required NocturneMemorySignalContext context,
  }) async {
    await _ensureLegacyEntitiesReady();
    final String normalizedDisplayUri = _store.canonicalizeUri(displayUri);
    final String normalizedContent = _normalizeContent(content);
    if (normalizedContent.isEmpty) {
      throw ArgumentError('content must not be empty');
    }
    final MemoryEntityRootPolicy policy =
        MemoryEntityPolicies.forRootUri(normalizedDisplayUri) ??
        (throw StateError(
          'uri is not under a managed entity root: $displayUri',
        ));
    final MemoryEntityRecord? existing = await _store.getRecordByDisplayUri(
      normalizedDisplayUri,
    );
    final String preferredName = normalizedDisplayUri == policy.rootUri
        ? policy.rootKey
        : _humanizeLeaf(normalizedDisplayUri);
    final MemoryVisualCandidate candidate = MemoryVisualCandidate(
      candidateId:
          'test_seed_${context.segmentId}_${context.batchIndex}_${normalizedDisplayUri.hashCode.abs()}',
      rootKey: policy.rootKey,
      entityType: policy.entityType,
      preferredName: preferredName,
      visualSignatureSummary: 'test visual seed for $preferredName',
      confidence: 1,
      facts: const <MemoryEntityFactCandidate>[],
      evidenceFrames: const <int>[0],
    );
    final MemoryEntityResolutionDecision resolution =
        MemoryEntityResolutionDecision(
          action: existing == null
              ? MemoryEntityResolutionAction.createNew
              : MemoryEntityResolutionAction.matchExisting,
          confidence: 1,
          matchedEntityId: existing?.entityId,
          reasons: const <String>['test seed through entity pipeline'],
        );
    final MemoryEntityMergePlan mergePlan = MemoryEntityMergePlan(
      preferredName: preferredName,
      summaryRewrite: normalizedContent,
      visualSignatureSummary: 'test visual seed for $preferredName',
      claimsToUpsert: const <MemoryEntityFactCandidate>[],
      eventsToAppend: const <MemoryEntityEventCandidate>[],
    );
    final MemoryEntityAuditDecision audit = MemoryEntityAuditDecision(
      action: MemoryEntityAuditAction.approve,
      confidence: 1,
      suggestedEntityId: existing?.entityId,
      reasons: const <String>['test seed approved'],
    );

    final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
    resolutionResult =
        MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>(
          value: resolution,
          inputJson: encodeJsonPretty(candidate.toJson()),
          outputJson: encodeJsonPretty(resolution.toJson()),
          modelUsed: 'test_seed',
        );
    final MemoryStructuredDecisionResult<MemoryEntityMergePlan>
    mergePlanResult = MemoryStructuredDecisionResult<MemoryEntityMergePlan>(
      value: mergePlan,
      inputJson: encodeJsonPretty(candidate.toJson()),
      outputJson: encodeJsonPretty(mergePlan.toJson()),
      modelUsed: 'test_seed',
    );
    final MemoryStructuredDecisionResult<MemoryEntityAuditDecision>
    auditResult = MemoryStructuredDecisionResult<MemoryEntityAuditDecision>(
      value: audit,
      inputJson: encodeJsonPretty(candidate.toJson()),
      outputJson: encodeJsonPretty(audit.toJson()),
      modelUsed: 'test_seed',
    );

    MemoryEntityApplyResult result = await _store.applyAIPipelineResult(
      visualCandidate: candidate,
      resolutionWorkflow: MemoryEntityResolutionWorkflowResult(
        finalResult: resolutionResult,
      ),
      mergePlanResult: mergePlanResult,
      auditResult: auditResult,
      shortlist: const <MemoryEntityDossier>[],
      segmentId: context.segmentId,
      batchIndex: context.batchIndex,
      segmentStartMs: context.segmentStartMs,
      segmentEndMs: context.segmentEndMs,
      evidenceSummary: context.evidenceSummary,
      appNames: context.appNames,
      exemplars: const <MemoryEntityExemplar>[],
    );
    final MemoryEntityRecord? record = result.record;
    if (record != null && record.displayUri != normalizedDisplayUri) {
      await _store.moveEntityLeaf(
        entityId: record.entityId,
        targetUri: normalizedDisplayUri,
      );
      final MemoryEntityRecord? moved = await _store.getRecordById(
        record.entityId,
      );
      if (moved != null) {
        result = MemoryEntityApplyResult(
          record: moved,
          created: result.created,
          needsReview: moved.needsReview,
          queuedForReview: result.queuedForReview,
          reviewReason: moved.reviewReason,
        );
      }
    }
    return result;
  }

  Future<Map<String, List<String>>> buildSnapshotSections({
    int maxProfilesPerRoot = 6,
  }) async {
    await _ensureLegacyEntitiesReady();
    await _store.refreshSignals();
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final NocturneMemoryRootSpec root in NocturneMemoryRoots.all) {
      final List<MemoryEntityRecord> rows = (await _store.listSignalRecords(
        rootUri: root.uri,
      )).take(maxProfilesPerRoot).toList(growable: false);
      if (rows.isEmpty) continue;

      final List<String> lines = <String>['候选信号（含未正式物化的记忆，用于去重与避免重复建节点）：'];
      for (final MemoryEntityRecord row in rows) {
        if (row.rawScore < 0.8) continue;
        final String status = _statusToStored(_statusFromEntity(row.status));
        final String preview = _snapshotPreview(
          row.currentSummary.trim().isNotEmpty
              ? row.currentSummary
              : row.latestContent,
        );
        final String when = row.lastSeenAt > 0
            ? DateFormat('yyyy-MM-dd').format(
                DateTime.fromMillisecondsSinceEpoch(row.lastSeenAt).toLocal(),
              )
            : '未知';
        lines.add(
          '- [$status] ${row.displayUri} | score=${row.decayedScore.toStringAsFixed(2)} raw=${row.rawScore.toStringAsFixed(2)} | 段落=${row.distinctSegmentCount} 天数=${row.distinctDayCount} 最近=$when | $preview',
        );
      }
      if (lines.length > 1) {
        out[root.uri] = lines;
      }
    }
    return out;
  }

  Future<NocturneMemorySignalDashboard> loadDashboard({
    int limitPerStatus = 8,
  }) async {
    await _ensureLegacyEntitiesReady();
    await _store.refreshSignals();
    final List<NocturneMemorySignalDiagnosticItem> items =
        (await _store.listSignalRecords())
            .map(_diagnosticItemFromRecord)
            .toList();
    final int candidateCount = items
        .where((item) => item.status == NocturneMemorySignalStatus.candidate)
        .length;
    final int activeCount = items
        .where((item) => item.status == NocturneMemorySignalStatus.active)
        .length;
    final int archivedCount = items
        .where((item) => item.status == NocturneMemorySignalStatus.archived)
        .length;
    final int reviewQueueCount = (await _store.listReviewQueueItems(
      limit: 500,
    )).length;
    final MemoryEntityQualityMetrics qualityMetrics = await _store
        .loadQualityMetrics();

    final List<NocturneMemorySignalRootSummary> roots = NocturneMemoryRoots.all
        .map((root) {
          final Iterable<NocturneMemorySignalDiagnosticItem> scoped = items
              .where((item) => item.rootUri == root.uri);
          int c = 0;
          int a = 0;
          int r = 0;
          for (final NocturneMemorySignalDiagnosticItem item in scoped) {
            switch (item.status) {
              case NocturneMemorySignalStatus.candidate:
                c += 1;
                break;
              case NocturneMemorySignalStatus.active:
                a += 1;
                break;
              case NocturneMemorySignalStatus.archived:
                r += 1;
                break;
            }
          }
          return NocturneMemorySignalRootSummary(
            rootUri: root.uri,
            candidateCount: c,
            activeCount: a,
            archivedCount: r,
          );
        })
        .toList(growable: false);

    List<NocturneMemorySignalDiagnosticItem> takeStatus(
      NocturneMemorySignalStatus status,
    ) {
      return items
          .where((item) => item.status == status)
          .take(limitPerStatus)
          .toList();
    }

    return NocturneMemorySignalDashboard(
      totalCount: items.length,
      candidateCount: candidateCount,
      activeCount: activeCount,
      archivedCount: archivedCount,
      reviewQueueCount: reviewQueueCount,
      qualityMetrics: qualityMetrics,
      roots: roots,
      topCandidates: takeStatus(NocturneMemorySignalStatus.candidate),
      topActive: takeStatus(NocturneMemorySignalStatus.active),
      topArchived: takeStatus(NocturneMemorySignalStatus.archived),
    );
  }

  Future<List<MemoryEntityReviewQueueItem>> loadReviewQueueItems({
    MemoryEntityReviewStatus status = MemoryEntityReviewStatus.pending,
    int limit = 200,
  }) {
    return _ensureLegacyEntitiesReady().then(
      (_) => _store.listReviewQueueItems(status: status, limit: limit),
    );
  }

  Future<MemoryEntityApplyResult> approveReviewQueueItem({
    required int reviewId,
    String? targetEntityId,
    bool forceCreateNew = false,
  }) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityApplyResult result = await _store.approveReviewQueueItem(
      reviewId: reviewId,
      targetEntityId: targetEntityId,
      forceCreateNew: forceCreateNew,
    );
    final MemoryEntityRecord? record = result.record;
    if (record != null && record.status != MemoryEntityStatus.candidate) {
      await _materializer.rematerializeEntity(record.entityId);
    }
    return result;
  }

  Future<void> dismissReviewQueueItem(int reviewId) async {
    await _ensureLegacyEntitiesReady();
    await _store.dismissReviewQueueItem(reviewId);
  }

  Future<List<NocturneMemorySignalDiagnosticItem>> loadItemsByStatus(
    NocturneMemorySignalStatus status,
  ) async {
    await _ensureLegacyEntitiesReady();
    await _store.refreshSignals();
    final MemoryEntityStatus entityStatus = _entityStatus(status);
    final List<MemoryEntityRecord> rows = await _store.listSignalRecords(
      status: entityStatus,
    );
    return rows.map(_diagnosticItemFromRecord).toList(growable: false);
  }

  Future<NocturneMemorySignalDiagnosticItem?> loadDiagnosticItem(
    String uri,
  ) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord? existing = await _store
        .getSignalRecordByDisplayUri(uri);
    if (existing == null) return null;
    await _store.refreshSignals(entityId: existing.entityId);
    final MemoryEntityRecord? record = await _store.getSignalRecordById(
      existing.entityId,
    );
    if (record == null) return null;
    return _diagnosticItemFromRecord(record);
  }

  Future<NocturneMemorySignalDiagnosticItem?> loadDiagnosticItemByEntityId(
    String entityId,
  ) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord? existing = await _store.getSignalRecordById(
      entityId,
    );
    if (existing == null) return null;
    await _store.refreshSignals(entityId: existing.entityId);
    final MemoryEntityRecord? record = await _store.getSignalRecordById(
      existing.entityId,
    );
    if (record == null) return null;
    return _diagnosticItemFromRecord(record);
  }

  Future<bool> hasProfileDescendants(String uri) {
    return _ensureLegacyEntitiesReady().then((_) => _store.hasDescendants(uri));
  }

  String materializedUriFor(String uri, NocturneMemorySignalStatus status) {
    return _materializer.materializedUriFor(
      displayUri: uri,
      status: _entityStatus(status),
    );
  }

  Future<void> rewriteProfileContent({
    required String uri,
    required String content,
  }) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordByDisplayUri(uri) ??
        (throw StateError('signal profile not found: $uri'));
    await rewriteProfileContentByEntityId(
      entityId: record.entityId,
      content: content,
    );
  }

  Future<void> rewriteProfileContentByEntityId({
    required String entityId,
    required String content,
  }) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found: $entityId'));
    await _store.rewriteEntityContent(
      entityId: record.entityId,
      content: content,
    );
    if (record.status != MemoryEntityStatus.candidate) {
      await _materializer.rematerializeEntity(record.entityId);
    }
  }

  Future<void> moveProfileLeaf({
    required String sourceUri,
    required String targetUri,
  }) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordByDisplayUri(sourceUri) ??
        (throw StateError('signal profile not found: $sourceUri'));
    await moveProfileLeafByEntityId(
      entityId: record.entityId,
      targetUri: targetUri,
    );
  }

  Future<void> moveProfileLeafByEntityId({
    required String entityId,
    required String targetUri,
  }) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found: $entityId'));
    final String oldDisplayUri = record.displayUri;
    await _store.moveEntityLeaf(
      entityId: record.entityId,
      targetUri: targetUri,
    );
    final MemoryEntityRecord updated =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found after move: $entityId'));
    if (updated.status != MemoryEntityStatus.candidate) {
      await _materializer.rematerializeEntity(updated.entityId);
    }
    if (oldDisplayUri != updated.displayUri) {
      await _materializer.removeDisplayUriVariants(<String>[oldDisplayUri]);
    }
  }

  Future<void> addAliasToProfile({
    required String targetUri,
    required String newUri,
  }) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordByDisplayUri(targetUri) ??
        (throw StateError('signal profile not found: $targetUri'));
    await addAliasToProfileByEntityId(
      entityId: record.entityId,
      newUri: newUri,
    );
  }

  Future<void> addAliasToProfileByEntityId({
    required String entityId,
    required String newUri,
  }) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found: $entityId'));
    await _store.addManagedUriAlias(entityId: record.entityId, uri: newUri);
    if (record.status != MemoryEntityStatus.candidate) {
      await _materializer.rematerializeEntity(record.entityId);
    }
  }

  Future<void> dropCandidate(String uri) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordByDisplayUri(uri) ??
        (throw StateError('signal profile not found: $uri'));
    await dropCandidateByEntityId(record.entityId);
  }

  Future<void> dropCandidateByEntityId(String entityId) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found: $entityId'));
    if (record.status != MemoryEntityStatus.candidate) {
      throw StateError('only candidate can be dropped: ${record.displayUri}');
    }
    await _store.deleteEntity(record.entityId);
  }

  Future<void> deleteProfile(String uri) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordByDisplayUri(uri) ??
        (throw StateError('signal profile not found: $uri'));
    await deleteProfileByEntityId(record.entityId);
  }

  Future<void> deleteProfileByEntityId(String entityId) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found: $entityId'));
    await _materializer.removeEntityMaterialization(
      record.entityId,
      snapshot: record,
    );
    await _store.deleteEntity(record.entityId);
  }

  Future<void> rematerializeProfile(String uri) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordByDisplayUri(uri) ??
        (throw StateError('signal profile not found: $uri'));
    await rematerializeProfileByEntityId(record.entityId);
  }

  Future<void> rematerializeProfileByEntityId(String entityId) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found: $entityId'));
    if (record.status == MemoryEntityStatus.candidate) return;
    await _materializer.rematerializeEntity(record.entityId);
  }

  Future<void> forceArchiveProfile(String uri) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordByDisplayUri(uri) ??
        (throw StateError('signal profile not found: $uri'));
    await forceArchiveProfileByEntityId(record.entityId);
  }

  Future<void> forceArchiveProfileByEntityId(String entityId) async {
    await _ensureLegacyEntitiesReady();
    final MemoryEntityRecord record =
        await _store.getRecordById(entityId) ??
        (throw StateError('signal profile not found: $entityId'));
    await _store.archiveEntity(record.entityId);
    await _materializer.rematerializeEntity(record.entityId);
  }

  Future<void> materializeProfiles({bool Function()? shouldStop}) async {
    await _ensureLegacyEntitiesReady();
    await _store.refreshSignals();
    await _materializer.materializeAll(shouldStop: shouldStop);
  }

  NocturneMemorySignalDiagnosticItem _diagnosticItemFromRecord(
    MemoryEntityRecord record,
  ) {
    return NocturneMemorySignalDiagnosticItem(
      entityId: record.entityId,
      uri: record.displayUri,
      rootUri: record.rootUri,
      title: record.displayUri == record.rootUri
          ? record.preferredName
          : _humanizeLeaf(record.displayUri),
      status: _statusFromEntity(record.status),
      rawScore: record.rawScore,
      decayedScore: record.decayedScore,
      activationScore: record.activationScore,
      distinctSegmentCount: record.distinctSegmentCount,
      distinctDayCount: record.distinctDayCount,
      minDistinctDays: record.minDistinctDays,
      strongSignalCount: record.strongSignalCount,
      firstSeenAt: record.firstSeenAt,
      lastSeenAt: record.lastSeenAt,
      isRootNode: record.displayUri == record.rootUri,
      allowRootMaterialization: record.allowRootMaterialization,
      allowSingleStrongActivation: record.allowSingleStrongActivation,
      evidenceSatisfied: record.evidenceSatisfied,
      readyToActivate: record.readyToActivate,
      rootMaterializationBlocked: record.rootMaterializationBlocked,
      missingActivationScore: record.missingActivationScore,
      missingDistinctDays: record.missingDistinctDays,
      latestContent: record.currentSummary.trim().isNotEmpty
          ? record.currentSummary
          : record.latestContent,
      needsReview: record.needsReview,
      reviewReason: record.reviewReason,
    );
  }

  NocturneMemorySignalStatus _statusFromEntity(MemoryEntityStatus status) {
    switch (status) {
      case MemoryEntityStatus.active:
        return NocturneMemorySignalStatus.active;
      case MemoryEntityStatus.archived:
        return NocturneMemorySignalStatus.archived;
      case MemoryEntityStatus.candidate:
        return NocturneMemorySignalStatus.candidate;
    }
  }

  MemoryEntityStatus _entityStatus(NocturneMemorySignalStatus status) {
    switch (status) {
      case NocturneMemorySignalStatus.active:
        return MemoryEntityStatus.active;
      case NocturneMemorySignalStatus.archived:
        return MemoryEntityStatus.archived;
      case NocturneMemorySignalStatus.candidate:
        return MemoryEntityStatus.candidate;
    }
  }

  String _statusToStored(NocturneMemorySignalStatus status) {
    switch (status) {
      case NocturneMemorySignalStatus.active:
        return 'active';
      case NocturneMemorySignalStatus.archived:
        return 'archived';
      case NocturneMemorySignalStatus.candidate:
        return 'candidate';
    }
  }

  String _humanizeLeaf(String uri) {
    final String leaf = _mem.parseUri(uri).path.split('/').last;
    return leaf.replaceAll(RegExp(r'[_-]+'), ' ').trim();
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

  static String _snapshotPreview(String content) {
    final String normalized = _normalizeContent(content);
    if (normalized.isEmpty) return '（无内容）';
    final String first = normalized.split('\n').first;
    return first.length > 80 ? '${first.substring(0, 80)}…' : first;
  }
}
