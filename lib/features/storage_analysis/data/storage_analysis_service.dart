import 'package:flutter/services.dart';

class StorageAnalysisService {
  StorageAnalysisService._();

  static const MethodChannel _channel = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  static Future<StorageAnalysisResult> fetch() async {
    final Map<String, dynamic>? raw = await _channel
        .invokeMapMethod<String, dynamic>('getDetailedStorageStats');
    if (raw == null) {
      throw StateError('storage_analysis_empty_result');
    }
    return StorageAnalysisResult.fromMap(raw);
  }
}

class StorageAnalysisResult {
  StorageAnalysisResult({
    required this.timestamp,
    required this.scanDurationMs,
    required this.hasUsageStatsPermission,
    required this.statsAvailable,
    required this.manualTotalBytes,
    required this.manualDataBytes,
    required this.manualCacheBytes,
    required this.manualExternalBytes,
    required this.nodes,
    required this.errors,
    this.totalBytes,
    this.appBytes,
    this.dataBytes,
    this.cacheBytes,
    this.storageUuid,
    this.externalBytes,
  });

  factory StorageAnalysisResult.fromMap(Map<String, dynamic> map) {
    int readInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? 0;
    }

    List<String> readErrors(dynamic value) {
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return const [];
    }

    final List<dynamic>? nodeList = map['nodes'] as List<dynamic>?;
    final List<StorageAnalysisNode> nodes = nodeList == null
        ? const []
        : nodeList
              .map(
                (e) => StorageAnalysisNode.fromMap(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();

    return StorageAnalysisResult(
      timestamp: readInt(map['timestamp']),
      scanDurationMs: readInt(map['scanDurationMs']),
      hasUsageStatsPermission: map['hasUsageStatsPermission'] == true,
      statsAvailable: map['statsAvailable'] == true,
      totalBytes: map.containsKey('totalBytes')
          ? readInt(map['totalBytes'])
          : null,
      appBytes: map.containsKey('appBytes') ? readInt(map['appBytes']) : null,
      dataBytes: map.containsKey('dataBytes')
          ? readInt(map['dataBytes'])
          : null,
      cacheBytes: map.containsKey('cacheBytes')
          ? readInt(map['cacheBytes'])
          : null,
      manualTotalBytes: readInt(map['manualTotalBytes']),
      manualDataBytes: readInt(map['manualDataBytes']),
      manualCacheBytes: readInt(map['manualCacheBytes']),
      manualExternalBytes: readInt(map['manualExternalBytes']),
      storageUuid: map['storageUuid']?.toString(),
      externalBytes: map.containsKey('externalBytes')
          ? readInt(map['externalBytes'])
          : null,
      nodes: nodes,
      errors: readErrors(map['errors']),
    );
  }

  final int timestamp;
  final int scanDurationMs;
  final bool hasUsageStatsPermission;
  final bool statsAvailable;

  final int manualTotalBytes;
  final int manualDataBytes;
  final int manualCacheBytes;
  final int manualExternalBytes;

  final int? totalBytes;
  final int? appBytes;
  final int? dataBytes;
  final int? cacheBytes;
  final int? externalBytes;
  final String? storageUuid;

  final List<StorageAnalysisNode> nodes;
  final List<String> errors;

  bool get hasSystemStats => hasUsageStatsPermission && statsAvailable;

  int get effectiveTotalBytes =>
      hasSystemStats ? (totalBytes ?? manualTotalBytes) : manualTotalBytes;

  int get effectiveDataBytes =>
      hasSystemStats ? (dataBytes ?? manualDataBytes) : manualDataBytes;

  int get effectiveCacheBytes =>
      hasSystemStats ? (cacheBytes ?? manualCacheBytes) : manualCacheBytes;

  int get effectiveAppBytes =>
      hasSystemStats ? (appBytes ?? 0) : (appBytes ?? 0);

  int get effectiveExternalBytes => externalBytes ?? manualExternalBytes;

  DateTime get timestampAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp);
}

class StorageAnalysisNode {
  StorageAnalysisNode({
    required this.id,
    required this.label,
    required this.bytes,
    required this.fileCount,
    required this.type,
    required this.children,
    this.path,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? const {};

  factory StorageAnalysisNode.fromMap(Map<String, dynamic> map) {
    List<dynamic>? rawChildren = map['children'] as List<dynamic>?;
    final children = rawChildren == null
        ? const <StorageAnalysisNode>[]
        : rawChildren
              .map(
                (child) => StorageAnalysisNode.fromMap(
                  Map<String, dynamic>.from(child as Map),
                ),
              )
              .toList();

    int readInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? 0;
    }

    return StorageAnalysisNode(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      bytes: readInt(map['bytes']),
      fileCount: readInt(map['fileCount']),
      path: map['path']?.toString(),
      type: map['type']?.toString() ?? 'directory',
      extra: map['extra'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(map['extra'] as Map)
          : const {},
      children: children,
    );
  }

  final String id;
  final String label;
  final int bytes;
  final int fileCount;
  final String? path;
  final String type;
  final Map<String, dynamic> extra;
  final List<StorageAnalysisNode> children;

  bool get hasChildren => children.isNotEmpty;
}
