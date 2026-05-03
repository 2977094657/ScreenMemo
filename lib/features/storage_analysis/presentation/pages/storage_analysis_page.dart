import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/data/platform/path_service.dart';
import 'package:screen_memo/features/permissions/application/permission_service.dart';
import 'package:screen_memo/features/storage_analysis/data/storage_analysis_service.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/utils/byte_formatter.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';

class StorageAnalysisPage extends StatefulWidget {
  const StorageAnalysisPage({super.key});

  @override
  State<StorageAnalysisPage> createState() => _StorageAnalysisPageState();
}

class _StorageAnalysisPageState extends State<StorageAnalysisPage> {
  StorageAnalysisResult? _result;
  bool _loading = true;
  String? _error;
  bool _detailsExpanded = false;
  bool _clearingCache = false;
  bool _clearingExternalLogs = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await StorageAnalysisService.fetch();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _requestUsageStatsPermission() async {
    await PermissionService.instance.requestUsageStatsPermission();
    if (!mounted) return;
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pageBg = theme.scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? theme.colorScheme.surfaceContainerHigh
          : pageBg,
      appBar: AppBar(
        title: Text(l10n.storageAnalysisPageTitle),
        centerTitle: true,
        backgroundColor: theme.brightness == Brightness.dark
            ? theme.colorScheme.surface
            : pageBg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.storageAnalysisLoadFailed,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing3),
              ElevatedButton(
                onPressed: _loadData,
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      );
    }

    final result = _result;
    if (result == null) {
      return Center(child: Text(l10n.storageAnalysisEmptyMessage));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacing3,
          AppTheme.spacing3,
          AppTheme.spacing3,
          AppTheme.spacing8,
        ),
        children: [
          _buildUsageProgressSection(context, l10n, result),
          const SizedBox(height: AppTheme.spacing3),
          _buildWeChatStyleHeader(context, l10n, result),
          const SizedBox(height: AppTheme.spacing3),
          if (!result.hasUsageStatsPermission)
            _buildPermissionCard(context, l10n),
          if (result.errors.isNotEmpty)
            _buildErrorCard(context, l10n, result.errors),
          _buildCategoryCards(context, l10n, result),
          const SizedBox(height: AppTheme.spacing3),
          _buildBreakdownSection(context, l10n, result),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final tintedErrorContainer = colorScheme.errorContainer.withValues(
      alpha: (colorScheme.errorContainer.a * 0.7).clamp(0.0, 1.0),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing3),
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: tintedErrorContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storageAnalysisUsagePermissionMissingTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            l10n.storageAnalysisUsagePermissionMissingDesc,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          FilledButton.tonal(
            onPressed: _requestUsageStatsPermission,
            child: Text(l10n.storageAnalysisUsagePermissionButton),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageProgressSection(
    BuildContext context,
    AppLocalizations l10n,
    StorageAnalysisResult result,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final appBytes = result.effectiveAppBytes;
    final dataBytes = result.effectiveDataBytes;
    final cacheBytes = result.effectiveCacheBytes;
    final externalBytes = result.effectiveExternalBytes;
    final totalBytes = max(
      appBytes + dataBytes + cacheBytes + externalBytes,
      0,
    );

    final segments = <_StorageUsageSegment>[
      _StorageUsageSegment(
        label: l10n.storageAnalysisDataLabel,
        bytes: dataBytes,
        color: AppTheme.success,
      ),
      _StorageUsageSegment(
        label: l10n.storageAnalysisCacheLabel,
        bytes: cacheBytes,
        color: colorScheme.error,
      ),
      _StorageUsageSegment(
        label: l10n.storageAnalysisAppLabel,
        bytes: appBytes,
        color: colorScheme.primary,
      ),
      _StorageUsageSegment(
        label: l10n.storageAnalysisExternalLabel,
        bytes: externalBytes,
        color: colorScheme.outline,
      ),
    ];
    final activeSegments = segments.where((s) => s.bytes > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSegmentedUsageBar(
          context,
          totalBytes,
          activeSegments,
          height: 12,
        ),
        const SizedBox(height: AppTheme.spacing2),
        Wrap(
          spacing: AppTheme.spacing3,
          runSpacing: AppTheme.spacing2,
          children: segments
              .map(
                (segment) =>
                    _LegendItem(color: segment.color, label: segment.label),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildWeChatStyleHeader(
    BuildContext context,
    AppLocalizations l10n,
    StorageAnalysisResult result,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final appBytes = result.effectiveAppBytes;
    final dataBytes = result.effectiveDataBytes;
    final cacheBytes = result.effectiveCacheBytes;
    final externalBytes = result.effectiveExternalBytes;
    final totalBytes = appBytes + dataBytes + cacheBytes + externalBytes;

    final timestamp = DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(result.timestampAsDateTime);

    final durationSeconds = max(result.scanDurationMs / 1000.0, 0);
    final durationLabel = durationSeconds >= 1
        ? l10n.storageAnalysisScanDurationSeconds(
            durationSeconds.toStringAsFixed(1),
          )
        : l10n.storageAnalysisScanDurationMilliseconds(
            result.scanDurationMs.toString(),
          );

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storageUsage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatBytes(totalBytes),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            l10n.storageAnalysisScanTimestamp(timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            durationLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (!result.hasSystemStats) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              l10n.storageAnalysisManualNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegmentedUsageBar(
    BuildContext context,
    int totalBytes,
    List<_StorageUsageSegment> segments, {
    double height = 10,
  }) {
    final cs = Theme.of(context).colorScheme;
    final trackColor = cs.surfaceContainerHighest.withValues(
      alpha: (cs.surfaceContainerHighest.a * 0.85).clamp(0.0, 1.0),
    );

    if (totalBytes <= 0 || segments.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: SizedBox(
          height: height,
          child: ColoredBox(color: trackColor),
        ),
      );
    }

    int toFlex(int bytes) {
      final ratio = bytes / totalBytes;
      return max((ratio * 1000).round(), bytes > 0 ? 1 : 0);
    }

    final active = segments.where((s) => s.bytes > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: trackColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < active.length; i++) ...[
                Expanded(
                  flex: toFlex(active[i].bytes),
                  child: ColoredBox(color: active[i].color),
                ),
                if (i != active.length - 1) const SizedBox(width: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context,
    AppLocalizations l10n,
    List<String> errors,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final tintedErrorContainer = colorScheme.errorContainer.withValues(
      alpha: (colorScheme.errorContainer.a * 0.4).clamp(0.0, 1.0),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing3),
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: tintedErrorContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storageAnalysisPartialErrors,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          for (final error in errors)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
              child: Text(
                '• $error',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryCards(
    BuildContext context,
    AppLocalizations l10n,
    StorageAnalysisResult result,
  ) {
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

    String desc({required String zh, required String en}) => isZh ? zh : en;

    StorageAnalysisNode? findNode(bool Function(StorageAnalysisNode n) test) {
      StorageAnalysisNode? match;
      void visit(StorageAnalysisNode node) {
        if (match != null) return;
        if (test(node)) {
          match = node;
          return;
        }
        for (final child in node.children) {
          visit(child);
          if (match != null) return;
        }
      }

      for (final root in result.nodes) {
        visit(root);
        if (match != null) break;
      }
      return match;
    }

    final cacheNode = findNode((n) => n.id == 'cache');
    final screenshotsNode = findNode((n) => n.id == 'screenshots');
    final outputDatabasesNode = findNode((n) => n.type == 'outputDatabases');
    final databasesNode = findNode((n) => n.type == 'databases');
    final externalLogsNode = findNode((n) => n.type == 'externalLogs');

    final cards = <Widget>[
      _StorageCategoryCard(
        title: l10n.storageAnalysisCacheLabel,
        bytes: cacheNode?.bytes ?? result.effectiveCacheBytes,
        detailText: _buildNodeDetailText(l10n, cacheNode),
        descriptionText: desc(
          zh: '缓存是应用运行产生的临时数据，清理缓存不会影响截图、动态等内容。',
          en: 'Cache contains temporary data. Clearing cache won’t affect your screenshots or records.',
        ),
        actionLabel: l10n.actionClear,
        actionPrimary: true,
        actionLoading: _clearingCache,
        onAction: _clearingCache ? null : () => _clearCache(l10n),
      ),
      if (screenshotsNode != null)
        _StorageCategoryCard(
          title: l10n.storageAnalysisLabelScreenshots,
          bytes: screenshotsNode.bytes,
          detailText: _buildNodeDetailText(l10n, screenshotsNode),
          descriptionText: desc(
            zh: '截图库包含截图图片文件占用，可进入查看各应用占用情况。',
            en: 'Screenshot library stores screenshot image files. Enter to view per-app usage.',
          ),
          actionLabel: l10n.actionEnter,
          onAction: () =>
              _showNodeDetailsSheet(context, l10n, node: screenshotsNode),
        ),
      if (outputDatabasesNode != null)
        _StorageCategoryCard(
          title: l10n.storageAnalysisLabelOutputDatabases,
          bytes: outputDatabasesNode.bytes,
          detailText: _buildNodeDetailText(l10n, outputDatabasesNode),
          descriptionText: desc(
            zh: '用于搜索索引与输出缓存数据。复制路径可用于导出/排障。',
            en: 'Stores search indexes and output caches. Copy the path for export/debugging.',
          ),
          actionLabel: l10n.actionCopy,
          onAction: outputDatabasesNode.path == null
              ? null
              : () => _copyPath(context, l10n, outputDatabasesNode.path!),
        ),
      if (databasesNode != null)
        _StorageCategoryCard(
          title: l10n.storageAnalysisLabelDatabases,
          bytes: databasesNode.bytes,
          detailText: _buildNodeDetailText(l10n, databasesNode),
          descriptionText: desc(
            zh: '应用核心数据库与配置文件。复制路径可用于排查问题。',
            en: 'Core app databases and configs. Copy the path for troubleshooting.',
          ),
          actionLabel: l10n.actionCopy,
          onAction: databasesNode.path == null
              ? null
              : () => _copyPath(context, l10n, databasesNode.path!),
        ),
      if (externalLogsNode != null ||
          result.effectiveExternalBytes > 0 ||
          _clearingExternalLogs)
        _StorageCategoryCard(
          title: l10n.storageAnalysisExternalLabel,
          bytes: externalLogsNode?.bytes ?? result.effectiveExternalBytes,
          detailText: _buildNodeDetailText(l10n, externalLogsNode),
          descriptionText: desc(
            zh: '外部日志用于故障排查。清理后将无法查看历史日志。',
            en: 'External logs help troubleshooting. Clearing removes historical logs.',
          ),
          actionLabel: l10n.actionClear,
          actionLoading: _clearingExternalLogs,
          onAction: _clearingExternalLogs
              ? null
              : () => _clearExternalLogs(l10n),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          cards[i],
          if (i != cards.length - 1) const SizedBox(height: AppTheme.spacing2),
        ],
      ],
    );
  }

  Widget _buildBreakdownSection(
    BuildContext context,
    AppLocalizations l10n,
    StorageAnalysisResult result,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final totalBytes = max(
      result.nodes.fold<int>(0, (sum, n) => sum + n.bytes),
      1,
    );

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () {
          setState(() {
            _detailsExpanded = !_detailsExpanded;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.storageAnalysisBreakdownTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              if (_detailsExpanded) ...[
                const SizedBox(height: AppTheme.spacing2),
                ...result.nodes.map(
                  (node) => StorageNodeTile(
                    node: node,
                    totalBytes: totalBytes,
                    depth: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _buildNodeDetailText(
    AppLocalizations l10n,
    StorageAnalysisNode? node,
  ) {
    if (node == null) return null;
    final parts = <String>[];
    if (node.fileCount > 0) {
      parts.add(
        l10n.storageAnalysisFileCount(
          NumberFormat.decimalPattern().format(node.fileCount),
        ),
      );
    }
    if (node.path != null && node.path!.isNotEmpty) {
      parts.add(node.path!);
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  Future<void> _clearCache(AppLocalizations l10n) async {
    if (_clearingCache) return;
    setState(() {
      _clearingCache = true;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      await _deleteDirContents(tempDir);

      final codeCacheDir = Directory(p.join(tempDir.parent.path, 'code_cache'));
      await _deleteDirContents(codeCacheDir);

      if (!mounted) return;
      UINotifier.success(context, l10n.clearSuccess);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, l10n.clearFailedWithError(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _clearingCache = false;
        });
      }
    }
  }

  Future<void> _clearExternalLogs(AppLocalizations l10n) async {
    if (_clearingExternalLogs) return;
    setState(() {
      _clearingExternalLogs = true;
    });

    try {
      final logsDir = await PathService.getLegacyExternalFilesDir(
        'output/logs',
      );
      if (logsDir != null) {
        await _deleteDirContents(logsDir);
      }

      if (!mounted) return;
      UINotifier.success(context, l10n.clearSuccess);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, l10n.clearFailedWithError(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _clearingExternalLogs = false;
        });
      }
    }
  }

  Future<void> _deleteDirContents(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  void _copyPath(BuildContext context, AppLocalizations l10n, String path) {
    try {
      Clipboard.setData(ClipboardData(text: path));
      UINotifier.success(context, l10n.copySuccess);
    } catch (_) {
      UINotifier.error(context, l10n.copyFailed);
    }
  }

  void _showNodeDetailsSheet(
    BuildContext context,
    AppLocalizations l10n, {
    required StorageAnalysisNode node,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = _resolveStorageNodeLabel(node, l10n);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: UISheetSurface(
            child: Column(
              children: [
                const SizedBox(height: AppTheme.spacing3),
                const UISheetHandle(),
                const SizedBox(height: AppTheme.spacing3),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacing4,
                    0,
                    AppTheme.spacing2,
                    AppTheme.spacing2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing1),
                            Text(
                              formatBytes(node.bytes),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (node.path != null)
                        IconButton(
                          tooltip: l10n.actionCopyPath,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () => _copyPath(context, l10n, node.path!),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppTheme.spacing3),
                    children: [
                      if (node.children.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppTheme.spacing2),
                          child: Text(
                            node.path ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        ...node.children.map(
                          (child) => StorageNodeTile(
                            node: child,
                            totalBytes: max(node.bytes, 1),
                            depth: 0,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class StorageNodeTile extends StatefulWidget {
  const StorageNodeTile({
    super.key,
    required this.node,
    required this.totalBytes,
    required this.depth,
  });

  final StorageAnalysisNode node;
  final int totalBytes;
  final int depth;

  @override
  State<StorageNodeTile> createState() => _StorageNodeTileState();
}

class _StorageNodeTileState extends State<StorageNodeTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.depth < 1;
  }

  @override
  void didUpdateWidget(covariant StorageNodeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.node.id != oldWidget.node.id) {
      _expanded = widget.depth < 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context);
    final hasChildren = widget.node.hasChildren;
    final indent = 16.0 * widget.depth;

    final ratio = widget.totalBytes > 0
        ? widget.node.bytes / widget.totalBytes
        : 0.0;
    final percentText = ratio > 0
        ? '${(ratio * 100).toStringAsFixed(ratio >= 0.1 ? 1 : 2)}%'
        : '--';

    final fileCount = widget.node.fileCount;
    final fileCountText = fileCount > 0
        ? l10n.storageAnalysisFileCount(
            NumberFormat.decimalPattern().format(fileCount),
          )
        : null;

    final label = _resolveStorageNodeLabel(widget.node, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasChildren
              ? () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                }
              : (widget.node.path != null ? () => _copyPath(context) : null),
          onLongPress: widget.node.path != null
              ? () => _copyPath(context)
              : null,
          child: Padding(
            padding: EdgeInsets.only(
              left: AppTheme.spacing1 + indent,
              right: AppTheme.spacing2,
              top: AppTheme.spacing2,
              bottom: AppTheme.spacing2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasChildren)
                  Padding(
                    padding: const EdgeInsets.only(right: AppTheme.spacing1),
                    child: Icon(
                      _expanded
                          ? Icons.expand_more
                          : Icons.chevron_right_outlined,
                      size: 18,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: (colorScheme.onSurfaceVariant.a * 0.6).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: textTheme.bodyMedium),
                      if (fileCountText != null || widget.node.path != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppTheme.spacing1 / 2,
                          ),
                          child: Text(
                            [
                              if (fileCountText != null) fileCountText,
                              if (widget.node.path != null) widget.node.path!,
                            ].join(' • '),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatBytes(widget.node.bytes),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      percentText,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (!hasChildren && widget.node.path != null)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: l10n.actionCopyPath,
                    onPressed: () => _copyPath(context),
                  ),
              ],
            ),
          ),
        ),
        if (hasChildren && _expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: widget.node.children
                  .map(
                    (child) => StorageNodeTile(
                      node: child,
                      totalBytes: widget.totalBytes,
                      depth: widget.depth + 1,
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  void _copyPath(BuildContext context) {
    final path = widget.node.path;
    if (path == null) return;
    Clipboard.setData(ClipboardData(text: path));
    UINotifier.success(
      context,
      AppLocalizations.of(context).storageAnalysisPathCopied,
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppTheme.spacing1),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _StorageUsageSegment {
  const _StorageUsageSegment({
    required this.label,
    required this.bytes,
    required this.color,
  });

  final String label;
  final int bytes;
  final Color color;
}

class _StorageCategoryCard extends StatelessWidget {
  const _StorageCategoryCard({
    required this.title,
    required this.bytes,
    this.detailText,
    this.descriptionText,
    this.actionLabel,
    this.actionPrimary = false,
    this.actionLoading = false,
    this.onAction,
  });

  final String title;
  final int bytes;
  final String? detailText;
  final String? descriptionText;
  final String? actionLabel;
  final bool actionPrimary;
  final bool actionLoading;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = cs.surface;
    final buttonBg = actionPrimary ? AppTheme.success : cs.surfaceContainerHigh;
    final buttonFg = actionPrimary ? AppTheme.successForeground : cs.onSurface;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: buttonBg,
                      foregroundColor: buttonFg,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing3,
                        vertical: AppTheme.spacing1,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      textStyle: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: actionLoading
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: buttonFg,
                            ),
                          )
                        : Text(actionLabel!),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              formatBytes(bytes),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detailText != null) ...[
              const SizedBox(height: AppTheme.spacing1),
              Text(
                detailText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (descriptionText != null) ...[
              const SizedBox(height: AppTheme.spacing2),
              Text(
                descriptionText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _resolveStorageNodeLabel(
  StorageAnalysisNode node,
  AppLocalizations l10n,
) {
  switch (node.type) {
    case 'appBinary':
      return l10n.storageAnalysisAppLabel;
    case 'group':
      switch (node.id) {
        case 'data':
          return l10n.storageAnalysisDataLabel;
        case 'cache':
          return l10n.storageAnalysisCacheLabel;
        default:
          return node.label;
      }
    case 'filesRoot':
      return l10n.storageAnalysisLabelFiles;
    case 'outputRoot':
      return l10n.storageAnalysisLabelOutput;
    case 'screenshotsRoot':
      return l10n.storageAnalysisLabelScreenshots;
    case 'screenshotsPackage':
      final appName = node.extra['appName']?.toString();
      final packageName = node.extra['packageName']?.toString();
      if (appName != null && packageName != null) {
        return '$appName ($packageName)';
      }
      return appName ?? packageName ?? node.label;
    case 'outputDatabases':
      return l10n.storageAnalysisLabelOutputDatabases;
    case 'filesChild':
      return node.label;
    case 'sharedPrefs':
      return l10n.storageAnalysisLabelSharedPrefs;
    case 'noBackup':
      return l10n.storageAnalysisLabelNoBackup;
    case 'appFlutter':
      return l10n.storageAnalysisLabelAppFlutter;
    case 'databases':
      return l10n.storageAnalysisLabelDatabases;
    case 'cacheDir':
      return l10n.storageAnalysisLabelCacheDir;
    case 'codeCache':
      return l10n.storageAnalysisLabelCodeCache;
    case 'externalLogs':
      return l10n.storageAnalysisLabelExternalLogs;
    case 'aggregated':
      final count = node.extra['count'];
      if (count is int) {
        return l10n.storageAnalysisOthersLabel(count);
      }
      return l10n.storageAnalysisOthersFallback;
    default:
      return node.label;
  }
}
