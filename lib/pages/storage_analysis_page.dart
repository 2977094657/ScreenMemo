import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/permission_service.dart';
import '../services/storage_analysis_service.dart';
import '../theme/app_theme.dart';
import '../utils/byte_formatter.dart';
import '../widgets/ui_components.dart';

class StorageAnalysisPage extends StatefulWidget {
  const StorageAnalysisPage({super.key});

  @override
  State<StorageAnalysisPage> createState() => _StorageAnalysisPageState();
}

class _StorageAnalysisPageState extends State<StorageAnalysisPage> {
  StorageAnalysisResult? _result;
  bool _loading = true;
  String? _error;

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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storageAnalysisPageTitle)),
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
        padding: const EdgeInsets.all(AppTheme.spacing4),
        children: [
          if (!result.hasUsageStatsPermission)
            _buildPermissionCard(context, l10n),
          _buildSummaryCard(context, l10n, result),
          if (result.errors.isNotEmpty)
            _buildErrorCard(context, l10n, result.errors),
          _buildBreakdownCard(context, l10n, result),
          const SizedBox(height: AppTheme.spacing6),
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
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
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

  Widget _buildSummaryCard(
    BuildContext context,
    AppLocalizations l10n,
    StorageAnalysisResult result,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline.withValues(
      alpha: (colorScheme.outline.a * 0.7).clamp(0.0, 1.0),
    );

    final totalBytes = result.effectiveTotalBytes;
    final appBytes = result.effectiveAppBytes;
    final dataBytes = result.effectiveDataBytes;
    final cacheBytes = result.effectiveCacheBytes;
    final externalBytes = result.effectiveExternalBytes;

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
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storageAnalysisSummaryTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Wrap(
            spacing: AppTheme.spacing4,
            runSpacing: AppTheme.spacing3,
            children: [
              _buildSummaryItem(
                context,
                label: l10n.storageAnalysisTotalLabel,
                value: formatBytes(totalBytes),
                highlight: true,
              ),
              _buildSummaryItem(
                context,
                label: l10n.storageAnalysisAppLabel,
                value: formatBytes(appBytes),
              ),
              _buildSummaryItem(
                context,
                label: l10n.storageAnalysisDataLabel,
                value: formatBytes(dataBytes),
              ),
              _buildSummaryItem(
                context,
                label: l10n.storageAnalysisCacheLabel,
                value: formatBytes(cacheBytes),
              ),
              _buildSummaryItem(
                context,
                label: l10n.storageAnalysisExternalLabel,
                value: formatBytes(externalBytes),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          Text(
            l10n.storageAnalysisScanTimestamp(timestamp),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            durationLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (!result.hasSystemStats)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spacing2),
              child: Text(
                l10n.storageAnalysisManualNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context, {
    required String label,
    required String value,
    bool highlight = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            value,
            style: highlight
                ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
                : textTheme.titleMedium,
          ),
        ],
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
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
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

  Widget _buildBreakdownCard(
    BuildContext context,
    AppLocalizations l10n,
    StorageAnalysisResult result,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outline.withValues(
      alpha: (colorScheme.outline.a * 0.7).clamp(0.0, 1.0),
    );

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.storageAnalysisBreakdownTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          ...result.nodes.map(
            (node) => StorageNodeTile(
              node: node,
              totalBytes: result.effectiveTotalBytes,
              depth: 0,
            ),
          ),
        ],
      ),
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

    final label = _resolveLabel(widget.node, l10n);

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

  String _resolveLabel(StorageAnalysisNode node, AppLocalizations l10n) {
    switch (node.type) {
      case 'appBinary':
        return l10n.storageAnalysisAppLabel;
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
}
