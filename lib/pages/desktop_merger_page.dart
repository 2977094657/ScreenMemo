import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';

/// 桌面端数据合并工具页面
/// 支持选择多个 ZIP 文件并合并到指定目录
class DesktopMergerPage extends StatefulWidget {
  const DesktopMergerPage({super.key});

  @override
  State<DesktopMergerPage> createState() => _DesktopMergerPageState();
}

class _DesktopMergerPageState extends State<DesktopMergerPage> {
  final List<File> _selectedZipFiles = [];
  final Map<String, _ZipAuditState> _zipAuditStates = {};
  String? _outputDirectory;
  bool _isMerging = false;
  bool _isAuditingZipFiles = false;
  double _progress = 0.0;
  String _currentStage = '';
  String? _currentEntry;
  String? _currentFileName;
  int _currentFileIndex = 0;
  final List<_MergeResult> _results = [];
  String? _errorMessage;
  String? _preflightMessage;
  bool _showDetails = true;

  // 累计统计（实时更新）
  int _totalScreenshots = 0;
  int _totalSkipped = 0;
  int _totalFiles = 0;
  final Set<String> _allAffectedApps = {};
  final List<String> _allWarnings = [];

  // 打包相关
  String? _outputZipPath;
  double _packingProgress = 0.0;
  bool _isPacking = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.desktopMergerTitle),
        centerTitle: true,
        elevation: 0,
        toolbarHeight: 40,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧：选择区域
            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 输出目录选择
                  _buildDirectorySelector(context),
                  const SizedBox(height: AppTheme.spacing2),
                  // ZIP 文件选择
                  _buildZipFileSelector(context),
                  const SizedBox(height: AppTheme.spacing2),
                  // 已选文件列表
                  Expanded(child: _buildFileList(context)),
                  const SizedBox(height: AppTheme.spacing2),
                  // 操作按钮
                  _buildActionButtons(context),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacing3),
            // 右侧：进度和结果区域
            Expanded(
              child:
                  (_isMerging ||
                      _isAuditingZipFiles ||
                      _results.isNotEmpty ||
                      _errorMessage != null ||
                      _preflightMessage != null)
                  ? SingleChildScrollView(child: _buildProgressArea(context))
                  : _buildEmptyState(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.merge_type,
            size: 48,
            color: theme.colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            t.desktopMergerDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorySelector(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing2,
          vertical: AppTheme.spacing1,
        ),
        child: Row(
          children: [
            Icon(Icons.folder, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: AppTheme.spacing2),
            Expanded(
              child: Text(
                _outputDirectory ?? t.desktopMergerSelectOutputDir,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: _outputDirectory != null
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: (_isMerging || _isAuditingZipFiles)
                  ? null
                  : _selectOutputDirectory,
              child: Text(
                t.desktopMergerBrowse,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZipFileSelector(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing2,
          vertical: AppTheme.spacing1,
        ),
        child: Row(
          children: [
            Icon(Icons.archive, color: Colors.orange.shade700, size: 20),
            const SizedBox(width: AppTheme.spacing2),
            Expanded(
              child: Text(
                '${t.desktopMergerZipFiles} (${_selectedZipFiles.length})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: (_isMerging || _isAuditingZipFiles)
                  ? null
                  : _selectZipFiles,
              child: Text(
                t.desktopMergerAddFiles,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_selectedZipFiles.isEmpty) {
      return Card(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload_file, size: 32, color: Colors.orange.shade700),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                t.desktopMergerNoFiles,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacing1),
        itemCount: _selectedZipFiles.length,
        itemBuilder: (context, index) {
          final file = _selectedZipFiles[index];
          final fileName = p.basename(file.path);
          final fileSize = _formatFileSize(file.lengthSync());
          final _ZipAuditState? auditState = _zipAuditStates[file.path];
          final Color auditColor = _auditStatusColor(theme, auditState);
          final IconData auditIcon = _auditStatusIcon(auditState);
          final String auditText = _auditStatusText(auditState);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.archive, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        fileSize,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (auditState?.isRunning == true)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(auditIcon, size: 12, color: auditColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              auditText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: auditColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!_isMerging && !_isAuditingZipFiles)
                  InkWell(
                    onTap: () => setState(() {
                      _zipAuditStates.remove(file.path);
                      _selectedZipFiles.removeAt(index);
                      _refreshPreflightMessage();
                    }),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressArea(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 合并进行中：显示进度和实时统计
            if (_isMerging) ...[
              // 进度头部
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isPacking) ...[
                          Text(
                            t.desktopMergerStagePacking,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.desktopMergerPackingProgress(
                              (_packingProgress * 100).toInt(),
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_currentEntry != null)
                            Text(
                              _currentEntry!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ] else ...[
                          Row(
                            children: [
                              Text(
                                t.desktopMergerFileProgress(
                                  _currentFileIndex + 1,
                                  _selectedZipFiles.length,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_currentFileName != null) ...[
                                const SizedBox(width: AppTheme.spacing2),
                                Expanded(
                                  child: Text(
                                    _currentFileName!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getStageLabel(_currentStage, t),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_currentEntry != null &&
                              _currentEntry != _currentFileName)
                            Text(
                              _currentEntry!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    _isPacking
                        ? '${(_packingProgress * 100).toInt()}%'
                        : '${(_progress * 100).toInt()}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing2),
              UIProgress(value: _isPacking ? _packingProgress : _progress),

              // 阶段提示信息
              Builder(
                builder: (context) {
                  final hint = _getStageHint(
                    _isPacking ? 'packing' : _currentStage,
                    t,
                  );
                  if (hint != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: AppTheme.spacing2),
                      child: Container(
                        padding: const EdgeInsets.all(AppTheme.spacing2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppTheme.spacing2),
                            Expanded(
                              child: Text(
                                hint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: AppTheme.spacing3),

              // 实时统计面板（打包时不显示，只有有数据时才显示）
              if (!_isPacking && _hasAnyStats()) _buildLiveStatsPanel(context),
            ],

            if (!_isMerging &&
                (_isAuditingZipFiles || _preflightMessage != null))
              _buildPreflightPanel(context),

            // 错误信息
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: AppTheme.spacing2),
                        Expanded(
                          child: Text(
                            t.desktopMergerFileFailed,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: t.copyResultsTooltip,
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _copyToClipboard(_errorMessage!),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 合并完成：显示详细汇总
            if (_results.isNotEmpty && !_isMerging) ...[
              _buildSummarySection(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreflightPanel(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasBlockingIssues = _selectedZipFiles.any(
      (File file) => _isAuditBlocking(file.path),
    );
    final Color tone = hasBlockingIssues
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final Color bg = hasBlockingIssues
        ? theme.colorScheme.errorContainer.withOpacity(0.25)
        : theme.colorScheme.primaryContainer.withOpacity(0.2);
    final String title = _isAuditingZipFiles ? 'ZIP 预检中' : 'ZIP 预检结果';
    final String body =
        _preflightMessage ??
        '正在检查所选 ZIP 是否包含完整的 screen / screenshot_memo.db / smm_*.db。';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing3),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacing3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_isAuditingZipFiles)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    hasBlockingIssues ? Icons.error_outline : Icons.fact_check,
                    color: tone,
                  ),
                const SizedBox(width: AppTheme.spacing2),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (body.trim().isNotEmpty)
                  IconButton(
                    tooltip: AppLocalizations.of(context).copyResultsTooltip,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copyToClipboard(body),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(color: tone),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建实时统计面板
  Widget _buildLiveStatsPanel(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.desktopMergerLiveStats,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Wrap(
            spacing: AppTheme.spacing4,
            runSpacing: AppTheme.spacing2,
            children: [
              // 实时统计中仅展示“新增截图数”，其余统计放在下方汇总区域
              _buildStatChip(
                context,
                t.desktopMergerStatScreenshots,
                _totalScreenshots,
                Icons.photo_library,
                theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context,
    String label,
    int value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).labelWithColon(label),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建汇总区域
  Widget _buildSummarySection(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final failedCount = _results.where((r) => !r.success).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 汇总标题
        Row(
          children: [
            Icon(Icons.summarize, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: AppTheme.spacing2),
            Text(
              t.desktopMergerSummaryTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _showDetails = !_showDetails),
              icon: Icon(
                _showDetails ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _showDetails
                    ? t.desktopMergerCollapseAll
                    : t.desktopMergerExpandAll,
              ),
            ),
            if (failedCount > 0)
              IconButton(
                tooltip: t.copyResultsTooltip,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () =>
                    _copyToClipboard(_buildAllFailedErrorDetails()),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing2),

        // 输出目录显示
        if (_outputZipPath != null) ...[
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing2),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: AppTheme.spacing2),
                Expanded(
                  child: Text(
                    _outputZipPath!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton.icon(
                  onPressed: _openOutputFolder,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(
                    t.desktopMergerOpenFolder,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
        ],

        // 简洁统计
        Container(
          padding: const EdgeInsets.all(AppTheme.spacing2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSimpleStat(
                context,
                '${_results.length}',
                t.desktopMergerSummaryTotal(_results.length).split(' ').last,
                Icons.folder_zip,
                theme.colorScheme.primary,
              ),
              _buildSimpleStat(
                context,
                '$_totalScreenshots',
                t.desktopMergerStatScreenshots,
                Icons.photo_library,
                Colors.green,
              ),
              _buildSimpleStat(
                context,
                '$_totalSkipped',
                t.desktopMergerStatSkipped,
                Icons.skip_next,
                theme.colorScheme.secondary,
              ),
              if (failedCount > 0)
                _buildSimpleStat(
                  context,
                  '$failedCount',
                  t.desktopMergerFileFailed,
                  Icons.error,
                  theme.colorScheme.error,
                ),
            ],
          ),
        ),
        if (_showDetails) ...[
          const SizedBox(height: AppTheme.spacing2),
          ..._results.map((result) => _buildFileResultCard(context, result)),
        ],
      ],
    );
  }

  Widget _buildSimpleStat(
    BuildContext context,
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFileResultCard(BuildContext context, _MergeResult result) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = result.report;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing2),
      child: ExpansionTile(
        leading: Icon(
          result.success ? Icons.check_circle : Icons.error,
          color: result.success ? Colors.green : theme.colorScheme.error,
        ),
        title: Text(
          result.fileName,
          style: theme.textTheme.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          result.success
              ? (report != null && report.insertedScreenshots > 0
                    ? t.desktopMergerInsertedCount(report.insertedScreenshots)
                    : t.desktopMergerNoData)
              : (result.errorMessage ?? t.desktopMergerFileFailed),
          style: theme.textTheme.bodySmall?.copyWith(
            color: result.success
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
        ),
        children: [
          if (report != null)
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacing3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 文件统计
                  Wrap(
                    spacing: AppTheme.spacing3,
                    runSpacing: AppTheme.spacing1,
                    children: [
                      _buildMiniStat(
                        context,
                        t.desktopMergerStatScreenshots,
                        report.insertedScreenshots,
                      ),
                      _buildMiniStat(
                        context,
                        t.desktopMergerStatSkipped,
                        report.skippedScreenshotDuplicates,
                      ),
                      _buildMiniStat(
                        context,
                        t.desktopMergerStatFiles,
                        report.copiedFiles,
                      ),
                      _buildMiniStat(
                        context,
                        t.desktopMergerStatReused,
                        report.reusedFiles,
                      ),
                    ],
                  ),
                  // 涉及应用
                  if (report.affectedPackages.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacing2),
                    Text(
                      t.desktopMergerAffectedApps(
                        report.affectedPackages.length,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.affectedPackages
                          .map(_getAppDisplayName)
                          .join(', '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (result.errorMessage != null || result.errorDetails != null)
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacing3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.errorMessage ?? t.desktopMergerFileFailed,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: t.copyResultsTooltip,
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copyToClipboard(
                          result.errorDetails ?? result.errorMessage ?? '',
                        ),
                      ),
                    ],
                  ),
                  if (result.errorDetails != null) ...[
                    const SizedBox(height: AppTheme.spacing1),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppTheme.spacing2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withOpacity(
                          0.25,
                        ),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          result.errorDetails!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(BuildContext context, String label, int value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context).labelWithColon(label),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          value.toString(),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _getAppDisplayName(String packageName) {
    // 简化包名显示，只取最后一部分
    final parts = packageName.split('.');
    if (parts.length > 2) {
      return parts.sublist(parts.length - 2).join('.');
    }
    return packageName;
  }

  Widget _buildActionButtons(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final needMoreFiles = _selectedZipFiles.length < 2 && !_isMerging;
    final bool hasBlockingZip = _selectedZipFiles.any(
      (File file) => _isAuditBlocking(file.path),
    );
    final bool waitingForAudit =
        _isAuditingZipFiles ||
        _selectedZipFiles.any((File file) => !_hasFinishedAudit(file.path));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 文件数量不足提示
        if (needMoreFiles && _selectedZipFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              t.desktopMergerMinFilesHint,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        if (!needMoreFiles && waitingForAudit)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '正在预检 ZIP，完成前不能开始合并',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        if (!needMoreFiles && !waitingForAudit && hasBlockingZip)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '存在未通过预检的 ZIP，已禁止开始合并',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        Row(
          children: [
            if (_selectedZipFiles.isNotEmpty &&
                !_isMerging &&
                !_isAuditingZipFiles)
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => setState(() {
                    _selectedZipFiles.clear();
                    _zipAuditStates.clear();
                    _results.clear();
                    _errorMessage = null;
                    _preflightMessage = null;
                  }),
                  child: Text(
                    t.desktopMergerClear,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            if (_selectedZipFiles.isNotEmpty && !_isMerging)
              const SizedBox(width: AppTheme.spacing1),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _canStartMerge() ? _startMerge : null,
                child: _isMerging
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        t.desktopMergerStart,
                        style: const TextStyle(fontSize: 12),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _selectOutputDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppLocalizations.of(context).desktopMergerSelectOutputDir,
    );
    if (result != null) {
      setState(() {
        _outputDirectory = result;
      });
    }
  }

  Future<void> _selectZipFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: true,
      dialogTitle: AppLocalizations.of(context).desktopMergerSelectZips,
    );
    if (result != null && result.files.isNotEmpty) {
      final List<File> newFiles = <File>[];
      setState(() {
        for (final file in result.files) {
          if (file.path != null) {
            final f = File(file.path!);
            // 避免重复添加
            if (!_selectedZipFiles.any((e) => e.path == f.path)) {
              _selectedZipFiles.add(f);
              newFiles.add(f);
            }
          }
        }
        if (newFiles.isNotEmpty) {
          _preflightMessage = '正在预检新添加的 ZIP...';
        }
      });
      if (newFiles.isNotEmpty) {
        unawaited(_auditZipFiles(newFiles));
      }
    }
  }

  bool _canStartMerge() {
    return !_isMerging &&
        !_isAuditingZipFiles &&
        _selectedZipFiles.length >= 2 && // 至少需要 2 个文件才能合并
        _outputDirectory != null &&
        _selectedZipFiles.every((File file) {
          final _ZipAuditState? state = _zipAuditStates[file.path];
          return state != null &&
              !state.isRunning &&
              state.report != null &&
              state.report!.isValidForMerge;
        });
  }

  /// 是否有任何统计数据
  bool _hasAnyStats() {
    return _totalScreenshots > 0 ||
        _totalSkipped > 0 ||
        _totalFiles > 0 ||
        _results.isNotEmpty;
  }

  Future<void> _auditZipFiles(List<File> files) async {
    if (files.isEmpty) return;
    setState(() {
      _isAuditingZipFiles = true;
      for (final File file in files) {
        _zipAuditStates[file.path] = const _ZipAuditState(isRunning: true);
      }
      _refreshPreflightMessage();
    });

    for (final File file in files) {
      try {
        final MergeZipAuditReport report = await ScreenshotDatabase.instance
            .auditMergeInputZip(file.path);
        if (!mounted) return;
        setState(() {
          _zipAuditStates[file.path] = _ZipAuditState(
            isRunning: false,
            report: report,
          );
          _refreshPreflightMessage();
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _zipAuditStates[file.path] = _ZipAuditState(
            isRunning: false,
            errorMessage: e.toString(),
          );
          _refreshPreflightMessage();
        });
      }
      await Future<void>.delayed(Duration.zero);
    }

    if (!mounted) return;
    setState(() {
      _isAuditingZipFiles = _selectedZipFiles.any(
        (File file) => _zipAuditStates[file.path]?.isRunning == true,
      );
      _refreshPreflightMessage();
    });
  }

  void _refreshPreflightMessage() {
    if (_selectedZipFiles.isEmpty) {
      _preflightMessage = null;
      _isAuditingZipFiles = false;
      return;
    }

    if (_isAuditingZipFiles) {
      _preflightMessage = '正在预检所选 ZIP，完成前不会允许开始合并。';
      return;
    }

    final List<String> failures = <String>[];
    for (final File file in _selectedZipFiles) {
      final _ZipAuditState? state = _zipAuditStates[file.path];
      if (state == null) {
        failures.add('${p.basename(file.path)}\n- 尚未完成预检。');
        continue;
      }
      if (state.isRunning) {
        failures.add('${p.basename(file.path)}\n- 正在预检。');
        continue;
      }
      if (state.report != null && !state.report!.isValidForMerge) {
        failures.add(
          '===== ${p.basename(file.path)} =====\n${state.report!.toText()}',
        );
        continue;
      }
      if (state.errorMessage != null && state.errorMessage!.trim().isNotEmpty) {
        failures.add(
          '===== ${p.basename(file.path)} =====\n预检异常: ${state.errorMessage}',
        );
      }
    }

    _preflightMessage = failures.isEmpty
        ? '所有已选 ZIP 都通过了预检，可以开始合并。'
        : failures.join('\n\n');
  }

  bool _hasFinishedAudit(String path) {
    final _ZipAuditState? state = _zipAuditStates[path];
    return state != null && !state.isRunning;
  }

  bool _isAuditBlocking(String path) {
    final _ZipAuditState? state = _zipAuditStates[path];
    if (state == null) return true;
    if (state.isRunning) return true;
    if (state.report != null) return !state.report!.isValidForMerge;
    return true;
  }

  Color _auditStatusColor(ThemeData theme, _ZipAuditState? state) {
    if (state == null || state.isRunning) {
      return theme.colorScheme.primary;
    }
    if (state.report != null && state.report!.isValidForMerge) {
      return Colors.green;
    }
    return theme.colorScheme.error;
  }

  IconData _auditStatusIcon(_ZipAuditState? state) {
    if (state == null || state.isRunning) {
      return Icons.hourglass_top;
    }
    if (state.report != null && state.report!.isValidForMerge) {
      return Icons.check_circle;
    }
    return Icons.error;
  }

  String _auditStatusText(_ZipAuditState? state) {
    if (state == null || state.isRunning) {
      return '预检中...';
    }
    if (state.report != null) {
      if (state.report!.isValidForMerge) {
        return '预检通过 · screen ${state.report!.screenFileCount} · 包 ${state.report!.screenPackageCount} · smm ${state.report!.smmDbCount}';
      }
      if (state.report!.blockingIssues.isNotEmpty) {
        return state.report!.blockingIssues.first;
      }
      return '预检未通过';
    }
    if (state.errorMessage != null && state.errorMessage!.trim().isNotEmpty) {
      return '预检异常: ${state.errorMessage}';
    }
    return '等待预检';
  }

  Future<void> _startMerge() async {
    if (!_canStartMerge()) {
      setState(() {
        _refreshPreflightMessage();
      });
      return;
    }

    final t = AppLocalizations.of(context);

    // 根据文件大小降序排序，确保最大的压缩包作为基准先合并
    _selectedZipFiles.sort((a, b) {
      try {
        final aSize = a.lengthSync();
        final bSize = b.lengthSync();
        return bSize.compareTo(aSize);
      } catch (_) {
        return 0;
      }
    });

    setState(() {
      _isMerging = true;
      _progress = 0.0;
      _currentStage = '';
      _currentEntry = null;
      _currentFileName = null;
      _currentFileIndex = 0;
      _results.clear();
      _errorMessage = null;
      _preflightMessage = null;
      _outputZipPath = null;
      _packingProgress = 0.0;
      _isPacking = false;
      // 重置累计统计
      _totalScreenshots = 0;
      _totalSkipped = 0;
      _totalFiles = 0;
      _allAffectedApps.clear();
      _allWarnings.clear();
    });

    // 只统计相对于“最大压缩包基线”新增的截图数量
    int totalNewScreenshots = 0;

    try {
      // 初始化数据库到输出目录
      final outputDir = Directory(_outputDirectory!);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // 设置数据库路径到输出目录
      await ScreenshotDatabase.instance.initializeForDesktop(_outputDirectory!);

      final totalFilesCount = _selectedZipFiles.length;
      for (int i = 0; i < totalFilesCount; i++) {
        final file = _selectedZipFiles[i];
        final fileName = p.basename(file.path);

        setState(() {
          _currentFileIndex = i;
          _currentFileName = fileName;
          _currentStage = 'processing_file';
          _currentEntry = '$fileName (${i + 1}/$totalFilesCount)';
        });

        try {
          final report = await ScreenshotDatabase.instance.mergeDataFromZip(
            zipPath: file.path,
            throwOnError: true,
            requireCompleteShardData: true,
            preflightAuditReport: _zipAuditStates[file.path]?.report,
            onProgress: (progress) {
              setState(() {
                // 计算总体进度
                final fileProgress = (i + progress.value) / totalFilesCount;
                _progress = fileProgress;
                _currentStage = progress.stage ?? 'processing';
                _currentEntry = progress.currentEntry ?? fileName;
              });
            },
          );

          if (report == null) {
            _results.add(
              _MergeResult(
                fileName: fileName,
                success: false,
                errorMessage: 'MergeReport is null',
                errorDetails: _buildMergeFailureDetails(
                  fileName: fileName,
                  zipPath: file.path,
                  stage: _currentStage,
                  entry: _currentEntry,
                  error: StateError('MergeReport is null'),
                  stackTrace: StackTrace.current,
                  t: t,
                ),
              ),
            );
            continue;
          }

          // 更新累计统计
          _results.add(
            _MergeResult(fileName: fileName, success: true, report: report),
          );

          // 第一个（最大的）压缩包作为基准，不计入“新增截图”
          final bool isBaselineFile = i == 0;
          final int addedScreenshots = isBaselineFile
              ? 0
              : report.insertedScreenshots;
          totalNewScreenshots += addedScreenshots;

          setState(() {
            _totalScreenshots = totalNewScreenshots;
            _totalSkipped += report.skippedScreenshotDuplicates;
            _totalFiles += report.copiedFiles;
            _allAffectedApps.addAll(report.affectedPackages);
            _allWarnings.addAll(report.warnings);
          });
        } catch (e, st) {
          final errorSummary = '${e.runtimeType}: $e';
          _results.add(
            _MergeResult(
              fileName: fileName,
              success: false,
              errorMessage: errorSummary,
              errorDetails: _buildMergeFailureDetails(
                fileName: fileName,
                zipPath: file.path,
                stage: _currentStage,
                entry: _currentEntry,
                error: e,
                stackTrace: st,
                t: t,
              ),
            ),
          );
          rethrow;
        }
      }

      // 合并完成，先固化数据库快照并做最终审计
      setState(() {
        _currentStage = 'merge_finalizing';
        _isPacking = false;
        _packingProgress = 0.0;
        _currentEntry = '固化数据库快照';
      });

      // 生成输出 ZIP 文件名
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final zipFileName = 'merged_backup_$timestamp.zip';
      final mergedOutputDir = p.join(_outputDirectory!, 'output');
      final outputZipPath = p.join(_outputDirectory!, zipFileName);

      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}

      await ScreenshotDatabase.instance.freezeMergedOutputForBackup(
        baseDirPath: _outputDirectory!,
      );

      setState(() {
        _currentEntry = '最终审计 merged output';
      });
      final MergeZipAuditReport finalAudit = await ScreenshotDatabase.instance
          .auditMergedOutputDirectory(baseDirPath: _outputDirectory!);
      _allWarnings.addAll(finalAudit.warnings);
      if (!finalAudit.isValidForMerge) {
        throw MergeAuditException(
          code: 'invalid_merged_output',
          message: finalAudit.blockingIssues.isNotEmpty
              ? finalAudit.blockingIssues.first
              : 'Merged output audit failed.',
          report: finalAudit,
        );
      }

      // 最终输出通过后才开始打包
      setState(() {
        _currentStage = 'packing';
        _isPacking = true;
        _currentEntry = null;
      });
      await _packWithSystemCommand(mergedOutputDir, outputZipPath);

      try {
        final cleanupDir = Directory(mergedOutputDir);
        if (await cleanupDir.exists()) {
          await cleanupDir.delete(recursive: true);
        }
      } catch (_) {
        // 清理失败不影响已生成的压缩包
      }

      setState(() {
        _progress = 1.0;
        _currentStage = 'completed';
        _isPacking = false;
        _outputZipPath = outputZipPath;
      });
    } catch (e, st) {
      setState(() {
        _errorMessage = _buildGlobalFailureDetails(
          stage: _currentStage,
          entry: _currentEntry,
          fileName: _currentFileName,
          error: e,
          stackTrace: st,
          t: AppLocalizations.of(context),
        );
      });
    } finally {
      try {
        await ScreenshotDatabase.instance.disposeDesktop();
      } catch (_) {}
      setState(() {
        _isMerging = false;
        _isPacking = false;
      });
    }
  }

  /// 使用系统命令打包（避免内存一次性占用过大），并轮询更新进度
  Future<void> _packWithSystemCommand(String sourceDir, String zipPath) async {
    final dir = Directory(sourceDir);
    if (!await dir.exists()) {
      throw Exception('Output directory does not exist: $sourceDir');
    }

    // 预先计算待打包文件的总大小，用于估算进度
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          totalSize += await entity.length();
        } catch (_) {
          // 忽略单个文件的统计错误
        }
      }
    }

    if (totalSize <= 0) {
      throw Exception('No files to pack in: $sourceDir');
    }

    // 删除已存在的 ZIP 文件
    final zipFile = File(zipPath);
    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    // 使用 tar/zip 等外部工具进行打包（这些工具本身是流式写入的）
    final isWindows = Platform.isWindows;

    Process process;
    if (isWindows) {
      // Windows 10+ 自带 tar，可用 tar -a -cf archive.zip . 生成 zip
      process = await Process.start(
        'tar',
        ['-a', '-cf', zipPath, '.'],
        workingDirectory: sourceDir,
        runInShell: true,
      );
    } else {
      // macOS/Linux 使用 zip 命令（-0 只存储不压缩，速度更快，内存占用更低）
      process = await Process.start('zip', [
        '-r',
        '-0',
        zipPath,
        '.',
      ], workingDirectory: sourceDir);
    }

    // 周期性检查目标 zip 文件大小，估算进度
    bool running = true;
    final timer = Timer.periodic(const Duration(milliseconds: 700), (_) async {
      if (!running) return;
      try {
        if (await zipFile.exists()) {
          final currentSize = await zipFile.length();
          if (totalSize > 0 && mounted) {
            final ratio = (currentSize / totalSize).clamp(0.0, 1.0);
            setState(() {
              _packingProgress = ratio;
            });
          }
        }
      } catch (_) {
        // 读取过程中可能出现短暂错误，忽略即可
      }
    });

    final exitCode = await process.exitCode;
    running = false;
    timer.cancel();

    if (exitCode != 0) {
      throw Exception('Failed to create ZIP (exitCode=$exitCode)');
    }

    if (mounted) {
      setState(() {
        _packingProgress = 1.0;
      });
    }
  }

  String _getStageLabel(String stage, AppLocalizations t) {
    switch (stage) {
      case 'merge_extracting':
        return t.desktopMergerStageExtracting;
      case 'merge_copying_files':
        return t.desktopMergerStageCopying;
      case 'merge_shard_databases':
        return t.desktopMergerStageMerging;
      case 'merge_finalizing':
        return t.desktopMergerStageFinalizing;
      case 'processing_file':
        return t.desktopMergerStageProcessing;
      case 'packing':
        return t.desktopMergerStagePacking;
      case 'completed':
        return t.desktopMergerStageCompleted;
      default:
        return t.desktopMergerStageProcessing;
    }
  }

  /// 获取阶段提示信息（解释为什么需要时间）
  String? _getStageHint(String stage, AppLocalizations t) {
    switch (stage) {
      case 'merge_extracting':
        return t.desktopMergerExtractingHint;
      case 'merge_copying_files':
        return t.desktopMergerCopyingHint;
      case 'merge_shard_databases':
        return t.desktopMergerMergingHint;
      case 'packing':
        return t.desktopMergerPackingHint;
      default:
        return null;
    }
  }

  /// 打开输出文件所在文件夹
  Future<void> _openOutputFolder() async {
    if (_outputZipPath == null) return;
    final dir = p.dirname(_outputZipPath!);
    final uri = Uri.file(dir);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _copyToClipboard(String text) async {
    final t = AppLocalizations.of(context);
    if (text.trim().isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.copySuccess)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.copyFailed)));
    }
  }

  String _buildMergeFailureDetails({
    required String fileName,
    required String zipPath,
    required String stage,
    required String? entry,
    required Object error,
    required StackTrace stackTrace,
    required AppLocalizations t,
  }) {
    final stageLabel = stage.isNotEmpty
        ? _getStageLabel(stage, t)
        : t.desktopMergerStageProcessing;
    final b = StringBuffer()
      ..writeln('fileName: $fileName')
      ..writeln('zipPath: $zipPath');
    if (stage.isNotEmpty) {
      b.writeln('stage: $stage ($stageLabel)');
    }
    if (entry != null && entry.isNotEmpty) {
      b.writeln('entry: $entry');
    }
    b
      ..writeln('error: ${error.runtimeType}: $error')
      ..writeln('stackTrace:')
      ..writeln(stackTrace);
    if (error is MergeAuditException && error.report != null) {
      b
        ..writeln()
        ..writeln('auditReport:')
        ..writeln(error.report!.toText());
    }
    return b.toString();
  }

  String _buildGlobalFailureDetails({
    required String stage,
    required String? entry,
    required String? fileName,
    required Object error,
    required StackTrace stackTrace,
    required AppLocalizations t,
  }) {
    final stageLabel = stage.isNotEmpty
        ? _getStageLabel(stage, t)
        : t.desktopMergerStageProcessing;
    final b = StringBuffer();
    if (fileName != null && fileName.isNotEmpty) {
      b.writeln('fileName: $fileName');
    }
    if (stage.isNotEmpty) {
      b.writeln('stage: $stage ($stageLabel)');
    }
    if (entry != null && entry.isNotEmpty) {
      b.writeln('entry: $entry');
    }
    b
      ..writeln('error: ${error.runtimeType}: $error')
      ..writeln('stackTrace:')
      ..writeln(stackTrace);
    if (error is MergeAuditException && error.report != null) {
      b
        ..writeln()
        ..writeln('auditReport:')
        ..writeln(error.report!.toText());
    }
    return b.toString();
  }

  String _buildAllFailedErrorDetails() {
    final failed = _results.where((r) => !r.success).toList(growable: false);
    if (failed.isEmpty) return '';
    final b = StringBuffer();
    for (final r in failed) {
      b.writeln('===== ${r.fileName} =====');
      b.writeln(r.errorDetails ?? r.errorMessage ?? 'Unknown error');
      b.writeln();
    }
    return b.toString();
  }
}

class _MergeResult {
  final String fileName;
  final bool success;
  final MergeReport? report;
  final String? errorMessage;
  final String? errorDetails;

  _MergeResult({
    required this.fileName,
    required this.success,
    this.report,
    this.errorMessage,
    this.errorDetails,
  });
}

class _ZipAuditState {
  final bool isRunning;
  final MergeZipAuditReport? report;
  final String? errorMessage;

  const _ZipAuditState({
    required this.isRunning,
    this.report,
    this.errorMessage,
  });
}
