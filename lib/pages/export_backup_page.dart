import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talker/talker.dart';

import '../l10n/app_localizations.dart';
import '../services/backup_inventory_service.dart';
import '../services/flutter_logger.dart' hide LogLevel;
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';
import '../utils/byte_formatter.dart';
import '../widgets/ui_components.dart';

typedef BackupExportExecutor =
    Future<Map<String, dynamic>?> Function({
      required BackupExportScope exportScope,
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
  BackupInventory? _fullInventory;
  Map<String, dynamic>? _result;
  Object? _error;
  StreamSubscription<TalkerData>? _exportLogSubscription;
  Future<void> _exportLogWriteChain = Future<void>.value();
  bool _inventoryLoading = false;
  bool _running = false;
  bool _cancelRequested = false;
  int _exportLogSessionNonce = 0;
  int? _activeExportLogSessionId;
  BackupExportScope _selectedScope = BackupExportScope.full;
  String? _exportLogPath;
  String? _lastExportLogDedupeKey;

  BackupExportExecutor get _executor =>
      widget.exportExecutor ??
      ({
        required BackupExportScope exportScope,
        required void Function(ExportProgressSnapshot snapshot) onProgress,
        required bool Function() isCancelled,
      }) {
        return ScreenshotDatabase.instance.exportDatabaseToDownloads(
          exportScope: exportScope,
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
    _exportLogSubscription = FlutterLogger.talker.stream.listen(
      _handleTalkerLogEvent,
    );
    unawaited(_loadInventoryPreview());
  }

  @override
  void dispose() {
    _exportLogSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInventoryPreview() async {
    if (_inventoryLoading || _running) {
      return;
    }
    if (mounted) {
      setState(() {
        _clearExportLogs();
        _inventoryLoading = true;
        _cancelRequested = false;
        _fullInventory = null;
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
          final ExportProgressSnapshot nextSnapshot = ExportProgressSnapshot(
            phase: ExportPhase.scanning,
            overallProgress: 0,
            completedBytes: 0,
            totalBytes: 0,
            categoryCompletedBytes: const <String, int>{},
            currentCategoryId: scopeId,
            currentEntry: currentPath,
          );
          setState(() {
            _recordSnapshotLogs(previous: _snapshot, next: nextSnapshot);
            _snapshot = nextSnapshot;
          });
        },
      );
      final BackupInventory scopedInventory = _inventoryForScope(inventory);
      if (!mounted) {
        return;
      }
      setState(() {
        _fullInventory = inventory;
        _inventoryLoading = false;
        _error = null;
        _result = null;
        _snapshot = _buildIdleSnapshot(scopedInventory);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fullInventory = null;
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
        _beginExportLogSession();
        _pushExportLog(
          _ExportLogLevel.info,
          'Export requested: scope=${_selectedScope.name}',
          dedupeKey: 'export-start:${_selectedScope.name}',
        );
        final BackupInventory? inventory = _inventory;
        if (inventory != null) {
          _pushExportLog(
            _ExportLogLevel.info,
            'Inventory confirmed: categories=${inventory.categories.length}, files=${inventory.totalFiles}, bytes=${formatBytes(inventory.totalBytes)}',
            dedupeKey:
                'export-inventory:${inventory.totalFiles}:${inventory.totalBytes}',
          );
        }
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
        exportScope: _selectedScope,
        onProgress: (ExportProgressSnapshot snapshot) {
          if (!mounted) {
            return;
          }
          setState(() {
            _recordSnapshotLogs(previous: _snapshot, next: snapshot);
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
        _pushExportLog(
          _ExportLogLevel.info,
          'Export completed: ${_resolvedOutputPath ?? result?['humanPath'] ?? '-'}',
          dedupeKey:
              'export-complete:${result?['humanPath'] ?? _resolvedOutputPath ?? '-'}',
        );
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
        _pushExportLog(
          _ExportLogLevel.warn,
          'Export cancelled by user. Partial files should be cleaned up.',
          dedupeKey: 'export-cancelled',
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
        _pushExportLog(
          _ExportLogLevel.error,
          'Export failed: $error',
          dedupeKey: 'export-failed:$error',
        );
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

  BackupInventory _inventoryForScope(BackupInventory inventory) {
    return BackupInventoryService.filterInventoryByScope(
      inventory,
      _selectedScope,
    );
  }

  ExportProgressSnapshot _buildIdleSnapshot(BackupInventory? inventory) {
    return ExportProgressSnapshot(
      phase: ExportPhase.idle,
      overallProgress: 0,
      completedBytes: 0,
      totalBytes: inventory?.totalBytes ?? 0,
      categoryCompletedBytes: _zeroCategoryProgress(inventory),
      inventory: inventory,
    );
  }

  void _handleScopeChanged(BackupExportScope scope) {
    if (_running || _selectedScope == scope) {
      return;
    }
    setState(() {
      _selectedScope = scope;
      _result = null;
      _error = null;
      if (_fullInventory != null) {
        _snapshot = _buildIdleSnapshot(_inventoryForScope(_fullInventory!));
      }
    });
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

  Future<void> _copyExportLogPath() async {
    final String? path = _exportLogPath;
    if (path == null || path.trim().isEmpty) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_copyLogPathSuccessText(context))));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_copyLogPathFailedText(context))));
    }
  }

  void _handleTalkerLogEvent(TalkerData data) {
    if (_activeExportLogSessionId == null) {
      return;
    }
    final ({String? tag, String message}) parsed = _splitTalkerTag(
      data.message?.toString(),
    );
    if ((parsed.tag ?? '').toUpperCase() != 'EXPORT') {
      return;
    }
    _pushExportLog(
      _mapTalkerLevel(data),
      parsed.message,
      dedupeKey:
          'talker:${data.time.microsecondsSinceEpoch}:${data.logLevel}:${parsed.message}',
    );
  }

  void _recordSnapshotLogs({
    required ExportProgressSnapshot? previous,
    required ExportProgressSnapshot next,
  }) {
    final String? currentEntry = next.currentEntry?.trim();
    final String? previousEntry = previous?.currentEntry?.trim();
    final ExportPhase? previousPhase = previous?.phase;
    final int previousCompleted = previous?.completedBytes ?? 0;
    final int nextCompleted = next.completedBytes;

    if (previousPhase != next.phase) {
      _pushExportLog(
        _phaseLogLevel(next.phase),
        'Phase -> ${next.phase.name}${_phaseSummarySuffix(next)}',
        dedupeKey:
            'phase:${next.phase.name}:${next.currentCategoryId ?? ''}:${currentEntry ?? ''}:$nextCompleted',
      );
    }

    switch (next.phase) {
      case ExportPhase.scanning:
        if (currentEntry != null &&
            currentEntry.isNotEmpty &&
            currentEntry != previousEntry) {
          final String scopeText =
              next.currentCategoryId?.trim().isNotEmpty == true
              ? next.currentCategoryId!.trim()
              : 'scope';
          _pushExportLog(
            _ExportLogLevel.info,
            'Scanning $scopeText :: $currentEntry',
            dedupeKey: 'scan:$scopeText:$currentEntry',
          );
        }
        break;
      case ExportPhase.packing:
        if (currentEntry != null && currentEntry.isNotEmpty) {
          final String categoryText =
              next.currentCategoryId?.trim().isNotEmpty == true
              ? next.currentCategoryId!.trim()
              : 'entry';
          final int? entryBytes = _entryBytesForArchivePath(currentEntry);
          if ((previousPhase != ExportPhase.packing ||
                  previousEntry != currentEntry) &&
              nextCompleted == previousCompleted) {
            final String sizeText = entryBytes != null
                ? ' (${formatBytes(entryBytes)})'
                : '';
            _pushExportLog(
              _ExportLogLevel.info,
              'Packing start $categoryText :: $currentEntry$sizeText',
              dedupeKey: 'pack-start:$currentEntry:$nextCompleted',
            );
          }
          if (nextCompleted > previousCompleted) {
            _pushExportLog(
              _ExportLogLevel.info,
              'Packing done $categoryText :: $currentEntry (${_formatCompletedBytes(nextCompleted, next.totalBytes)})',
              dedupeKey: 'pack-done:$currentEntry:$nextCompleted',
            );
          }
        }
        break;
      case ExportPhase.verifying:
        if (previousPhase != ExportPhase.verifying) {
          _pushExportLog(
            _ExportLogLevel.info,
            currentEntry?.isNotEmpty == true
                ? 'Verifying archive :: $currentEntry'
                : 'Verifying archive integrity',
            dedupeKey: 'verify:${currentEntry ?? ''}',
          );
        }
        break;
      case ExportPhase.completed:
        if (previousPhase != ExportPhase.completed) {
          _pushExportLog(
            _ExportLogLevel.info,
            next.outputPath?.trim().isNotEmpty == true
                ? 'Archive saved :: ${next.outputPath!.trim()}'
                : 'Export completed',
            dedupeKey: 'completed:${next.outputPath ?? ''}',
          );
        }
        break;
      case ExportPhase.failed:
        if (previousPhase != ExportPhase.failed ||
            next.errorMessage != previous?.errorMessage) {
          _pushExportLog(
            _ExportLogLevel.error,
            next.errorMessage?.trim().isNotEmpty == true
                ? 'Phase failed :: ${next.errorMessage!.trim()}'
                : 'Export failed',
            dedupeKey: 'phase-failed:${next.errorMessage ?? ''}',
          );
        }
        break;
      case ExportPhase.cancelled:
        if (previousPhase != ExportPhase.cancelled) {
          _pushExportLog(
            _ExportLogLevel.warn,
            'Export cancelled and cleanup started',
            dedupeKey: 'phase-cancelled',
          );
        }
        break;
      case ExportPhase.idle:
        break;
    }
  }

  void _beginExportLogSession() {
    _exportLogSessionNonce++;
    _activeExportLogSessionId = _exportLogSessionNonce;
    _exportLogPath = null;
    _lastExportLogDedupeKey = null;
    _exportLogWriteChain = Future<void>.value();
  }

  void _clearExportLogs() {
    _activeExportLogSessionId = null;
    _exportLogPath = null;
    _lastExportLogDedupeKey = null;
    _exportLogWriteChain = Future<void>.value();
  }

  void _pushExportLog(
    _ExportLogLevel level,
    String message, {
    String? dedupeKey,
  }) {
    final int? sessionId = _activeExportLogSessionId;
    if (sessionId == null) {
      return;
    }
    final String normalized = message.trimRight();
    if (normalized.isEmpty) {
      return;
    }
    final String key = dedupeKey ?? '${level.name}|$normalized';
    if (_lastExportLogDedupeKey == key) {
      return;
    }
    _lastExportLogDedupeKey = key;
    final String line =
        '${_formatLogTime(DateTime.now())} [${_exportLogLevelFileLabel(level)}] $normalized';
    _exportLogWriteChain = _exportLogWriteChain
        .then((_) async {
          final String? path = await _ensureExportLogPathForSession(sessionId);
          if (path == null || _activeExportLogSessionId != sessionId) {
            return;
          }
          await File(
            path,
          ).writeAsString('$line\n', mode: FileMode.append, flush: true);
        })
        .catchError((_) {});
  }

  Future<String?> _ensureExportLogPathForSession(int sessionId) async {
    if (_activeExportLogSessionId != sessionId) {
      return null;
    }
    final String? existingPath = _exportLogPath?.trim();
    if (existingPath != null && existingPath.isNotEmpty) {
      return existingPath;
    }

    String? todayDir;
    try {
      todayDir = await FlutterLogger.getTodayLogsDir();
    } catch (_) {
      todayDir = null;
    }
    final String trimmedTodayDir = (todayDir ?? '').trim();
    final Directory dir = trimmedTodayDir.isNotEmpty
        ? Directory(
            '$trimmedTodayDir${Platform.pathSeparator}backup_export_sessions',
          )
        : Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}screen_memo_backup_export_sessions',
          );
    await dir.create(recursive: true);

    final String filePath =
        '${dir.path}${Platform.pathSeparator}backup_export_${_formatFileTimestamp(DateTime.now())}.log';
    final File file = File(filePath);
    if (!await file.exists()) {
      await file.writeAsString('', flush: true);
    }
    if (_activeExportLogSessionId != sessionId) {
      return null;
    }

    if (mounted) {
      setState(() {
        _exportLogPath = file.path;
      });
    } else {
      _exportLogPath = file.path;
    }
    return file.path;
  }

  String _phaseSummarySuffix(ExportProgressSnapshot snapshot) {
    if (snapshot.totalBytes <= 0) {
      return '';
    }
    return ' (${_formatCompletedBytes(snapshot.completedBytes, snapshot.totalBytes)})';
  }

  int? _entryBytesForArchivePath(String? archivePath) {
    if (archivePath == null || archivePath.isEmpty) {
      return null;
    }
    final BackupInventory? inventory = _inventory;
    if (inventory == null) {
      return null;
    }
    for (final BackupInventoryCategory category in inventory.categories) {
      for (final BackupInventoryFile file in category.files) {
        if (file.archivePath == archivePath) {
          return file.bytes;
        }
      }
    }
    return null;
  }

  String _formatCompletedBytes(int completedBytes, int totalBytes) {
    if (totalBytes <= 0) {
      return formatBytes(completedBytes);
    }
    return '${formatBytes(completedBytes)} / ${formatBytes(totalBytes)}';
  }

  String _formatLogTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${three(time.millisecond)}';
  }

  String _formatFileTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}_${two(time.hour)}-${two(time.minute)}-${two(time.second)}-${three(time.millisecond)}';
  }

  _ExportLogLevel _phaseLogLevel(ExportPhase phase) {
    switch (phase) {
      case ExportPhase.failed:
        return _ExportLogLevel.error;
      case ExportPhase.cancelled:
        return _ExportLogLevel.warn;
      case ExportPhase.idle:
      case ExportPhase.scanning:
      case ExportPhase.packing:
      case ExportPhase.verifying:
      case ExportPhase.completed:
        return _ExportLogLevel.info;
    }
  }

  _ExportLogLevel _mapTalkerLevel(TalkerData data) {
    final LogLevel level = data.logLevel ?? LogLevel.info;
    if (level == LogLevel.error || level == LogLevel.critical) {
      return _ExportLogLevel.error;
    }
    if (level == LogLevel.warning) {
      return _ExportLogLevel.warn;
    }
    return _ExportLogLevel.info;
  }

  ({String? tag, String message}) _splitTalkerTag(String? raw) {
    final String text = raw ?? '';
    if (!text.startsWith('[')) {
      return (tag: null, message: text);
    }
    final int end = text.indexOf(']');
    if (end <= 1) {
      return (tag: null, message: text);
    }
    final String tag = text.substring(1, end).trim();
    final String message = text.substring(end + 1).trimLeft();
    return (tag: tag.isEmpty ? null : tag, message: message);
  }

  String _exportLogLevelFileLabel(_ExportLogLevel level) {
    switch (level) {
      case _ExportLogLevel.info:
        return 'INFO';
      case _ExportLogLevel.warn:
        return 'WARN';
      case _ExportLogLevel.error:
        return 'ERROR';
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
              _buildScopeCard(context),
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
              if (_activeExportLogSessionId != null ||
                  _exportLogPath != null) ...[
                const SizedBox(height: AppTheme.spacing3),
                _buildLogPathCard(context),
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
            UIProgress(
              value: (_inventoryLoading || _running) ? null : 0,
              height: 10,
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

  Widget _buildScopeCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool scopeLocked = _running;
    final List<_ExportScopeChoice> choices = <_ExportScopeChoice>[
      _ExportScopeChoice(
        scope: BackupExportScope.full,
        label: _scopeLabel(context, BackupExportScope.full),
        description: _scopeDescription(context, BackupExportScope.full),
      ),
      _ExportScopeChoice(
        scope: BackupExportScope.databasesOnly,
        label: _scopeLabel(context, BackupExportScope.databasesOnly),
        description: _scopeDescription(
          context,
          BackupExportScope.databasesOnly,
        ),
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
            _scopeTitle(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            _scopeSummary(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          for (int i = 0; i < choices.length; i++) ...[
            _buildScopeOption(context, choices[i], scopeLocked),
            if (i != choices.length - 1)
              const SizedBox(height: AppTheme.spacing2),
          ],
        ],
      ),
    );
  }

  Widget _buildScopeOption(
    BuildContext context,
    _ExportScopeChoice choice,
    bool scopeLocked,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool selected = _selectedScope == choice.scope;
    final Color borderColor = selected ? cs.primary : cs.outlineVariant;
    final Color bgColor = selected
        ? cs.primaryContainer.withValues(
            alpha: (cs.primaryContainer.a * 0.38).clamp(0.0, 1.0),
          )
        : cs.surface;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: scopeLocked ? null : () => _handleScopeChanged(choice.scope),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(AppTheme.spacing3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? cs.primary : cs.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    choice.description,
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
                      UIProgress(
                        value: ratio,
                        height: 6,
                        backgroundColor: color.withValues(alpha: 0.18),
                        valueColor: color,
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

  Widget _buildLogPathCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? logPath = _exportLogPath?.trim().isNotEmpty == true
        ? _exportLogPath!.trim()
        : null;
    final bool pathReady = logPath != null;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _logPathTitle(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: pathReady ? _copyExportLogPath : null,
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: Text(_copyLogPathText(context)),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            _logPathSummaryText(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(
                alpha: (cs.surfaceContainerHighest.a * 0.78).clamp(0.0, 1.0),
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SelectionArea(
              child: Text(
                logPath ?? _logPathPreparingText(context),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: pathReady ? null : cs.onSurfaceVariant,
                  height: 1.4,
                ),
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
    final bool inventoryEmpty = _inventory?.isEmpty ?? true;
    final bool canStartExport =
        !_inventoryLoading && _inventory != null && !inventoryEmpty;
    return FilledButton.icon(
      style: actionStyle,
      onPressed: _inventoryLoading
          ? null
          : scanFailed
          ? _loadInventoryPreview
          : canStartExport
          ? _startExport
          : inventoryEmpty && _inventory != null
          ? null
          : _loadInventoryPreview,
      icon: Icon(
        _inventoryLoading
            ? Icons.hourglass_top
            : scanFailed
            ? Icons.refresh
            : inventoryEmpty && _inventory != null
            ? Icons.inventory_2_outlined
            : Icons.play_arrow_rounded,
      ),
      label: Text(
        _inventoryLoading
            ? _scanningScopeButtonText(context)
            : scanFailed
            ? _rescanButtonText(context)
            : inventoryEmpty && _inventory != null
            ? _emptyScopeButtonText(context)
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
    if (!_running && inventory != null && inventory.isEmpty) {
      return _emptyScopeSummary(context);
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
        return _scanningPhaseText(context);
      case ExportPhase.packing:
        return _packingPhaseText(context);
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

  String _logPathTitle(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出日志文件';
    }
    return 'Export Log File';
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

  String _copyLogPathText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '复制日志路径';
    }
    return 'Copy Log Path';
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

  String _copyLogPathSuccessText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出日志路径已复制';
    }
    return 'Export log path copied';
  }

  String _copyLogPathFailedText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '复制导出日志路径失败';
    }
    return 'Failed to copy export log path';
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
    final bool isZh = code.startsWith('zh');
    switch (_selectedScope) {
      case BackupExportScope.full:
        return isZh
            ? '正在遍历截图、数据库、偏好设置与其他持久化目录。'
            : 'Scanning screenshots, databases, preferences, and other persistent folders.';
      case BackupExportScope.databasesOnly:
        return isZh
            ? '正在遍历主库、分片库、设置库与应用数据库目录。'
            : 'Scanning the main database, shards, settings stores, and app database directory.';
    }
  }

  String _preparingSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    switch (_selectedScope) {
      case BackupExportScope.full:
        return isZh
            ? '正在扫描本次完整导出范围，确认无遗漏后才会允许开始导出。'
            : 'Scanning the full backup scope first so export starts only after everything is confirmed.';
      case BackupExportScope.databasesOnly:
        return isZh
            ? '正在扫描数据库导出范围，只会预估数据库相关内容。'
            : 'Scanning the database-only export scope and estimating database content only.';
    }
  }

  String _progressSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final BackupInventory? inventory = _inventory;
    if (inventory == null) {
      return _scanningSummary(context);
    }
    final bool isZh = code.startsWith('zh');
    switch (_selectedScope) {
      case BackupExportScope.full:
        return isZh
            ? '已统计 ${inventory.categories.length} 类数据，正在按字节进度写入 ZIP。'
            : 'Found ${inventory.categories.length} data groups and now writing them into the ZIP by bytes.';
      case BackupExportScope.databasesOnly:
        return isZh
            ? '已统计 ${inventory.categories.length} 类数据库内容，正在按字节进度写入 ZIP。'
            : 'Found ${inventory.categories.length} database groups and now writing them into the ZIP by bytes.';
    }
  }

  String _readySummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final BackupInventory? inventory = _inventory;
    if (inventory == null) {
      return _preparingSummary(context);
    }
    final bool isZh = code.startsWith('zh');
    switch (_selectedScope) {
      case BackupExportScope.full:
        return isZh
            ? '已确认 ${inventory.categories.length} 类持久化数据，点击底部按钮开始导出。'
            : 'Confirmed ${inventory.categories.length} persistent data groups. Tap the button below to start export.';
      case BackupExportScope.databasesOnly:
        return isZh
            ? '已确认 ${inventory.categories.length} 类数据库内容，点击底部按钮开始导出。'
            : 'Confirmed ${inventory.categories.length} database groups. Tap the button below to start export.';
    }
  }

  String _emptyScopeSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return _selectedScope == BackupExportScope.databasesOnly
          ? '当前设备上没有扫描到可导出的数据库内容，可以切回完整导出查看其他数据。'
          : '当前导出范围内没有可导出的持久化数据。';
    }
    return _selectedScope == BackupExportScope.databasesOnly
        ? 'No exportable database content was found. Switch back to Full Export to see other data.'
        : 'No exportable persistent data was found in the current scope.';
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
      return _selectedScope == BackupExportScope.databasesOnly
          ? (isZh ? '重新导出数据库' : 'Export Databases Again')
          : (isZh ? '重新开始导出' : 'Start Export Again');
    }
    return _selectedScope == BackupExportScope.databasesOnly
        ? (isZh ? '开始导出数据库' : 'Export Databases')
        : (isZh ? '开始导出' : 'Start Export');
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

  String _emptyScopeButtonText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return _selectedScope == BackupExportScope.databasesOnly
          ? '当前没有数据库可导出'
          : '当前范围无可导出数据';
    }
    return _selectedScope == BackupExportScope.databasesOnly
        ? 'No Databases To Export'
        : 'Nothing To Export';
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

  String _logPathSummaryText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '本次导出的关键进度和错误会直接写入这个文件，出问题时把它发出来就能排查。';
    }
    return 'Progress and failures for this export are written directly into this file for troubleshooting.';
  }

  String _logPathPreparingText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '正在创建本次导出的日志文件…';
    }
    return 'Creating the export log file...';
  }

  String _scopeTitle(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '导出范围';
    }
    return 'Export Scope';
  }

  String _scopeSummary(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final BackupInventory? inventory = _inventory;
    final String selectedLabel = _scopeLabel(context, _selectedScope);
    if (code.startsWith('zh')) {
      if (inventory == null) {
        return '先选择本次导出的范围，扫描完成后会显示该范围内的预估体积与分类。';
      }
      return '当前选择：$selectedLabel，预计 ${formatBytes(inventory.totalBytes)}，共 ${_fileCountText(context, inventory.totalFiles)}。';
    }
    if (inventory == null) {
      return 'Choose what this export should contain. The scanned estimate will update for the selected scope.';
    }
    return 'Selected: $selectedLabel, estimated ${formatBytes(inventory.totalBytes)} across ${_fileCountText(context, inventory.totalFiles)}.';
  }

  String _scopeLabel(BuildContext context, BackupExportScope scope) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    switch (scope) {
      case BackupExportScope.full:
        return isZh ? '完整导出' : 'Full Export';
      case BackupExportScope.databasesOnly:
        return isZh ? '仅导出数据库' : 'Databases Only';
    }
  }

  String _scopeDescription(BuildContext context, BackupExportScope scope) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    switch (scope) {
      case BackupExportScope.full:
        return isZh
            ? '包含截图、数据库、偏好设置和其他持久化目录。'
            : 'Includes screenshots, databases, preferences, and other persistent folders.';
      case BackupExportScope.databasesOnly:
        return isZh
            ? '只包含主数据库、分片数据库、每应用设置库和应用级数据库目录。'
            : 'Includes only the main database, shard databases, per-app settings, and app database directory.';
    }
  }

  String _scanningPhaseText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    switch (_selectedScope) {
      case BackupExportScope.full:
        return isZh ? '正在扫描全部持久化数据…' : 'Scanning persistent data...';
      case BackupExportScope.databasesOnly:
        return isZh ? '正在扫描数据库相关内容…' : 'Scanning database content...';
    }
  }

  String _packingPhaseText(BuildContext context) {
    final String code = AppLocalizations.of(context).localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    switch (_selectedScope) {
      case BackupExportScope.full:
        return isZh ? '正在按类型打包备份…' : 'Packing backup by data type...';
      case BackupExportScope.databasesOnly:
        return isZh ? '正在打包数据库备份…' : 'Packing database backup...';
    }
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

enum _ExportLogLevel { info, warn, error }

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

class _ExportScopeChoice {
  const _ExportScopeChoice({
    required this.scope,
    required this.label,
    required this.description,
  });

  final BackupExportScope scope;
  final String label;
  final String description;
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
