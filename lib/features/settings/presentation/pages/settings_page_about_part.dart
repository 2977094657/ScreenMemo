part of 'settings_page.dart';

// ========== 关于页面 ==========
extension _SettingsAboutPart on _SettingsPageState {
  static const int _aboutOnboardingTapTarget = 10;
  static const int _aboutOnboardingHintThreshold = 3;

  Widget _buildAboutPage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        final String version = info?.version ?? '—';

        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacing5,
                    AppTheme.spacing5,
                    AppTheme.spacing5,
                    AppTheme.spacing4,
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        child: Image.asset('logo.png', width: 64, height: 64),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Text(
                        l10n.aboutAppName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing1),
                      Text(
                        l10n.aboutSlogan,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      Text(
                        l10n.aboutDescription,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            _buildAboutSectionTitle(context, l10n.aboutVersionSectionTitle),
            _buildCard(
              context: context,
              children: [
                _buildAboutInfoRow(
                  context: context,
                  icon: Icons.new_releases_outlined,
                  label: l10n.aboutCurrentVersion,
                  value: version,
                  showBottomBorder: true,
                  onTap: _onAboutVersionTap,
                ),
                _buildAboutInfoRow(
                  context: context,
                  icon: Icons.system_update_alt_outlined,
                  label: l10n.updateCheckNowAction,
                  value: l10n.actionRefresh,
                  showBottomBorder: false,
                  onTap: _checkForUpdates,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            _buildAboutSectionTitle(context, l10n.aboutFeedbackTitle),
            _buildCard(
              context: context,
              children: [
                _buildAboutLinkItem(
                  context: context,
                  icon: Icons.code_outlined,
                  title: l10n.aboutGithub,
                  subtitle: 'github.com/2977094657/ScreenMemo',
                  url: 'https://github.com/2977094657/ScreenMemo',
                  showBottomBorder: true,
                ),
                _buildAboutLinkItem(
                  context: context,
                  icon: Icons.group_outlined,
                  title: l10n.aboutQqGroup,
                  subtitle: '640740880',
                  url: 'https://qm.qq.com/q/ob2NMRDzna',
                  showBottomBorder: true,
                ),
                _buildAboutLinkItem(
                  context: context,
                  icon: Icons.bug_report_outlined,
                  title: l10n.aboutIssueFeedback,
                  subtitle: l10n.aboutFeedbackDesc,
                  url: 'https://github.com/2977094657/ScreenMemo/issues',
                  showBottomBorder: false,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            _buildAboutSectionTitle(context, l10n.supportSectionTitle),
            _buildCard(
              context: context,
              children: [
                _buildAboutNavItem(
                  context: context,
                  icon: Icons.volunteer_activism_outlined,
                  title: l10n.supportEntryTitle,
                  subtitle: l10n.supportEntrySubtitle,
                  onTap: () => _switchSubPage(_SettingsSubPage.support),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            _buildAboutSectionTitle(context, l10n.aboutOpenSourceTitle),
            _buildCard(
              context: context,
              children: [
                _buildAboutInfoRow(
                  context: context,
                  icon: Icons.gavel_outlined,
                  label: l10n.aboutLicenseAgpl,
                  value: 'AGPL v3',
                  showBottomBorder: true,
                  onTap: () => _openAboutUrl(
                    'https://www.gnu.org/licenses/agpl-3.0.html',
                  ),
                ),
                _buildAboutInfoRow(
                  context: context,
                  icon: Icons.article_outlined,
                  label: l10n.aboutThirdPartyLicenses,
                  value: l10n.actionOpen,
                  showBottomBorder: false,
                  onTap: () => _showAboutLicenses(info),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildAboutSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTheme.spacing1,
        bottom: AppTheme.spacing2,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
        ),
      ),
    );
  }

  Widget _buildAboutInfoRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required bool showBottomBorder,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final borderSide = _settingsDividerSide(context);
    final child = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: showBottomBorder ? borderSide : BorderSide.none),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, icon),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }

  Widget _buildAboutLinkItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
    required bool showBottomBorder,
  }) {
    final theme = Theme.of(context);
    final borderSide = _settingsDividerSide(context);
    return InkWell(
      onTap: () => _openAboutUrl(url),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing3,
        ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutNavItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing3,
        ),
        child: Row(
          children: [
            _buildSettingsLeadingIcon(
              context,
              icon,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
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

  void _onAboutVersionTap() {
    final l10n = AppLocalizations.of(context);
    final int nextCount = (_aboutVersionTapCount + 1).clamp(
      0,
      _aboutOnboardingTapTarget,
    );
    final int remaining = _aboutOnboardingTapTarget - nextCount;

    if (remaining <= 0) {
      _settingsSetState(() {
        _aboutVersionTapCount = 0;
      });
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OnboardingPage(
            themeService: widget.themeService,
            previewMode: true,
          ),
        ),
      );
      return;
    }

    _settingsSetState(() {
      _aboutVersionTapCount = nextCount;
    });
    if (remaining <= _aboutOnboardingHintThreshold) {
      UINotifier.info(context, l10n.aboutTapVersionRemaining(remaining));
    }
  }

  Future<void> _openAboutUrl(String url) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.parse(url);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        UINotifier.error(context, l10n.aboutOpenLinkFailed(url));
      }
    } catch (_) {
      if (mounted) UINotifier.error(context, l10n.aboutOpenLinkFailed(url));
    }
  }

  Future<void> _checkForUpdates() async {
    await UpdatePromptCoordinator.instance.checkAndPrompt(
      context,
      force: true,
      reason: 'manual_about',
    );
  }

  void _showAboutLicenses(PackageInfo? info) {
    showLicensePage(
      context: context,
      applicationName: AppLocalizations.of(context).aboutAppName,
      applicationVersion: info == null
          ? null
          : '${info.version}+${info.buildNumber}',
      applicationLegalese: 'AGPL v3',
    );
  }
}
