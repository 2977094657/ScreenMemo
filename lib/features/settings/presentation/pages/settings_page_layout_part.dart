part of 'settings_page.dart';

// ========== 设置页布局与通用组件 ==========
extension _SettingsLayoutPart on _SettingsPageState {
  PreferredSizeWidget _buildSettingsAppBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String title = l10n.settingsTitle;
    if (_subPage == _SettingsSubPage.permissions) {
      title = l10n.permissionsSectionTitle;
    } else if (_subPage == _SettingsSubPage.display) {
      title = l10n.displaySectionTitle;
    } else if (_subPage == _SettingsSubPage.screenshot) {
      title = l10n.screenshotSectionTitle;
    } else if (_subPage == _SettingsSubPage.segmentSummary) {
      title = l10n.segmentSummarySectionTitle;
    } else if (_subPage == _SettingsSubPage.dailyReminder) {
      title = l10n.dailyReminderSectionTitle;
    } else if (_subPage == _SettingsSubPage.appHealth) {
      title = 'App 运行状态';
    } else if (_subPage == _SettingsSubPage.dataBackup) {
      title = l10n.dataBackupSectionTitle;
    } else if (_subPage == _SettingsSubPage.logManagement) {
      title = l10n.logManagementTitle;
    } else if (_subPage == _SettingsSubPage.advanced) {
      title = l10n.advancedSectionTitle;
    } else if (_subPage == _SettingsSubPage.about) {
      title = l10n.aboutSectionTitle;
    }

    final bool canPop = Navigator.of(context).canPop();
    return AppBar(
      toolbarHeight: 36,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leadingWidth: kToolbarHeight,
      leading: _subPage == _SettingsSubPage.home
          ? (canPop
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : const SizedBox.shrink())
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed:
                  _subPage == _SettingsSubPage.logManagement &&
                      !_isLogDirectoryRoot
                  ? _goUpLogDirectory
                  : () => _switchSubPage(_SettingsSubPage.home),
            ),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(top: 2.0),
        child: Text(title),
      ),
      backgroundColor: _settingsBackgroundColor(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      actions: [
        if (_subPage == _SettingsSubPage.permissions)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllPermissions,
            tooltip: l10n.refreshPermissionStatus,
          ),
        if (_subPage == _SettingsSubPage.appHealth)
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showAppHealthTimelineSheet,
            tooltip: '时间线设置',
          ),
        if (_subPage == _SettingsSubPage.appHealth)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadAppHealthStatus(refresh: true),
            tooltip: '刷新状态',
          ),
        if (_subPage == _SettingsSubPage.logManagement)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _logManagementLoading ? null : _loadLogDirectory,
            tooltip: l10n.logManagementRefreshTooltip,
          ),
        if (_subPage == _SettingsSubPage.logManagement)
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            onPressed:
                (_logDirectoryListing?.fileCount ?? 0) <= 0 ||
                    _logManagementSharing ||
                    _logManagementDeleting
                ? null
                : _shareAllLogs,
            tooltip: l10n.logManagementShareAll,
          ),
        if (_subPage != _SettingsSubPage.permissions &&
            _subPage != _SettingsSubPage.appHealth &&
            _subPage != _SettingsSubPage.logManagement)
          const SizedBox(width: kToolbarHeight),
      ],
    );
  }

  Widget _buildSettingsBody(BuildContext context) {
    switch (_subPage) {
      case _SettingsSubPage.home:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildNavItem(
                  context: context,
                  icon: Icons.verified_user_outlined,
                  title: AppLocalizations.of(context).permissionsSectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.permissions),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.palette_outlined,
                  title: AppLocalizations.of(context).displaySectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.display),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.photo_library_outlined,
                  title: AppLocalizations.of(context).screenshotSectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.screenshot),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.insights_outlined,
                  title: AppLocalizations.of(
                    context,
                  ).segmentSummarySectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.segmentSummary),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.notifications_outlined,
                  title: AppLocalizations.of(context).dailyReminderSectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.dailyReminder),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.monitor_heart_outlined,
                  title: 'App 运行状态',
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.appHealth),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.storage_outlined,
                  title: AppLocalizations.of(context).dataBackupSectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.dataBackup),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.receipt_long_outlined,
                  title: AppLocalizations.of(context).logManagementTitle,
                  showBottomBorder: false,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.logManagement),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            _buildCard(
              context: context,
              children: [
                _buildNavItem(
                  context: context,
                  icon: Icons.tune,
                  title: AppLocalizations.of(context).advancedSectionTitle,
                  showBottomBorder: false,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.advanced),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            _buildCard(
              context: context,
              children: [
                _buildNavItem(
                  context: context,
                  icon: Icons.info_outline,
                  title: AppLocalizations.of(context).aboutSectionTitle,
                  showBottomBorder: false,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.about),
                ),
              ],
            ),
          ],
        );
      case _SettingsSubPage.permissions:
        if (_isLoading || _isLoadingKeepAlive) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [_buildPermissionsDropdown(context)],
            ),
          ],
        );
      case _SettingsSubPage.display:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildThemeModeItem(context),
                _buildPrivacyModeItem(context),
                _buildNsfwEntryItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.screenshot:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildScreenshotIntervalItem(context),
                _buildScreenshotQualityItem(context),
                _buildScreenshotExpireItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.segmentSummary:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildSegmentSampleItem(context),
                _buildSegmentDurationItem(context),
                _buildDynamicMergeMaxSpanItem(context),
                _buildDynamicMergeMaxGapItem(context),
                _buildDynamicMergeMaxImagesItem(context),
                _buildAiRequestIntervalItem(context),
                _buildSegmentsJsonAutoRetryMaxItem(context),
                _buildAiRawResponseCleanupItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.dailyReminder:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildDailyNotifyItem(context),
                _buildDailyNotifyBannerItem(context),
                _buildDailyNotifyTestItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.appHealth:
        return _buildAppHealthPage(context);
      case _SettingsSubPage.dataBackup:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildStorageAnalysisItem(context),
                _buildExportItem(context),
                _buildImportItem(context),
                _buildImportDiagnosticsItem(context),
                _buildRecalculateAllItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.logManagement:
        return _buildLogManagementPage(context);
      case _SettingsSubPage.advanced:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildStreamRenderImagesItem(context),
                _buildAiChatPerfOverlayItem(context),
                _buildDynamicEntryLogIconItem(context),
                _buildLoggingToggleItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.about:
        return _buildAboutPage(context);
    }
  }

  Widget _buildCard({
    required BuildContext context,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  EdgeInsets _settingsListPadding() {
    return const EdgeInsets.fromLTRB(
      AppTheme.spacing4,
      AppTheme.spacing2,
      AppTheme.spacing4,
      AppTheme.spacing4,
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool showBottomBorder,
    bool isRootPageItem = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderSide = _settingsDividerSide(context);
    final EdgeInsetsGeometry padding = EdgeInsets.symmetric(
      horizontal: AppTheme.spacing4,
      vertical: isRootPageItem ? AppTheme.spacing3 : AppTheme.spacing3 - 2,
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          border: Border(
            bottom: showBottomBorder ? borderSide : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            _buildSettingsLeadingIcon(context, icon),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsLeadingIcon(
    BuildContext context,
    IconData icon, {
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Icon(
          icon,
          color: color ?? colorScheme.onSurfaceVariant,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacing1,
            bottom: AppTheme.spacing3,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.8),
              width: 1,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
