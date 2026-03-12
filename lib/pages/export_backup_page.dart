import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/backup_inventory_service.dart';
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';
import '../utils/byte_formatter.dart';

typedef BackupExportExecutor =
    Future<Map<String, dynamic>?> Function({
      required void Function(ExportProgressSnapshot snapshot) onProgress,
      required bool Function() isCancelled,
    });

typedef BackupInventoryLoader =
    Future<BackupInventory> Function({
      void Function(String scopeId, String? currentPath)? onProgress,
    });

class ExportBackupPage extends StatefulWidget {
  const ExportBackupPage({
    super.key,
    this.exportExecutor,
    this.inventoryLoader,
  });

  final BackupExportExecutor? exportExecutor;
  final BackupInventoryLoader? inventoryLoader;

  @override
  State<ExportBackupPage> createState() => _ExportBackupPageState();
}

class _ExportBackupPageState extends State<ExportBackupPage> {
  ExportProgressSnapshot? _snapshot;
  Map<String, dynamic>? _result;
  Object? _error;
  bool _inventoryLoading = false;
  bool _running = false;
  bool _cancelRequested = false;

  BackupExportExecutor get _executor =>
      widget.exportExecutor ??
      ({
        required void Function(ExportProgressSnapshot snapshot) onProgress,
        required bool Function() isCancelled,
      }) {
        return ScreenshotDatabase.instance.exportDatabaseToDownloads(
          onDetailedProgress: onProgress,
          shouldCancel: isCancelled,
        );
      };

  BackupInventoryLoader get _inventoryLoader =>
      widget.inventoryLoader ??
      ({void Function(String scopeId, String? currentPath)? onProgress}) {
        return BackupInventoryService.scan(onProgress: onProgress);
      };

  @override
  void initState() {
    super.initState();
    unawaited(_loadInventoryPreview());
  }

  Future<void> _loadInventoryPreview() async {
    if (_inventoryLoading || _running) {
      return;
    }
    if (mounted) {
      setState(() {
        _inventoryLoading = true;
        _cancelRequested = false;
        _error = null;
        _result = null;
        _snapshot = const ExportProgressSnapshot(
          phase: ExportPhase.scanning,
          overallProgress: 0,
          completedBytes: 0,
          totalBytes: 0,
          categoryCompletedBytes: <String, int>{},
        );
      });
    }

    try {
      final BackupInventory inventory = await _inventoryLoader(
        onProgress: (String scopeId, String? currentPath) {
          if (!mounted) {
            return;
          }
          setState(() {
            _snapshot = ExportProgressSnapshot(
              phase: ExportPhase.scanning,
              overallProgress: 0,
              completedBytes: 0,
              totalBytes: 0,
              categoryCompletedBytes: const <String, int>{},
              currentCategoryId: scopeId,
              currentEntry: currentPath,
            );
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _inventoryLoading = false;
        _error = null;
        _result = null;
        _snapshot = ExportProgressSnapshot(
          phase: ExportPhase.idle,
          overallProgress: 0,
          completedBytes: 0,
          totalBytes: inventory.totalBytes,
          categoryCompletedBytes: _zeroCategoryProgress(inventory),
          inventory: inventory,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inventoryLoading = false;
        _error = error;
        _snapshot = ExportProgressSnapshot(
          phase: ExportPhase.failed,
          overallProgress: 0,
          completedBytes: 0,
          totalBytes: 0,
          categoryCompletedBytes: const <String, int>{},
          errorMessage: error.toString(),
        );
      });
    }
  }

  Future<void> _startExport() async {
    if (_running || _inventoryLoading) {
      return;
    }

    final BackupInventory? previewInventory = _inventory;
    if (previewInventory == null) {
      await _loadInventoryPreview();
      if (!mounted || _inventory == null || _error != null) {
        return;
      }
    }

    if (mounted) {
      setState(() {
        _running = true;
        _cancelRequested = false;
        _error = null;
        _result = null;
        _snapshot = ExportProgressSnapshot(
          phase: ExportPhase.scanning,
          overallProgress: 0,
          completedBytes: 0,
          totalBytes: _inventory?.totalBytes ?? 0,
          categoryCompletedBytes: _zeroCategoryProgress(_inventory),
          inventory: _inventory,
        );
      });
    }

    try {
      final Map<String, dynamic>? result = await _executor(
        onProgress: (ExportProgressSnapshot snapshot) {
          if (!mounted) {
            return;
          }
          setState(() {
            _snapshot = snapshot;
          });
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _running = false;
        _cancelRequested = false;
      });
    } on BackupExportCancelledException {
      if (!mounted) {
        return;
      }
      setState(() {
        _running = false;
        _cancelRequested = false;
        _error = null;
        _result = null;
        _snapshot = _snapshot?.phase == ExportPhase.cancelled
            ? _snapshot
            : ExportProgressSnapshot(
                phase: ExportPhase.cancelled,
                overallProgress: 0,
                completedBytes: _snapshot?.completedBytes ?? 0,
                totalBytes: _inventory?.totalBytes ?? 0,
                categoryCompletedBytes: Map<String, int>.from(
                  _snapshot?.categoryCompletedBytes ??
                      _zeroCategoryProgress(_inventory),
                ),
                inventory: _inventory,
              );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cancelledCleanupText(context))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _running = false;
        _cancelRequested = false;
      });
    }
  }

  Map<String, int> _zeroCategoryProgress(BackupInventory? inventory) {
    if (inventory == null) {
      return <String, int>{};
    }
    return <String, int>{
      for (final BackupInventoryCategory category in inventory.categories)
        category.id: 0,
    };
  }

  Future<void> _copyExportPath() async {
    final String? path = _resolvedOutputPath;
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_copySuccessText(context))));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_copyFailedText(context))));
    }
  }

  String? get _resolvedOutputPath =>
      (_result?['humanPath'] as String?) ??
      (_snapshot?.outputPath?.trim().isNotEmpty == true
          ? _snapshot!.outputPath
          : null);

  BackupInventory? get _inventory => _snapshot?.inventory;

  List<String> get _warnings => _inventory?.warnings ?? const <String>[];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color pageBg = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.scaffoldBackgroundColor;

    return PopScope(
      canPop: !_running,
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          title: Text(_pageTitle(context)),
          centerTitle: true,
          backgroundColor: theme.brightness == Brightness.dark
              ? theme.colorScheme.surface
              : pageBg,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: !_running,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacing3,
              AppTheme.spacing3,
              AppTheme.spacing3,
              AppTheme.spacing8,
            ),
            children: [
              _buildHeaderCard(context),
              const SizedBox(height: AppTheme.spacing3),
              _buildProgressCard(context),
              const SizedBox(height: AppTheme.spacing3),
              _buildCategoryList(context),
              const SizedBox(height: AppTheme.spacing3),
              _buildExcludedCard(context),
              if (_warnings.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacing3),
                _buildWarningsCard(context),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppTheme.spacing3),
                _buildErrorCard(context),
              ],
              const SizedBox(height: AppTheme.spacing4),
              _buildBottomActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final BackupInventory? inventory = _inventory;
    final int totalBytes = inventory?.totalBytes ?? 0;
    final int totalFiles = inventory?.totalFiles ?? 0;
    final String subtitle = _statusSummaryText(context);

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _headlineLabel(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              inventory != null
                  ? formatBytes(totalBytes)
                  : _headlineValueText(context),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (totalFiles > 0) ...[
            const SizedBox(height: AppTheme.spacing1),
            Text(
              _fileCountText(context, totalFiles),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (_resolvedOutputPath != null) ...[
            const SizedBox(height: AppTheme.spacing2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacing3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(
                  alpha: (cs.surfaceContainerHighest.a * 0.72).clamp(0.0, 1.0),
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Text(
                _resolvedOutputPath!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final BackupInventory? inventory = _inventory;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _progressTitle(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          if (inventory == null || inventory.categories.isEmpty)
            LinearProgressIndicator(
              value: (_inventoryLoading || _running) ? null : 0,
              minHeight: 10,
            )
          else
            _BackupSegmentedProgressBar(
              inventory: inventory,
              snapshot: _snapshot,
            ),
          const SizedBox(height: AppTheme.spacing3),
          Row(
            children: [
              Expanded(
                child: Text(
                  _phaseLabel(context),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _progressPercentLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_currentEntryLabel != null) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              _currentEntryLabel!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: AppTheme.spacing2),
          Text(
            _doNotLeaveHint(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context) {
    final BackupInventory? inventory = _inventory;
    if (inventory == null || inventory.categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: inventory.categories.map((BackupInventoryCategory category) {
        final int completedBytes =
            _snapshot?.categoryCompletedBytes[category.id] ?? 0;
        final double ratio = category.totalBytes <= 0
            ? 0
            : (completedBytes / category.totalBytes).clamp(0.0, 1.0);
        final bool finished = ratio >= 0.999;
        final bool active =
            _snapshot?.currentCategoryId == category.id && _running;
        final bool cancelled =
            _snapshot?.phase == ExportPhase.cancelled && completedBytes > 0;
        final Color color = _categoryColor(context, category.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _categoryLabel(context, category.id),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${(ratio * 100).toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacing1),
                      Text(
                        '${formatBytes(category.totalBytes)} · ${_fileCountText(context, category.fileCount)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: color.withValues(alpha: 0.18),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.spacing2),
                Icon(
                  finished
                      ? Icons.check_circle
                      : active
                      ? Icons.sync
                      : cancelled
                      ? Icons.pause_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: finished
                      ? AppTheme.success
                      : active
                      ? color
                      : cancelled
                      ? color
                      : Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExcludedCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<BackupExcludedItem> excludedItems =
        _inventory?.excludedItems ??
        const <BackupExcludedItem>[
          BackupExcludedItem(
            id: BackupExcludedIds.cache,
            reason: 'Cache is not exported.',
          ),
          BackupExcludedItem(
            id: BackupExcludedIds.codeCache,
            reason: 'Code cache is not exported.',
          ),
          BackupExcludedItem(
            id: BackupExcludedIds.outputTemp,
            reason: 'Temporary output files are not exported.',
          ),
          BackupExcludedItem(
            id: BackupExcludedIds.externalLogs,
            reason: 'External logs are not exported in v1.',
          ),
        ];

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _excludedTitle(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          for (final BackupExcludedItem item in excludedItems)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.remove_circle_outline,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTheme.spacing2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _excludedLabel(context, item.id),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.bytes > 0
                              ? '${item.reason} (${formatBytes(item.bytes)})'
                              : item.reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWarningsCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(
          alpha: (cs.primaryContainer.a * 0.2).clamp(0.0, 1.0),
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _warningsTitle(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          for (final String warning in _warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
              child: Text(
                '• $warning',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(
          alpha: (cs.errorContainer.a * 0.4).clamp(0.0, 1.0),
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _errorTitle(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          SelectableText(
            _error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final ButtonStyle actionStyle = _actionButtonStyle();

    if (_running) {
      return FilledButton.tonalIcon(
        style: actionStyle,
        onPressed: _cancelRequested
            ? null
            : () {
                setState(() {
                  _cancelRequested = true;
                });
              },
        icon: Icon(_cancelRequested ? Icons.hourglass_top : Icons.close),
        label: Text(
          _cancelRequested
              ? _cancellingText(context)
              : _cancelButtonText(context),
        ),
      );
    }

    if (_resolvedOutputPath != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: actionStyle,
              onPressed: _copyExportPath,
              child: Text(_copyPathText(context)),
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: FilledButton(
              style: actionStyle,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppLocalizations.of(context).dialogOk),
            ),
          ),
        ],
      );
    }

    final bool scanFailed = _error != null && _inventory == null;
    final bool canStartExport = !_inventoryLoading && _inventory != null;
    return FilledButton.icon(
      style: actionStyle,
      onPressed: _inventoryLoading
          ? null
          : scanFailed
          ? _loadInventoryPreview
          : canStartExport
          ? _startExport
          : _loadInventoryPreview,
      icon: Icon(
        _inventoryLoading
            ? Icons.hourglass_top
            : scanFailed
            ? Icons.refresh
            : Icons.play_arrow_rounded,
      ),
      label: Text(
        _inventoryLoading
            ? _scanningScopeButtonText(context)
            : scanFailed
            ? _rescanButtonText(context)
            : _startExportButtonText(context),
      ),
    );
  }

  ButtonStyle _actionButtonStyle() {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll<Size>(Size.fromHeight(46)),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
      ),
    );
  }

  String get _progressPercentLabel {
    final ExportProgressSnapshot? snapshot = _snapshot;
    if (snapshot == null) {
      return '--';
    }
    if (snapshot.phase == ExportPhase.idle) {
      return '0%';
    }
    if (snapshot.phase == ExportPhase.scanning && snapshot.totalBytes <= 0) {
      return '--';
    }
    return '${(snapshot.overallProgress * 100).toStringAsFixed(0)}%';
  }

  String? get _currentEntryLabel {
    final String? entry = _snapshot?.currentEntry;
    if (entry == null || entry.isEmpty) {
      return null;
    }
    const int maxLen = 72;
    if (entry.length <= maxLen) {
      return entry;
    }
    return '...${entry.substring(entry.length - maxLen)}';
  }

  String _statusSummaryText(BuildContext context) {
    final BackupInventory? inventory = _inventory;
    if (_inventoryLoading) {
      return _preparingSummary(context);
    }
    if (_error != null && inventory == null) {
      return _scanFailedSummary(context);
    }
    if (_running && inventory == null) {
      return _scanningSummary(context);
    }
    if (_error != null) {
      return _failedSummary(context);
    }
    if (_resolvedOutputPath != null) {
      return _completedSummary(context);
    }
    if (_snapshot?.phase == ExportPhase.cancelled) {
      return _cancelledSummary(context);
    }
    if (!_running && inventory != null) {
      return _readySummary(context);
    }
    return _progressSummary(context);
  }

  String _headlineLabel(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '本次导出内容';
    }
    return 'Backup content';
  }

  String _headlineValueText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (_inventoryLoading) {
      return isZh ? '扫描中' : 'Scanning';
    }
    if (_snapshot?.phase == ExportPhase.cancelled) {
      return isZh ? '已取消' : 'Cancelled';
    }
    if (_error != null && _inventory == null) {
      return isZh ? '扫描失败' : 'Scan failed';
    }
    return isZh ? '等待开始' : 'Ready';
  }

  String _phaseLabel(BuildContext context) {
    final ExportPhase phase = _snapshot?.phase ?? ExportPhase.idle;
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (_cancelRequested && _running) {
      return isZh
          ? '正在取消导出并清理半成品…'
          : 'Cancelling export and cleaning partial files...';
    }
    if (_inventoryLoading) {
      return isZh
          ? '正在扫描导出范围，尚未开始导出…'
          : 'Scanning backup scope. Export has not started...';
    }
    switch (phase) {
      case ExportPhase.idle:
        return isZh ? '范围已确认，点击开始导出。' : 'Scope confirmed. Tap Start Export.';
      case ExportPhase.scanning:
        return isZh ? '正在扫描全部持久化数据…' : 'Scanning persistent data...';
      case ExportPhase.packing:
        return isZh ? '正在按类型打包备份…' : 'Packing backup by data type...';
      case ExportPhase.verifying:
        return isZh ? '正在校验备份文件…' : 'Verifying backup archive...';
      case ExportPhase.completed:
        return isZh
            ? '导出完成，可以确认备份已生成。'
            : 'Export finished. The backup archive is ready.';
      case ExportPhase.failed:
        return _inventory == null
            ? (isZh ? '扫描失败，请重试。' : 'Scan failed. Please retry.')
            : (isZh
                  ? '导出失败，请检查错误并重试。'
                  : 'Export failed. Review the error and retry.');
      case ExportPhase.cancelled:
        return isZh
            ? '导出已取消，未完成备份已清理。'
            : 'Export cancelled and partial files were cleaned up.';
    }
  }

  String _pageTitle(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出备份';
    }
    return 'Export Backup';
  }

  String _progressTitle(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出进度';
    }
    return 'Export Progress';
  }

  String _excludedTitle(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '本次未导出';
    }
    return 'Excluded From This Backup';
  }

  String _warningsTitle(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '扫描提示';
    }
    return 'Scan Notes';
  }

  String _errorTitle(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return _inventory == null ? '扫描失败' : '导出失败';
    }
    return _inventory == null ? 'Scan Failed' : 'Export Failed';
  }

  String _copyPathText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '复制路径';
    }
    return 'Copy Path';
  }

  String _copySuccessText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出路径已复制';
    }
    return 'Backup path copied';
  }

  String _copyFailedText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '复制路径失败';
    }
    return 'Failed to copy backup path';
  }

  String _cancelButtonText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '取消导出';
    }
    return 'Cancel Export';
  }

  String _cancellingText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '正在取消并清理';
    }
    return 'Cancelling';
  }

  String _doNotLeaveHint(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (_running) {
      return isZh
          ? '请保持应用打开，直到导出完成。'
          : 'Keep the app open until the export finishes.';
    }
    if (_inventoryLoading) {
      return isZh
          ? '正在确认本次导出范围，完成后即可开始导出。'
          : 'The export scope is being scanned. Start export after it finishes.';
    }
    if (_snapshot?.phase == ExportPhase.cancelled) {
      return isZh
          ? '未完成的备份文件已清理，可重新开始导出。'
          : 'Partial backup files were cleaned up. You can start again.';
    }
    if (_resolvedOutputPath != null) {
      return isZh
          ? '可以复制备份路径，或返回设置页继续操作。'
          : 'You can copy the backup path or return to Settings.';
    }
    if (code.startsWith('zh')) {
      return '点击开始导出后，请保持应用打开直到完成。';
    }
    return 'Once export starts, keep the app open until it finishes.';
  }

  String _scanningSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '正在遍历截图、数据库、偏好设置与其他持久化目录。';
    }
    return 'Scanning screenshots, databases, preferences, and other persistent folders.';
  }

  String _preparingSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '正在扫描本次导出范围，确认无遗漏后才会允许开始导出。';
    }
    return 'Scanning the backup scope first so export can start only after the full range is confirmed.';
  }

  String _progressSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final BackupInventory? inventory = _inventory;
    if (inventory == null) {
      return _scanningSummary(context);
    }
    if (code.startsWith('zh')) {
      return '已统计 ${inventory.categories.length} 类数据，正在按字节进度写入 ZIP。';
    }
    return 'Found ${inventory.categories.length} data groups and now writing them into the ZIP by bytes.';
  }

  String _readySummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final BackupInventory? inventory = _inventory;
    if (inventory == null) {
      return _preparingSummary(context);
    }
    if (code.startsWith('zh')) {
      return '已确认 ${inventory.categories.length} 类持久化数据，点击底部按钮开始导出。';
    }
    return 'Confirmed ${inventory.categories.length} persistent data groups. Tap the button below to start export.';
  }

  String _completedSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '备份已保存到下载目录，可直接用于后续导入恢复。';
    }
    return 'The backup has been saved to Downloads and is ready for future restore.';
  }

  String _cancelledSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出已取消，未完成的备份 ZIP 与临时文件都已清理。';
    }
    return 'The export was cancelled, and unfinished ZIP plus temporary files were cleaned up.';
  }

  String _failedSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出中断，当前页面保留了失败原因与已扫描结果。';
    }
    return 'The export stopped. This page keeps the failure reason and scanned results.';
  }

  String _scanFailedSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出范围扫描失败，当前不会开始导出，请先重试扫描。';
    }
    return 'Scanning the export scope failed, so export will not start until you retry the scan.';
  }

  String _startExportButtonText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (_snapshot?.phase == ExportPhase.cancelled || _error != null) {
      return isZh ? '重新开始导出' : 'Start Export Again';
    }
    return isZh ? '开始导出' : 'Start Export';
  }

  String _scanningScopeButtonText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '正在扫描导出范围';
    }
    return 'Scanning Scope';
  }

  String _rescanButtonText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '重新扫描范围';
    }
    return 'Rescan Scope';
  }

  String _cancelledCleanupText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出已取消，未完成的备份文件已清理。';
    }
    return 'Export cancelled. Unfinished backup files were cleaned up.';
  }

  String _fileCountText(BuildContext context, int count) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '$count 个文件';
    }
    return '$count files';
  }

  String _categoryLabel(BuildContext context, String id) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    switch (id) {
      case BackupCategoryIds.screenshots:
        return isZh ? '截图文件' : 'Screenshots';
      case BackupCategoryIds.mainDatabase:
        return isZh ? '主数据库' : 'Main database';
      case BackupCategoryIds.shardDatabases:
        return isZh ? '分片数据库' : 'Shard databases';
      case BackupCategoryIds.perAppSettings:
        return isZh ? '每应用设置库' : 'Per-app settings';
      case BackupCategoryIds.otherOutput:
        return isZh ? '其他 output 数据' : 'Other output data';
      case BackupCategoryIds.sharedPrefs:
        return isZh ? '偏好设置' : 'Shared prefs';
      case BackupCategoryIds.appFlutter:
        return isZh ? 'Flutter 持久化目录' : 'Flutter data';
      case BackupCategoryIds.noBackup:
        return isZh ? 'no_backup 目录' : 'no_backup';
      case BackupCategoryIds.appDatabases:
        return isZh ? '应用级数据库目录' : 'App databases';
      default:
        return id;
    }
  }

  String _excludedLabel(BuildContext context, String id) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    switch (id) {
      case BackupExcludedIds.cache:
        return isZh ? 'cache 目录' : 'Cache directory';
      case BackupExcludedIds.codeCache:
        return isZh ? 'code_cache 目录' : 'Code cache';
      case BackupExcludedIds.outputTemp:
        return isZh ? '临时输出与缩略图' : 'Temporary output and thumbnails';
      case BackupExcludedIds.externalLogs:
        return isZh ? '外部日志' : 'External logs';
      default:
        return id;
    }
  }

  Color _categoryColor(BuildContext context, String id) {
    switch (id) {
      case BackupCategoryIds.screenshots:
        return const Color(0xFFE88A34);
      case BackupCategoryIds.mainDatabase:
        return const Color(0xFF3B82F6);
      case BackupCategoryIds.shardDatabases:
        return const Color(0xFF10B981);
      case BackupCategoryIds.perAppSettings:
        return const Color(0xFF0EA5A4);
      case BackupCategoryIds.otherOutput:
        return const Color(0xFF84CC16);
      case BackupCategoryIds.sharedPrefs:
        return const Color(0xFFF97316);
      case BackupCategoryIds.appFlutter:
        return const Color(0xFF64748B);
      case BackupCategoryIds.noBackup:
        return const Color(0xFFEF4444);
      case BackupCategoryIds.appDatabases:
        return const Color(0xFF14B8A6);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}

class _BackupSegmentedProgressBar extends StatelessWidget {
  const _BackupSegmentedProgressBar({
    required this.inventory,
    required this.snapshot,
  });

  final BackupInventory inventory;
  final ExportProgressSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<BackupInventoryCategory> categories = inventory.categories;
    final int totalBytes = inventory.totalBytes <= 0 ? 1 : inventory.totalBytes;

    int toFlex(int bytes) {
      final double ratio = bytes / totalBytes;
      return (ratio * 1000).round().clamp(1, 1000);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: SizedBox(
        height: 14,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < categories.length; i++) ...[
              Expanded(
                flex: toFlex(categories[i].totalBytes),
                child: _SegmentFill(
                  color: _segmentColor(context, categories[i].id),
                  progress: categories[i].totalBytes <= 0
                      ? 0
                      : ((snapshot?.categoryCompletedBytes[categories[i].id] ??
                                    0) /
                                categories[i].totalBytes)
                            .clamp(0.0, 1.0),
                  trackColor: cs.surfaceContainerHighest,
                ),
              ),
              if (i != categories.length - 1) const SizedBox(width: 1),
            ],
          ],
        ),
      ),
    );
  }

  Color _segmentColor(BuildContext context, String id) {
    switch (id) {
      case BackupCategoryIds.screenshots:
        return const Color(0xFFE88A34);
      case BackupCategoryIds.mainDatabase:
        return const Color(0xFF3B82F6);
      case BackupCategoryIds.shardDatabases:
        return const Color(0xFF10B981);
      case BackupCategoryIds.perAppSettings:
        return const Color(0xFF0EA5A4);
      case BackupCategoryIds.otherOutput:
        return const Color(0xFF84CC16);
      case BackupCategoryIds.sharedPrefs:
        return const Color(0xFFF97316);
      case BackupCategoryIds.appFlutter:
        return const Color(0xFF64748B);
      case BackupCategoryIds.noBackup:
        return const Color(0xFFEF4444);
      case BackupCategoryIds.appDatabases:
        return const Color(0xFF14B8A6);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}

class _SegmentFill extends StatelessWidget {
  const _SegmentFill({
    required this.color,
    required this.progress,
    required this.trackColor,
  });

  final Color color;
  final double progress;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: trackColor.withValues(alpha: 0.24)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: DecoratedBox(decoration: BoxDecoration(color: color)),
        ),
      ),
    );
  }
}
