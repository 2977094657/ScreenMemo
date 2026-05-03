import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';

class ImportDiagnosticsPage extends StatefulWidget {
  const ImportDiagnosticsPage({super.key});

  @override
  State<ImportDiagnosticsPage> createState() => _ImportDiagnosticsPageState();
}

class _ImportDiagnosticsPageState extends State<ImportDiagnosticsPage> {
  ImportDiagnosticsReport? _report;
  ImportOcrRepairTaskStatus _ocrTaskStatus = ImportOcrRepairTaskStatus.fromMap(
    null,
  );
  bool _loading = true;
  String? _error;
  bool _repairing = false;
  bool _repairingOcr = false;
  bool _pollingOcrTask = false;
  Timer? _ocrTaskPollTimer;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _runDiagnostics();
    // ignore: discarded_futures
    _refreshOcrTaskStatus();
    _startOcrTaskPolling();
  }

  @override
  void dispose() {
    _ocrTaskPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final Stopwatch sw = Stopwatch()..start();
    try {
      final report = await ScreenshotDatabase.instance.diagnoseImportState();
      final status = await ScreenshotDatabase.instance
          .getImportOcrRepairTaskStatus();
      if (!mounted) return;
      setState(() {
        _report = report;
        _ocrTaskStatus = status;
        _loading = false;
      });
      try {
        await FlutterLogger.nativeInfo('IMPORT_DIAG', report.toText());
      } catch (_) {}
    } catch (e, st) {
      try {
        await FlutterLogger.handle(
          e,
          st,
          tag: 'IMPORT_DIAG',
          message: 'diagnoseImportState failed',
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      sw.stop();
      try {
        await FlutterLogger.nativeDebug(
          'IMPORT_DIAG',
          'diagnostics run finished in ${sw.elapsedMilliseconds}ms',
        );
      } catch (_) {}
    }
  }

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: report.toText()));
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).importDiagnosticsReportCopied,
        );
      }
    } catch (_) {
      if (mounted)
        UINotifier.error(context, AppLocalizations.of(context).copyFailed);
    }
  }

  Future<void> _repairIndex() async {
    if (_repairing) return;
    setState(() => _repairing = true);
    try {
      final rep = await ScreenshotDatabase.instance.repairImportIndex();
      try {
        await FlutterLogger.nativeInfo('IMPORT_DIAG', rep.toText());
      } catch (_) {}
      if (!mounted) return;

      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: '修复完成',
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: SelectableText(
              rep.toText(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: const [
          UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
        ],
      );

      // Re-run diagnostics after repair.
      await _runDiagnostics();
    } catch (e, st) {
      try {
        await FlutterLogger.handle(
          e,
          st,
          tag: 'IMPORT_DIAG',
          message: 'repairImportIndex failed',
        );
      } catch (_) {}
      if (!mounted) return;
      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: '修复失败',
        message: e.toString(),
        actions: const [
          UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
        ],
      );
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  Future<void> _repairOcr() async {
    if (_repairingOcr) return;
    setState(() => _repairingOcr = true);
    try {
      final previous = _ocrTaskStatus;
      final status = await ScreenshotDatabase.instance
          .startImportOcrRepairTask();
      try {
        await FlutterLogger.nativeInfo('IMPORT_DIAG', status.toText());
      } catch (_) {}
      if (!mounted) return;
      setState(() => _ocrTaskStatus = status);
      _startOcrTaskPolling();

      if (status.isCompleted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).importDiagnosticsNoRepairableOcr,
        );
        await _runDiagnostics();
      } else if (status.isActive && !previous.isActive) {
        UINotifier.info(
          context,
          AppLocalizations.of(context).importDiagnosticsOcrRepairStarted,
        );
      } else if (status.isActive) {
        UINotifier.info(
          context,
          AppLocalizations.of(context).importDiagnosticsOcrRepairResumed,
        );
      }
    } catch (e, st) {
      try {
        await FlutterLogger.handle(
          e,
          st,
          tag: 'IMPORT_DIAG',
          message: 'repairImportOcr failed',
        );
      } catch (_) {}
      if (!mounted) return;
      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: '图片文字修复失败',
        message: e.toString(),
        actions: const [
          UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
        ],
      );
    } finally {
      if (mounted) setState(() => _repairingOcr = false);
    }
  }

  Future<void> _cancelOcrTask() async {
    try {
      final status = await ScreenshotDatabase.instance
          .cancelImportOcrRepairTask();
      if (!mounted) return;
      setState(() => _ocrTaskStatus = status);
      UINotifier.info(
        context,
        AppLocalizations.of(context).importDiagnosticsOcrRepairStopped,
      );
    } catch (e, st) {
      try {
        await FlutterLogger.handle(
          e,
          st,
          tag: 'IMPORT_DIAG',
          message: 'cancelImportOcrRepairTask failed',
        );
      } catch (_) {}
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).importDiagnosticsStopRepairFailed,
        );
      }
    }
  }

  void _startOcrTaskPolling() {
    _ocrTaskPollTimer?.cancel();
    _ocrTaskPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      // ignore: discarded_futures
      _refreshOcrTaskStatus();
    });
  }

  Future<void> _refreshOcrTaskStatus({
    bool rerunDiagnosticsOnComplete = true,
  }) async {
    if (_pollingOcrTask) return;
    _pollingOcrTask = true;
    try {
      final previous = _ocrTaskStatus;
      final status = await ScreenshotDatabase.instance
          .getImportOcrRepairTaskStatus();
      if (!mounted) return;
      setState(() => _ocrTaskStatus = status);
      if (rerunDiagnosticsOnComplete &&
          previous.isActive &&
          !status.isActive &&
          status.isCompleted) {
        await _runDiagnostics();
      }
    } catch (_) {
    } finally {
      _pollingOcrTask = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color pageBg = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).importDiagnosticsTitle),
        centerTitle: true,
        backgroundColor: pageBg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).actionCopy,
            onPressed: _report == null ? null : _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
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
                AppLocalizations.of(context).importDiagnosticsFailedTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.spacing2),
              SelectableText(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing3),
              FilledButton.tonal(
                onPressed: _runDiagnostics,
                child: Text(AppLocalizations.of(context).actionRetry),
              ),
            ],
          ),
        ),
      );
    }

    final ImportDiagnosticsReport report = _report!;
    final List<Widget> cards = <Widget>[
      _buildSummaryCard(context, report),
      _buildActionsCard(context, report),
      _buildPathsCard(context, report),
      _buildFsCard(context, report),
      _buildDbCard(context, report),
      _buildTimelineCard(context, report),
      _buildOcrCard(context, report),
      if (report.suggestions.isNotEmpty) _buildSuggestionsCard(context, report),
      if (report.warnings.isNotEmpty)
        _buildListCard(context, '警告', report.warnings),
      if (report.errors.isNotEmpty)
        _buildListCard(context, '错误', report.errors),
      _buildRawReportCard(context, report),
    ];

    return RefreshIndicator(
      onRefresh: _runDiagnostics,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacing3,
          AppTheme.spacing3,
          AppTheme.spacing3,
          AppTheme.spacing8,
        ),
        itemBuilder: (context, index) => cards[index],
        separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacing3),
        itemCount: cards.length,
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: child,
    );
  }

  Widget _buildTitleRow(BuildContext context, String title, Widget trailing) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    ImportDiagnosticsReport report,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (label, color, icon) = _levelUi(report.level, cs);
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(
      report.timestampMillis,
    );

    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '概览',
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            '运行时间：${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(
              context,
            ).importDiagnosticsDurationMs(report.durationMs),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '可修复索引：${report.canRepairIndex ? '是' : '否'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: report.canRepairIndex ? cs.primary : cs.onSurfaceVariant,
              fontWeight: report.canRepairIndex
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '可修复图片文字：${report.canRepairOcr ? '是' : '否'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: report.canRepairOcr ? cs.primary : cs.onSurfaceVariant,
              fontWeight: report.canRepairOcr
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathsCard(BuildContext context, ImportDiagnosticsReport report) {
    final theme = Theme.of(context);
    final p = report.paths;
    final bool mismatch =
        p.expectedMasterDbExists && !p.openedMasterDbPathMatchesExpected;
    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '路径',
            Icon(
              mismatch ? Icons.warning_amber_rounded : Icons.folder_outlined,
              size: 18,
              color: mismatch
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          _kv(context, 'baseDir', p.baseDirPath ?? '(null)'),
          _kv(context, 'outputDir', p.outputDirPath ?? '(null)'),
          _kv(
            context,
            'expected masterDb',
            '${p.expectedMasterDbPath ?? '(null)'} '
                '(exists=${p.expectedMasterDbExists} size=${p.expectedMasterDbSizeBytes})',
          ),
          _kv(
            context,
            'opened masterDb',
            '${p.openedMasterDbPath ?? '(null)'} '
                '(matchesExpected=${p.openedMasterDbPathMatchesExpected})',
          ),
          if (mismatch) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              '主库路径不一致会导致导入的 DB 未被读取。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFsCard(BuildContext context, ImportDiagnosticsReport report) {
    final theme = Theme.of(context);
    final fs = report.filesystem;
    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '文件结构',
            Icon(
              Icons.insert_drive_file_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          _kv(context, 'outputDirExists', fs.outputDirExists.toString()),
          _kv(
            context,
            'screenDir',
            '${fs.screenDirPath ?? '(null)'} '
                '(exists=${fs.screenDirExists} packages=${fs.screenPackageDirCount})',
          ),
          if (fs.samplePackages.isNotEmpty)
            _kv(context, 'sample packages', fs.samplePackages.join(', ')),
          _kv(
            context,
            'shardsDir',
            '${fs.shardsDirPath ?? '(null)'} '
                '(exists=${fs.shardsDirExists} dbFiles=${fs.shardDbFileCount})',
          ),
          if (fs.sampleShardDbFiles.isNotEmpty)
            _kv(context, 'sample shard db', fs.sampleShardDbFiles.join(', ')),
          _kv(context, 'shard smm db', fs.shardSmmDbFileCount.toString()),
          if (fs.sampleShardSmmDbFiles.isNotEmpty)
            _kv(context, 'sample smm db', fs.sampleShardSmmDbFiles.join(', ')),
        ],
      ),
    );
  }

  Widget _buildDbCard(BuildContext context, ImportDiagnosticsReport report) {
    final theme = Theme.of(context);
    final db = report.database;
    final List<Widget> rows = <Widget>[
      _kv(context, 'openOk', db.openOk.toString()),
      if (!db.openOk && db.openError != null)
        _kv(context, 'openError', db.openError!),
      _kv(context, 'userVersion', db.userVersion?.toString() ?? '(null)'),
    ];
    for (final t in db.tableExists.keys) {
      final exists = db.tableExists[t] ?? false;
      final count = db.tableRowCounts[t];
      rows.add(
        _kv(context, t, 'exists=$exists rows=${count?.toString() ?? '(n/a)'}'),
      );
    }

    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '数据库',
            Icon(
              Icons.storage_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildTimelineCard(
    BuildContext context,
    ImportDiagnosticsReport report,
  ) {
    final theme = Theme.of(context);
    final tl = report.timeline;
    final String latest = tl.latestCaptureMillis == null
        ? '(null)'
        : DateTime.fromMillisecondsSinceEpoch(
            tl.latestCaptureMillis!,
          ).toString();
    final String range =
        '${DateTime.fromMillisecondsSinceEpoch(tl.rangeStartMillis)} ~ '
        '${DateTime.fromMillisecondsSinceEpoch(tl.rangeEndMillis)}';
    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '时间线自检',
            Icon(
              Icons.timeline_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          _kv(context, 'lookbackDays', tl.lookbackDays.toString()),
          _kv(context, 'latestCapture', latest),
          _kv(context, 'range', range),
          _kv(context, 'availableDays', tl.availableDays.toString()),
          if (tl.sampleDays.isNotEmpty)
            _kv(context, 'sample', tl.sampleDays.join(', ')),
        ],
      ),
    );
  }

  Widget _buildOcrCard(BuildContext context, ImportDiagnosticsReport report) {
    final theme = Theme.of(context);
    final ocr = report.ocr;
    final task = _ocrTaskStatus;
    final Color statusColor = _ocrTaskStatusColor(context, task);
    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '图片文字自检',
            Icon(
              Icons.text_snippet_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          _kv(context, 'rowsInRange', ocr.totalRowsInRange.toString()),
          _kv(context, 'rowsWithOcr', ocr.rowsWithOcrInRange.toString()),
          _kv(context, 'rowsMissingOcr', ocr.rowsMissingOcrInRange.toString()),
          if (ocr.sampleMissingPaths.isNotEmpty)
            _kv(context, 'sample missing', ocr.sampleMissingPaths.join(', ')),
          const SizedBox(height: AppTheme.spacing2),
          const Divider(height: 1),
          const SizedBox(height: AppTheme.spacing2),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).importDiagnosticsBackgroundRepairTask,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  _ocrTaskStatusLabel(task),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          _kv(
            context,
            'progress',
            task.candidateRows > 0
                ? '${task.processedRows}/${task.candidateRows} (${task.progressPercent})'
                : task.progressPercent,
          ),
          if (task.candidateRows > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: UIProgress(
                value: task.candidateRows <= 0
                    ? null
                    : (task.processedRows / task.candidateRows).clamp(0, 1),
                height: 6,
              ),
            ),
          if (task.totalWorks > 0)
            _kv(
              context,
              'workItem',
              '${task.currentWorkIndex}/${task.totalWorks}',
            ),
          if (task.currentPackageName.isNotEmpty ||
              task.currentTableName.isNotEmpty)
            _kv(
              context,
              'current',
              '${task.currentPackageName}/${task.currentYear}/${task.currentTableName}#>${task.currentLastId}',
            ),
          if (task.startedAt > 0)
            _kv(context, 'startedAt', _fmtTime(task.startedAt)),
          if (task.updatedAt > 0)
            _kv(context, 'updatedAt', _fmtTime(task.updatedAt)),
          if (task.completedAt > 0)
            _kv(context, 'completedAt', _fmtTime(task.completedAt)),
          if (task.lastError != null)
            _kv(context, 'lastError', task.lastError!),
          if (task.warnings.isNotEmpty)
            _kv(context, 'taskWarnings', task.warnings.take(3).join(' | ')),
          if (task.isActive) ...[
            const SizedBox(height: AppTheme.spacing2),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _cancelOcrTask,
                child: Text(
                  AppLocalizations.of(context).importDiagnosticsStopRepair,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _ocrTaskStatusLabel(ImportOcrRepairTaskStatus status) {
    if (status.isIdle) return '未启动';
    if (status.isPreparing) return '准备中';
    if (status.isPending || status.isRunning) return '运行中';
    if (status.isCompleted) return '已完成';
    if (status.isFailed) return '失败';
    if (status.isCancelled) return '已停止';
    return status.status;
  }

  Color _ocrTaskStatusColor(
    BuildContext context,
    ImportOcrRepairTaskStatus status,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (status.isCompleted) return cs.primary;
    if (status.isPreparing || status.isPending || status.isRunning)
      return cs.tertiary;
    if (status.isFailed) return cs.error;
    if (status.isCancelled) return cs.onSurfaceVariant;
    return cs.onSurfaceVariant;
  }

  String _fmtTime(int millis) {
    if (millis <= 0) return '(null)';
    return DateTime.fromMillisecondsSinceEpoch(millis).toString();
  }

  Widget _buildSuggestionsCard(
    BuildContext context,
    ImportDiagnosticsReport report,
  ) {
    final theme = Theme.of(context);
    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '建议',
            Icon(
              Icons.lightbulb_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          ...report.suggestions.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• ' + s, style: theme.textTheme.bodySmall),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListCard(
    BuildContext context,
    String title,
    List<String> items,
  ) {
    final theme = Theme.of(context);
    final bool isAlert = title == '错误' || title == '警告';
    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            title,
            Icon(
              title == '错误' ? Icons.error_outline : Icons.warning_amber_rounded,
              size: 18,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          ...items.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ' + s,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isAlert ? theme.colorScheme.error : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(
    BuildContext context,
    ImportDiagnosticsReport report,
  ) {
    return _buildCard(
      context,
      child: Wrap(
        spacing: AppTheme.spacing2,
        runSpacing: AppTheme.spacing2,
        children: [
          FilledButton.tonal(
            onPressed: _runDiagnostics,
            child: Text(AppLocalizations.of(context).actionRetry),
          ),
          FilledButton.tonal(
            onPressed: _copyReport,
            child: Text(AppLocalizations.of(context).actionCopy),
          ),
          FilledButton(
            onPressed: (!report.canRepairIndex || _repairing)
                ? null
                : _repairIndex,
            child: _repairing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    AppLocalizations.of(context).importDiagnosticsRepairIndex,
                  ),
          ),
          FilledButton(
            onPressed:
                ((!report.canRepairOcr &&
                        !_ocrTaskStatus.isActive &&
                        !_ocrTaskStatus.isFailed &&
                        !_ocrTaskStatus.isCancelled) ||
                    _repairingOcr)
                ? null
                : _repairOcr,
            child: _repairingOcr
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _ocrTaskStatus.isActive
                        ? '后台修复中'
                        : (_ocrTaskStatus.isFailed ||
                              _ocrTaskStatus.isCancelled)
                        ? '继续修复图片文字'
                        : '修复图片文字',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawReportCard(
    BuildContext context,
    ImportDiagnosticsReport report,
  ) {
    final theme = Theme.of(context);
    return _buildCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(
            context,
            '完整报告',
            Icon(
              Icons.article_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: SelectableText(
                report.toText(),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String label, Color color, IconData icon) _levelUi(
    ImportDiagnosticsLevel lv,
    ColorScheme cs,
  ) {
    switch (lv) {
      case ImportDiagnosticsLevel.ok:
        return ('OK', cs.primary, Icons.check_circle_outline);
      case ImportDiagnosticsLevel.warn:
        return ('WARN', cs.error, Icons.warning_amber_rounded);
      case ImportDiagnosticsLevel.error:
        return ('ERROR', cs.error, Icons.error_outline);
    }
  }
}
