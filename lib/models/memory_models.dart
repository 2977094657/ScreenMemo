import 'dart:collection';

class MemorySnapshot {
  MemorySnapshot({
    required List<MemoryTag> pendingTags,
    required List<MemoryTag> confirmedTags,
    required List<MemoryEventSummary> recentEvents,
    int? pendingTotalCount,
    int? confirmedTotalCount,
    int? recentEventTotalCount,
    this.lastUpdatedAt,
    this.personaSummary = '',
  })  : pendingTags = _unmodifiableTags(pendingTags),
        confirmedTags = _unmodifiableTags(confirmedTags),
        recentEvents = _unmodifiableEvents(recentEvents),
        pendingTotalCount = pendingTotalCount ?? pendingTags.length,
        confirmedTotalCount = confirmedTotalCount ?? confirmedTags.length,
        recentEventTotalCount = recentEventTotalCount ?? recentEvents.length;

  final List<MemoryTag> pendingTags;
  final List<MemoryTag> confirmedTags;
  final List<MemoryEventSummary> recentEvents;
  final int pendingTotalCount;
  final int confirmedTotalCount;
  final int recentEventTotalCount;
  final DateTime? lastUpdatedAt;
  final String personaSummary;

  MemorySnapshot copyWith({
    List<MemoryTag>? pendingTags,
    List<MemoryTag>? confirmedTags,
    List<MemoryEventSummary>? recentEvents,
    int? pendingTotalCount,
    int? confirmedTotalCount,
    int? recentEventTotalCount,
    DateTime? lastUpdatedAt,
    String? personaSummary,
  }) {
    final List<MemoryTag> nextPending =
        _unmodifiableTags(pendingTags ?? this.pendingTags);
    final List<MemoryTag> nextConfirmed =
        _unmodifiableTags(confirmedTags ?? this.confirmedTags);
    final List<MemoryEventSummary> nextEvents =
        _unmodifiableEvents(recentEvents ?? this.recentEvents);
    return MemorySnapshot(
      pendingTags: nextPending,
      confirmedTags: nextConfirmed,
      recentEvents: nextEvents,
      pendingTotalCount: pendingTotalCount ?? this.pendingTotalCount,
      confirmedTotalCount: confirmedTotalCount ?? this.confirmedTotalCount,
      recentEventTotalCount: recentEventTotalCount ?? this.recentEventTotalCount,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      personaSummary: personaSummary ?? this.personaSummary,
    );
  }

  MemorySnapshot mergeTag(MemoryTag tag) {
    final List<MemoryTag> pending = List<MemoryTag>.from(pendingTags);
    final List<MemoryTag> confirmed = List<MemoryTag>.from(confirmedTags);
    pending.removeWhere((element) => element.id == tag.id);
    confirmed.removeWhere((element) => element.id == tag.id);
    if (tag.isConfirmed) {
      confirmed.insert(0, tag);
    } else {
      pending.insert(0, tag);
    }
    return copyWith(
      pendingTags: pending,
      confirmedTags: confirmed,
      lastUpdatedAt: tag.lastSeenAt ?? lastUpdatedAt,
      personaSummary: personaSummary,
    );
  }

  static MemorySnapshot fromMap(Map<String, dynamic> map) {
    final List<dynamic> pendingRaw = (map['pendingTags'] as List?) ?? const [];
    final List<dynamic> confirmedRaw = (map['confirmedTags'] as List?) ?? const [];
    final List<dynamic> eventsRaw = (map['recentEvents'] as List?) ?? const [];
    final List<MemoryTag> pending = pendingRaw
        .whereType<Map>()
        .map((e) => MemoryTag.fromMap(_asStringMap(e)))
        .toList(growable: false);
    final List<MemoryTag> confirmed = confirmedRaw
        .whereType<Map>()
        .map((e) => MemoryTag.fromMap(_asStringMap(e)))
        .toList(growable: false);
    final List<MemoryEventSummary> events = eventsRaw
        .whereType<Map>()
        .map((e) => MemoryEventSummary.fromMap(_asStringMap(e)))
        .toList(growable: false);
    final DateTime? updated = _toDateTime(map['lastUpdatedAt']);
    final int pendingTotal =
        (map['pendingTotalCount'] as num?)?.toInt() ?? pending.length;
    final int confirmedTotal =
        (map['confirmedTotalCount'] as num?)?.toInt() ?? confirmed.length;
    final int eventTotal =
        (map['recentEventTotalCount'] as num?)?.toInt() ?? events.length;
    final String personaSummary =
        (map['personaSummary'] as String?)?.trim() ?? '';
    return MemorySnapshot(
      pendingTags: pending,
      confirmedTags: confirmed,
      recentEvents: events,
      pendingTotalCount: pendingTotal,
      confirmedTotalCount: confirmedTotal,
      recentEventTotalCount: eventTotal,
      lastUpdatedAt: updated,
      personaSummary: personaSummary,
    );
  }

  static List<MemoryTag> _unmodifiableTags(List<MemoryTag> input) =>
      List<MemoryTag>.unmodifiable(input);

  static List<MemoryEventSummary> _unmodifiableEvents(List<MemoryEventSummary> input) =>
      List<MemoryEventSummary>.unmodifiable(input);
}

class MemoryTag {
  const MemoryTag({
    required this.id,
    required this.tagKey,
    required this.label,
    required this.level1,
    required this.level2,
    required this.level3,
    required this.level4,
    required this.fullPath,
    required this.category,
    required this.status,
    required this.occurrences,
    required this.confidence,
    this.firstSeenAt,
    this.lastSeenAt,
    this.autoConfirmedAt,
    this.manualConfirmedAt,
    this.evidences = const <TagEvidence>[],
    this.evidenceTotalCount = 0,
  });

  final int id;
  final String tagKey;
  final String label;
  final String level1;
  final String level2;
  final String level3;
  final String level4;
  final String fullPath;
  final String category;
  final String status;
  final int occurrences;
  final double confidence;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final DateTime? autoConfirmedAt;
  final DateTime? manualConfirmedAt;
  final List<TagEvidence> evidences;
  final int evidenceTotalCount;

  bool get isConfirmed => status == MemoryTagStatus.confirmed;

  MemoryTag copyWith({
    String? label,
    String? level1,
    String? level2,
    String? level3,
    String? level4,
    String? fullPath,
    String? category,
    String? status,
    int? occurrences,
    double? confidence,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    DateTime? autoConfirmedAt,
    DateTime? manualConfirmedAt,
    List<TagEvidence>? evidences,
    int? evidenceTotalCount,
  }) {
    return MemoryTag(
      id: id,
      tagKey: tagKey,
      label: label ?? this.label,
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
      level4: level4 ?? this.level4,
      fullPath: fullPath ?? this.fullPath,
      category: category ?? this.category,
      status: status ?? this.status,
      occurrences: occurrences ?? this.occurrences,
      confidence: confidence ?? this.confidence,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      autoConfirmedAt: autoConfirmedAt ?? this.autoConfirmedAt,
      manualConfirmedAt: manualConfirmedAt ?? this.manualConfirmedAt,
      evidences: List<TagEvidence>.unmodifiable(evidences ?? this.evidences),
      evidenceTotalCount: evidenceTotalCount ?? this.evidenceTotalCount,
    );
  }

  static MemoryTag fromMap(Map<String, dynamic> map) {
    final List<dynamic> evidenceRaw = (map['evidences'] as List?) ?? const [];
    final List<TagEvidence> evidence = evidenceRaw
        .whereType<Map>()
        .map((e) => TagEvidence.fromMap(_asStringMap(e)))
        .toList(growable: false);
    final int totalCount =
        (map['evidenceTotalCount'] as num?)?.toInt() ?? evidence.length;
    final String fullPathRaw = (map['fullPath'] as String?)?.trim() ?? (map['label'] as String?)?.trim() ?? '';
    final String level1Raw = (map['level1'] as String?)?.trim() ?? '';
    final String level2Raw = (map['level2'] as String?)?.trim() ?? '';
    final String level3Raw = (map['level3'] as String?)?.trim() ?? '';
    final String level4Raw = (map['level4'] as String?)?.trim() ?? '';
    final _HierarchySegments segments = _HierarchySegments.resolve(
      level1: level1Raw,
      level2: level2Raw,
      level3: level3Raw,
      level4: level4Raw,
      fallback: fullPathRaw,
    );
    return MemoryTag(
      id: _toInt(map['id']) ?? 0,
      tagKey: (map['tagKey'] as String?) ?? '',
      label: segments.fullPath,
      level1: segments.level1,
      level2: segments.level2,
      level3: segments.level3,
      level4: segments.level4,
      fullPath: segments.fullPath,
      category: (map['category'] as String?) ?? MemoryTagCategory.other,
      status: (map['status'] as String?) ?? MemoryTagStatus.pending,
      occurrences: _toInt(map['occurrences']) ?? 0,
      confidence: _toDouble(map['confidence']) ?? 0.0,
      firstSeenAt: _toDateTime(map['firstSeenAt']),
      lastSeenAt: _toDateTime(map['lastSeenAt']),
      autoConfirmedAt: _toDateTime(map['autoConfirmedAt']),
      manualConfirmedAt: _toDateTime(map['manualConfirmedAt']),
      evidences: List<TagEvidence>.unmodifiable(evidence),
      evidenceTotalCount: totalCount,
    );
  }
}

class _HierarchySegments {
  const _HierarchySegments({
    required this.level1,
    required this.level2,
    required this.level3,
    required this.level4,
    required this.fullPath,
  });

  final String level1;
  final String level2;
  final String level3;
  final String level4;
  final String fullPath;

  static _HierarchySegments resolve({
    required String level1,
    required String level2,
    required String level3,
    required String level4,
    required String fallback,
  }) {
    final List<String> normalized = <String>[level1, level2, level3, level4]
        .map((e) => e.trim())
        .toList(growable: false);
    final bool hasAll = normalized.every((element) => element.isNotEmpty);
    if (hasAll) {
      return _HierarchySegments(
        level1: normalized[0],
        level2: normalized[1],
        level3: normalized[2],
        level4: normalized[3],
        fullPath: normalized.join(' / '),
      );
    }

    final String effectiveFallback = fallback.trim();
    final List<String> fallbackParts = effectiveFallback.isEmpty
        ? const <String>[]
        : effectiveFallback.split(RegExp(r'[\/／\|｜]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final List<String> merged = <String>[
      normalized[0].isNotEmpty ? normalized[0] : (fallbackParts.isNotEmpty ? fallbackParts[0] : '待分类'),
      normalized[1].isNotEmpty ? normalized[1] : (fallbackParts.length > 1 ? fallbackParts[1] : '未分组'),
      normalized[2].isNotEmpty ? normalized[2] : (fallbackParts.length > 2 ? fallbackParts[2] : '未知专题'),
      normalized[3].isNotEmpty
          ? normalized[3]
          : (fallbackParts.length > 3
              ? fallbackParts[3]
              : (effectiveFallback.isEmpty ? '未命名标签' : effectiveFallback)),
    ];

    final String resolvedFullPath = merged.join(' / ').trim();

    return _HierarchySegments(
      level1: merged[0],
      level2: merged[1],
      level3: merged[2],
      level4: merged[3],
      fullPath: resolvedFullPath.isEmpty ? effectiveFallback : resolvedFullPath,
    );
  }
}

class TagEvidence {
  const TagEvidence({
    required this.id,
    required this.tagId,
    required this.eventId,
    required this.excerpt,
    required this.confidence,
    required this.createdAt,
    required this.lastModifiedAt,
    required this.isUserEdited,
    this.notes,
  });

  final int id;
  final int tagId;
  final int eventId;
  final String excerpt;
  final double confidence;
  final DateTime? createdAt;
  final DateTime? lastModifiedAt;
  final bool isUserEdited;
  final String? notes;

  static TagEvidence fromMap(Map<String, dynamic> map) {
    return TagEvidence(
      id: _toInt(map['id']) ?? 0,
      tagId: _toInt(map['tagId']) ?? 0,
      eventId: _toInt(map['eventId']) ?? 0,
      excerpt: (map['excerpt'] as String?) ?? '',
      confidence: _toDouble(map['confidence']) ?? 0.0,
      createdAt: _toDateTime(map['createdAt']),
      lastModifiedAt: _toDateTime(map['lastModifiedAt']),
      isUserEdited: _toBool(map['isUserEdited']),
      notes: map['notes'] as String?,
    );
  }
}

class MemoryEventSummary {
  const MemoryEventSummary({
    required this.id,
    this.externalId,
    required this.occurredAt,
    required this.type,
    required this.source,
    required this.content,
    required this.containsUserContext,
    this.relatedTagIds = const <int>[],
  });

  final int id;
  final String? externalId;
  final DateTime occurredAt;
  final String type;
  final String source;
  final String content;
  final bool containsUserContext;
  final List<int> relatedTagIds;

  static MemoryEventSummary fromMap(Map<String, dynamic> map) {
    final List<int> related = ((map['relatedTagIds'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList(growable: false);
    return MemoryEventSummary(
      id: _toInt(map['id']) ?? 0,
      externalId: map['externalId'] as String?,
      occurredAt: _toDateTime(map['occurredAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      type: (map['type'] as String?) ?? '',
      source: (map['source'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      containsUserContext: _toBool(map['containsUserContext']),
      relatedTagIds: List<int>.unmodifiable(related),
    );
  }
}

abstract class MemoryProgressState {
  const MemoryProgressState();
}

class MemoryProgressIdle extends MemoryProgressState {
  const MemoryProgressIdle();
}

class MemoryProgressRunning extends MemoryProgressState {
  const MemoryProgressRunning({
    required this.processedCount,
    required this.totalCount,
    required this.progress,
    this.currentEventId,
    this.currentEventExternalId,
    this.currentEventType,
    this.newlyDiscoveredTags = const <String>[],
  });

  final int processedCount;
  final int totalCount;
  final double progress;
  final int? currentEventId;
  final String? currentEventExternalId;
  final String? currentEventType;
  final List<String> newlyDiscoveredTags;

  double get safeProgress {
    if (totalCount <= 0) {
      return progress.clamp(0.0, 1.0);
    }
    if (progress > 0) {
      return progress.clamp(0.0, 1.0);
    }
    return (processedCount / totalCount).clamp(0.0, 1.0);
  }
}

class MemoryProgressCompleted extends MemoryProgressState {
  const MemoryProgressCompleted({
    required this.totalCount,
    required this.duration,
  });

  final int totalCount;
  final Duration duration;
}

class MemoryProgressFailed extends MemoryProgressState {
  const MemoryProgressFailed({
    required this.processedCount,
    required this.totalCount,
    required this.errorMessage,
    this.rawResponse,
    this.failureCode,
    this.failedEventExternalId,
  });

  final int processedCount;
  final int totalCount;
  final String errorMessage;
  final String? rawResponse;
  final String? failureCode;
  final String? failedEventExternalId;
}

class MemoryTagUpdate {
  const MemoryTagUpdate({
    required this.tag,
    required this.isNewTag,
    required this.statusChanged,
  });

  final MemoryTag tag;
  final bool isNewTag;
  final bool statusChanged;
}

class MemoryTagStatus {
  static const String pending = 'pending';
  static const String confirmed = 'confirmed';
}

class MemoryTagCategory {
  static const String identity = 'identity';
  static const String relationship = 'relationship';
  static const String interest = 'interest';
  static const String behavior = 'behavior';
  static const String preference = 'preference';
  static const String other = 'other';
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

bool _toBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase();
    return lower == 'true' || lower == '1';
  }
  return false;
}

DateTime? _toDateTime(dynamic value) {
  final int? millis = _toInt(value);
  if (millis == null || millis <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: false).toLocal();
}

Map<String, dynamic> _asStringMap(Map<dynamic, dynamic> map) {
  final HashMap<String, dynamic> result = HashMap<String, dynamic>();
  map.forEach((dynamic key, dynamic value) {
    if (key != null) {
      result[key.toString()] = value;
    }
  });
  return result;
}

