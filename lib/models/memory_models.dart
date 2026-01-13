import 'dart:collection';
import 'dart:convert';

class MemorySnapshot {
  MemorySnapshot({
    required List<MemoryEventSummary> recentEvents,
    int? recentEventTotalCount,
    this.lastUpdatedAt,
    this.personaSummary = '',
    PersonaProfile? personaProfile,
  }) : recentEvents = _unmodifiableEvents(recentEvents),
       recentEventTotalCount = recentEventTotalCount ?? recentEvents.length,
       personaProfile = personaProfile ?? PersonaProfile.empty();

  final List<MemoryEventSummary> recentEvents;
  final int recentEventTotalCount;
  final DateTime? lastUpdatedAt;
  final String personaSummary;
  final PersonaProfile personaProfile;

  MemorySnapshot copyWith({
    List<MemoryEventSummary>? recentEvents,
    int? recentEventTotalCount,
    DateTime? lastUpdatedAt,
    String? personaSummary,
    PersonaProfile? personaProfile,
  }) {
    final List<MemoryEventSummary> nextEvents = _unmodifiableEvents(
      recentEvents ?? this.recentEvents,
    );
    return MemorySnapshot(
      recentEvents: nextEvents,
      recentEventTotalCount:
          recentEventTotalCount ?? this.recentEventTotalCount,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      personaSummary: personaSummary ?? this.personaSummary,
      personaProfile: personaProfile ?? this.personaProfile,
    );
  }

  static MemorySnapshot fromMap(Map<String, dynamic> map) {
    final List<dynamic> eventsRaw = (map['recentEvents'] as List?) ?? const [];
    final List<MemoryEventSummary> events = eventsRaw
        .whereType<Map>()
        .map((e) => MemoryEventSummary.fromMap(_asStringMap(e)))
        .toList(growable: false);
    final DateTime? updated = _toDateTime(map['lastUpdatedAt']);
    final int eventTotal =
        (map['recentEventTotalCount'] as num?)?.toInt() ?? events.length;
    final String personaSummary =
        (map['personaSummary'] as String?)?.trim() ?? '';
    final dynamic personaProfileRaw = map['personaProfile'];
    final PersonaProfile personaProfile = personaProfileRaw is Map
        ? PersonaProfile.fromMap(
            Map<String, dynamic>.from(personaProfileRaw as Map),
          )
        : PersonaProfile.empty();
    return MemorySnapshot(
      recentEvents: events,
      recentEventTotalCount: eventTotal,
      lastUpdatedAt: updated,
      personaSummary: personaSummary,
      personaProfile: personaProfile,
    );
  }

  static List<MemoryEventSummary> _unmodifiableEvents(
    List<MemoryEventSummary> input,
  ) => List<MemoryEventSummary>.unmodifiable(input);
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
  });

  final int id;
  final String? externalId;
  final DateTime occurredAt;
  final String type;
  final String source;
  final String content;
  final bool containsUserContext;

  static MemoryEventSummary fromMap(Map<String, dynamic> map) {
    return MemoryEventSummary(
      id: _toInt(map['id']) ?? 0,
      externalId: map['externalId'] as String?,
      occurredAt:
          _toDateTime(map['occurredAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      type: (map['type'] as String?) ?? '',
      source: (map['source'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      containsUserContext: _toBool(map['containsUserContext']),
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
  });

  final int processedCount;
  final int totalCount;
  final double progress;
  final int? currentEventId;
  final String? currentEventExternalId;
  final String? currentEventType;

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

class PersonaProfile {
  const PersonaProfile({
    required this.title,
    required this.sections,
    required this.traits,
    required this.version,
    required this.lastUpdatedAt,
  });

  final String title;
  final List<PersonaSection> sections;
  final List<String> traits;
  final int version;
  final DateTime? lastUpdatedAt;

  factory PersonaProfile.empty() {
    return PersonaProfile(
      title: '### **正在构建的个人画像**',
      sections: const <PersonaSection>[],
      traits: const <String>[],
      version: 1,
      lastUpdatedAt: null,
    );
  }

  PersonaProfile copyWith({
    String? title,
    List<PersonaSection>? sections,
    List<String>? traits,
    int? version,
    DateTime? lastUpdatedAt,
  }) {
    return PersonaProfile(
      title: title?.trim().isNotEmpty == true ? title!.trim() : this.title,
      sections: List<PersonaSection>.unmodifiable(sections ?? this.sections),
      traits: List<String>.unmodifiable(traits ?? this.traits),
      version: version ?? this.version,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }

  static PersonaProfile fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return PersonaProfile.empty();
    }
    final PersonaProfile fallback = PersonaProfile.empty();
    final String title = (raw['title'] as String?)?.trim() ?? '';
    final int version = (raw['version'] as num?)?.toInt() ?? fallback.version;
    final DateTime? updatedAt = _toDateTime(raw['lastUpdatedAt']);

    final LinkedHashMap<String, PersonaSection> sectionMap =
        LinkedHashMap<String, PersonaSection>();
    final List<dynamic> sectionRaw = (raw['sections'] as List?) ?? const [];
    for (final Map<dynamic, dynamic> entry in sectionRaw.whereType<Map>()) {
      final PersonaSection? parsed = PersonaSection.tryFromMap(
        Map<String, dynamic>.from(entry),
      );
      if (parsed != null) {
        sectionMap[parsed.id] = parsed;
      }
    }
    final List<PersonaSection> sections = List<PersonaSection>.unmodifiable(
      sectionMap.values,
    );

    final List<String> traits = ((raw['traits'] as List?) ?? const [])
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    return PersonaProfile(
      title: title.isNotEmpty ? title : fallback.title,
      sections: sections,
      traits: List<String>.unmodifiable(traits),
      version: version,
      lastUpdatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'title': title,
      'version': version,
      'lastUpdatedAt': lastUpdatedAt?.millisecondsSinceEpoch,
      'sections': sections.map((e) => e.toMap()).toList(growable: false),
      'traits': traits,
    };
  }

  String toJsonString({bool pretty = false, int indent = 2}) {
    if (pretty) {
      final JsonEncoder encoder = JsonEncoder.withIndent(' ' * indent);
      return encoder.convert(toMap());
    }
    return jsonEncode(toMap());
  }

  String toPrettyJsonString([int indent = 2]) =>
      toJsonString(pretty: true, indent: indent);

  String toMarkdown() {
    final StringBuffer buffer = StringBuffer();
    if (title.trim().isNotEmpty) {
      buffer.writeln(title.trim());
      buffer.writeln();
    }
    for (final PersonaSection section in sections) {
      if (section.items.isEmpty) continue;
      if (section.title.trim().isNotEmpty) {
        buffer.writeln(section.title.trim());
        buffer.writeln();
      }
      for (final PersonaItem item in section.items) {
        final String heading = item.heading.trim();
        final String detail = item.detail.trim();
        if (heading.isEmpty && detail.isEmpty) continue;
        buffer.write(
          '*   **${item.slot}. ${heading.isEmpty ? item.slot : heading}**',
        );
        if (detail.isNotEmpty) {
          buffer.write(': $detail');
        }
        buffer.writeln();
      }
      buffer.writeln();
    }
    if (traits.isNotEmpty) {
      buffer.writeln('#### **用户核心特质总结**');
      buffer.writeln();
      for (final String trait in traits) {
        final String trimmed = trait.trim();
        if (trimmed.isEmpty) continue;
        buffer.writeln('* $trimmed');
      }
    }
    return buffer.toString().trim();
  }
}

class PersonaSection {
  const PersonaSection({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<PersonaItem> items;

  static List<PersonaSection> defaultSections() {
    return const <PersonaSection>[];
  }

  PersonaSection copyWith({String? title, List<PersonaItem>? items}) {
    return PersonaSection(
      id: id,
      title: title?.trim().isNotEmpty == true ? title!.trim() : this.title,
      items: List<PersonaItem>.unmodifiable(items ?? this.items),
    );
  }

  static PersonaSection? tryFromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final String? id = (raw['id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    final String title = (raw['title'] as String?)?.trim() ?? '';
    final List<PersonaItem> items = ((raw['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => PersonaItem.tryFromMap(Map<String, dynamic>.from(e)))
        .whereType<PersonaItem>()
        .toList(growable: false);
    return PersonaSection(
      id: id,
      title: title.isNotEmpty ? title : id,
      items: List<PersonaItem>.unmodifiable(items),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'items': items.map((e) => e.toMap()).toList(growable: false),
    };
  }
}

class PersonaItem {
  const PersonaItem({
    required this.slot,
    required this.heading,
    required this.detail,
  });

  final String slot;
  final String heading;
  final String detail;

  PersonaItem copyWith({String? heading, String? detail}) {
    return PersonaItem(
      slot: slot,
      heading: heading?.trim().isNotEmpty == true
          ? heading!.trim()
          : this.heading,
      detail: detail?.trim() ?? this.detail,
    );
  }

  static PersonaItem? tryFromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final String? slot = (raw['slot'] as String?)?.trim();
    final String? heading = (raw['heading'] as String?)?.trim();
    if (slot == null || slot.isEmpty || heading == null || heading.isEmpty) {
      return null;
    }
    final String detail = (raw['detail'] as String?)?.trim() ?? '';
    return PersonaItem(slot: slot, heading: heading, detail: detail);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'slot': slot,
      'heading': heading,
      'detail': detail,
    };
  }
}
