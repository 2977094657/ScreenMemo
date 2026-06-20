part of 'settings_page.dart';

// ========== 数据导入导出与备份 ==========
extension _SettingsBackupPart on _SettingsPageState {
  Future<void> _recalculateAllStatistics() async {
    if (_recalculatingAll) return;
    final AppLocalizations t = AppLocalizations.of(context);
    _settingsSetState(() {
      _recalculatingAll = true;
    });

    final ValueNotifier<ScreenshotRecomputeProgress> progressNotifier =
        ValueNotifier<ScreenshotRecomputeProgress>(
          const ScreenshotRecomputeProgress(
            phase: 'prepare',
            current: 0,
            total: 0,
          ),
        );
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    BuildContext? progressDialogContext;
    bool dialogClosed = false;
    bool cancelRequested = false;

    void requestCancel() {
      if (cancelRequested) return;
      cancelRequested = true;
      final ScreenshotRecomputeProgress current = progressNotifier.value;
      progressNotifier.value = ScreenshotRecomputeProgress(
        phase: 'cancel_requested',
        current: current.current,
        total: current.total,
        inserted: current.inserted,
        processedFiles: current.processedFiles,
        packageName: current.packageName,
      );
    }

    final Future<void> progressDialog = showUIDialog<void>(
      context: context,
      barrierDismissible: false,
      canPop: false,
      title: t.recalculateAllTitle,
      constraints: const BoxConstraints(maxWidth: 420, minWidth: 280),
      content: Builder(
        builder: (BuildContext dialogContext) {
          progressDialogContext = dialogContext;
          return _buildRecalculateProgressContent(t, progressNotifier);
        },
      ),
      actions: [
        UIDialogAction<void>(
          text: t.dialogCancel,
          closeOnPress: false,
          onPressed: (_) async => requestCancel(),
        ),
      ],
    );

    Future<void> closeProgressDialog() async {
      if (dialogClosed) return;
      bool didPop = false;
      try {
        final BuildContext? dialogContext = progressDialogContext;
        if (dialogContext != null && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
          didPop = true;
        } else if (navigator.canPop()) {
          navigator.pop();
          didPop = true;
        }
      } catch (_) {}
      dialogClosed = true;
      if (didPop) {
        try {
          await progressDialog;
        } catch (_) {}
      }
    }

    try {
      final bool completed = await ScreenshotService.instance
          .recomputeAllAppStats(
            onProgress: (ScreenshotRecomputeProgress progress) {
              if (!dialogClosed && !cancelRequested) {
                progressNotifier.value = progress;
              }
            },
            shouldCancel: () => cancelRequested,
          );
      if (mounted) {
        await closeProgressDialog();
        if (!mounted) return;
        if (completed) {
          UINotifier.success(context, t.recalculateAllSuccess);
        } else {
          UINotifier.info(context, _recalculateCanceledMessage(t));
        }
      }
    } catch (e) {
      if (mounted) {
        await closeProgressDialog();
        if (!mounted) return;
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: t.recalculateAllFailedTitle,
          content: Text(e.toString()),
          actions: [
            UIDialogAction(
              text: t.dialogOk,
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      }
    } finally {
      await closeProgressDialog();
      if (mounted) {
        _settingsSetState(() {
          _recalculatingAll = false;
        });
      }
      progressNotifier.dispose();
    }
  }

  Widget _buildRecalculateProgressContent(
    AppLocalizations t,
    ValueListenable<ScreenshotRecomputeProgress> progressNotifier,
  ) {
    final ThemeData theme = Theme.of(context);
    final Color detailColor = theme.colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<ScreenshotRecomputeProgress>(
      valueListenable: progressNotifier,
      builder: (_, ScreenshotRecomputeProgress progress, __) {
        final double? value = progress.value;
        final String? percent = value == null
            ? null
            : '${(value * 100).clamp(0, 100).round()}%';
        final bool canceling = progress.phase == 'cancel_requested';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              canceling ? _recalculateCancelHint(t) : t.recalculateAllProgress,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacing3),
            UIProgress(value: value, height: 6),
            const SizedBox(height: AppTheme.spacing2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatRecalculateProgressDetail(progress),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: detailColor,
                    ),
                  ),
                ),
                if (percent != null) ...[
                  const SizedBox(width: AppTheme.spacing2),
                  Text(
                    percent,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: detailColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            if (!canceling) ...[
              const SizedBox(height: AppTheme.spacing2),
              Text(
                _recalculateCancelTip(t),
                style: theme.textTheme.bodySmall?.copyWith(color: detailColor),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _isZhLocale(AppLocalizations t) =>
      t.localeName.toLowerCase().startsWith('zh');

  String _recalculateCancelHint(AppLocalizations t) {
    return _isZhLocale(t)
        ? '正在取消，当前步骤结束后会停止。'
        : 'Cancelling after the current step...';
  }

  String _recalculateCancelTip(AppLocalizations t) {
    return _isZhLocale(t)
        ? '如需停止本次重新统计，可点击下方取消。'
        : 'Tap Cancel to stop this recalculation.';
  }

  String _recalculateCanceledMessage(AppLocalizations t) {
    return _isZhLocale(t) ? '已取消重新统计。' : 'Recalculation canceled.';
  }

  String _formatRecalculateProgressDetail(
    ScreenshotRecomputeProgress progress,
  ) {
    final String phaseLabel = switch (progress.phase) {
      'cancel_requested' => 'Cancelling',
      'scan_prepare' => 'Preparing scan',
      'scan_files' => 'Scanning screenshot files',
      'recompute_app' => 'Recomputing app statistics',
      'recalculate_totals' => 'Recalculating totals',
      'refresh_cache' => 'Refreshing cache',
      'refresh_days' => 'Refreshing timeline days',
      'done' => 'Done',
      _ => 'Preparing',
    };
    final List<String> parts = <String>[phaseLabel];
    if (progress.total > 0) {
      parts.add(
        '${progress.current.clamp(0, progress.total)}/${progress.total}',
      );
    }
    if (progress.packageName != null && progress.packageName!.isNotEmpty) {
      parts.add(progress.packageName!);
    }
    if (progress.processedFiles > 0) {
      parts.add('files ${progress.processedFiles}');
    }
    if (progress.inserted > 0) {
      parts.add('repaired +${progress.inserted}');
    }
    return parts.join(' · ');
  }

  // 已移除导入来源选择（统一通过 ZIP 导入）

  String _formatImportExportStageLabel(
    AppLocalizations t,
    String? stage,
    bool isExport,
  ) {
    final String code = t.localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');

    if (stage == 'scanning') {
      if (isZh) {
        return isExport ? '正在扫描文件…' : '正在扫描压缩包…';
      }
      return isExport ? 'Scanning files...' : 'Scanning archive...';
    }
    if (stage == 'packing') {
      if (isZh) {
        return '正在打包数据…';
      }
      return 'Packing data...';
    }
    if (stage == 'extracting') {
      if (isZh) {
        return '正在解压数据…';
      }
      return 'Extracting data...';
    }
    if (isZh) {
      return isExport ? '导出数据进行中…' : '导入数据进行中…';
    }
    return isExport ? 'Exporting data...' : 'Importing data...';
  }

  String _importExportDialogTitle(AppLocalizations t, bool isExport) {
    final String code = t.localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (isZh) {
      return isExport ? '正在导出数据' : '正在导入数据';
    }
    return isExport ? 'Exporting data' : 'Importing data';
  }

  String _importExportDoNotCloseHint(AppLocalizations t) {
    final String code = t.localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (isZh) {
      return '请保持应用打开，不要离开此页面。';
    }
    return 'Please keep the app open and do not leave this page.';
  }

  Future<void> _showImportExportOverlayDialog({
    required bool isExport,
    required ValueListenable<double> progressNotifier,
    required ValueListenable<String?> stageNotifier,
    required ValueListenable<String?> entryNotifier,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'import_export_progress',
      barrierColor: Colors.black54,
      pageBuilder: (BuildContext dialogContext, _, __) {
        final ThemeData theme = Theme.of(dialogContext);
        final AppLocalizations t = AppLocalizations.of(dialogContext);
        final String title = _importExportDialogTitle(t, isExport);

        return PopScope(
          canPop: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  child: ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (_, double value, __) {
                      // 不再展示百分比进度，统一使用循环进度条
                      return ValueListenableBuilder<String?>(
                        valueListenable: stageNotifier,
                        builder: (_, String? stage, ___) {
                          final String stageLabel =
                              _formatImportExportStageLabel(t, stage, isExport);
                          return ValueListenableBuilder<String?>(
                            valueListenable: entryNotifier,
                            builder: (_, String? entry, ____) {
                              final String? entryLabel =
                                  _shortenImportExportEntry(entry);
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: AppTheme.spacing3),
                                  Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppTheme.spacing2),
                                  Text(
                                    stageLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (entryLabel != null) ...[
                                    const SizedBox(height: AppTheme.spacing1),
                                    Text(
                                      entryLabel,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontFamily: 'monospace',
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: AppTheme.spacing2),
                                  Text(
                                    _importExportDoNotCloseHint(t),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _shortenImportExportEntry(String? entry) {
    if (entry == null || entry.isEmpty) return null;
    const int maxLen = 48;
    if (entry.length <= maxLen) return entry;
    return '...' + entry.substring(entry.length - maxLen);
  }

  Future<void> _showNativeExportDialog() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'native_export_progress',
      barrierColor: Colors.black54,
      pageBuilder: (BuildContext dialogContext, _, __) {
        final ThemeData theme = Theme.of(dialogContext);
        final AppLocalizations t = AppLocalizations.of(dialogContext);
        final String title = _importExportDialogTitle(t, true);
        final String hint = _importExportDoNotCloseHint(t);
        return PopScope(
          canPop: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      const UIProgress(value: null, height: 4),
                      const SizedBox(height: AppTheme.spacing2),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 导出数据到下载目录
  Future<void> _exportDatabase() async {
    if (_exportingDb) return;
    _settingsSetState(() {
      _exportingDb = true;
    });
    try {
      await FlutterLogger.nativeInfo('UI_EXPORT', '开始导出');
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const ExportBackupPage()),
      );
    } catch (e) {
      if (!mounted) return;
      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: '导出失败',
        content: Text(e.toString()),
        actions: const [
          UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
        ],
      );
    } finally {
      if (mounted) {
        _settingsSetState(() {
          _exportingDb = false;
        });
      }
    }
  }

  Future<void> _importData() async {
    if (_importingData) return;

    _settingsSetState(() {
      _importingData = true;
    });

    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
    final ValueNotifier<String?> stageNotifier = ValueNotifier<String?>(null);
    final ValueNotifier<String?> entryNotifier = ValueNotifier<String?>(null);
    bool overlayShown = false;
    String? selectedFileName;
    String? selectedFilePath;

    try {
      await FlutterLogger.nativeInfo('UI_IMPORT', '打开文件选择器');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: false,
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        await FlutterLogger.nativeWarn('UI_IMPORT', '用户取消选择文件');
        return;
      }

      final file = result.files.first;
      final Uint8List? bytes = file.bytes;
      final String? path = file.path;
      selectedFileName = file.name;
      selectedFilePath = path;
      await FlutterLogger.nativeInfo(
        'UI_IMPORT',
        '已选择 文件名=${file.name} 大小=${bytes?.length ?? 0} 路径=${path ?? ''}',
      );

      unawaited(
        _showImportExportOverlayDialog(
          isExport: false,
          progressNotifier: progressNotifier,
          stageNotifier: stageNotifier,
          entryNotifier: entryNotifier,
        ),
      );
      overlayShown = true;

      // 停止截图服务以避免导入过程中的DB/FS冲突
      final bool wasRunning = ScreenshotService.instance.isRunning;
      if (wasRunning) {
        await FlutterLogger.nativeInfo('UI_IMPORT', '导入前停止服务');
        try {
          await ScreenshotService.instance.stopScreenshotService();
        } catch (_) {}
      }

      void handleProgress(ImportExportProgress p) {
        progressNotifier.value = p.value;
        stageNotifier.value = p.stage;
        entryNotifier.value = p.currentEntry;
      }

      Map<String, dynamic>? importRes;

      // 覆盖导入优先走原生 ZIP 导入（依赖 zipPath），无法获取路径时回退到 Dart 流式实现
      if (path != null && path.isNotEmpty) {
        stageNotifier.value = 'import_native_zip';
        progressNotifier.value = 0.02;
        final res = await _screenshotDatabase.importDataFromZip(
          zipPath: path,
          zipBytes: null,
          overwrite: true,
          onProgress: handleProgress,
        );
        importRes = res;
        progressNotifier.value = 1.0;
      } else if (bytes != null && bytes.isNotEmpty) {
        importRes = await _screenshotDatabase.importDataFromZipStreaming(
          zipBytes: bytes,
          onProgress: handleProgress,
        );
      }

      if (!mounted) return;
      if (importRes != null) {
        await _resyncScreenshotSettingsAfterImport();
        await FlutterLogger.nativeInfo(
          'UI_IMPORT',
          '导入成功 已解压=' +
              (importRes['extracted']?.toString() ?? 'null') +
              ' 目标=' +
              (importRes['targetDir']?.toString() ?? ''),
        );
        await ScreenshotService.instance.invalidateStatsCache();
        ScreenshotService.instance.invalidateAvailableDayCountCache();
        final bool requiresRestart = importRes['requiresRestart'] == true;
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).importCompleteTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).dataExtractedTo),
              const SizedBox(height: AppTheme.spacing2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Text(
                  (importRes['targetDir'] as String?) ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (requiresRestart) ...[
                const SizedBox(height: AppTheme.spacing3),
                Text(
                  Localizations.localeOf(context).languageCode.toLowerCase() ==
                          'zh'
                      ? '本次导入已恢复偏好设置或应用级目录。为了让这些内容立即生效，建议重启应用一次。'
                      : 'This restore updated preferences or app-level directories. Restart the app once so every change takes effect immediately.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            UIDialogAction(
              text: AppLocalizations.of(context).dialogOk,
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      } else {
        await FlutterLogger.nativeWarn('UI_IMPORT', '导入结果为 null');
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).importFailedTitle,
          message: AppLocalizations.of(context).importFailedCheckZip,
          actions: [
            UIDialogAction(
              text: AppLocalizations.of(context).dialogOk,
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      await FlutterLogger.handle(e, st, tag: 'UI_IMPORT', message: '导入异常');

      final l10n = AppLocalizations.of(context);
      final detailText = StringBuffer()
        ..writeln('fileName: ${selectedFileName ?? ''}')
        ..writeln('path: ${selectedFilePath ?? ''}')
        ..writeln('stage: ${stageNotifier.value ?? ''}')
        ..writeln('entry: ${entryNotifier.value ?? ''}')
        ..writeln('error: ${e.runtimeType}: $e')
        ..writeln('stackTrace:')
        ..writeln(st);

      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: l10n.importFailedTitle,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: SelectableText(
              detailText.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
        actions: [
          UIDialogAction(
            text: l10n.copyResultsTooltip,
            closeOnPress: false,
            onPressed: (_) async {
              final text = detailText.toString();
              try {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.copySuccess)));
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.copyFailed)));
              }
            },
          ),
          UIDialogAction(
            text: l10n.dialogOk,
            style: UIDialogActionStyle.primary,
          ),
        ],
      );
    } finally {
      try {
        await FlutterLogger.nativeInfo('UI_IMPORT', '导入流程结束');
      } catch (_) {}
      if (mounted) {
        _settingsSetState(() {
          _importingData = false;
        });
      }
      try {
        if (mounted && overlayShown) {
          final NavigatorState nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) {
            nav.pop();
          }
        }
      } catch (_) {}
      progressNotifier.dispose();
      stageNotifier.dispose();
      entryNotifier.dispose();
    }
  }

  Widget _buildStorageAnalysisItem(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.storage_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.storageAnalysisEntryTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.storageAnalysisEntryDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StorageAnalysisPage(),
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l10n.actionEnter),
          ),
        ],
      ),
    );
  }

  Widget _buildExportItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.file_download_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).exportDataTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).exportDataDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _exportingDb ? null : _exportDatabase,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: _exportingDb
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(AppLocalizations.of(context).actionExport),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudBackupItem(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.cloud_upload_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.cloudBackupEntryTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.cloudBackupEntrySubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CloudBackupSettingsPage(),
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l10n.actionEnter),
          ),
        ],
      ),
    );
  }

  Widget _buildImportItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.file_upload_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).importDataTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).importDataDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _importingData ? null : _importData,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: _importingData
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(AppLocalizations.of(context).actionImport),
          ),
        ],
      ),
    );
  }

  Widget _buildRecalculateAllItem(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.sync),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.recalculateAllTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  t.recalculateAllDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _recalculatingAll ? null : _recalculateAllStatistics,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: _recalculatingAll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t.recalculateAllAction),
          ),
        ],
      ),
    );
  }
}
