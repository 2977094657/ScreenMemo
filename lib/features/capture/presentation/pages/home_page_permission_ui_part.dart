part of 'home_page.dart';

extension _HomePagePermissionUiPart on _HomePageState {
  Future<void> _refreshPermissions() async {
    try {
      final permissionService = PermissionService.instance;

      // 显示加载提示
      if (mounted) {
        UINotifier.info(
          context,
          AppLocalizations.of(context).refreshingPermissionsInfo,
          duration: const Duration(seconds: 1),
        );
      }

      // 强制刷新权限状态
      await permissionService.forceRefreshPermissions();

      // 失效统计缓存，确保后续读取为最新
      await ScreenshotService.instance.invalidateStatsCache();
      // 立即重新加载统计
      await _loadStats();

      // 重新检查权限问题
      await _checkPermissionIssues(autoOpenDiagnostic: true);

      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).permissionsRefreshed,
          duration: const Duration(seconds: 1),
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).refreshPermissionsFailed('$e'),
        );
      }
    }
  }

  /// 显示权限状态
  Future<void> _showPermissionStatus() async {
    try {
      final permissionService = PermissionService.instance;
      final permissions = await permissionService.checkAllPermissions();

      if (mounted) {
        final action = await showUIDialog<String>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).permissionStatusTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPermissionStatusItem(
                AppLocalizations.of(context).storagePermissionTitle,
                permissions['storage'] ?? false,
              ),
              _buildPermissionStatusItem(
                AppLocalizations.of(context).notificationPermissionTitle,
                permissions['notification'] ?? false,
              ),
              _buildPermissionStatusItem(
                AppLocalizations.of(context).accessibilityPermissionTitle,
                permissions['accessibility'] ?? false,
              ),
              _buildPermissionStatusItem(
                AppLocalizations.of(context).screenRecordingPermissionTitle,
                true,
              ),
            ],
          ),
          actions: [
            UIDialogAction<String>(
              text: AppLocalizations.of(context).goToSettings,
              result: 'go_settings',
            ),
            UIDialogAction<String>(
              text: AppLocalizations.of(context).dialogOk,
              style: UIDialogActionStyle.primary,
              result: 'ok',
            ),
          ],
        );
        if (!mounted) return;
        if (action == 'go_settings') {
          // 使用页面上下文进行导航，避免在对话框上下文已销毁时导航卡住
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsPage(themeService: widget.themeService),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).checkPermissionStatusFailed('$e'),
        );
      }
    }
  }

  Widget _buildPermissionStatusItem(String name, bool granted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          granted
              ? Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 14,
                    color: AppTheme.successForeground,
                  ),
                )
              : const Icon(Icons.cancel, color: AppTheme.destructive, size: 20),
          const SizedBox(width: 8),
          Text(name),
          const Spacer(),
          Text(
            granted
                ? AppLocalizations.of(context).grantedLabel
                : AppLocalizations.of(context).notGrantedLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: granted
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : AppTheme.destructive,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarActionButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          splashRadius: 20,
          iconSize: 22,
          visualDensity: VisualDensity.compact,
          icon: icon,
        ),
      ),
    );
  }

  Widget _buildRuntimeDiagnosticDrawer() {
    final diagnostic = _runtimeDiagnostic;
    if (diagnostic == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final expanded = _runtimeDiagnosticExpanded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing4,
        AppTheme.spacing3,
        AppTheme.spacing4,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: AppTheme.destructive.withValues(alpha: 0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              onTap: () {
                _homeSetState(() {
                  _runtimeDiagnosticExpanded = !_runtimeDiagnosticExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.destructive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.destructive,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            diagnostic.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing1),
                          Text(
                            diagnostic.summary,
                            maxLines: expanded ? null : 2,
                            overflow: expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭诊断面板',
                      onPressed: _dismissRuntimeDiagnosticDrawer,
                      icon: const Icon(Icons.close),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacing4,
                  0,
                  AppTheme.spacing4,
                  AppTheme.spacing4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final detail in diagnostic.details)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTheme.spacing2,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppTheme.destructive,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacing2),
                            Expanded(
                              child: Text(
                                detail,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppTheme.spacing2),
                    Wrap(
                      spacing: AppTheme.spacing2,
                      runSpacing: AppTheme.spacing2,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copyRuntimeDiagnostic,
                          icon: const Icon(
                            Icons.content_copy_outlined,
                            size: 18,
                          ),
                          label: Text(
                            AppLocalizations.of(
                              context,
                            ).runtimeDiagnosticCopyInfoAction,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: diagnostic.filePath == null
                              ? null
                              : _openRuntimeDiagnosticFile,
                          icon: const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 18,
                          ),
                          label: Text(
                            AppLocalizations.of(
                              context,
                            ).runtimeDiagnosticOpenFileAction,
                          ),
                        ),
                        if (diagnostic.showSettingsAction)
                          TextButton.icon(
                            onPressed: _openSettingsFromDiagnostic,
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            label: Text(
                              AppLocalizations.of(
                                context,
                              ).runtimeDiagnosticOpenSettingsAction,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeToolbarIcon(IconData icon, {Color? color}) {
    return Icon(icon, size: 22, weight: 300, color: color);
  }
}
