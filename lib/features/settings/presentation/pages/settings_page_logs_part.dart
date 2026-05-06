part of 'settings_page.dart';

// ========== 日志管理 ==========
extension _SettingsLogsPart on _SettingsPageState {
  bool get _isLogDirectoryRoot => _logDirectoryRelativePath.isEmpty;

  Future<void> _loadLogDirectory({String? relativePath}) async {
    if (_logManagementLoading) return;
    final String target = relativePath ?? _logDirectoryRelativePath;
    _settingsSetState(() {
      _logManagementLoading = true;
    });

    try {
      final LogDirectoryListing listing = await LogExportService.listDirectory(
        relativePath: target,
      );
      if (!mounted) return;
      _settingsSetState(() {
        _logDirectoryRelativePath = listing.relativePath;
        _logDirectoryListing = listing;
      });
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).logManagementLoadFailed(e.toString()),
      );
    } finally {
      if (mounted) {
        _settingsSetState(() {
          _logManagementLoading = false;
        });
      }
    }
  }

  Future<void> _openLogDirectory(LogBrowserEntry entry) async {
    if (!entry.isDirectory || _logManagementLoading) return;
    await _loadLogDirectory(relativePath: entry.relativePath);
  }

  Future<void> _goUpLogDirectory() async {
    if (_isLogDirectoryRoot || _logManagementLoading) return;
    final List<String> parts = _logDirectoryRelativePath.split('/');
    final String parent = parts.length <= 1
        ? ''
        : parts.take(parts.length - 1).join('/');
    await _loadLogDirectory(relativePath: parent);
  }

  Future<void> _shareAllLogs() async {
    await _shareLogsArchive();
  }

  Future<void> _shareLogEntry(LogBrowserEntry entry) async {
    await _shareLogsArchive(entry: entry);
  }

  Future<void> _shareLogsArchive({LogBrowserEntry? entry}) async {
    if (_logManagementSharing) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int exportBytes = entry?.totalBytes ?? _totalLogBytes();
    if (exportBytes <= 0) {
      UINotifier.error(context, l10n.logManagementShareEmpty);
      return;
    }

    final bool ok = await _confirmLargeLogExportIfNeeded(exportBytes);
    if (!ok || !mounted) return;

    _settingsSetState(() {
      _logManagementSharing = true;
    });

    try {
      final archive = entry == null
          ? await LogExportService.createZipForAll()
          : await LogExportService.createZipForBrowserEntry(entry);
      if (!mounted) return;

      final int zipBytes = await archive.length();
      await Share.shareXFiles(<XFile>[
        XFile(archive.path),
      ], text: l10n.logShareText);

      if (!mounted) return;
      UINotifier.success(
        context,
        l10n.logManagementZipReady(_formatLogByteSize(zipBytes)),
      );
      await _loadLogDirectory();
    } on StateError catch (_) {
      if (!mounted) return;
      UINotifier.error(context, l10n.logManagementShareEmpty);
      await _loadLogDirectory();
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, l10n.logManagementShareFailed(e.toString()));
    } finally {
      if (mounted) {
        _settingsSetState(() {
          _logManagementSharing = false;
        });
      }
    }
  }

  Future<void> _deleteLogEntry(LogBrowserEntry entry) async {
    if (_logManagementDeleting) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDirectory = entry.isDirectory;
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: isDirectory
          ? l10n.logManagementDeleteFolderTitle
          : l10n.logManagementDeleteFileTitle,
      message: isDirectory
          ? l10n.logManagementDeleteFolderMessage(
              entry.name,
              _formatLogFileCount(entry.fileCount),
              _formatLogByteSize(entry.totalBytes),
            )
          : l10n.logManagementDeleteFileMessage(entry.name),
      confirmText: l10n.actionDelete,
      cancelText: l10n.dialogCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;

    _settingsSetState(() {
      _logManagementDeleting = true;
    });

    try {
      final LogDeleteResult result = await LogExportService.deleteBrowserEntry(
        entry,
      );
      if (!mounted) return;
      if (entry.isFile) {
        if (result.targetDeleted) {
          UINotifier.success(context, l10n.logManagementFileDeleted);
        } else {
          UINotifier.info(context, l10n.logManagementFileMissing);
        }
      } else {
        if (result.targetDeleted) {
          final String message = result.fileCount > 0
              ? l10n.logManagementFolderDeleted(
                  _formatLogFileCount(result.fileCount),
                )
              : l10n.logManagementFolderDeletedEmpty;
          UINotifier.success(context, message);
        } else {
          UINotifier.info(context, l10n.logManagementFolderMissing);
        }
      }
      await _loadLogDirectory();
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, l10n.logManagementDeleteFailed(e.toString()));
    } finally {
      if (mounted) {
        _settingsSetState(() {
          _logManagementDeleting = false;
        });
      }
    }
  }

  Future<bool> _confirmLargeLogExportIfNeeded(int bytes) async {
    if (bytes <= LogExportService.largeExportThresholdBytes) return true;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return UIDialogs.showConfirm(
      context,
      title: l10n.logManagementLargeExportTitle,
      message: l10n.logManagementLargeExportMessage(_formatLogByteSize(bytes)),
      confirmText: l10n.logManagementLargeExportConfirm,
      cancelText: l10n.dialogCancel,
    );
  }

  Widget _buildLogManagementPage(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final LogDirectoryListing? listing = _logDirectoryListing;
    final List<LogBrowserEntry> entries =
        listing?.entries ?? const <LogBrowserEntry>[];
    final bool showParentEntry =
        !_isLogDirectoryRoot && listing != null && listing.exists;

    return RefreshIndicator(
      onRefresh: _loadLogDirectory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _settingsListPadding(),
        children: [
          _buildCard(
            context: context,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing4,
                  vertical: AppTheme.spacing3,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.logManagementCurrentPath(
                          _formatBreadcrumbPath(
                            listing?.relativePath ?? _logDirectoryRelativePath,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Text(
                      l10n.logManagementSummary(
                        _formatLogFileCount(listing?.fileCount ?? 0),
                        _formatLogByteSize(listing?.totalBytes ?? 0),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_logManagementLoading && listing != null)
                const LinearProgressIndicator(minHeight: 2),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          if (_logManagementLoading && listing == null)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spacing6),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppTheme.spacing3),
                    Text(
                      l10n.logManagementLoading,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (listing == null ||
              !listing.exists ||
              (!showParentEntry && entries.isEmpty))
            _buildLogManagementEmptyCard(
              context,
              isCurrentFolder: !_isLogDirectoryRoot,
            )
          else
            _buildCard(
              context: context,
              children: [
                if (showParentEntry)
                  _buildLogParentDirectoryItem(
                    context,
                    showBottomBorder: entries.isNotEmpty,
                  ),
                for (int i = 0; i < entries.length; i++)
                  _buildLogBrowserEntryItem(
                    context,
                    entries[i],
                    showBottomBorder: i != entries.length - 1,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLogManagementEmptyCard(
    BuildContext context, {
    required bool isCurrentFolder,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return _buildCard(
      context: context,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing5,
            vertical: AppTheme.spacing8,
          ),
          child: Column(
            children: [
              Icon(
                isCurrentFolder
                    ? Icons.folder_open_outlined
                    : Icons.receipt_long_outlined,
                size: 40,
                color: cs.onSurfaceVariant.withValues(alpha: 0.72),
              ),
              const SizedBox(height: AppTheme.spacing3),
              Text(
                isCurrentFolder
                    ? l10n.logManagementEmptyFolderTitle
                    : l10n.logManagementNoLogsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing2),
              Text(
                isCurrentFolder
                    ? l10n.logManagementEmptyFolderDesc
                    : l10n.logManagementNoLogsDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogParentDirectoryItem(
    BuildContext context, {
    required bool showBottomBorder,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool busy =
        _logManagementLoading ||
        _logManagementSharing ||
        _logManagementDeleting;

    return InkWell(
      onTap: busy ? null : _goUpLogDirectory,
      child: Container(
        padding: const EdgeInsets.only(
          left: AppTheme.spacing4,
          right: AppTheme.spacing4,
          top: AppTheme.spacing3,
          bottom: AppTheme.spacing3,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: showBottomBorder
                ? _settingsDividerSide(context)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            _buildSettingsLeadingIcon(
              context,
              Icons.subdirectory_arrow_left_outlined,
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Text(
                l10n.logManagementParentDirectory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogBrowserEntryItem(
    BuildContext context,
    LogBrowserEntry entry, {
    required bool showBottomBorder,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool busy = _logManagementSharing || _logManagementDeleting;
    final bool isDirectory = entry.isDirectory;
    final String modifiedText = entry.latestModified == null
        ? l10n.logManagementUnknownTime
        : _formatLogDateTime(entry.latestModified!);
    final String subtitle = isDirectory
        ? l10n.logManagementFolderSubtitle(
            _formatLogFileCount(entry.fileCount),
            _formatLogByteSize(entry.totalBytes),
            modifiedText,
          )
        : l10n.logManagementFileSubtitle(
            _formatLogByteSize(entry.totalBytes),
            modifiedText,
          );

    return Container(
      padding: const EdgeInsets.only(
        left: AppTheme.spacing4,
        right: AppTheme.spacing2,
        top: AppTheme.spacing3,
        bottom: AppTheme.spacing3,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBottomBorder
              ? _settingsDividerSide(context)
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSettingsLeadingIcon(
            context,
            isDirectory ? Icons.folder_outlined : Icons.description_outlined,
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              onTap: isDirectory && !busy
                  ? () => _openLogDirectory(entry)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.archivePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacing1),
          IconButton(
            tooltip: isDirectory
                ? l10n.logManagementShareFolder
                : l10n.logManagementShareFile,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: busy || entry.fileCount <= 0
                ? null
                : () => _shareLogEntry(entry),
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: isDirectory
                ? l10n.logManagementDeleteFolder
                : l10n.logManagementDeleteFile,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: busy ? null : () => _deleteLogEntry(entry),
            icon: Icon(Icons.delete_outline, color: busy ? null : cs.error),
          ),
        ],
      ),
    );
  }

  int _totalLogBytes() {
    return _logDirectoryListing?.totalBytes ?? 0;
  }

  String _formatCurrentLogPath() {
    return _logDirectoryRelativePath.isEmpty
        ? 'output/logs'
        : 'output/logs/$_logDirectoryRelativePath';
  }

  String _formatBreadcrumbPath(String relativePath) {
    if (relativePath.isEmpty) return 'output / logs';
    return 'output / logs / ${relativePath.split('/').join(' / ')}';
  }

  String _formatLogDateTime(DateTime date) {
    final String locale = AppLocalizations.of(context).localeName;
    return intl.DateFormat.yMd(locale).add_Hm().format(date);
  }

  String _formatLogFileCount(int count) {
    final String locale = AppLocalizations.of(context).localeName;
    return intl.NumberFormat.decimalPattern(locale).format(count);
  }

  String _formatLogByteSize(int bytes) {
    return formatBytes(math.max(bytes, 0));
  }
}
