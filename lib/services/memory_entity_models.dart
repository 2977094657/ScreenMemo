import 'dart:convert';

enum MemoryEntityStatus {
  candidate('candidate'),
  active('active'),
  archived('archived');

  const MemoryEntityStatus(this.wireName);
  final String wireName;

  static MemoryEntityStatus fromWire(String raw) {
    final String value = raw.trim().toLowerCase();
    for (final MemoryEntityStatus status in MemoryEntityStatus.values) {
      if (status.wireName == value) return status;
    }
    return MemoryEntityStatus.candidate;
  }
}

enum MemoryEntityCardinality {
  singleton('singleton'),
  multi('multi');

  const MemoryEntityCardinality(this.wireName);
  final String wireName;

  static MemoryEntityCardinality fromWire(String raw) {
    final String value = raw.trim().toLowerCase();
    for (final MemoryEntityCardinality item in MemoryEntityCardinality.values) {
      if (item.wireName == value) return item;
    }
    return MemoryEntityCardinality.multi;
  }
}

enum MemoryEntityResolutionAction {
  matchExisting('MATCH_EXISTING'),
  createNew('CREATE_NEW'),
  addAliasToExisting('ADD_ALIAS_TO_EXISTING'),
  reviewRequired('REVIEW_REQUIRED');

  const MemoryEntityResolutionAction(this.wireName);
  final String wireName;

  static MemoryEntityResolutionAction fromWire(String raw) {
    final String value = raw.trim().toUpperCase();
    for (final MemoryEntityResolutionAction item
        in MemoryEntityResolutionAction.values) {
      if (item.wireName == value) return item;
    }
    return MemoryEntityResolutionAction.reviewRequired;
  }
}

enum MemoryEntityAuditAction {
  approve('APPROVE'),
  blockDuplicate('BLOCK_DUPLICATE'),
  blockAmbiguous('BLOCK_AMBIGUOUS'),
  blockLowEvidence('BLOCK_LOW_EVIDENCE');

  const MemoryEntityAuditAction(this.wireName);
  final String wireName;

  static MemoryEntityAuditAction fromWire(String raw) {
    final String value = raw.trim().toUpperCase();
    for (final MemoryEntityAuditAction item in MemoryEntityAuditAction.values) {
      if (item.wireName == value) return item;
    }
    return MemoryEntityAuditAction.blockAmbiguous;
  }
}

enum MemoryEntityReviewStatus {
  pending('pending'),
  approved('approved'),
  dismissed('dismissed');

  const MemoryEntityReviewStatus(this.wireName);
  final String wireName;

  static MemoryEntityReviewStatus fromWire(String raw) {
    final String value = raw.trim().toLowerCase();
    for (final MemoryEntityReviewStatus item
        in MemoryEntityReviewStatus.values) {
      if (item.wireName == value) return item;
    }
    return MemoryEntityReviewStatus.pending;
  }
}

class MemoryEntityFactCandidate {
  const MemoryEntityFactCandidate({
    required this.factType,
    required this.value,
    required this.cardinality,
    required this.confidence,
    this.slotKey,
    this.evidenceFrames = const <int>[],
  });

  final String factType;
  final String? slotKey;
  final String value;
  final MemoryEntityCardinality cardinality;
  final double confidence;
  final List<int> evidenceFrames;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fact_type': factType,
    'slot_key': slotKey,
    'value': value,
    'cardinality': cardinality.wireName,
    'confidence': confidence,
    'evidence_frames': evidenceFrames,
  };

  factory MemoryEntityFactCandidate.fromJson(Map<String, dynamic> json) {
    final List<int> frames = <int>[];
    final dynamic rawFrames = json['evidence_frames'];
    if (rawFrames is List) {
      for (final dynamic raw in rawFrames) {
        if (raw is num) frames.add(raw.toInt());
      }
    }
    return MemoryEntityFactCandidate(
      factType: (json['fact_type'] as String? ?? '').trim(),
      slotKey: (json['slot_key'] as String?)?.trim(),
      value: (json['value'] as String? ?? '').trim(),
      cardinality: MemoryEntityCardinality.fromWire(
        (json['cardinality'] as String? ?? 'multi'),
      ),
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      evidenceFrames: frames,
    );
  }
}

class MemoryEntityEventCandidate {
  const MemoryEntityEventCandidate({
    required this.note,
    this.evidenceFrames = const <int>[],
  });

  final String note;
  final List<int> evidenceFrames;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'note': note,
    'evidence_frames': evidenceFrames,
  };

  factory MemoryEntityEventCandidate.fromJson(Map<String, dynamic> json) {
    final List<int> frames = <int>[];
    final dynamic rawFrames = json['evidence_frames'];
    if (rawFrames is List) {
      for (final dynamic raw in rawFrames) {
        if (raw is num) frames.add(raw.toInt());
      }
    }
    return MemoryEntityEventCandidate(
      note: (json['note'] as String? ?? '').trim(),
      evidenceFrames: frames,
    );
  }
}

class MemoryVisualCandidate {
  const MemoryVisualCandidate({
    required this.candidateId,
    required this.rootKey,
    required this.entityType,
    required this.preferredName,
    required this.visualSignatureSummary,
    required this.confidence,
    required this.facts,
    this.aliases = const <String>[],
    this.stableVisualCues = const <String>[],
    this.evidenceFrames = const <int>[],
    this.shouldSkip = false,
    this.skipReason,
  });

  final String candidateId;
  final String rootKey;
  final String entityType;
  final String preferredName;
  final List<String> aliases;
  final String visualSignatureSummary;
  final List<String> stableVisualCues;
  final List<MemoryEntityFactCandidate> facts;
  final double confidence;
  final List<int> evidenceFrames;
  final bool shouldSkip;
  final String? skipReason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'candidate_id': candidateId,
    'root_key': rootKey,
    'entity_type': entityType,
    'preferred_name': preferredName,
    'aliases': aliases,
    'visual_signature_summary': visualSignatureSummary,
    'stable_visual_cues': stableVisualCues,
    'facts': facts.map((item) => item.toJson()).toList(growable: false),
    'confidence': confidence,
    'evidence_frames': evidenceFrames,
    'should_skip': shouldSkip,
    'skip_reason': skipReason,
  };

  factory MemoryVisualCandidate.fromJson(Map<String, dynamic> json) {
    final List<String> aliases = <String>[];
    final dynamic rawAliases = json['aliases'];
    if (rawAliases is List) {
      for (final dynamic raw in rawAliases) {
        final String text = (raw as String? ?? '').trim();
        if (text.isNotEmpty) aliases.add(text);
      }
    }
    final List<String> cues = <String>[];
    final dynamic rawCues = json['stable_visual_cues'];
    if (rawCues is List) {
      for (final dynamic raw in rawCues) {
        final String text = (raw as String? ?? '').trim();
        if (text.isNotEmpty) cues.add(text);
      }
    }
    final List<int> frames = <int>[];
    final dynamic rawFrames = json['evidence_frames'];
    if (rawFrames is List) {
      for (final dynamic raw in rawFrames) {
        if (raw is num) frames.add(raw.toInt());
      }
    }
    final List<MemoryEntityFactCandidate> facts = <MemoryEntityFactCandidate>[];
    final dynamic rawFacts = json['facts'];
    if (rawFacts is List) {
      for (final dynamic raw in rawFacts) {
        if (raw is Map) {
          facts.add(
            MemoryEntityFactCandidate.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      }
    }
    return MemoryVisualCandidate(
      candidateId: (json['candidate_id'] as String? ?? '').trim(),
      rootKey: (json['root_key'] as String? ?? '').trim(),
      entityType: (json['entity_type'] as String? ?? '').trim(),
      preferredName: (json['preferred_name'] as String? ?? '').trim(),
      aliases: aliases,
      visualSignatureSummary:
          (json['visual_signature_summary'] as String? ?? '').trim(),
      stableVisualCues: cues,
      facts: facts,
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      evidenceFrames: frames,
      shouldSkip: json['should_skip'] == true,
      skipReason: (json['skip_reason'] as String?)?.trim(),
    );
  }
}

class MemoryBatchExtractionResult {
  const MemoryBatchExtractionResult({
    required this.entities,
    this.modelUsed,
    this.rawPayload,
  });

  final List<MemoryVisualCandidate> entities;
  final String? modelUsed;
  final String? rawPayload;
}

class MemoryEntityExemplar {
  const MemoryEntityExemplar({
    this.sampleId,
    required this.filePath,
    this.captureTime,
    this.appName,
    this.positionIndex,
    this.rank,
    this.reason,
  });

  final int? sampleId;
  final String filePath;
  final int? captureTime;
  final String? appName;
  final int? positionIndex;
  final int? rank;
  final String? reason;

  Map<String, dynamic> toJson({bool includeFilePath = true}) =>
      <String, dynamic>{
        'sample_id': sampleId,
        if (includeFilePath) 'file_path': filePath,
        'capture_time': captureTime,
        'app_name': appName,
        'position_index': positionIndex,
        'rank': rank,
        'reason': reason,
      };

  factory MemoryEntityExemplar.fromMap(Map<String, dynamic> map) {
    int? toNullableInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    return MemoryEntityExemplar(
      sampleId: toNullableInt(map['sample_id'] ?? map['id']),
      filePath: (map['file_path'] ?? '').toString().trim(),
      captureTime: toNullableInt(map['capture_time']),
      appName: (map['app_name'] as String?)?.trim(),
      positionIndex: toNullableInt(map['position_index']),
      rank: toNullableInt(map['rank']),
      reason: (map['reason'] as String?)?.trim(),
    );
  }
}

class MemoryEntityClaimSnapshot {
  const MemoryEntityClaimSnapshot({
    required this.claimId,
    required this.factType,
    required this.value,
    required this.cardinality,
    required this.confidence,
    this.slotKey,
    this.active = true,
    this.evidenceFrames = const <int>[],
    this.sourceBatchId,
    this.status = 'active',
    this.validFrom,
    this.validTo,
  });

  final String claimId;
  final String factType;
  final String? slotKey;
  final String value;
  final MemoryEntityCardinality cardinality;
  final double confidence;
  final bool active;
  final List<int> evidenceFrames;
  final String? sourceBatchId;
  final String status;
  final int? validFrom;
  final int? validTo;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'claim_id': claimId,
    'fact_type': factType,
    'slot_key': slotKey,
    'value': value,
    'cardinality': cardinality.wireName,
    'confidence': confidence,
    'active': active,
    'status': status,
    'valid_from': validFrom,
    'valid_to': validTo,
    'evidence_frames': evidenceFrames,
    'source_batch_id': sourceBatchId,
  };

  factory MemoryEntityClaimSnapshot.fromMap(Map<String, dynamic> map) {
    int toInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    List<int> readFrames(Object? raw) {
      if (raw is List) {
        return raw
            .whereType<num>()
            .map((item) => item.toInt())
            .toList(growable: false);
      }
      final String text = (raw ?? '').toString().trim();
      if (text.isEmpty) return const <int>[];
      try {
        final dynamic decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded
              .whereType<num>()
              .map((item) => item.toInt())
              .toList(growable: false);
        }
      } catch (_) {}
      return const <int>[];
    }

    return MemoryEntityClaimSnapshot(
      claimId: (map['claim_id'] ?? map['id'] ?? '').toString().trim(),
      factType: (map['fact_type'] ?? '').toString().trim(),
      slotKey: (map['slot_key'] as String?)?.trim(),
      value: (map['value_text'] ?? map['value'] ?? '').toString().trim(),
      cardinality: MemoryEntityCardinality.fromWire(
        (map['cardinality'] ?? '').toString(),
      ),
      confidence: ((map['confidence'] as num?) ?? 0).toDouble(),
      active: toInt(map['active']) > 0 || map['active'] == true,
      status:
          (map['status'] ?? (toInt(map['active']) > 0 ? 'active' : 'inactive'))
              .toString()
              .trim(),
      validFrom: toInt(map['valid_from']) > 0 ? toInt(map['valid_from']) : null,
      validTo: toInt(map['valid_to']) > 0 ? toInt(map['valid_to']) : null,
      evidenceFrames: readFrames(
        map['evidence_frames_json'] ?? map['evidence_frames'],
      ),
      sourceBatchId: (map['source_batch_id'] as String?)?.trim(),
    );
  }
}

class MemoryEntityEventSnapshot {
  const MemoryEntityEventSnapshot({
    required this.note,
    this.evidenceFrames = const <int>[],
    this.sourceBatchId,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String note;
  final List<int> evidenceFrames;
  final String? sourceBatchId;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'note': note,
    'evidence_frames': evidenceFrames,
    'source_batch_id': sourceBatchId,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory MemoryEntityEventSnapshot.fromMap(Map<String, dynamic> map) {
    int toInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    List<int> readFrames(Object? raw) {
      if (raw is List) {
        return raw
            .whereType<num>()
            .map((item) => item.toInt())
            .toList(growable: false);
      }
      final String text = (raw ?? '').toString().trim();
      if (text.isEmpty) return const <int>[];
      try {
        final dynamic decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded
              .whereType<num>()
              .map((item) => item.toInt())
              .toList(growable: false);
        }
      } catch (_) {}
      return const <int>[];
    }

    return MemoryEntityEventSnapshot(
      note: (map['note'] ?? map['event_note'] ?? '').toString().trim(),
      evidenceFrames: readFrames(
        map['evidence_frames_json'] ?? map['evidence_frames'],
      ),
      sourceBatchId: (map['source_batch_id'] as String?)?.trim(),
      createdAt: toInt(map['created_at']),
      updatedAt: toInt(map['updated_at']),
    );
  }
}

class MemoryEntitySearchCandidate {
  const MemoryEntitySearchCandidate({
    required this.entityId,
    required this.rootUri,
    required this.entityType,
    required this.preferredName,
    required this.canonicalKey,
    required this.displayUri,
    required this.currentSummary,
    required this.visualSignatureSummary,
    required this.status,
    required this.rawScore,
    required this.decayedScore,
    required this.distinctSegmentCount,
    required this.distinctDayCount,
    required this.strongSignalCount,
    required this.exemplarSampleIds,
    required this.aliases,
    this.lastEvidenceSummary,
  });

  final String entityId;
  final String rootUri;
  final String entityType;
  final String preferredName;
  final String canonicalKey;
  final String displayUri;
  final String currentSummary;
  final String visualSignatureSummary;
  final MemoryEntityStatus status;
  final double rawScore;
  final double decayedScore;
  final int distinctSegmentCount;
  final int distinctDayCount;
  final int strongSignalCount;
  final List<int> exemplarSampleIds;
  final List<String> aliases;
  final String? lastEvidenceSummary;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'entity_id': entityId,
    'root_uri': rootUri,
    'entity_type': entityType,
    'preferred_name': preferredName,
    'canonical_key': canonicalKey,
    'display_uri': displayUri,
    'current_summary': currentSummary,
    'visual_signature_summary': visualSignatureSummary,
    'status': status.wireName,
    'raw_score': rawScore,
    'decayed_score': decayedScore,
    'distinct_segment_count': distinctSegmentCount,
    'distinct_day_count': distinctDayCount,
    'strong_signal_count': strongSignalCount,
    'exemplar_sample_ids': exemplarSampleIds,
    'aliases': aliases,
    'last_evidence_summary': lastEvidenceSummary,
  };
}

class MemoryEntityDossier {
  const MemoryEntityDossier({
    required this.candidate,
    this.claims = const <MemoryEntityClaimSnapshot>[],
    this.exemplars = const <MemoryEntityExemplar>[],
    this.events = const <MemoryEntityEventSnapshot>[],
  });

  final MemoryEntitySearchCandidate candidate;
  final List<MemoryEntityClaimSnapshot> claims;
  final List<MemoryEntityExemplar> exemplars;
  final List<MemoryEntityEventSnapshot> events;

  String get entityId => candidate.entityId;

  Map<String, dynamic> toJson({bool includeFilePaths = false}) =>
      <String, dynamic>{
        ...candidate.toJson(),
        'claims': claims.map((item) => item.toJson()).toList(growable: false),
        'exemplars': exemplars
            .map((item) => item.toJson(includeFilePath: includeFilePaths))
            .toList(growable: false),
        'events': events.map((item) => item.toJson()).toList(growable: false),
      };
}

class MemoryStructuredDecisionResult<T> {
  const MemoryStructuredDecisionResult({
    required this.value,
    required this.inputJson,
    required this.outputJson,
    this.modelUsed,
  });

  final T value;
  final String inputJson;
  final String outputJson;
  final String? modelUsed;
}

class MemoryPipelineAuditEntry {
  const MemoryPipelineAuditEntry({
    required this.stage,
    required this.action,
    required this.confidence,
    required this.inputJson,
    required this.outputJson,
    required this.payloadJson,
    this.modelUsed,
  });

  final String stage;
  final String action;
  final double confidence;
  final String inputJson;
  final String outputJson;
  final String payloadJson;
  final String? modelUsed;
}

class MemoryEntityResolutionDecision {
  const MemoryEntityResolutionDecision({
    required this.action,
    required this.confidence,
    this.matchedEntityId,
    this.suggestedPreferredName,
    this.aliasesToAdd = const <String>[],
    this.reasons = const <String>[],
    this.conflicts = const <String>[],
    this.needsReview = false,
  });

  final MemoryEntityResolutionAction action;
  final double confidence;
  final String? matchedEntityId;
  final String? suggestedPreferredName;
  final List<String> aliasesToAdd;
  final List<String> reasons;
  final List<String> conflicts;
  final bool needsReview;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'decision': action.wireName,
    'confidence': confidence,
    'matched_entity_id': matchedEntityId,
    'suggested_preferred_name': suggestedPreferredName,
    'aliases_to_add': aliasesToAdd,
    'reasons': reasons,
    'conflicts': conflicts,
    'needs_review': needsReview,
  };

  factory MemoryEntityResolutionDecision.fromJson(Map<String, dynamic> json) {
    List<String> readStringList(Object? raw) {
      final List<String> out = <String>[];
      if (raw is List) {
        for (final dynamic item in raw) {
          final String text = (item as String? ?? '').trim();
          if (text.isNotEmpty) out.add(text);
        }
      }
      return out;
    }

    return MemoryEntityResolutionDecision(
      action: MemoryEntityResolutionAction.fromWire(
        (json['decision'] as String? ?? ''),
      ),
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      matchedEntityId: (json['matched_entity_id'] as String?)?.trim(),
      suggestedPreferredName: (json['suggested_preferred_name'] as String?)
          ?.trim(),
      aliasesToAdd: readStringList(json['aliases_to_add']),
      reasons: readStringList(json['reasons']),
      conflicts: readStringList(json['conflicts']),
      needsReview: json['needs_review'] == true,
    );
  }
}

class MemoryEntityMergePlan {
  const MemoryEntityMergePlan({
    required this.preferredName,
    required this.summaryRewrite,
    required this.visualSignatureSummary,
    required this.claimsToUpsert,
    required this.eventsToAppend,
    this.aliasesToAdd = const <String>[],
    this.notes,
  });

  final String preferredName;
  final List<String> aliasesToAdd;
  final String summaryRewrite;
  final String visualSignatureSummary;
  final List<MemoryEntityFactCandidate> claimsToUpsert;
  final List<MemoryEntityEventCandidate> eventsToAppend;
  final String? notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'preferred_name': preferredName,
    'aliases_to_add': aliasesToAdd,
    'summary_rewrite': summaryRewrite,
    'visual_signature_summary': visualSignatureSummary,
    'claims_to_upsert': claimsToUpsert
        .map((item) => item.toJson())
        .toList(growable: false),
    'events_to_append': eventsToAppend
        .map((item) => item.toJson())
        .toList(growable: false),
    'notes': notes,
  };

  factory MemoryEntityMergePlan.fromJson(Map<String, dynamic> json) {
    final List<String> aliases = <String>[];
    final dynamic rawAliases = json['aliases_to_add'];
    if (rawAliases is List) {
      for (final dynamic raw in rawAliases) {
        final String text = (raw as String? ?? '').trim();
        if (text.isNotEmpty) aliases.add(text);
      }
    }
    final List<MemoryEntityEventCandidate> events =
        <MemoryEntityEventCandidate>[];
    final dynamic rawStructuredEvents = json['events_to_append'];
    if (rawStructuredEvents is List) {
      for (final dynamic raw in rawStructuredEvents) {
        if (raw is! Map) continue;
        final MemoryEntityEventCandidate event =
            MemoryEntityEventCandidate.fromJson(Map<String, dynamic>.from(raw));
        if (event.note.isNotEmpty) {
          events.add(event);
        }
      }
    }
    if (events.isEmpty) {
      final dynamic rawLegacyEvents = json['event_notes'];
      if (rawLegacyEvents is List) {
        for (final dynamic raw in rawLegacyEvents) {
          final String text = (raw as String? ?? '').trim();
          if (text.isNotEmpty) {
            events.add(MemoryEntityEventCandidate(note: text));
          }
        }
      }
    }
    final List<MemoryEntityFactCandidate> claims =
        <MemoryEntityFactCandidate>[];
    final dynamic rawClaims = json['claims_to_upsert'];
    if (rawClaims is List) {
      for (final dynamic raw in rawClaims) {
        if (raw is Map) {
          claims.add(
            MemoryEntityFactCandidate.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      }
    }
    return MemoryEntityMergePlan(
      preferredName: (json['preferred_name'] as String? ?? '').trim(),
      aliasesToAdd: aliases,
      summaryRewrite: (json['summary_rewrite'] as String? ?? '').trim(),
      visualSignatureSummary:
          (json['visual_signature_summary'] as String? ?? '').trim(),
      claimsToUpsert: claims,
      eventsToAppend: events,
      notes: (json['notes'] as String?)?.trim(),
    );
  }
}

class MemoryEntityResolutionWorkflowResult {
  const MemoryEntityResolutionWorkflowResult({
    required this.finalResult,
    this.auditTrail = const <MemoryPipelineAuditEntry>[],
  });

  final MemoryStructuredDecisionResult<MemoryEntityResolutionDecision>
  finalResult;
  final List<MemoryPipelineAuditEntry> auditTrail;
}

class MemoryEntityAuditDecision {
  const MemoryEntityAuditDecision({
    required this.action,
    required this.confidence,
    this.suggestedEntityId,
    this.reasons = const <String>[],
    this.notes,
  });

  final MemoryEntityAuditAction action;
  final double confidence;
  final String? suggestedEntityId;
  final List<String> reasons;
  final String? notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'action': action.wireName,
    'confidence': confidence,
    'suggested_entity_id': suggestedEntityId,
    'reasons': reasons,
    'notes': notes,
  };

  factory MemoryEntityAuditDecision.fromJson(Map<String, dynamic> json) {
    final List<String> reasons = <String>[];
    final dynamic rawReasons = json['reasons'];
    if (rawReasons is List) {
      for (final dynamic raw in rawReasons) {
        final String text = (raw as String? ?? '').trim();
        if (text.isNotEmpty) reasons.add(text);
      }
    }
    return MemoryEntityAuditDecision(
      action: MemoryEntityAuditAction.fromWire(
        (json['action'] as String? ?? ''),
      ),
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      suggestedEntityId: (json['suggested_entity_id'] as String?)?.trim(),
      reasons: reasons,
      notes: (json['notes'] as String?)?.trim(),
    );
  }
}

class MemoryEntityReviewQueueItem {
  const MemoryEntityReviewQueueItem({
    required this.id,
    required this.candidateId,
    required this.rootUri,
    required this.entityType,
    required this.preferredName,
    required this.segmentId,
    required this.batchIndex,
    required this.reviewStage,
    required this.reviewReason,
    required this.status,
    required this.candidateJson,
    required this.shortlistJson,
    required this.resolutionJson,
    required this.mergePlanJson,
    required this.auditJson,
    this.suggestedEntityId,
    this.evidenceSummary,
    this.appNames = const <String>[],
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final int id;
  final String candidateId;
  final String rootUri;
  final String entityType;
  final String preferredName;
  final int segmentId;
  final int batchIndex;
  final String reviewStage;
  final String reviewReason;
  final String? suggestedEntityId;
  final MemoryEntityReviewStatus status;
  final String candidateJson;
  final String shortlistJson;
  final String resolutionJson;
  final String mergePlanJson;
  final String auditJson;
  final String? evidenceSummary;
  final List<String> appNames;
  final int createdAt;
  final int updatedAt;

  factory MemoryEntityReviewQueueItem.fromMap(Map<String, Object?> map) {
    int toInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final List<String> apps = <String>[];
    final String rawApps = (map['app_names_json'] ?? '').toString().trim();
    if (rawApps.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawApps);
        if (decoded is List) {
          for (final dynamic item in decoded) {
            final String text = (item as String? ?? '').trim();
            if (text.isNotEmpty) apps.add(text);
          }
        }
      } catch (_) {}
    }

    return MemoryEntityReviewQueueItem(
      id: toInt(map['id']),
      candidateId: (map['candidate_id'] ?? '').toString().trim(),
      rootUri: (map['root_uri'] ?? '').toString().trim(),
      entityType: (map['entity_type'] ?? '').toString().trim(),
      preferredName: (map['preferred_name'] ?? '').toString().trim(),
      segmentId: toInt(map['segment_id']),
      batchIndex: toInt(map['batch_index']),
      reviewStage: (map['review_stage'] ?? '').toString().trim(),
      reviewReason: (map['review_reason'] ?? '').toString().trim(),
      suggestedEntityId: (map['suggested_entity_id'] as String?)?.trim(),
      status: MemoryEntityReviewStatus.fromWire(
        (map['status'] ?? '').toString(),
      ),
      candidateJson: (map['candidate_json'] ?? '').toString(),
      shortlistJson: (map['shortlist_json'] ?? '').toString(),
      resolutionJson: (map['resolution_json'] ?? '').toString(),
      mergePlanJson: (map['merge_plan_json'] ?? '').toString(),
      auditJson: (map['audit_json'] ?? '').toString(),
      evidenceSummary: (map['evidence_summary'] as String?)?.trim(),
      appNames: apps,
      createdAt: toInt(map['created_at']),
      updatedAt: toInt(map['updated_at']),
    );
  }
}

class MemoryEntityRecord {
  const MemoryEntityRecord({
    required this.entityId,
    required this.rootUri,
    required this.entityType,
    required this.preferredName,
    required this.preferredNameNorm,
    required this.canonicalKey,
    required this.displayUri,
    required this.status,
    required this.currentSummary,
    required this.latestContent,
    required this.visualSignatureSummary,
    required this.rawScore,
    required this.decayedScore,
    required this.activationScore,
    required this.evidenceCount,
    required this.distinctSegmentCount,
    required this.distinctDayCount,
    required this.strongSignalCount,
    required this.minDistinctDays,
    required this.allowSingleStrongActivation,
    required this.allowRootMaterialization,
    required this.evidenceSatisfied,
    required this.readyToActivate,
    required this.rootMaterializationBlocked,
    required this.missingActivationScore,
    required this.missingDistinctDays,
    required this.needsReview,
    this.reviewReason,
    this.lifecycleStatus,
    this.firstSeenAt = 0,
    this.lastSeenAt = 0,
    this.activatedAt = 0,
    this.archivedAt = 0,
    this.lastMaterializedAt = 0,
    this.lastEvidenceSummary,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String entityId;
  final String rootUri;
  final String entityType;
  final String preferredName;
  final String preferredNameNorm;
  final String canonicalKey;
  final String displayUri;
  final MemoryEntityStatus status;
  final String currentSummary;
  final String latestContent;
  final String visualSignatureSummary;
  final double rawScore;
  final double decayedScore;
  final double activationScore;
  final int evidenceCount;
  final int distinctSegmentCount;
  final int distinctDayCount;
  final int strongSignalCount;
  final int minDistinctDays;
  final bool allowSingleStrongActivation;
  final bool allowRootMaterialization;
  final bool evidenceSatisfied;
  final bool readyToActivate;
  final bool rootMaterializationBlocked;
  final double missingActivationScore;
  final int missingDistinctDays;
  final bool needsReview;
  final String? reviewReason;
  final String? lifecycleStatus;
  final int firstSeenAt;
  final int lastSeenAt;
  final int activatedAt;
  final int archivedAt;
  final int lastMaterializedAt;
  final String? lastEvidenceSummary;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'entity_id': entityId,
    'root_uri': rootUri,
    'entity_type': entityType,
    'preferred_name': preferredName,
    'preferred_name_norm': preferredNameNorm,
    'canonical_key': canonicalKey,
    'display_uri': displayUri,
    'status': status.wireName,
    'current_summary': currentSummary,
    'latest_content': latestContent,
    'visual_signature_summary': visualSignatureSummary,
    'raw_score': rawScore,
    'decayed_score': decayedScore,
    'activation_score': activationScore,
    'evidence_count': evidenceCount,
    'distinct_segment_count': distinctSegmentCount,
    'distinct_day_count': distinctDayCount,
    'strong_signal_count': strongSignalCount,
    'min_distinct_days': minDistinctDays,
    'allow_single_strong_activation': allowSingleStrongActivation,
    'allow_root_materialization': allowRootMaterialization,
    'evidence_satisfied': evidenceSatisfied,
    'ready_to_activate': readyToActivate,
    'root_materialization_blocked': rootMaterializationBlocked,
    'missing_activation_score': missingActivationScore,
    'missing_distinct_days': missingDistinctDays,
    'needs_review': needsReview,
    'review_reason': reviewReason,
    'lifecycle_status': lifecycleStatus,
    'first_seen_at': firstSeenAt,
    'last_seen_at': lastSeenAt,
    'activated_at': activatedAt,
    'archived_at': archivedAt,
    'last_materialized_at': lastMaterializedAt,
    'last_evidence_summary': lastEvidenceSummary,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory MemoryEntityRecord.fromMap(Map<String, Object?> map) {
    int toInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    double toDouble(Object? value) {
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool toBool(Object? value) {
      final int raw = toInt(value);
      return raw > 0 || value == true;
    }

    return MemoryEntityRecord(
      entityId: (map['entity_id'] ?? '').toString(),
      rootUri: (map['root_uri'] ?? '').toString(),
      entityType: (map['entity_type'] ?? '').toString(),
      preferredName: (map['preferred_name'] ?? '').toString(),
      preferredNameNorm: (map['preferred_name_norm'] ?? '').toString(),
      canonicalKey: (map['canonical_key'] ?? '').toString(),
      displayUri: (map['display_uri'] ?? map['uri'] ?? '').toString(),
      status: MemoryEntityStatus.fromWire((map['status'] ?? '').toString()),
      currentSummary: (map['current_summary'] ?? '').toString(),
      latestContent: (map['latest_content'] ?? '').toString(),
      visualSignatureSummary: (map['visual_signature_summary'] ?? '')
          .toString(),
      rawScore: toDouble(map['raw_score']),
      decayedScore: toDouble(map['decayed_score']),
      activationScore: toDouble(map['activation_score']),
      evidenceCount: toInt(map['evidence_count']),
      distinctSegmentCount: toInt(map['distinct_segment_count']),
      distinctDayCount: toInt(map['distinct_day_count']),
      strongSignalCount: toInt(map['strong_signal_count']),
      minDistinctDays: toInt(map['min_distinct_days']),
      allowSingleStrongActivation: toBool(
        map['allow_single_strong_activation'],
      ),
      allowRootMaterialization: toBool(map['allow_root_materialization']),
      evidenceSatisfied: toBool(map['evidence_satisfied']),
      readyToActivate: toBool(map['ready_to_activate']),
      rootMaterializationBlocked: toBool(map['root_materialization_blocked']),
      missingActivationScore: toDouble(map['missing_activation_score']),
      missingDistinctDays: toInt(map['missing_distinct_days']),
      needsReview: toBool(map['needs_review']),
      reviewReason: (map['review_reason'] as String?)?.trim(),
      lifecycleStatus: (map['lifecycle_status'] as String?)?.trim(),
      firstSeenAt: toInt(map['first_seen_at']),
      lastSeenAt: toInt(map['last_seen_at']),
      activatedAt: toInt(map['activated_at']),
      archivedAt: toInt(map['archived_at']),
      lastMaterializedAt: toInt(map['last_materialized_at']),
      lastEvidenceSummary: (map['last_evidence_summary'] as String?)?.trim(),
      createdAt: toInt(map['created_at']),
      updatedAt: toInt(map['updated_at']),
    );
  }
}

class MemoryEntityApplyResult {
  const MemoryEntityApplyResult({
    this.record,
    required this.created,
    required this.needsReview,
    this.queuedForReview = false,
    this.reviewReason,
  });

  final MemoryEntityRecord? record;
  final bool created;
  final bool needsReview;
  final bool queuedForReview;
  final String? reviewReason;
}

class MemoryEntityPipelineBatchRun {
  const MemoryEntityPipelineBatchRun({
    required this.segmentId,
    required this.batchIndex,
    required this.status,
    required this.sampleCount,
    required this.candidateCount,
    required this.appliedCount,
    required this.reviewCount,
    required this.skippedCount,
    this.modelName,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final int segmentId;
  final int batchIndex;
  final String status;
  final int sampleCount;
  final int candidateCount;
  final int appliedCount;
  final int reviewCount;
  final int skippedCount;
  final String? modelName;
  final int createdAt;
  final int updatedAt;

  factory MemoryEntityPipelineBatchRun.fromMap(Map<String, Object?> map) {
    int toInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return MemoryEntityPipelineBatchRun(
      segmentId: toInt(map['segment_id']),
      batchIndex: toInt(map['batch_index']),
      status: (map['status'] ?? '').toString().trim(),
      sampleCount: toInt(map['sample_count']),
      candidateCount: toInt(map['candidate_count']),
      appliedCount: toInt(map['applied_count']),
      reviewCount: toInt(map['review_count']),
      skippedCount: toInt(map['skipped_count']),
      modelName: (map['model_name'] as String?)?.trim(),
      createdAt: toInt(map['created_at']),
      updatedAt: toInt(map['updated_at']),
    );
  }
}

class MemoryEntityQualityMetrics {
  const MemoryEntityQualityMetrics({
    required this.createdNewCount,
    required this.matchedExistingCount,
    required this.reviewQueuedCount,
    required this.duplicateBlockCount,
    required this.ambiguousBlockCount,
    required this.lowEvidenceBlockCount,
    required this.totalBatchCount,
    required this.emptyBatchCount,
    required this.emptyBatchRate,
    required this.duplicateClusterCount,
    required this.materializedNodeCount,
    required this.materializedEntityCount,
    required this.materializationDrift,
    required this.manualReviewApprovedCount,
  });

  final int createdNewCount;
  final int matchedExistingCount;
  final int reviewQueuedCount;
  final int duplicateBlockCount;
  final int ambiguousBlockCount;
  final int lowEvidenceBlockCount;
  final int totalBatchCount;
  final int emptyBatchCount;
  final double emptyBatchRate;
  final int duplicateClusterCount;
  final int materializedNodeCount;
  final int materializedEntityCount;
  final int materializationDrift;
  final int manualReviewApprovedCount;
}

String encodeJsonPretty(Map<String, dynamic> value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}
